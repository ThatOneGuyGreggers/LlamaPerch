import Foundation
#if canImport(CProcessSupport)
    import CProcessSupport
#endif

struct AppFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

/// A named local model and bounded CPU launch settings; removing it never removes the GGUF.
public struct ModelProfile: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var path: String
    public var context = 2048
    public var threads = 2
    public var batchThreads = 2
    public var notes = ""

    public init(name: String, path: String) { self.name = name; self.path = path }
}

/// Versioned global settings and up to 100 profiles, persisted only on explicit changes.
public struct AppConfiguration: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var executable = "/usr/local/bin/llama-server"
    public var port = 8080
    public var startupTimeout: Double = 300
    public var shutdownTimeout: Double = 5
    public var profiles: [ModelProfile] = []
    public var selectedID: UUID?

    public init() {}
    public var selectedProfile: ModelProfile? { profiles.first { $0.id == selectedID } }

    /// Checks stored bounds without requiring files to still exist. Throws a useful input error.
    public func validate() throws {
        guard schemaVersion == 1 else { throw AppFailure("Unsupported settings version: \(schemaVersion).") }
        guard (1024...65535).contains(port) else { throw AppFailure("Port must be between 1024 and 65535.") }
        guard startupTimeout.isFinite, (10...1800).contains(startupTimeout),
            shutdownTimeout.isFinite, (1...30).contains(shutdownTimeout)
        else {
            throw AppFailure(
                "Startup timeout must be 10–1800 seconds; shutdown timeout must be 1–30 seconds.")
        }
        guard executable.utf8.count <= 4096, profiles.count <= 100 else {
            throw AppFailure("Settings exceed the path or 100-profile limit.")
        }
        guard Set(profiles.map(\.id)).count == profiles.count else {
            throw AppFailure("Duplicate profile IDs.")
        }
        guard
            Set(
                profiles.map {
                    URL(fileURLWithPath: $0.path).standardizedFileURL.resolvingSymlinksInPath().path
                }
            ).count
                == profiles.count
        else {
            throw AppFailure("A model file is already registered. Edit its existing profile.")
        }
        guard selectedID == nil || selectedProfile != nil else {
            throw AppFailure("Selected model profile is missing.")
        }
        for profile in profiles { try profile.validate() }
    }
}

extension ModelProfile {
    public static var threadLimit: Int {
        let count = ProcessInfo.processInfo.activeProcessorCount
        return count > 0 ? count : 2
    }

    /// Validates profile metadata and numeric limits, without reading the model.
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            name.utf8.count <= 128, path.utf8.count <= 4096, notes.utf8.count <= 4096
        else {
            throw AppFailure(
                "Enter a model name (up to 128 bytes); paths and notes are limited to 4096 bytes.")
        }
        guard (512...8192).contains(context) else { throw AppFailure("Context must be 512–8192 tokens.") }
        guard (1...Self.threadLimit).contains(threads), (1...Self.threadLimit).contains(batchThreads) else {
            throw AppFailure("Thread counts must be 1–\(Self.threadLimit).")
        }
    }
}

public struct LaunchConfiguration: Sendable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let profile: ModelProfile
    public let port: Int
    public let startupTimeout: Double
    public let shutdownTimeout: Double

    /// Builds a CPU-only, single-slot invocation. Rejects invalid settings and inaccessible files.
    public init(
        settings: AppConfiguration, profile: ModelProfile,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        try settings.validate()
        try profile.validate()
        let executable = URL(fileURLWithPath: settings.executable)
        guard settings.executable.hasPrefix("/"),
            FileManager.default.isExecutableFile(atPath: executable.path),
            try executable.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey])
                .isRegularFile == true
        else {
            throw AppFailure("Choose a readable, executable llama-server file using its full path.")
        }
        let model = URL(fileURLWithPath: profile.path)
        guard profile.path.hasPrefix("/"), model.pathExtension.lowercased() == "gguf",
            FileManager.default.isReadableFile(atPath: model.path),
            try model.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile
                == true
        else {
            throw AppFailure("The GGUF file is missing or unreadable: \(profile.path)")
        }
        self.executable = executable
        self.profile = profile
        self.port = settings.port
        self.startupTimeout = settings.startupTimeout
        self.shutdownTimeout = settings.shutdownTimeout
        self.environment = environment.filter { !$0.key.hasPrefix("LLAMA_ARG_") }
        self.arguments = [
            "--model", model.path, "--host", "127.0.0.1", "--port", String(settings.port),
            "--ctx-size", String(profile.context), "--threads", String(profile.threads),
            "--threads-batch", String(profile.batchThreads), "--parallel", "1",
            "--n-gpu-layers", "0", "--device", "none", "--no-op-offload",
        ]
    }
}

/// Keeps numeric input as entered so an invalid edit cannot silently save the old value.
/// Drafts are separate from saved settings; profile validation still happens before persistence.
public struct SettingsDraft: Equatable, Sendable {
    public var settings: AppConfiguration
    public var port: String
    public var startupTimeout: String
    public var shutdownTimeout: String

    public init(settings: AppConfiguration) {
        self.settings = settings
        port = String(settings.port)
        startupTimeout = Self.display(settings.startupTimeout)
        shutdownTimeout = Self.display(settings.shutdownTimeout)
    }

    private static func display(_ number: Double) -> String {
        number.rounded() == number ? String(format: "%.0f", number) : String(number)
    }

    /// Parses entered numbers and checks their ranges. Throws without changing saved settings.
    public func configuration() throws -> AppConfiguration {
        guard let port = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)),
            (1024...65535).contains(port)
        else {
            throw AppFailure("Enter a port from 1024 to 65535.")
        }
        guard let startup = Double(startupTimeout.trimmingCharacters(in: .whitespacesAndNewlines)),
            startup.isFinite, (10...1800).contains(startup)
        else {
            throw AppFailure("Enter a startup timeout from 10 to 1800 seconds.")
        }
        guard let shutdown = Double(shutdownTimeout.trimmingCharacters(in: .whitespacesAndNewlines)),
            shutdown.isFinite, (1...30).contains(shutdown)
        else {
            throw AppFailure("Enter a shutdown timeout from 1 to 30 seconds.")
        }
        var result = settings
        result.port = port
        result.startupTimeout = startup
        result.shutdownTimeout = shutdown
        return result
    }
}
