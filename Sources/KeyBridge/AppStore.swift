import AppKit
import SwiftUI
import ServiceManagement
import UserNotifications

@MainActor final class AppStore: ObservableObject {
    @Published var catalog = Catalog()
    @Published var settings = LocalSettings()
    @Published var applied: AppliedState?
    @Published var busy = false
    @Published var error: String?
    @Published var message = "接続設定を登録してください。"
    @Published var lastRefresh: Date?
    @Published var selectedSetID: UUID?
    @Published var needsRecovery = false
    @Published private(set) var mcpSharingEnabled = false
    let demo: Bool
    private let keychain = LocalKeychain()
    private var repository: SecretRepository?
    private let environment: EnvironmentController
    private let defaults: UserDefaults
    private var timer: Timer?
    private var started = false
    private var raw: [String: String] = [:]
    private var notified: Set<String> = []
    private let mcpPublisher = MCPMetadataPublisher()
    init(demo: Bool = ProcessInfo.processInfo.arguments.contains("--demo"), repositoryOverride: SecretRepository? = nil, localDefaults: UserDefaults? = nil, environmentOverride: EnvironmentController? = nil) {
        self.demo = demo
        defaults = localDefaults ?? (demo ? (UserDefaults(suiteName: "dev.keybridge.demo") ?? .standard) : .standard)
        mcpSharingEnabled = !demo && defaults.bool(forKey: "mcpSharingEnabled")
        environment = environmentOverride ?? EnvironmentController(backend: demo ? MemoryEnvironment() : LaunchEnvironment(), vault: demo ? MemoryVault() : LocalKeychain())
        if !demo, let data = defaults.data(forKey: "settings"), let stored = try? JSONDecoder().decode(LocalSettings.self, from: data) { settings = stored }
        if demo {
            repository = repositoryOverride ?? MemoryRepository.demo(); message = "デモモード · 実際のキーやMacの環境は変更しません。"
        } else {
            do { try connect(); applied = try environment.current(); selectedSetID = applied?.setID }
            catch { self.error = error.localizedDescription }
        }
    }
    var stateLabel: String {
        if needsRecovery { return "復旧が必要" }
        guard let applied else { return "未適用" }
        guard let set = catalog.sets.first(where: { $0.id == applied.setID }) else { return "更新あり" }
        guard let resolved = try? set.resolve(in: catalog.entries), resolved == applied.values, set == applied.set else { return "再適用が必要" }
        return "適用中"
    }
    var appliedName: String { applied?.set.name ?? "セット未適用" }
    func start(login: Bool) {
        guard !started else { return }; started = true
        Task {
            await perform {
                if self.repository == nil && !login { return }
                try await self.refresh()
                try await self.restoreInstalledLoginItem()
                if login && self.settings.automaticApply {
                    guard let id = self.settings.loginSetID else { throw BridgeError("ログイン時のセットを設定してください。") }
                    try await self.apply(id)
                    if !self.settings.executable.isEmpty { try await self.launch(id) }
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.busy, self.repository != nil else { return }
                await self.perform { try await self.refresh() }
            }
        }
    }
    func perform(_ work: @escaping () async throws -> Void) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do { try await work() } catch { self.error = error.localizedDescription }
    }
    private func connect() throws {
        guard !settings.project.isEmpty, !settings.config.isEmpty else { repository = nil; return }
        guard let token = try keychain.token(project: settings.project, config: settings.config), !token.isEmpty else { repository = nil; return }
        repository = DopplerRepository(project: settings.project, config: settings.config, token: token)
    }
    func refresh() async throws {
        guard let repository else { throw BridgeError("設定画面でDopplerの接続情報を登録してください。") }
        let fresh = try await repository.read()
        let catalog = try RecordCodec.catalog(from: fresh)
        self.raw = fresh; self.catalog = catalog; lastRefresh = Date()
        if selectedSetID == nil { selectedSetID = catalog.sets.first?.id }
        message = demo ? "デモモード · 実際のキーやMacの環境は変更しません。" : "Dopplerから最新の情報を取得しました。"
        try publishMCP()
        await notifyExpiry()
    }
    func saveEntry(_ entry: KeyEntry, original: KeyEntry?) async throws {
        try entry.validate()
        try await save(name: RecordCodec.entryName(entry.id), value: RecordCodec.encode(entry), expected: try original.map { try RecordCodec.encode($0) })
    }
    func saveSet(_ set: KeySet, original: KeySet?) async throws {
        _ = try set.resolve(in: catalog.entries, now: .distantPast)
        try await save(name: RecordCodec.setName(set.id), value: RecordCodec.encode(set), expected: try original.map { try RecordCodec.encode($0) })
    }
    private func save(name: String, value: String, expected: String?) async throws {
        guard let repository else { throw BridgeError("先にDopplerの接続設定をしてください。") }
        let remote = try await repository.read()
        guard remote[name] == expected else { throw BridgeError("別のMacで変更されています。最新情報を取得し、編集し直してください。") }
        try await repository.write(name: name, value: value)
        try await refresh()
    }
    func deleteEntry(_ entry: KeyEntry) async throws { try await delete(name: RecordCodec.entryName(entry.id), expected: RecordCodec.encode(entry)) }
    func deleteSet(_ set: KeySet) async throws { try await delete(name: RecordCodec.setName(set.id), expected: RecordCodec.encode(set)) }
    private func delete(name: String, expected: String) async throws {
        guard let repository else { throw BridgeError("先にDopplerの接続設定をしてください。") }
        guard try await repository.read()[name] == expected else { throw BridgeError("別のMacで変更されています。最新情報を取得して確認してください。") }
        try await repository.delete(name: name); try await refresh()
    }
    func apply(_ id: UUID) async throws {
        try await refresh()
        guard let set = catalog.sets.first(where: { $0.id == id }) else { throw BridgeError("適用するセットが見つかりません。") }
        do { applied = try environment.apply(set: set, entries: catalog.entries); selectedSetID = id; needsRecovery = false }
        catch {
            if error.localizedDescription.contains("復旧") { needsRecovery = true }
            throw error
        }
        message = demo ? "デモ内で適用しました。実環境は変更していません。" : "適用しました。ターミナル・IDEは再起動してください。"
        try publishMCP()
    }
    func clear() throws {
        do { try environment.clear(); applied = nil; needsRecovery = false }
        catch { if error.localizedDescription.contains("復旧") { needsRecovery = true }; throw error }
        message = "解除しました。起動済みアプリが持つ値は残ります。"
        try publishMCP()
    }
    func launch(_ id: UUID) async throws {
        guard !demo else { message = "デモモードではプログラムを実際に起動しません。"; return }
        try await refresh()
        guard let set = catalog.sets.first(where: { $0.id == id }) else { throw BridgeError("セットが見つかりません。") }
        let values = try set.resolve(in: catalog.entries)
        try await ProgramLauncher.launch(settings: settings, values: values)
        message = "指定したプログラムをキー付きで起動しました。"
    }
    func configure(token: String) async throws {
        guard !demo else { message = "デモモードでは接続設定を保存しません。"; return }
        settings.project = settings.project.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.config = settings.config.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !settings.project.isEmpty, !settings.config.isEmpty else { throw BridgeError("ProjectとConfigを入力してください。") }
        if !token.isEmpty { try keychain.saveToken(token.trimmingCharacters(in: .whitespacesAndNewlines), project: settings.project, config: settings.config) }
        // Save connection even if network is unavailable so it can be retried later.
        try persistSettings(); try connect(); try await refresh()
    }
    func disconnect() throws {
        guard !demo else { return }
        try keychain.saveToken(nil, project: settings.project, config: settings.config)
        repository = nil; catalog = Catalog(); raw = [:]; lastRefresh = nil
        try mcpPublisher.disable()
        message = "このMacのTokenを削除しました。Doppler上のキーと現在の適用値は維持しています。"
    }
    private func persistSettings() throws {
        let data = try JSONEncoder().encode(settings); defaults.set(data, forKey: "settings")
    }
    func setMCPSharing(_ enabled: Bool) async throws {
        guard !demo else { return }
        if enabled {
            try await refresh()
            try mcpPublisher.publish(MCPMetadata(catalog: catalog, applied: applied, now: lastRefresh ?? Date()))
        } else { try mcpPublisher.disable() }
        mcpSharingEnabled = enabled
        defaults.set(enabled, forKey: "mcpSharingEnabled")
        message = enabled ? "MCPでキーの説明情報を参照できます。秘密値は共有しません。" : "MCPへの説明情報の共有を停止しました。"
    }
    private func publishMCP() throws {
        guard !demo, mcpSharingEnabled, lastRefresh != nil else { return }
        try mcpPublisher.publish(MCPMetadata(catalog: catalog, applied: applied, now: lastRefresh ?? Date()))
    }
    var mcpServerPath: String {
        Bundle.main.resourceURL?.appendingPathComponent("keybridge_mcp.py").path ?? ""
    }
    var mcpConfiguration: String {
        let object: [String: Any] = ["mcpServers": ["keybridge": ["command": "/usr/bin/python3", "args": [mcpServerPath]]]]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }
    func savePreferences() async throws {
        guard !demo else { message = "デモモードでは自動起動・通知設定を変更しません。"; return }
        if settings.automaticApply {
            guard let id = settings.loginSetID, catalog.sets.contains(where: { $0.id == id }) else { throw BridgeError("ログイン時に適用するセットを選択してください。") }
            if defaults.string(forKey: "loginApplicationPath") != Bundle.main.bundlePath, SMAppService.mainApp.status == .enabled {
                try await SMAppService.mainApp.unregister()
            }
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            defaults.set(Bundle.main.bundlePath, forKey: "loginApplicationPath")
        } else if SMAppService.mainApp.status == .enabled { try await SMAppService.mainApp.unregister() }
        if settings.notifications {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            if !allowed { settings.notifications = false; throw BridgeError("通知が許可されていません。システム設定で許可してください。") }
        }
        try persistSettings(); message = SMAppService.mainApp.status == .requiresApproval ? "システム設定のログイン項目で承認してください。" : "このMacの設定を保存しました。"
    }
    private func restoreInstalledLoginItem() async throws {
        guard !demo, settings.automaticApply,
              Bundle.main.bundleURL.deletingLastPathComponent().path == "/Applications",
              defaults.string(forKey: "loginApplicationPath") != Bundle.main.bundlePath else { return }
        // Preserve the user's existing login preference while moving the app location.
        if SMAppService.mainApp.status == .enabled { try await SMAppService.mainApp.unregister() }
        try SMAppService.mainApp.register()
        defaults.set(Bundle.main.bundlePath, forKey: "loginApplicationPath")
        if SMAppService.mainApp.status == .requiresApproval { message = "システム設定のログイン項目でKeyBridgeを承認してください。" }
    }
    func reveal(_ entry: KeyEntry) async throws -> String {
        if !demo { try await OwnerAuthentication.verify() }
        return entry.value
    }
    func copy(_ entry: KeyEntry) async throws {
        let value = try await reveal(entry)
        let pasteboard = NSPasteboard.general; pasteboard.clearContents(); pasteboard.setString(value, forType: .string)
        let version = pasteboard.changeCount
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if pasteboard.changeCount == version { pasteboard.clearContents() }
        }
        message = "コピーしました。クリップボードは変更がなければ30秒後に消去します。"
    }
    private func notifyExpiry() async {
        guard !demo, settings.notifications else { return }
        for entry in catalog.entries {
            guard let label = entry.expiryLabel else { continue }
            let id = entry.id.uuidString + label + String(entry.updatedAt.timeIntervalSince1970)
            guard !notified.contains(id) else { continue }
            let content = UNMutableNotificationContent(); content.title = "KeyBridge · \(label)"; content.body = entry.name; content.sound = .default
            try? await UNUserNotificationCenter.current().add(.init(identifier: id, content: content, trigger: nil))
            notified.insert(id)
        }
    }
}
