import XCTest
@testable import KeyBridge

final class MCPMetadataTests: XCTestCase {
    func testExplicitMetadataAllowlistExcludesSecretAndFreeText() throws {
        let entry = KeyEntry(name: "Google AI Studio", service: "Gemini", variable: "GOOGLE_AI_S_KEY", value: "NEVER_EXPORT_THIS_SECRET", notes: "PRIVATE_MEMO", tags: ["TTS"], url: "https://example.com/private")
        let set = KeySet(name: "Normal", entryIDs: [entry.id])
        let applied = AppliedState(setID: set.id, values: [entry.variable: entry.value], previous: [:], set: set, entries: [entry])
        let metadata = MCPMetadata(catalog: Catalog(entries: [entry], sets: [set]), applied: applied)
        let data = try JSONEncoder().encode(metadata)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains(entry.value)); XCTAssertFalse(json.contains(entry.notes)); XCTAssertFalse(json.contains(entry.url))
        XCTAssertTrue(json.contains(entry.variable)); XCTAssertTrue(metadata.keys[0].matchesAppliedValue)
        var changed = entry; changed.value = "changed"
        XCTAssertFalse(MCPMetadata(catalog: Catalog(entries: [changed]), applied: applied).keys[0].matchesAppliedValue)
    }
    func testExpirationAndFilePermissionsAndDisable() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let publisher = MCPMetadataPublisher(directory: dir)
        let entry = KeyEntry(name: "expired", service: "service", variable: "TEST_KEY", value: "SECRET", expiresAt: .distantPast)
        let metadata = MCPMetadata(catalog: Catalog(entries: [entry]), applied: nil)
        XCTAssertTrue(metadata.keys[0].expired)
        try publisher.publish(metadata)
        let attrs = try FileManager.default.attributesOfItem(atPath: publisher.file.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let parentAttrs = try FileManager.default.attributesOfItem(atPath: dir.path)
        XCTAssertEqual((parentAttrs[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        try publisher.disable()
        XCTAssertFalse(FileManager.default.fileExists(atPath: publisher.file.path))
    }
}
