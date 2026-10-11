import Foundation

protocol SecretRepository {
    func read() async throws -> [String: String]
    func write(name: String, value: String) async throws
    func delete(name: String) async throws
}

final class DopplerRepository: SecretRepository {
    private let project: String
    private let config: String
    private let token: String
    private let session: URLSession
    init(project: String, config: String, token: String, session: URLSession? = nil) {
        self.project = project; self.config = config; self.token = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 20
        self.session = session ?? URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
    }
    final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    private func request(method: String, name: String? = nil, value: String? = nil) async throws -> Data {
        guard !project.isEmpty, !config.isEmpty, !token.isEmpty else { throw BridgeError("設定画面でProject、Config、Tokenを登録してください。") }
        let path = method == "DELETE" ? "secret" : "secrets"
        var components = URLComponents(string: "https://api.doppler.com/v3/configs/config/\(path)")!
        if method != "POST" {
            components.queryItems = [.init(name: "project", value: project), .init(name: "config", value: config)]
            if let name { components.queryItems?.append(.init(name: "name", value: name)) }
            if method == "GET" { components.queryItems?.append(.init(name: "include_managed_secrets", value: "false")) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if method == "POST", let name, let value {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["project": project, "config": config, "secrets": [name: value]])
        }
        let data: Data; let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw BridgeError("Dopplerに接続できません。ネットワークを確認して再試行してください。") }
        guard let http = response as? HTTPURLResponse else { throw BridgeError("Dopplerの応答を確認できません。") }
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw BridgeError("Dopplerの認証に失敗しました。Tokenを確認してください。")
        case 403: throw BridgeError("操作する権限がありません。ConfigとTokenの読み書き権限を確認してください。")
        case 404: throw BridgeError("Project、Config、または対象キーが見つかりません。")
        case 429: throw BridgeError("Dopplerの利用制限に達しました。時間をおいて再試行してください。")
        default: throw BridgeError("Dopplerで処理できませんでした（HTTP \(http.statusCode)）。")
        }
    }
    func read() async throws -> [String: String] {
        let data = try await request(method: "GET")
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let items = root["secrets"] as? [String: Any] else { throw BridgeError("Dopplerの応答形式に対応していません。") }
        var result: [String: String] = [:]
        for (name, item) in items where name.hasPrefix("KEYBRIDGE_V1_") {
            guard let fields = item as? [String: Any], let raw = fields["raw"] as? String else { throw BridgeError("Dopplerのキー情報を読み取れません。") }
            result[name] = raw
        }
        return result
    }
    func write(name: String, value: String) async throws { _ = try await request(method: "POST", name: name, value: value) }
    func delete(name: String) async throws { _ = try await request(method: "DELETE", name: name) }
}

final class MemoryRepository: SecretRepository {
    var secrets: [String: String] = [:]
    func read() async throws -> [String: String] { secrets }
    func write(name: String, value: String) async throws { secrets[name] = value }
    func delete(name: String) async throws { secrets.removeValue(forKey: name) }
    static func demo() -> MemoryRepository {
        let repo = MemoryRepository()
        let a = KeyEntry(name: "Gemini・個人開発", service: "Gemini", variable: "GEMINI_API_KEY", value: "DEMO_NOT_A_REAL_KEY", notes: "自作の画像・動画スクリプト用", tags: ["画像", "個人"], url: "https://aistudio.google.com/apikey")
        let b = KeyEntry(name: "ElevenLabs・ナレーション", service: "ElevenLabs", variable: "ELEVENLABS_API_KEY", value: "DEMO_NOT_A_REAL_KEY", notes: "動画のナレーション生成", tags: ["音声", "動画"], url: "https://elevenlabs.io", expiresAt: Date().addingTimeInterval(5 * 86400))
        let set = KeySet(name: "制作・開発", entryIDs: [a.id, b.id])
        for e in [a, b] { repo.secrets[RecordCodec.entryName(e.id)] = try! RecordCodec.encode(e) }
        repo.secrets[RecordCodec.setName(set.id)] = try! RecordCodec.encode(set)
        return repo
    }
}
