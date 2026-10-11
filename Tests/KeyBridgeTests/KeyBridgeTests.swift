import XCTest
@testable import KeyBridge

final class KeyBridgeTests: XCTestCase {
    func key(_ name: String = "GEMINI_API_KEY", value: String = "fake-value") -> KeyEntry { KeyEntry(name: "テスト用", service: "Gemini", variable: name, value: value) }
    func testEnvironmentNamesRejectInjectionAndRuntimeOverrides() throws {
        for name in ["PATH", "HOME", "DYLD_INSERT_LIBRARIES", "DOPPLER_TOKEN", "NODE_OPTIONS", "PYTHONPATH", "BAD;COMMAND", "1KEY", "KEYBRIDGE_V1_ENTRY_X"] { XCTAssertThrowsError(try EnvironmentRules.validate(name)) }
        try EnvironmentRules.validate("GEMINI_API_KEY"); try EnvironmentRules.validate("ELEVENLABS_API_KEY")
    }
    func testEntryValidationAndExpiry() throws {
        var entry = key(); try entry.validate()
        entry.value = ""; XCTAssertThrowsError(try entry.validate())
        entry.value = "abc\0def"; XCTAssertThrowsError(try entry.validate())
        entry.value = "line1\nline2"; try entry.validate()
        entry.url = "file:///tmp/a"; XCTAssertThrowsError(try entry.validate())
        entry.url = "https://example.com"; entry.expiresAt = Date(timeIntervalSince1970: 1)
        XCTAssertThrowsError(try KeySet(name: "expired", entryIDs: [entry.id]).resolve(in: [entry]))
    }
    func testSetMissingAndDuplicateKeysAreRejected() throws {
        let a = key(); let b = key()
        XCTAssertThrowsError(try KeySet(name: "dup", entryIDs: [a.id, b.id]).resolve(in: [a, b]))
        XCTAssertThrowsError(try KeySet(name: "missing", entryIDs: [UUID()]).resolve(in: []))
        XCTAssertThrowsError(try KeySet(name: "empty").resolve(in: []))
        XCTAssertEqual(try KeySet(name: "ok", entryIDs: [a.id]).resolve(in: [a]), ["GEMINI_API_KEY": "fake-value"])
    }
    func testRecordsRoundTripWithoutReferenceExpansion() throws {
        var entry = key(value: "${OTHER_SECRET}\n日本語"); entry.createdAt = Date(timeIntervalSince1970: 10); entry.updatedAt = entry.createdAt
        let encoded = try RecordCodec.encode(entry)
        XCTAssertFalse(encoded.contains("${"))
        XCTAssertEqual(try RecordCodec.decode(encoded, as: KeyEntry.self), entry)
        let catalog = try RecordCodec.catalog(from: [RecordCodec.entryName(entry.id): encoded, "UNRELATED_SECRET": "leave-alone"])
        XCTAssertEqual(catalog.entries, [entry])
        XCTAssertThrowsError(try RecordCodec.catalog(from: [RecordCodec.entryName(UUID()): encoded]))
        XCTAssertThrowsError(try RecordCodec.decode("garbage", as: KeyEntry.self))
    }
    func testSetSwitchRestoresRemovedVariablesAndClearRestoresOriginal() throws {
        let backend = MemoryEnvironment(); backend.values = ["GEMINI_API_KEY": "original", "UNRELATED": "stay"]
        let vault = MemoryVault(); let env = EnvironmentController(backend: backend, vault: vault)
        let a = key(); let b = key("ELEVENLABS_API_KEY", value: "voice")
        _ = try env.apply(set: KeySet(name: "A", entryIDs: [a.id]), entries: [a])
        XCTAssertEqual(backend.values["GEMINI_API_KEY"], a.value)
        _ = try env.apply(set: KeySet(name: "B", entryIDs: [b.id]), entries: [b])
        XCTAssertEqual(backend.values["GEMINI_API_KEY"], "original")
        XCTAssertEqual(backend.values["ELEVENLABS_API_KEY"], "voice")
        try env.clear()
        XCTAssertNil(backend.values["ELEVENLABS_API_KEY"])
        XCTAssertEqual(backend.values["UNRELATED"], "stay")
        XCTAssertNil(vault.state)
    }
    func testReapplyKeepsOriginalBaseline() throws {
        let backend = MemoryEnvironment(); backend.values["GEMINI_API_KEY"] = "original"
        let env = EnvironmentController(backend: backend, vault: MemoryVault())
        var entry = key(); let set = KeySet(name: "set", entryIDs: [entry.id])
        _ = try env.apply(set: set, entries: [entry]); entry.value = "changed"
        _ = try env.apply(set: set, entries: [entry]); try env.clear()
        XCTAssertEqual(backend.values["GEMINI_API_KEY"], "original")
    }
    func testExternalChangesAreNeverOverwrittenDuringClearOrSwitch() throws {
        let backend = MemoryEnvironment(); let env = EnvironmentController(backend: backend, vault: MemoryVault())
        let entry = key(); let set = KeySet(name: "set", entryIDs: [entry.id])
        _ = try env.apply(set: set, entries: [entry]); backend.values[entry.variable] = "external"
        XCTAssertThrowsError(try env.clear())
        XCTAssertThrowsError(try env.apply(set: set, entries: [entry]))
        XCTAssertEqual(backend.values[entry.variable], "external")
    }
    func testPartialFailureRollsBackAndKeepsPreviousState() throws {
        let backend = FaultEnvironment(); let vault = MemoryVault(); let env = EnvironmentController(backend: backend, vault: vault)
        let a = key("A_API_KEY"); let b = key("B_API_KEY")
        backend.values = [a.variable: "original"]
        backend.failOnCall = 2
        XCTAssertThrowsError(try env.apply(set: KeySet(name: "set", entryIDs: [a.id, b.id]), entries: [a, b]))
        XCTAssertEqual(backend.values, [a.variable: "original"])
        XCTAssertNil(vault.state)
    }
    func testRollbackFailureReportsRecoveryRequired() throws {
        let backend = FaultEnvironment(); let vault = MemoryVault(); let env = EnvironmentController(backend: backend, vault: vault)
        let a = key("A_API_KEY"); let b = key("B_API_KEY")
        backend.failOnCall = 2; backend.alwaysFailAfter = true
        XCTAssertThrowsError(try env.apply(set: KeySet(name: "set", entryIDs: [a.id, b.id]), entries: [a, b])) { error in XCTAssertTrue(error.localizedDescription.contains("復旧")) }
        XCTAssertNotNil(vault.state)
    }
    func testPreviousLoginStateIsDiscardedWhenEnvironmentIsEmpty() throws {
        let backend = MemoryEnvironment(); let vault = MemoryVault(); let env = EnvironmentController(backend: backend, vault: vault)
        let a = key(); _ = try env.apply(set: KeySet(name: "set", entryIDs: [a.id]), entries: [a])
        backend.values = [:]
        XCTAssertNil(try env.current()); XCTAssertNil(vault.state)
    }
    func testDopplerReadWriteDeleteRequests() async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockHTTP.self]
        let session = URLSession(configuration: configuration)
        let repo = DopplerRepository(project: "project", config: "dev", token: "fake-test-token", session: session)
        MockHTTP.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fake-test-token")
            XCTAssertEqual(request.url?.host, "api.doppler.com")
            switch request.httpMethod {
            case "GET": return (200, Data("{\"secrets\":{\"KEYBRIDGE_V1_TEST\":{\"raw\":\"encoded\"},\"OTHER\":{\"raw\":\"ignore\"}}}".utf8))
            case "POST":
                let body = try JSONSerialization.jsonObject(with: bodyData(request)) as! [String: Any]
                XCTAssertEqual(body["project"] as? String, "project")
                XCTAssertEqual(body["secrets"] as? [String: String], ["KEYBRIDGE_V1_TEST": "encoded"])
                return (200, Data("{}".utf8))
            case "DELETE":
                XCTAssertEqual(request.url?.path, "/v3/configs/config/secret")
                XCTAssertTrue(request.url!.query!.contains("name=KEYBRIDGE_V1_TEST"))
                return (204, Data())
            default: throw BridgeError("unexpected method")
            }
        }
        let result = try await repo.read(); XCTAssertEqual(result, ["KEYBRIDGE_V1_TEST": "encoded"])
        try await repo.write(name: "KEYBRIDGE_V1_TEST", value: "encoded"); try await repo.delete(name: "KEYBRIDGE_V1_TEST")
    }
    @MainActor func testNormalStartupWithoutConnectionDoesNotCrash() throws {
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "dev.keybridge.test." + UUID().uuidString))
        let controller = EnvironmentController(backend: MemoryEnvironment(), vault: MemoryVault())
        let store = AppStore(demo: false, localDefaults: preferences, environmentOverride: controller)
        XCTAssertFalse(store.demo)
        XCTAssertNil(store.error)
        XCTAssertTrue(store.catalog.entries.isEmpty)
        XCTAssertEqual(store.stateLabel, "未適用")
    }
    @MainActor func testEditingRemoteChangedRecordStopsBeforeWrite() async throws {
        let repository = MemoryRepository()
        var original = key(); original.createdAt = Date(timeIntervalSince1970: 10); original.updatedAt = original.createdAt
        repository.secrets[RecordCodec.entryName(original.id)] = try RecordCodec.encode(original)
        let store = AppStore(demo: true, repositoryOverride: repository)
        try await store.refresh()
        var remote = original; remote.value = "changed-on-other-mac"
        repository.secrets[RecordCodec.entryName(original.id)] = try RecordCodec.encode(remote)
        var local = original; local.name = "local edit"
        do { try await store.saveEntry(local, original: original); XCTFail("conflict must stop write") }
        catch { XCTAssertTrue(error.localizedDescription.contains("別のMac")) }
        let saved = try RecordCodec.decode(repository.secrets[RecordCodec.entryName(original.id)]!, as: KeyEntry.self)
        XCTAssertEqual(saved.value, remote.value)
    }
    @MainActor func testSavingDoesNotReapplyEnvironment() async throws {
        let repository = MemoryRepository()
        var original = key(); original.createdAt = Date(timeIntervalSince1970: 10); original.updatedAt = original.createdAt
        let set = KeySet(name: "demo", entryIDs: [original.id], updatedAt: original.updatedAt)
        repository.secrets[RecordCodec.entryName(original.id)] = try RecordCodec.encode(original)
        repository.secrets[RecordCodec.setName(set.id)] = try RecordCodec.encode(set)
        let store = AppStore(demo: true, repositoryOverride: repository)
        try await store.apply(set.id)
        var changed = original; changed.value = "new-value"
        try await store.saveEntry(changed, original: original)
        XCTAssertEqual(store.applied?.values[original.variable], original.value)
        XCTAssertEqual(store.stateLabel, "再適用が必要")
        try await store.apply(set.id)
        XCTAssertEqual(store.applied?.values[original.variable], changed.value)
        try store.clear(); XCTAssertNil(store.applied)
    }
    func testLiveLaunchEnvironmentWithDisposableValue() throws {
        guard ProcessInfo.processInfo.environment["KEYBRIDGE_RUN_SYSTEM_TESTS"] == "1" else { throw XCTSkip("Run explicitly to test launchctl with disposable values") }
        let backend = LaunchEnvironment()
        let name = "KB_TEST_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let before = try backend.get(name)
        defer { try? backend.set(name, value: before) }
        try backend.set(name, value: "fake-integration-value")
        XCTAssertEqual(try backend.get(name), "fake-integration-value")
        try backend.set(name, value: nil)
        XCTAssertNil(try backend.get(name))
    }

    func testAPIErrorDoesNotExposeServerResponseOrToken() async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockHTTP.self]
        let repo = DopplerRepository(project: "p", config: "c", token: "sensitive-fake", session: URLSession(configuration: configuration))
        MockHTTP.handler = { _ in (403, Data("sensitive-fake PRIVATE_PAYLOAD".utf8)) }
        do { _ = try await repo.read(); XCTFail("must fail") } catch {
            XCTAssertFalse(error.localizedDescription.contains("sensitive-fake"))
            XCTAssertFalse(error.localizedDescription.contains("PRIVATE_PAYLOAD"))
        }
    }
}

final class FaultEnvironment: EnvironmentBackend {
    var values: [String: String] = [:]
    var calls = 0
    var failOnCall = Int.max
    var alwaysFailAfter = false
    func get(_ name: String) throws -> String? { values[name] }
    func set(_ name: String, value: String?) throws {
        calls += 1
        if calls == failOnCall || (alwaysFailAfter && calls > failOnCall) { throw BridgeError("test fault") }
        values[name] = value
    }
}

final class MockHTTP: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

private func bodyData(_ request: URLRequest) -> Data {
    if let data = request.httpBody { return data }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open(); defer { stream.close() }
    var result = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; result.append(buffer, count: count) }
    return result
}
