import Darwin
import Foundation
import XCTest
#if canImport(LlamaMenuCore)
    @testable import LlamaMenuCore
#endif
#if canImport(CProcessSupport)
    import CProcessSupport
#endif

@MainActor
final class LifecycleTests: XCTestCase {
    private func setup(_ mode: String) throws -> (URL, AppConfiguration, ModelProfile) {
        let folder = try TestFiles.folder()
        let executable = folder.appendingPathComponent("fixture server")
        try FileManager.default.copyItem(at: TestFiles.fixture, to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let model = folder.appendingPathComponent("\(mode).gguf")
        try Data("GGUF".utf8).write(to: model)
        var settings = AppConfiguration()
        settings.executable = executable.path
        settings.startupTimeout = 10
        settings.shutdownTimeout = 1
        // Pick an unused candidate; production launch still checks for a racing listener.
        settings.port = try XCTUnwrap((19080..<19180).first { llama_check_port(UInt16($0)) == 0 })
        let profile = ModelProfile(name: mode, path: model.path)
        settings.profiles = [profile]
        settings.selectedID = profile.id
        return (folder, settings, profile)
    }

    private func wait(_ controller: ServerController, state: ServerState, timeout: Double = 15) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while controller.state != state && ProcessInfo.processInfo.systemUptime < deadline {
            if controller.state == .failed && state != .failed { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(controller.state, state, controller.errorMessage ?? controller.logs)
    }

    func testRealModelWhenRequested() async throws {
        guard let path = ProcessInfo.processInfo.environment["LLAMA_SMOKE_MODEL"] else {
            throw XCTSkip("Set LLAMA_SMOKE_MODEL to opt into a real CPU model test.")
        }
        var settings = AppConfiguration()
        settings.port = try XCTUnwrap((19280..<19380).first { llama_check_port(UInt16($0)) == 0 })
        let profile = ModelProfile(name: "Real model", path: path)
        settings.profiles = [profile]
        settings.selectedID = profile.id
        let controller = ServerController()
        let started = ProcessInfo.processInfo.systemUptime
        controller.start(settings: settings, profile: profile)
        try await wait(controller, state: .running, timeout: 310)
        guard controller.state == .running else { _ = await controller.stop(); return }
        let startupSeconds = ProcessInfo.processInfo.systemUptime - started
        do {
            try await recordCompletion(
                controller, port: settings.port, path: path, startupSeconds: startupSeconds)
        } catch {
            _ = await controller.stop()
            throw error
        }
        let stopped = await controller.stop()
        XCTAssertTrue(stopped)
        XCTAssertFalse(controller.hasOwnedChild)
        // A second load proves restart against the real executable, rather than only a fixture.
        controller.start(settings: settings, profile: profile)
        try await wait(controller, state: .running, timeout: 310)
        _ = await controller.stop()
        XCTAssertFalse(controller.hasOwnedChild)
    }

    private func recordCompletion(
        _ controller: ServerController, port: Int, path: String,
        startupSeconds: Double
    ) async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "prompt": "The capital of France is", "max_tokens": 8, "temperature": 0, "stream": false,
        ])
        let requestStart = ProcessInfo.processInfo.systemUptime
        let (body, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual(
            (response as? HTTPURLResponse)?.statusCode, 200, String(decoding: body, as: UTF8.self))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let choices = try XCTUnwrap(payload["choices"] as? [[String: Any]])
        XCTAssertFalse((choices.first?["text"] as? String ?? "").isEmpty)
        let report: [String: Any] = [
            "model": path, "version": controller.version,
            "startupSeconds": startupSeconds,
            "requestSeconds": ProcessInfo.processInfo.systemUptime - requestStart,
            "response": payload,
            "settings": ["context": 2048, "threads": 2, "batchThreads": 2, "slots": 1, "gpuLayers": 0],
        ]
        if let directory = ProcessInfo.processInfo.environment["LLAMA_SMOKE_OUTPUT"] {
            let folder = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: folder.appendingPathComponent("smoke.json"), options: .atomic)
            try controller.logs.write(
                to: folder.appendingPathComponent("server.log"), atomically: true, encoding: .utf8)
        }
        print("REAL MODEL: startup \(startupSeconds)s; response \(String(decoding: body, as: UTF8.self))")
    }

    func testDelayedReadinessRestartAndTwoModels() async throws {
        let (folder, settings, profile) = try setup("delay")
        defer { TestFiles.remove(folder) }
        let controller = ServerController()
        controller.start(settings: settings, profile: profile)
        XCTAssertEqual(controller.state, .starting)
        controller.start(settings: settings, profile: profile)
        try await wait(controller, state: .running)
        XCTAssertEqual(controller.runningProfileID, profile.id)
        let healthy = try await HealthMonitor.isReady(port: settings.port)
        XCTAssertTrue(healthy)
        let stopped = await controller.stop()
        XCTAssertTrue(stopped)
        XCTAssertFalse(controller.hasOwnedChild)
        var second = profile
        second.id = UUID()
        second.name = "Second"
        controller.start(settings: settings, profile: second)
        try await wait(controller, state: .running)
        XCTAssertEqual(controller.runningProfileID, second.id)
        _ = await controller.stop()
    }

    func testEarlyExitAndCancellationLeaveNoChild() async throws {
        let (folder, settings, profile) = try setup("early-exit")
        defer { TestFiles.remove(folder) }
        let controller = ServerController()
        controller.start(settings: settings, profile: profile)
        try await wait(controller, state: .failed)
        XCTAssertFalse(controller.hasOwnedChild)
        XCTAssertTrue(controller.logs.contains("rejected model"))
        controller.start(settings: settings, profile: profile)
        let stopped = await controller.stop()
        XCTAssertTrue(stopped)
        XCTAssertEqual(controller.state, .stopped)
        XCTAssertFalse(controller.hasOwnedChild)
    }

    func testIgnoredTerminationIsForcedAndFloodDoesNotBlockStartup() async throws {
        let (folder, settings, profile) = try setup("flood-ignore-term")
        defer { TestFiles.remove(folder) }
        let controller = ServerController()
        controller.start(settings: settings, profile: profile)
        try await wait(controller, state: .running, timeout: 15)
        let stopped = await controller.stop()
        XCTAssertTrue(stopped)
        XCTAssertFalse(controller.hasOwnedChild)
        XCTAssertLessThanOrEqual(controller.logs.utf8.count, LogBuffer.byteLimit)
    }

    func testPortConflictDoesNotKillUnrelatedServer() async throws {
        let (folder, settings, profile) = try setup("normal")
        defer { TestFiles.remove(folder) }
        let launch = try LaunchConfiguration(settings: settings, profile: profile)
        let unrelated = ManagedChild(
            executable: launch.executable, arguments: launch.arguments,
            environment: launch.environment, buffer: LogBuffer())
        try unrelated.launch()
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while llama_owns_listener(unrelated.process.processIdentifier, UInt16(settings.port)) != 1
            && ProcessInfo.processInfo.systemUptime < deadline
        {
            await pauseForCleanup()
        }
        let controller = ServerController()
        controller.start(settings: settings, profile: profile)
        try await wait(controller, state: .failed)
        XCTAssertTrue(unrelated.process.isRunning)
        XCTAssertFalse(controller.hasOwnedChild)
        XCTAssertTrue(controller.errorMessage?.contains("unavailable") == true)
        let stopped = await unrelated.stop(grace: 1)
        XCTAssertTrue(stopped)
    }

    func testSmallOutputAppearsBeforeExitAndUnexpectedExitIsReaped() async throws {
        let (folder, settings, profile) = try setup("normal")
        defer { TestFiles.remove(folder) }
        let controller = ServerController()
        controller.start(settings: settings, profile: profile)
        try await wait(controller, state: .running)
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while !controller.logs.contains("fixture: listening")
            && ProcessInfo.processInfo.systemUptime < deadline
        {
            await pauseForCleanup()
        }
        XCTAssertTrue(controller.logs.contains("fixture: listening"))
        let pid = try XCTUnwrap(controller.ownedProcessID)
        XCTAssertEqual(kill(pid, SIGTERM), 0)
        try await wait(controller, state: .failed)
        XCTAssertFalse(controller.hasOwnedChild)
    }

    func testRacingListenerCannotMakeAChildWithoutASocketReady() async throws {
        let (folder, settings, profile) = try setup("no-listener")
        defer { TestFiles.remove(folder) }
        let controller = ServerController()
        controller.start(settings: settings, profile: profile)
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while controller.ownedProcessID == nil && ProcessInfo.processInfo.systemUptime < deadline {
            await pauseForCleanup()
        }
        var other = profile
        other.path = folder.appendingPathComponent("normal.gguf").path
        try Data("GGUF".utf8).write(to: URL(fileURLWithPath: other.path))
        let launch = try LaunchConfiguration(settings: settings, profile: other)
        let listener = ManagedChild(
            executable: launch.executable, arguments: launch.arguments,
            environment: launch.environment, buffer: LogBuffer())
        try listener.launch()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(controller.state, .starting)
        XCTAssertNil(controller.runningProfileID)
        let stopped = await controller.stop()
        XCTAssertTrue(stopped)
        XCTAssertTrue(listener.process.isRunning)
        let listenerStopped = await listener.stop(grace: 1)
        XCTAssertTrue(listenerStopped)
    }

    func testStartupTimeoutAndOversizedHealthResponseCleanUp() async throws {
        for mode in ["loading", "oversized"] {
            let (folder, settings, profile) = try setup(mode)
            let controller = ServerController()
            controller.start(settings: settings, profile: profile)
            try await wait(controller, state: .failed, timeout: 15)
            XCTAssertFalse(controller.hasOwnedChild)
            XCTAssertTrue(controller.errorMessage?.contains("timed out") == true)
            TestFiles.remove(folder)
        }
    }
}
