import Foundation

struct BridgeError: LocalizedError, Equatable {
    var message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct KeyEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var service = ""
    var variable = ""
    var value = ""
    var environment = "開発"
    var notes = ""
    var tags: [String] = []
    var url = ""
    var expiresAt: Date?
    var createdAt = Date()
    var updatedAt = Date()
    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !service.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BridgeError("表示名とサービス名を入力してください。") }
        try EnvironmentRules.validate(variable)
        guard !value.isEmpty, !value.contains("\0") else { throw BridgeError("キーは空値とNUL文字を使用できません。") }
        if !url.isEmpty {
            guard let u = URL(string: url), ["http", "https"].contains(u.scheme?.lowercased() ?? ""), u.host != nil else { throw BridgeError("関連URLはhttpまたはhttpsのURLを入力してください。") }
        }
    }
    var expiryLabel: String? {
        guard let d = expiresAt else { return nil }
        if d < Date() { return "期限切れ" }
        if d < Date().addingTimeInterval(7 * 86400) { return "期限まで7日以内" }
        return nil
    }
}

struct KeySet: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var entryIDs: [UUID] = []
    var updatedAt = Date()
    func resolve(in entries: [KeyEntry], now: Date = Date()) throws -> [String: String] {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BridgeError("セット名を入力してください。") }
        guard !entryIDs.isEmpty else { throw BridgeError("セットにキーを追加してください。") }
        var result: [String: String] = [:]
        for id in entryIDs {
            guard let entry = entries.first(where: { $0.id == id }) else { throw BridgeError("セット内のキーが削除されています。セットを編集してください。") }
            try entry.validate()
            guard entry.expiresAt.map({ $0 > now }) ?? true else { throw BridgeError("期限切れのキーがあります。更新してから適用してください。") }
            guard result[entry.variable] == nil else { throw BridgeError("セット内で環境変数名「\(entry.variable)」が重複しています。") }
            result[entry.variable] = entry.value
        }
        return result
    }
}

enum EnvironmentRules {
    static let forbidden: Set<String> = ["HOME", "PATH", "SHELL", "USER", "LOGNAME", "TMPDIR", "ENV", "BASH_ENV", "ZDOTDIR", "DOPPLER_TOKEN", "PYTHONPATH", "PYTHONHOME", "NODE_OPTIONS", "LD_PRELOAD", "LD_LIBRARY_PATH", "GIT_CONFIG", "GIT_CONFIG_COUNT", "GIT_SSH", "GIT_SSH_COMMAND", "SSH_AUTH_SOCK", "XPC_SERVICE_NAME"]
    static func validate(_ name: String) throws {
        guard name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { throw BridgeError("環境変数名は英数字とアンダースコアを使い、数字で始めないでください。") }
        let upper = name.uppercased()
        guard !forbidden.contains(upper), !upper.hasPrefix("DYLD_"), !upper.hasPrefix("KEYBRIDGE_"), !upper.hasPrefix("DOPPLER_") else { throw BridgeError("この環境変数名は実行環境や認証に影響するため使用できません。") }
    }
}

struct Catalog: Equatable {
    var entries: [KeyEntry] = []
    var sets: [KeySet] = []
}

struct LocalSettings: Codable, Equatable {
    var project = ""
    var config = ""
    var loginSetID: UUID?
    var automaticApply = false
    var executable = ""
    var arguments = ""
    var directory = ""
    var notifications = false
    var argumentList: [String] { arguments.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty } }
}

struct AppliedState: Codable, Equatable {
    var setID: UUID
    var values: [String: String]
    var previous: [String: String]
    var set: KeySet
    var entries: [KeyEntry]
}

struct RecordEnvelope<T: Codable>: Codable {
    var version = 1
    var payload: T
}

enum RecordCodec {
    static let entryPrefix = "KEYBRIDGE_V1_ENTRY_"
    static let setPrefix = "KEYBRIDGE_V1_SET_"
    static func entryName(_ id: UUID) -> String { entryPrefix + id.uuidString.replacingOccurrences(of: "-", with: "") }
    static func setName(_ id: UUID) -> String { setPrefix + id.uuidString.replacingOccurrences(of: "-", with: "") }
    static func encode<T: Codable>(_ item: T) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(RecordEnvelope(payload: item)).base64EncodedString()
    }
    static func decode<T: Codable>(_ string: String, as type: T.Type) throws -> T {
        guard let bytes = Data(base64Encoded: string) else { throw BridgeError("共有データの形式が不正です。") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(RecordEnvelope<T>.self, from: bytes), envelope.version == 1 else { throw BridgeError("共有データの形式・バージョンに対応していません。") }
        return envelope.payload
    }
    static func catalog(from secrets: [String: String]) throws -> Catalog {
        var result = Catalog()
        for (name, value) in secrets {
            if name.hasPrefix(entryPrefix) {
                let item = try decode(value, as: KeyEntry.self)
                guard name == entryName(item.id) else { throw BridgeError("キーの識別情報が一致しません。") }
                result.entries.append(item)
            } else if name.hasPrefix(setPrefix) {
                let item = try decode(value, as: KeySet.self)
                guard name == setName(item.id) else { throw BridgeError("セットの識別情報が一致しません。") }
                result.sets.append(item)
            }
        }
        result.entries.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        result.sets.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return result
    }
}
