import Foundation

// Explicit allowlist: KeyEntry.value, notes, URL and Token never enter this DTO.
struct MCPKeyMetadata: Codable {
    var id: UUID
    var name: String
    var service: String
    var variable: String
    var environment: String
    var tags: [String]
    var expiresAt: Date?
    var expired: Bool
    var matchesAppliedValue: Bool
}

struct MCPSetMetadata: Codable {
    var id: UUID
    var name: String
    var entryIDs: [UUID]
    var selectedForMac: Bool
}

struct MCPMetadata: Codable {
    var version = 1
    var generatedAt: Date
    var keys: [MCPKeyMetadata]
    var sets: [MCPSetMetadata]
    init(catalog: Catalog, applied: AppliedState?, now: Date = Date()) {
        generatedAt = now
        keys = catalog.entries.map { entry in
            MCPKeyMetadata(id: entry.id, name: entry.name, service: entry.service,
                           variable: entry.variable, environment: entry.environment, tags: entry.tags,
                           expiresAt: entry.expiresAt, expired: entry.expiresAt.map { $0 <= now } ?? false,
                           matchesAppliedValue: applied?.set.entryIDs.contains(entry.id) == true && applied?.values[entry.variable] == entry.value)
        }
        sets = catalog.sets.map { MCPSetMetadata(id: $0.id, name: $0.name, entryIDs: $0.entryIDs, selectedForMac: applied?.setID == $0.id) }
    }
}

struct MCPMetadataPublisher {
    let directory: URL
    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("KeyBridge", isDirectory: true)) {
        self.directory = directory
    }
    var file: URL { directory.appendingPathComponent("mcp-catalog.json") }
    func publish(_ metadata: MCPMetadata) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(metadata).write(to: file, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    func disable() throws {
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}
