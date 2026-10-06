import Foundation
import XCTest
#if canImport(LlamaPerchCore)
    @testable import LlamaPerchCore
#endif

final class ConfigurationTests: XCTestCase {
    func testLaunchArgumentsKeepPathsAsSingleValuesAndDisableOffload() throws {
        let folder = try TestFiles.folder()
        defer { TestFiles.remove(folder) }
        let model = folder.appendingPathComponent("模型 with spaces.gguf")
        try Data("GGUF".utf8).write(to: model)
        let profile = ModelProfile(name: "Small", path: model.path)
        var settings = AppConfiguration()
        settings.executable = TestFiles.fixture.path
        let launch = try LaunchConfiguration(
            settings: settings, profile: profile,
            environment: ["LLAMA_ARG_HOST": "0.0.0.0", "LLAMA_ARG_REUSE_PORT": "1", "PATH": "/usr/bin"])
        XCTAssertEqual(launch.arguments[1], model.path)
        XCTAssertEqual(launch.environment, ["PATH": "/usr/bin"])
        XCTAssertTrue(launch.arguments.contains("--no-op-offload"))
        let slots = try XCTUnwrap(launch.arguments.firstIndex(of: "--parallel"))
        XCTAssertEqual(launch.arguments[slots + 1], "1")
        let gpu = try XCTUnwrap(launch.arguments.firstIndex(of: "--n-gpu-layers"))
        XCTAssertEqual(launch.arguments[gpu + 1], "0")
    }

    func testSymlinkedModelsAndExecutablesAreAccepted() throws {
        let folder = try TestFiles.folder()
        defer { TestFiles.remove(folder) }
        let blob = folder.appendingPathComponent("cached-blob")
        let model = folder.appendingPathComponent("cached-model.gguf")
        let executable = folder.appendingPathComponent("llama-server")
        try Data("GGUF".utf8).write(to: blob)
        try FileManager.default.createSymbolicLink(at: model, withDestinationURL: blob)
        try FileManager.default.createSymbolicLink(at: executable, withDestinationURL: TestFiles.fixture)
        var settings = AppConfiguration()
        settings.executable = executable.path
        let launch = try LaunchConfiguration(
            settings: settings, profile: ModelProfile(name: "Cached", path: model.path))
        XCTAssertEqual(launch.arguments[1], model.path)
    }

    func testSettingsDraftRoundTripPreservesProfileEditsAndSavedSettings() throws {
        var saved = AppConfiguration()
        saved.profiles = [ModelProfile(name: "Original", path: "/model.gguf")]
        saved.selectedID = saved.profiles[0].id
        var draft = SettingsDraft(settings: saved)
        XCTAssertEqual(try draft.configuration(), saved)
        draft.settings.profiles[0].name = "Edited"
        draft.port = " 8090 "
        let result = try draft.configuration()
        XCTAssertEqual(result.port, 8090)
        XCTAssertEqual(result.profiles[0].name, "Edited")
        XCTAssertEqual(saved.profiles[0].name, "Original")
        XCTAssertEqual(result.selectedID, saved.selectedID)
    }

    func testInvalidDraftNumbersNeverFallBackToSavedValues() {
        let original = SettingsDraft(settings: AppConfiguration())
        for input in ["", "abc", "8080.5", "65536", "1023", "999999999999999999999999"] {
            var draft = original
            draft.port = input
            XCTAssertThrowsError(try draft.configuration(), input)
        }
        for input in ["nan", "inf", "9", "1801"] {
            var draft = original
            draft.startupTimeout = input
            XCTAssertThrowsError(try draft.configuration(), input)
        }
        var draft = original
        draft.shutdownTimeout = "0"
        XCTAssertThrowsError(try draft.configuration())
        XCTAssertEqual(original.port, "8080")
    }

    func testInvalidBoundsDuplicatesAndMissingFilesAreRejected() throws {
        var settings = AppConfiguration()
        settings.port = 65536
        XCTAssertThrowsError(try settings.validate())
        settings.port = 8080
        var profile = ModelProfile(name: "Model", path: "/missing.gguf")
        profile.context = 8193
        XCTAssertThrowsError(try profile.validate())
        profile.context = 2048
        profile.threads = 0
        XCTAssertThrowsError(try profile.validate())
        profile.threads = 2
        XCTAssertThrowsError(try LaunchConfiguration(settings: settings, profile: profile))
        settings.profiles = [profile, ModelProfile(name: "Duplicate", path: profile.path)]
        XCTAssertThrowsError(try settings.validate())
        settings.profiles = []
        settings.startupTimeout = .nan
        XCTAssertThrowsError(try settings.validate())
    }

    func testLogRetentionAndPartialLinesAreBounded() {
        let logs = LogBuffer()
        for _ in 0..<400 { logs.append(Data(repeating: 120, count: 4096), channel: "stdout") }
        logs.append(Data("\ncomplete\n".utf8), channel: "stdout")
        let text = logs.snapshot()
        XCTAssertLessThanOrEqual(text.utf8.count, LogBuffer.byteLimit)
        XCTAssertTrue(text.contains("[truncated]"))
        XCTAssertTrue(text.contains("complete"))
        for _ in 0..<11_000 { logs.note("record") }
        XCTAssertLessThanOrEqual(logs.snapshot().split(separator: "\n").count, LogBuffer.recordLimit)
    }

    func testProbeOutputOverflowIsReported() {
        let logs = LogBuffer(inputLimit: 8)
        logs.append(Data("12345678".utf8), channel: "stdout")
        XCTAssertFalse(logs.overflowed)
        logs.append(Data("9".utf8), channel: "stdout")
        XCTAssertTrue(logs.overflowed)
    }
}

enum TestFiles {
    static func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LlamaPerchTests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func remove(_ folder: URL) {
        do { try FileManager.default.removeItem(at: folder) } catch {
            XCTFail("Fixture cleanup failed: \(error)")
        }
    }

    static var fixture: URL {
        #if SWIFT_PACKAGE
            return Bundle.module.url(forResource: "server", withExtension: "py", subdirectory: "Fixtures")!
        #else
            return Bundle(for: ConfigurationTests.self).url(
                forResource: "server", withExtension: "py", subdirectory: "Fixtures")!
        #endif
    }
}
