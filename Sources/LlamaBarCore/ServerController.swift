import Combine
import Foundation
#if canImport(CProcessSupport)
    import CProcessSupport
#endif

public enum ServerState: String, Sendable {
    case stopped = "Stopped", starting = "Starting", running = "Running", stopping = "Stopping", failed =
        "Failed"
}

/// Main-actor process owner. Starts never queue; Stop cancels startup before releasing any child.
@MainActor
public final class ServerController: ObservableObject {
    @Published public private(set) var state: ServerState = .stopped
    @Published public private(set) var runningProfileID: UUID?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var logs = ""
    @Published public private(set) var version = "Not checked"
    @Published public private(set) var activePort: Int?
    private var child: ManagedChild?
    private var probeChild: ManagedChild?
    private var buffer = LogBuffer()
    private var generation = UUID()
    private var startup: Task<Void, Never>?
    private var monitoring: Task<Void, Never>?
    private var publishing: Task<Void, Never>?
    private var shutdownTimeout: Double = 5

    public init() {}
    public var ownedProcessID: Int32? { child?.process.processIdentifier }
    public var hasOwnedChild: Bool { child != nil || probeChild != nil }
    public var isBusy: Bool { state == .starting || state == .stopping }
    public var canStart: Bool { child == nil && probeChild == nil && startup == nil && state != .stopping }

    /// Starts validation and loading asynchronously; rejects another launch until cleanup completes.
    public func start(settings: AppConfiguration, profile: ModelProfile) {
        guard canStart else { return }
        let identifier = UUID()
        generation = identifier
        state = .starting
        errorMessage = nil
        buffer = LogBuffer()
        logs = ""
        beginPublishing()
        startup = Task {
            do {
                let configuration = try await Task.detached {
                    try LaunchConfiguration(settings: settings, profile: profile)
                }.value
                try Task.checkCancellation()
                version = try await ServerProbe.validate(configuration, onChild: { self.probeChild = $0 })
                try Task.checkCancellation()
                try await launch(configuration, identifier: identifier)
            } catch {
                guard generation == identifier else { return }
                await fail("Could not start server: \(error.localizedDescription)")
            }
            if generation == identifier { startup = nil }
        }
    }

    private func launch(_ configuration: LaunchConfiguration, identifier: UUID) async throws {
        let portError = llama_check_port(UInt16(configuration.port))
        guard portError == 0 else {
            throw AppFailure(
                "Port \(configuration.port) is unavailable (system error \(portError)). Choose another port.")
        }
        let owned = ManagedChild(
            executable: configuration.executable, arguments: configuration.arguments,
            environment: configuration.environment, buffer: buffer)
        child = owned
        shutdownTimeout = configuration.shutdownTimeout
        activePort = configuration.port
        buffer.note("Launching \(configuration.executable.path) with \(configuration.arguments)")
        try owned.launch()
        try await waitUntilReady(owned, configuration: configuration)
        guard generation == identifier else { throw CancellationError() }
        state = .running
        runningProfileID = configuration.profile.id
        buffer.note("Server is ready at http://127.0.0.1:\(configuration.port)/v1")
        beginMonitoring(owned, port: configuration.port, identifier: identifier)
    }

    private func waitUntilReady(_ owned: ManagedChild, configuration: LaunchConfiguration) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + configuration.startupTimeout
        var lastHealthError = "The model is still loading."
        while ProcessInfo.processInfo.systemUptime < deadline {
            try Task.checkCancellation()
            guard owned.process.isRunning else {
                throw AppFailure("Server exited with code \(owned.process.terminationStatus). See logs.")
            }
            let ownership = llama_owns_listener(owned.process.processIdentifier, UInt16(configuration.port))
            guard ownership >= 0 else {
                throw AppFailure("Cannot verify ownership of the server's listening socket.")
            }
            if ownership == 1 {
                do {
                    if try await HealthMonitor.isReady(port: configuration.port), owned.process.isRunning,
                        llama_owns_listener(owned.process.processIdentifier, UInt16(configuration.port)) == 1
                    {
                        return
                    }
                } catch { lastHealthError = error.localizedDescription }
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw AppFailure("Startup timed out. \(lastHealthError)")
    }

    private func beginMonitoring(_ owned: ManagedChild, port: Int, identifier: UUID) {
        monitoring = Task {
            var failures = 0
            // This loop belongs to one live launch and ends on cancellation or a failed check.
            while !Task.isCancelled && generation == identifier {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    guard owned.process.isRunning else {
                        throw AppFailure(
                            "Server exited unexpectedly (code \(owned.process.terminationStatus)).")
                    }
                    guard llama_owns_listener(owned.process.processIdentifier, UInt16(port)) == 1 else {
                        throw AppFailure("The managed server no longer owns its listening socket.")
                    }
                    guard try await HealthMonitor.isReady(port: port) else {
                        throw AppFailure("The server is not ready.")
                    }
                    failures = 0
                } catch {
                    if Task.isCancelled || generation != identifier { return }
                    failures += 1
                    buffer.note("Health check failed: \(error.localizedDescription)")
                    if !owned.process.isRunning || failures >= 3 {
                        await fail(error.localizedDescription)
                        return
                    }
                }
            }
        }
    }

    private func beginPublishing() {
        publishing?.cancel()
        publishing = Task {
            while !Task.isCancelled {
                logs = buffer.snapshot()
                if let child, !child.process.isRunning, state == .running {
                    await fail("Server exited unexpectedly (code \(child.process.terminationStatus)).")
                }
                await pauseForUI()
            }
        }
    }

    private func fail(_ message: String) async {
        errorMessage = message
        buffer.note(message)
        state = .stopping
        monitoring?.cancel()
        let cleaned = await cleanChild()
        state = .failed
        if !cleaned { errorMessage = "\(message) Cleanup is incomplete; use Stop again before restarting." }
        finishPublishing()
    }

    /// Cancels startup, terminates the child, and returns true only after exit and log EOF.
    public func stop() async -> Bool {
        guard state != .stopping else { return false }
        generation = UUID()
        state = .stopping
        startup?.cancel()
        monitoring?.cancel()
        await startup?.value
        startup = nil
        let cleaned = await cleanChild()
        state = cleaned ? .stopped : .failed
        errorMessage =
            cleaned ? nil : "Server cleanup is incomplete. Stop again before starting another server."
        finishPublishing()
        return cleaned
    }

    private func cleanChild() async -> Bool {
        if let probeChild {
            guard await probeChild.stop(grace: 0.2) else { return false }
            self.probeChild = nil
        }
        guard let child else { return true }
        guard await child.stop(grace: shutdownTimeout) else { return false }
        self.child = nil
        runningProfileID = nil
        activePort = nil
        return true
    }

    private func finishPublishing() {
        logs = buffer.snapshot()
        publishing?.cancel()
        publishing = nil
    }
}

private func pauseForUI() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { continuation.resume() }
    }
}
