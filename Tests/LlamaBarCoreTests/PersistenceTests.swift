import Foundation
import XCTest
#if canImport(LlamaBarCore)
    @testable import LlamaBarCore
#endif

final class PersistenceTests: XCTestCase {
    func testRoundTripAndMissingSettings() async throws {
        let folder = try TestFiles.folder()
        defer { TestFiles.remove(folder) }
        let store = ConfigurationStore(url: folder.appendingPathComponent("settings.json"))
        var settings = try await store.load()
        let profile = ModelProfile(name: "Saved", path: "/local.gguf")
        settings.profiles = [profile]
        settings.selectedID = profile.id
        try await store.save(settings)
        let restored = try await store.load()
        XCTAssertEqual(restored, settings)
    }

    func testMalformedSettingsArePreservedUntilExplicitRecovery() async throws {
        let folder = try TestFiles.folder()
        defer { TestFiles.remove(folder) }
        let url = folder.appendingPathComponent("settings.json")
        let damaged = Data("{broken".utf8)
        try damaged.write(to: url)
        let store = ConfigurationStore(url: url)
        do { _ = try await store.load(); XCTFail("Malformed data should fail") } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        do { try await store.save(AppConfiguration()); XCTFail("Saving must require recovery") } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        XCTAssertEqual(try Data(contentsOf: url), damaged)
        _ = try await store.recover()
        let backup = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .first { $0.lastPathComponent.hasPrefix("settings-backup") })
        XCTAssertEqual(try Data(contentsOf: backup), damaged)
        let restored = try await store.load()
        XCTAssertEqual(restored, AppConfiguration())
    }

    func testUnsupportedSchemaAndOversizedSettingsAreRejected() async throws {
        let folder = try TestFiles.folder()
        defer { TestFiles.remove(folder) }
        let url = folder.appendingPathComponent("settings.json")
        var settings = AppConfiguration()
        settings.schemaVersion = 99
        try JSONEncoder().encode(settings).write(to: url)
        let store = ConfigurationStore(url: url)
        do { _ = try await store.load(); XCTFail("Unknown schema should fail") } catch {
            XCTAssertTrue(error.localizedDescription.contains("version"))
        }
        try Data(repeating: 0, count: 1_048_577).write(to: url)
        do { _ = try await store.load(); XCTFail("Oversized data should fail") } catch {
            XCTAssertTrue(error.localizedDescription.contains("1 MiB"))
        }
    }
}
