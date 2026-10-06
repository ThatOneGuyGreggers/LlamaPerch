import Darwin
import Foundation

/// Owns one child and both pipe readers. All process transitions run on the main actor.
@MainActor
final class ManagedChild {
    let process = Process()
    let buffer: LogBuffer
    private let output: PipeReader
    private let errors: PipeReader

    init(executable: URL, arguments: [String], environment: [String: String], buffer: LogBuffer) {
        self.buffer = buffer
        output = PipeReader(buffer: buffer, channel: "stdout")
        errors = PipeReader(buffer: buffer, channel: "stderr")
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output.pipe
        process.standardError = errors.pipe
    }

    func launch() throws {
        // Closing the parent's writers also guarantees EOF if launch fails.
        defer { output.closeWriter(); errors.closeWriter() }
        try process.run()
    }

    /// Requests termination, escalates only this owned child, and waits for exit and pipe EOF.
    /// Returns false on unresolved cleanup; the caller must retain this instance and block relaunch.
    func stop(grace: Double) async -> Bool {
        if process.isRunning { process.terminate() }
        await waitForExit(seconds: grace)
        if process.isRunning {
            if kill(process.processIdentifier, SIGKILL) != 0 && errno != ESRCH {
                buffer.note("Force termination failed: \(String(cString: strerror(errno)))")
            }
            await waitForExit(seconds: 5)
        }
        guard !process.isRunning else { return false }
        // Pipe readers normally finish at exit; do not release them while a writer remains open.
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while (!output.isFinished || !errors.isFinished) && ProcessInfo.processInfo.systemUptime < deadline {
            await pauseForCleanup()
        }
        return output.isFinished && errors.isFinished
    }

    private func waitForExit(seconds: Double) async {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { await pauseForCleanup() }
    }
}

/// Cleanup must finish even when the initiating task was cancelled.
func pauseForCleanup() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { continuation.resume() }
    }
}

@MainActor
struct ServerProbe {
    static let requiredFlags = [
        "--model", "--host", "--port", "--ctx-size", "--threads",
        "--threads-batch", "--parallel", "--n-gpu-layers", "--device", "--no-op-offload",
    ]

    /// Runs bounded probes and returns version diagnostics. Cancellation terminates and reaps the probe.
    static func validate(_ configuration: LaunchConfiguration, onChild: (ManagedChild?) -> Void) async throws
        -> String
    {
        let version = try await run(configuration, flag: "--version", onChild: onChild)
        let help = try await run(configuration, flag: "--help", onChild: onChild)
        let missing = requiredFlags.filter { !help.contains($0) }
        guard missing.isEmpty else {
            throw AppFailure("This server lacks required options: \(missing.joined(separator: ", ")).")
        }
        return version
    }

    private static func run(
        _ configuration: LaunchConfiguration, flag: String, onChild: (ManagedChild?) -> Void
    ) async throws -> String {
        let buffer = LogBuffer(inputLimit: 262_144)
        let child = ManagedChild(
            executable: configuration.executable, arguments: [flag],
            environment: configuration.environment, buffer: buffer)
        onChild(child)
        try child.launch()
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while child.process.isRunning && !Task.isCancelled && !buffer.overflowed
            && ProcessInfo.processInfo.systemUptime < deadline
        {
            await pauseForCleanup()
        }
        let wasRunning = child.process.isRunning
        let cleaned = await child.stop(grace: 0.2)
        guard cleaned else {
            throw AppFailure(
                "The \(flag) probe could not finish cleanup. Quit and inspect the server executable.")
        }
        onChild(nil)
        try Task.checkCancellation()
        guard !wasRunning, !buffer.overflowed else {
            throw AppFailure("The \(flag) probe exceeded 10 seconds or 256 KiB of output.")
        }
        guard child.process.terminationStatus == 0 else {
            throw AppFailure("The \(flag) probe failed: \(buffer.snapshot())")
        }
        return buffer.snapshot()
    }
}
