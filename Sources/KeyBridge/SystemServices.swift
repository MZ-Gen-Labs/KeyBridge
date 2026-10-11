import AppKit
import Security
import LocalAuthentication
import ServiceManagement

protocol StateVault {
    func load() throws -> AppliedState?
    func save(_ state: AppliedState?) throws
}

final class LocalKeychain: StateVault {
    private let service = "dev.keybridge.local.v1"
    private func query(_ account: String) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false] }
    func data(_ account: String) throws -> Data? {
        var q = query(account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw BridgeError("Macのキーチェーンを読み出せません（\(status)）。ロック状態とアクセス許可を確認してください。") }
        return result as? Data
    }
    func put(_ data: Data?, account: String) throws {
        let q = query(account)
        if let data {
            let changes = [kSecValueData as String: data]
            let update = SecItemUpdate(q as CFDictionary, changes as CFDictionary)
            if update == errSecItemNotFound {
                var add = q; add[kSecValueData as String] = data
                let status = SecItemAdd(add as CFDictionary, nil)
                guard status == errSecSuccess else { throw BridgeError("キーチェーンへ保存できません（\(status)）。") }
            } else if update != errSecSuccess { throw BridgeError("キーチェーンを更新できません（\(update)）。") }
        } else {
            let status = SecItemDelete(q as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw BridgeError("キーチェーンから削除できません（\(status)）。") }
        }
    }
    func token(project: String, config: String) throws -> String? {
        guard let data = try data(tokenAccount(project, config)) else { return nil }; return String(data: data, encoding: .utf8)
    }
    func saveToken(_ token: String?, project: String, config: String) throws { try put(token?.data(using: .utf8), account: tokenAccount(project, config)) }
    private func tokenAccount(_ project: String, _ config: String) -> String { "doppler:" + Data((project + "\0" + config).utf8).base64EncodedString() }
    func load() throws -> AppliedState? {
        guard let d = try data("applied-state") else { return nil }
        guard let state = try? JSONDecoder().decode(AppliedState.self, from: d) else { throw BridgeError("適用状態を読み出せません。") }
        return state
    }
    func save(_ state: AppliedState?) throws { try put(try state.map { try JSONEncoder().encode($0) }, account: "applied-state") }
}

final class MemoryVault: StateVault {
    var state: AppliedState?
    func load() throws -> AppliedState? { state }
    func save(_ state: AppliedState?) throws { self.state = state }
}

protocol EnvironmentBackend {
    func get(_ name: String) throws -> String?
    func set(_ name: String, value: String?) throws
}

final class LaunchEnvironment: EnvironmentBackend {
    private func run(_ args: [String]) throws -> (Int32, Data) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/launchctl"); p.arguments = args
        let output = Pipe(); p.standardOutput = output; p.standardError = FileHandle.nullDevice
        // Do not pass the manager's inherited API keys or token into launchctl.
        p.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()]
        do { try p.run() } catch { throw BridgeError("Macの起動環境へアクセスできません。") }
        let data = output.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return (p.terminationStatus, data)
    }
    func get(_ name: String) throws -> String? {
        let (status, data) = try run(["getenv", name])
        guard status == 0, !data.isEmpty else { return nil }
        guard var value = String(data: data, encoding: .utf8) else { throw BridgeError("環境変数を読み出せません。") }
        if value.hasSuffix("\n") { value.removeLast() }
        return value
    }
    func set(_ name: String, value: String?) throws {
        let args = value.map { ["setenv", name, $0] } ?? ["unsetenv", name]
        guard try run(args).0 == 0 else { throw BridgeError("環境変数「\(name)」を変更できません。") }
    }
}

final class MemoryEnvironment: EnvironmentBackend {
    var values: [String: String] = [:]
    func get(_ name: String) throws -> String? { values[name] }
    func set(_ name: String, value: String?) throws { values[name] = value }
}

final class EnvironmentController {
    let backend: EnvironmentBackend
    let vault: StateVault
    init(backend: EnvironmentBackend, vault: StateVault) { self.backend = backend; self.vault = vault }
    func current() throws -> AppliedState? {
        guard let state = try vault.load() else { return nil }
        // A fresh login has no matching variables; discard the previous session record.
        let absent = try state.values.keys.allSatisfy { try backend.get($0) == nil }
        if absent { try vault.save(nil); return nil }
        return state
    }
    func apply(set: KeySet, entries: [KeyEntry]) throws -> AppliedState {
        let values = try set.resolve(in: entries)
        let old = try current()
        var before: [String: String] = [:]
        let names = Set(values.keys).union(old?.values.keys.map { $0 } ?? [])
        for name in names { before[name] = try backend.get(name) }
        if let old {
            for (name, value) in old.values {
                guard before[name] == value else { throw BridgeError("「\(name)」は他のツールで変更されています。競合を解消してから再試行してください。") }
            }
        }
        var previous = before
        if let old {
            for name in old.values.keys { previous[name] = old.previous[name] }
        }
        previous = previous.filter { values[$0.key] != nil }
        let state = AppliedState(setID: set.id, values: values, previous: previous, set: set, entries: entries.filter { set.entryIDs.contains($0.id) })
        // Persist recovery information before changing any environment variables.
        try vault.save(state)
        var changed: [String] = []
        do {
            for name in names.sorted() {
                let desired = values[name] ?? old?.previous[name]
                try backend.set(name, value: desired); changed.append(name)
            }
        } catch {
            try rollback(changed, before: before, old: old)
            throw error
        }
        return state
    }
    func clear() throws {
        guard let old = try current() else { return }
        var before: [String: String] = [:]
        for (name, value) in old.values {
            before[name] = try backend.get(name)
            guard before[name] == value else { throw BridgeError("「\(name)」は他のツールで変更されています。解除を停止しました。") }
        }
        var changed: [String] = []
        do {
            for name in old.values.keys.sorted() { try backend.set(name, value: old.previous[name]); changed.append(name) }
            try vault.save(nil)
        } catch {
            try rollback(changed, before: before, old: old)
            throw error
        }
    }
    private func rollback(_ names: [String], before: [String: String], old: AppliedState?) throws {
        var failed = false
        for name in names.reversed() { do { try backend.set(name, value: before[name]) } catch { failed = true } }
        if failed { throw BridgeError("途中で失敗し、元の環境への復旧も完了しませんでした。適用状態を確認してください。") }
        try vault.save(old)
    }
}

@MainActor enum OwnerAuthentication {
    static func verify() async throws {
        let context = LAContext(); context.localizedCancelTitle = "キャンセル"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { throw BridgeError("本人確認を利用できません。Macのログインパスワード設定を確認してください。") }
        do { _ = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "KeyBridgeのキーを表示・コピーします。") }
        catch { throw BridgeError("本人確認がキャンセルされたか、確認できませんでした。") }
    }
}

@MainActor enum ProgramLauncher {
    static func launch(settings: LocalSettings, values: [String: String]) async throws {
        guard !settings.executable.isEmpty else { throw BridgeError("起動するプログラムを設定してください。") }
        let url = URL(fileURLWithPath: settings.executable)
        guard FileManager.default.fileExists(atPath: url.path) else { throw BridgeError("指定したプログラムが見つかりません。") }
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("DOPPLER_") && !$0.key.hasPrefix("KEYBRIDGE_") }
        environment.merge(values) { _, new in new }
        if url.pathExtension == "app" {
            let configuration = NSWorkspace.OpenConfiguration(); configuration.environment = environment; configuration.arguments = settings.argumentList
            configuration.createsNewApplicationInstance = true
            do { _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration) }
            catch { throw BridgeError("指定したアプリを起動できません。") }
        } else {
            guard FileManager.default.isExecutableFile(atPath: url.path) else { throw BridgeError("実行可能なファイルを指定してください。スクリプトの場合はPython等を実行ファイルに指定します。") }
            let p = Process(); p.executableURL = url; p.arguments = settings.argumentList; p.environment = environment
            if !settings.directory.isEmpty { p.currentDirectoryURL = URL(fileURLWithPath: settings.directory) }
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
            do { try p.run() } catch { throw BridgeError("プログラムを起動できません。パスと作業ディレクトリを確認してください。") }
        }
    }
}
