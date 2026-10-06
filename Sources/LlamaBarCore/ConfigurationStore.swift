import Foundation

/// Serializes bounded settings IO. Failed reads never trigger an automatic overwrite.
public actor ConfigurationStore {
    public let url: URL
    private var mayWrite = false
    private let maximumBytes = 1_048_576

    public init(url: URL) { self.url = url }

    // Preserve the established location so the rename retains existing model profiles.
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LlamaMenuBar/settings.json")
    }

    public func load() throws -> AppConfiguration {
        mayWrite = false
        guard FileManager.default.fileExists(atPath: url.path) else {
            mayWrite = true
            return AppConfiguration()
        }
        // Inspect size before allocating; preserve malformed or unsupported files in place.
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= maximumBytes else {
            throw AppFailure("Settings exceed 1 MiB. The original file has been preserved.")
        }
        let data = try readBounded()
        guard data.count <= maximumBytes else {
            throw AppFailure("Settings grew beyond 1 MiB during reading.")
        }
        let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)
        try configuration.validate()
        mayWrite = true
        return configuration
    }

    private func readBounded() throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        let data: Data
        do { data = try handle.read(upToCount: maximumBytes + 1) ?? Data() } catch {
            do { try handle.close() } catch let closeError {
                throw AppFailure(
                    "Reading settings failed: \(error.localizedDescription). Closing failed: \(closeError.localizedDescription)"
                )
            }
            throw error
        }
        try handle.close()
        return data
    }

    /// Atomically writes validated settings; requires a successful load or explicit recovery first.
    public func save(_ configuration: AppConfiguration) throws {
        guard mayWrite else { throw AppFailure("Recover the existing settings before saving changes.") }
        try configuration.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        guard data.count <= maximumBytes else { throw AppFailure("Settings exceed 1 MiB.") }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Moves unreadable settings to a unique backup and writes defaults only on explicit user action.
    public func recover() throws -> AppConfiguration {
        if FileManager.default.fileExists(atPath: url.path) {
            let backup = url.deletingLastPathComponent().appendingPathComponent(
                "settings-backup-\(UUID()).json")
            try FileManager.default.moveItem(at: url, to: backup)
        }
        mayWrite = true
        let defaults = AppConfiguration()
        try save(defaults)
        return defaults
    }
}
