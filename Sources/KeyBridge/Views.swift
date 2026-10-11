import SwiftUI
import AppKit

enum Section: String, CaseIterable, Identifiable {
    case keys = "キー", sets = "セット", apply = "適用", settings = "設定"
    var id: String { rawValue }
    var icon: String { switch self { case .keys: "key.horizontal"; case .sets: "square.stack.3d.up"; case .apply: "arrow.up.forward.app"; case .settings: "slider.horizontal.3" } }
    var subtitle: String { switch self { case .keys: "APIキーと説明情報をまとめて管理"; case .sets: "用途ごとに、必要なキーをひとまとめに"; case .apply: "このMacで使うセットを選んで適用"; case .settings: "Doppler接続と、このMacの起動設定" } }
}

struct MainView: View {
    @EnvironmentObject var store: AppStore
    @State private var section: Section = .keys
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 10) {
                    Image(systemName: "key.horizontal.fill").font(.title2).foregroundStyle(.blue)
                    Text("KeyBridge").font(.title2.bold())
                }.padding(.top, 12)
                VStack(spacing: 6) {
                    ForEach(Section.allCases) { item in
                        Button { section = item } label: {
                            Label(item.rawValue, systemImage: item.icon).font(.system(size: 14, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(section == item ? Color.accentColor.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).foregroundStyle(section == item ? Color.accentColor : .primary)
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Label(store.stateLabel, systemImage: store.applied == nil ? "circle" : "checkmark.circle.fill").foregroundStyle(store.stateLabel == "適用中" ? .green : .secondary)
                    Text(store.appliedName).font(.caption).lineLimit(2)
                    Divider()
                    Label(store.demo ? "デモモード" : "Doppler", systemImage: store.demo ? "play.rectangle" : "cloud")
                    Text(store.demo ? "架空データで操作を確認" : "キーとセットをMac間で共有").font(.caption).foregroundStyle(.secondary)
                }.font(.subheadline)
            }.padding(20).frame(width: 200).frame(maxHeight: .infinity).background(Color(nsColor: .windowBackgroundColor))
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) { Text(section.rawValue).font(.largeTitle.bold()); Text(section.subtitle).foregroundStyle(.secondary) }
                    Spacer()
                    if store.busy { ProgressView().controlSize(.small) }
                    Button { Task { await store.perform { try await store.refresh() } } } label: { Label("更新", systemImage: "arrow.clockwise") }.disabled(store.busy)
                }
                if store.demo { Label("デモモード：Doppler・Macの環境・自動起動設定は変更しません。", systemImage: "info.circle").font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)) }
                Group {
                    switch section {
                    case .keys: KeysView()
                    case .sets: SetsView()
                    case .apply: ApplyView()
                    case .settings: SettingsView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider()
                HStack {
                    Text(store.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    if let time = store.lastRefresh { Text(time, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }
            }.padding(26).background(Color(nsColor: .controlBackgroundColor))
        }
        .alert("操作を完了できませんでした", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("閉じる") { store.error = nil } } message: { Text(store.error ?? "") }
    }
}

struct KeysView: View {
    @EnvironmentObject var store: AppStore
    @State private var search = ""
    @State private var selected: UUID?
    @State private var editor: KeyEntry?
    @State private var original: KeyEntry?
    @State private var deleting: KeyEntry?
    @State private var revealed: String?
    var filtered: [KeyEntry] { store.catalog.entries.filter { search.isEmpty || [$0.name, $0.service, $0.environment, $0.notes, $0.variable, $0.tags.joined(separator: " ")].joined(separator: " ").localizedCaseInsensitiveContains(search) } }
    var entry: KeyEntry? { store.catalog.entries.first { $0.id == selected } }
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                TextField("名前・サービス・タグで検索", text: $search).textFieldStyle(.roundedBorder)
                Menu {
                    Button("空のキー") { original = nil; editor = KeyEntry() }
                    Button("Gemini API") { original = nil; editor = KeyEntry(name: "Gemini・開発用", service: "Gemini", variable: "GEMINI_API_KEY", url: "https://aistudio.google.com/apikey") }
                    Button("ElevenLabs API") { original = nil; editor = KeyEntry(name: "ElevenLabs・開発用", service: "ElevenLabs", variable: "ELEVENLABS_API_KEY", url: "https://elevenlabs.io") }
                } label: { Label("キーを追加", systemImage: "plus") }.disabled(store.busy)
            }
            HStack(spacing: 18) {
                List(selection: $selected) {
                    ForEach(filtered) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(item.name).font(.headline); Spacer(); if item.expiryLabel != nil { Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange) } }
                            Text("\(item.service) · \(item.environment)").font(.caption).foregroundStyle(.secondary)
                            Text(item.variable).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }.padding(.vertical, 7).tag(item.id)
                    }
                }.listStyle(.inset).frame(minWidth: 260, maxWidth: 330).overlay {
                    if filtered.isEmpty { ContentUnavailableView(search.isEmpty ? "キーがありません" : "該当するキーがありません", systemImage: "key", description: Text(search.isEmpty ? "接続設定を行い、キーを追加してください。" : "別の検索語を試してください。")) }
                }
                Divider()
                if let entry {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack { Text(entry.name).font(.title2.bold()); Spacer(); Text(entry.environment).font(.caption).padding(6).background(.blue.opacity(0.1), in: Capsule()) }
                            Text(entry.service).foregroundStyle(.secondary)
                            LabeledContent("環境変数", value: entry.variable)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("キーの値").font(.caption).foregroundStyle(.secondary)
                                Text(revealed ?? "••••••••••••••••••••").font(.system(.body, design: .monospaced)).textSelection(.enabled).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                                HStack {
                                    Button(revealed == nil ? "本人確認して表示" : "値を隠す") {
                                        if revealed != nil { revealed = nil } else {
                                            Task { await store.perform {
                                                revealed = try await store.reveal(entry)
                                                Task { @MainActor in try? await Task.sleep(nanoseconds: 20_000_000_000); revealed = nil }
                                            } }
                                        }
                                    }
                                    Button("コピー") { Task { await store.perform { try await store.copy(entry) } } }
                                }.disabled(store.busy)
                            }
                            if !entry.notes.isEmpty { Text(entry.notes).textSelection(.enabled) }
                            if !entry.tags.isEmpty { Text(entry.tags.map { "#" + $0 }.joined(separator: "  ")).foregroundStyle(.blue) }
                            if let url = URL(string: entry.url), ["http", "https"].contains(url.scheme ?? "") { Link("サービスの管理画面", destination: url) }
                            if let expires = entry.expiresAt {
                                LabeledContent("有効期限") { Text(expires, style: .date) }
                                if let label = entry.expiryLabel { Label(label, systemImage: "clock").foregroundStyle(.orange) }
                            }
                            LabeledContent("更新日") { Text(entry.updatedAt, style: .date) }.foregroundStyle(.secondary)
                            Divider()
                            HStack { Button("編集") { original = entry; var draft = entry; draft.value = ""; editor = draft }; Spacer(); Button("削除", role: .destructive) { deleting = entry } }.disabled(store.busy)
                        }.padding(.horizontal, 6)
                    }.frame(maxWidth: .infinity)
                } else { ContentUnavailableView("キーを選択", systemImage: "key.horizontal", description: Text("用途や登録情報をここで確認できます。")).frame(maxWidth: .infinity) }
            }
        }
        .onChange(of: selected) { _, _ in revealed = nil }
        .onChange(of: store.catalog) { _, _ in revealed = nil }
        .sheet(item: $editor) { draft in KeyEditor(draft: draft, original: original).environmentObject(store) }
        .alert("キーを削除しますか？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("キャンセル", role: .cancel) { deleting = nil }
            Button("削除", role: .destructive) { if let entry = deleting { Task { await store.perform { try await store.deleteEntry(entry) } } }; deleting = nil }
        } message: {
            let count = store.catalog.sets.filter { $0.entryIDs.contains(deleting?.id ?? UUID()) }.count
            Text("共有先のMacからも削除されます。\(count)個のセットが参照しています。API提供元のキー失効は行いません。")
        }
    }
}

struct KeyEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State var draft: KeyEntry
    let original: KeyEntry?
    @State private var tags = ""
    @State private var expiry = false
    @State private var date = Date().addingTimeInterval(30 * 86400)
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(original == nil ? "キーを登録" : "キーを編集").font(.title2.bold())
            Form {
                TextField("表示名", text: $draft.name)
                TextField("サービス名", text: $draft.service)
                TextField("環境変数名", text: $draft.variable)
                SecureField(original == nil ? "キーの値" : "新しい値（空欄なら現在の値を維持）", text: $draft.value)
                Picker("使用環境", selection: $draft.environment) { ForEach(["開発", "本番", "検証", "共通"], id: \.self) { Text($0) } }
                TextField("タグ（カンマ区切り）", text: $tags)
                TextField("関連URL", text: $draft.url)
                TextField("用途メモ", text: $draft.notes, axis: .vertical).lineLimit(3...6)
                Toggle("有効期限を登録", isOn: $expiry)
                if expiry { DatePicker("有効期限", selection: $date, displayedComponents: [.date]) }
            }.formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            Text("保存後、適用中の値を変えるには「再適用」が必要です。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("キャンセル") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    Task {
                        await store.perform {
                            do {
                                var item = draft
                                if item.value.isEmpty, let original { item.value = original.value }
                                item.tags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                item.expiresAt = expiry ? date : nil; item.updatedAt = Date()
                                try await store.saveEntry(item, original: original); dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(store.busy)
            }
        }.padding(24).frame(width: 600, height: 650)
        .onAppear { tags = draft.tags.joined(separator: ", "); expiry = draft.expiresAt != nil; date = draft.expiresAt ?? date }
    }
}

struct SetsView: View {
    @EnvironmentObject var store: AppStore
    @State private var editor: KeySet?
    @State private var original: KeySet?
    @State private var deleting: KeySet?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("\(store.catalog.sets.count) セット").foregroundStyle(.secondary); Spacer(); Button { original = nil; editor = KeySet() } label: { Label("セットを追加", systemImage: "plus") }.disabled(store.busy) }
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(store.catalog.sets) { set in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Label(set.name, systemImage: "square.stack.3d.up").font(.headline); Spacer(); Text("\(set.entryIDs.count) キー").foregroundStyle(.secondary) }
                            ForEach(set.entryIDs, id: \.self) { id in
                                if let entry = store.catalog.entries.first(where: { $0.id == id }) { Text("\(entry.name)  ·  \(entry.variable)").font(.callout).foregroundStyle(.secondary) }
                                else { Label("削除されたキー · 編集が必要", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                            }
                            if let reason = validation(set) { Text(reason).font(.caption).foregroundStyle(.orange) }
                            HStack { Button("編集") { original = set; editor = set }; Spacer(); Button("削除", role: .destructive) { deleting = set } }.disabled(store.busy)
                        }.padding(18).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }.overlay { if store.catalog.sets.isEmpty { ContentUnavailableView("セットを作成", systemImage: "square.stack.3d.up", description: Text("画像生成や動画制作など、用途ごとにキーをまとめます。")) } }
        }
        .sheet(item: $editor) { draft in SetEditor(draft: draft, original: original).environmentObject(store) }
        .alert("セットを削除しますか？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("キャンセル", role: .cancel) { deleting = nil }
            Button("削除", role: .destructive) { if let set = deleting { Task { await store.perform { try await store.deleteSet(set) } } }; deleting = nil }
        } message: { Text("共有先のMacからも削除されます。現在適用している値は、手動で解除するまで残ります。") }
    }
    private func validation(_ set: KeySet) -> String? { do { _ = try set.resolve(in: store.catalog.entries); return nil } catch { return error.localizedDescription } }
}

struct SetEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State var draft: KeySet
    let original: KeySet?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(original == nil ? "セットを作成" : "セットを編集").font(.title2.bold())
            TextField("セット名", text: $draft.name).textFieldStyle(.roundedBorder)
            Text("含めるキーを選択").foregroundStyle(.secondary)
            List {
                ForEach(store.catalog.entries) { entry in
                    Toggle(isOn: Binding(get: { draft.entryIDs.contains(entry.id) }, set: { if $0 { if !draft.entryIDs.contains(entry.id) { draft.entryIDs.append(entry.id) } } else { draft.entryIDs.removeAll { $0 == entry.id } } })) {
                        VStack(alignment: .leading) { Text(entry.name); Text("\(entry.environment) · \(entry.variable)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack { Button("キャンセル") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("保存") {
                Task { await store.perform {
                    do {
                        var set = draft; set.entryIDs.removeAll { id in !store.catalog.entries.contains { $0.id == id } }; set.updatedAt = Date()
                        try await store.saveSet(set, original: original); dismiss()
                    } catch { self.error = error.localizedDescription }
                } }
            }.buttonStyle(.borderedProminent).disabled(store.busy) }
        }.padding(24).frame(width: 560, height: 500)
    }
}

struct ApplyView: View {
    @EnvironmentObject var store: AppStore
    @State private var confirm = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    Image(systemName: store.applied == nil ? "circle.dashed" : "checkmark.shield").font(.system(size: 32)).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 6) { Text(store.stateLabel).font(.title2.bold()); Text(store.appliedName).foregroundStyle(.secondary) }
                    Spacer()
                    Button("解除") { Task { await store.perform { try store.clear() } } }.disabled(store.busy || store.applied == nil)
                }.padding(20).background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                Picker("適用するセット", selection: $store.selectedSetID) {
                    Text("選択してください").tag(Optional<UUID>.none)
                    ForEach(store.catalog.sets) { Text($0.name).tag(Optional($0.id)) }
                }
                if let set = store.catalog.sets.first(where: { $0.id == store.selectedSetID }) {
                    ForEach(set.entryIDs, id: \.self) { id in
                        if let entry = store.catalog.entries.first(where: { $0.id == id }) { LabeledContent(entry.name, value: entry.variable) }
                    }
                }
                Button { confirm = true } label: { Label(store.applied == nil ? "このMacへ適用" : "切り替え・再適用", systemImage: "arrow.up.forward.app") }.buttonStyle(.borderedProminent).controlSize(.large).disabled(store.busy || store.selectedSetID == nil)
                Text("適用は手動解除またはログアウトまで続きます。管理アプリを終了しても維持します。起動済みのターミナル・IDE・GUIアプリは再起動してください。").foregroundStyle(.secondary)
                Divider()
                Text("指定プログラムだけに渡して起動").font(.headline)
                Text("設定画面で実行ファイルと引数を指定できます。Mac全体の適用を変更せず、選んだセットを起動先に渡します。").foregroundStyle(.secondary)
                Text(store.settings.executable.isEmpty ? "起動先は未設定" : store.settings.executable).font(.callout.monospaced())
                Button("キー付きで起動") { if let id = store.selectedSetID { Task { await store.perform { try await store.launch(id) } } } }.disabled(store.busy || store.selectedSetID == nil || store.settings.executable.isEmpty)
            }
        }
        .alert("このMacへ広く適用しますか？", isPresented: $confirm) {
            Button("キャンセル", role: .cancel) { }
            Button("適用") { if let id = store.selectedSetID { Task { await store.perform { try await store.apply(id) } } } }
        } message: { Text("ログイン中ユーザーが以後起動する複数のアプリへキーが渡ります。設定処理中は値がプロセス引数に一時的に現れます。対象を限定したい場合は「キー付きで起動」を利用してください。") }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var token = ""
    @State private var deleteToken = false
    var body: some View {
        Form {
            SwiftUI.Section("Doppler接続") {
                Text("専用Project / Configと、Config限定の読み書き可能なService Tokenを用意してください。").foregroundStyle(.secondary)
                TextField("Project", text: $store.settings.project)
                TextField("Config", text: $store.settings.config)
                SecureField("Token（空欄なら保存済みTokenを使用）", text: $token)
                HStack {
                    Button("保存して接続") { Task { await store.perform { try await store.configure(token: token); token = "" } } }.disabled(store.busy || store.demo)
                    Button("このMacのTokenを削除", role: .destructive) { deleteToken = true }.disabled(store.busy || store.demo)
                    Spacer()
                    Link("Dopplerを開く", destination: URL(string: "https://dashboard.doppler.com")!)
                }
                Text("TokenはMacのキーチェーンへ保存します。キーとセットはDoppler上で共有されます。").font(.caption).foregroundStyle(.secondary)
            }
            SwiftUI.Section("このMacのログイン後の動作") {
                Toggle("ログイン後にセットを適用", isOn: $store.settings.automaticApply)
                Picker("自動適用するセット", selection: $store.settings.loginSetID) {
                    Text("選択してください").tag(Optional<UUID>.none)
                    ForEach(store.catalog.sets) { Text($0.name).tag(Optional($0.id)) }
                }
                Text("適用に成功した後、下記のプログラムを起動します。起動先が空欄なら適用だけを行います。").font(.caption).foregroundStyle(.secondary)
            }
            SwiftUI.Section("AIからキーの使い方を参照（MCP）") {
                Toggle("MCPに説明情報を共有", isOn: Binding(get: { store.mcpSharingEnabled }, set: { enabled in
                    Task { await store.perform { try await store.setMCPSharing(enabled) } }
                })).disabled(store.busy || store.demo)
                Text("表示名・サービス名・環境変数名・環境・タグ・期限・セット構成を共有します。名前やタグに秘密値を入れないでください。キーの値、Token、用途メモ、関連URLは共有しません。").font(.caption).foregroundStyle(.secondary)
                Text("接続したAIは、一覧の検索とPython・JavaScript・シェルでの参照方法を確認できます。適用やキーの変更は管理画面で行います。").font(.caption).foregroundStyle(.secondary)
                Button("MCP接続設定をコピー") {
                    let pasteboard = NSPasteboard.general; pasteboard.clearContents(); pasteboard.setString(store.mcpConfiguration, forType: .string)
                }.disabled(store.demo)
                Text("対応するAIアプリのMCP設定に追加してください。Mac内で接続します。共有中はKeyBridgeを起動したままにしてください。").font(.caption).foregroundStyle(.secondary)
            }
            SwiftUI.Section("指定プログラム") {
                HStack {
                    TextField("実行ファイルまたは.appの絶対パス", text: $store.settings.executable)
                    Button("選択") { choose(directory: false) }
                }
                TextField("引数（1行に1つ。引用符は不要）", text: $store.settings.arguments, axis: .vertical).lineLimit(2...4)
                HStack { TextField("作業ディレクトリ（任意）", text: $store.settings.directory); Button("選択") { choose(directory: true) } }
                Text("例：実行ファイルにPython、引数に自作スクリプトの絶対パスを指定します。").font(.caption).foregroundStyle(.secondary)
            }
            SwiftUI.Section("期限通知") {
                Toggle("期限の7日前からmacOS通知を表示", isOn: $store.settings.notifications)
                Text("期限は手動登録です。API提供元での失効は行いません。通知はアプリ稼働中に確認します。").font(.caption).foregroundStyle(.secondary)
            }
            Button("このMacの設定を保存") { Task { await store.perform { try await store.savePreferences() } } }.buttonStyle(.borderedProminent).disabled(store.busy || store.demo)
        }.formStyle(.grouped)
        .alert("保存したTokenを削除しますか？", isPresented: $deleteToken) { Button("キャンセル", role: .cancel) { }; Button("削除", role: .destructive) { Task { await store.perform { try store.disconnect() } } } } message: { Text("Doppler上のキーは削除しません。現在の適用も継続します。") }
    }
    private func choose(directory: Bool) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = directory; panel.canChooseFiles = !directory; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if directory { store.settings.directory = url.path } else { store.settings.executable = url.path }
        }
    }
}
