import AppKit
import Combine
import Foundation
#if canImport(LlamaBarCore)
    import LlamaBarCore
#endif

@MainActor
final class AppState: ObservableObject {
    @Published var configuration = AppConfiguration()
    @Published var draft = SettingsDraft(settings: AppConfiguration())
    @Published var ready = false
    @Published var storageNeedsRecovery = false
    @Published var message: String?
    @Published var changingModel = false
    @Published private(set) var saving = false
    let server = ServerController()
    private let store: ConfigurationStore
    private var forwarding: AnyCancellable?

    init(settingsURL: URL = ConfigurationStore.defaultURL) {
        store = ConfigurationStore(url: settingsURL)
        forwarding = server.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        Task { await load() }
    }

    private func load() async {
        do { configuration = try await store.load() } catch {
            storageNeedsRecovery = true
            message =
                "Could not read settings: \(error.localizedDescription). The original file is preserved."
        }
        reloadDraft()
        ready = true
    }

    var canEdit: Bool { ready && !storageNeedsRecovery && !changingModel && !saving && !server.isBusy }
    var hasUnsavedChanges: Bool { draft != SettingsDraft(settings: configuration) }
    var canStart: Bool {
        ready && !storageNeedsRecovery && !changingModel && !saving && !hasUnsavedChanges
            && selected != nil && server.canStart
    }
    var selected: ModelProfile? { configuration.selectedProfile }
    var apiURL: String { "http://127.0.0.1:\(server.activePort ?? configuration.port)/v1" }

    /// Commits settings only after a successful atomic write; errors leave the previous state intact.
    func save(_ draft: AppConfiguration) async -> Bool {
        guard !saving else { message = "A settings save is already in progress."; return false }
        // Menu selection updates an untouched editor; an edited draft remains available until saved.
        let wasClean = !hasUnsavedChanges
        saving = true
        defer { saving = false }
        do {
            try await store.save(draft)
            configuration = draft
            if wasClean { reloadDraft() }
            message = nil
            return true
        } catch { message = "Could not save settings: \(error.localizedDescription)"; return false }
    }

    func recover() {
        Task {
            do {
                configuration = try await store.recover()
                reloadDraft()
                storageNeedsRecovery = false
                message = "Defaults restored. The old settings were kept in Application Support."
            } catch { message = "Could not recover settings: \(error.localizedDescription)" }
        }
    }

    func start() {
        guard canStart, let selected else {
            message =
                hasUnsavedChanges
                ? "Save or discard your changes before starting the server."
                : "Add and select a model in Settings first."
            return
        }
        server.start(settings: configuration, profile: selected)
    }

    func stop() { Task { _ = await server.stop() } }

    func restart() {
        guard !changingModel, !saving, !server.isBusy, !hasUnsavedChanges, let selected else { return }
        changingModel = true
        Task {
            defer { changingModel = false }
            if await server.stop() { server.start(settings: configuration, profile: selected) }
        }
    }

    func select(_ profile: ModelProfile) {
        guard canEdit, !hasUnsavedChanges, profile.id != configuration.selectedID else { return }
        changingModel = true
        Task {
            defer { changingModel = false }
            var draft = configuration
            draft.selectedID = profile.id
            do {
                // Reject an unreadable target before disrupting the running server.
                if server.hasOwnedChild {
                    _ = try await Task.detached { try LaunchConfiguration(settings: draft, profile: profile) }
                        .value
                }
                guard await save(draft) else { return }
                if server.hasOwnedChild, await server.stop() {
                    server.start(settings: draft, profile: profile)
                }
            } catch { message = "Cannot switch model: \(error.localizedDescription)" }
        }
    }

    func reloadDraft() { draft = SettingsDraft(settings: configuration) }

    func saveDraft() async -> Bool {
        do {
            let snapshot = try draft.configuration()
            guard await save(snapshot) else { return false }
            reloadDraft()
            return true
        } catch { message = error.localizedDescription; return false }
    }

    func copyAPIURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(apiURL, forType: .string)
    }

    func openServerPage() {
        guard let url = URL(string: "http://127.0.0.1:\(server.activePort ?? configuration.port)/") else {
            return
        }
        if !NSWorkspace.shared.open(url) { message = "Could not open the server page in your browser." }
    }
}
