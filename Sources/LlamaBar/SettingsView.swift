import AppKit
import SwiftUI
import UniformTypeIdentifiers
#if canImport(LlamaBarCore)
    import LlamaBarCore
#endif

enum SettingsPane: Hashable { case general, models }

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var pane: SettingsPane
    @State private var editingID: UUID?
    @State private var confirmRecovery = false
    @State private var confirmDiscard = false
    @State private var removed: ModelProfile?
    @State private var removedIndex = 0
    @State private var removedSelection: UUID?

    init(state: AppState, initialPane: SettingsPane = .general) {
        self.state = state
        _pane = State(initialValue: initialPane)
    }

    private var editable: Bool { state.canEdit && !state.server.hasOwnedChild }
    private var draftError: String? {
        do { _ = try state.draft.configuration(); return nil } catch { return error.localizedDescription }
    }

    var body: some View {
        VStack(spacing: 0) {
            ServerSummary(state: state)
                .padding(20)
            if let message = state.server.errorMessage ?? state.message {
                feedback(
                    message,
                    symbol: state.server.errorMessage == nil ? "info.circle" : "exclamationmark.triangle"
                ).padding(.horizontal, 20).padding(.bottom, 12)
            }
            if state.hasUnsavedChanges, let draftError {
                feedback(draftError).padding(.horizontal, 20).padding(.bottom, 12)
            }
            if !state.ready {
                ProgressView("Loading settings…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.storageNeedsRecovery {
                recovery
            } else {
                TabView(selection: $pane) {
                    general.tabItem { Label("General", systemImage: "slider.horizontal.3") }.tag(
                        SettingsPane.general)
                    models.tabItem { Label("Models", systemImage: "square.stack") }.tag(SettingsPane.models)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                footer
            }
        }
        .frame(minWidth: 740, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowDirtyMarker(edited: state.hasUnsavedChanges).frame(width: 0, height: 0))
        .onAppear { editingID = editingID ?? state.draft.settings.selectedID }
        .onChange(of: state.ready) { loaded in
            if loaded && editingID == nil { editingID = state.draft.settings.selectedID }
        }
        .alert("Restore default settings?", isPresented: $confirmRecovery) {
            Button("Cancel", role: .cancel) {}
            Button("Back Up and Restore") { state.recover() }
        } message: {
            Text(
                "Your current settings will be backed up in Application Support. Your model files will stay in place."
            )
        }
        .alert("Discard unsaved changes?", isPresented: $confirmDiscard) {
            Button("Cancel", role: .cancel) {}
            Button("Discard Changes", role: .destructive) {
                state.reloadDraft(); removed = nil; editingID = state.draft.settings.selectedID
            }
        } message: {
            Text("Your saved settings and model files will stay in place.")
        }
    }

    private var general: some View {
        Form {
            Section("Server") {
                LabeledContent("Executable") {
                    HStack {
                        TextField("Path to llama-server", text: $state.draft.settings.executable)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Server executable path")
                        Button("Choose…") {
                            if let url = chooseFile(title: "Choose llama-server") {
                                state.draft.settings.executable = url.path
                            }
                        }.help("Choose your installed llama-server executable")
                    }
                }
                Text("Choose an installed llama-server. The app starts one local server using CPU inference.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Port") {
                    TextField("8080", text: $state.draft.port)
                        .labelsHidden().textFieldStyle(.roundedBorder)
                        .frame(width: 100).accessibilityLabel("Server port, 1024 to 65535")
                }
                LabeledContent("Saved API address") {
                    Text(state.apiURL).textSelection(.enabled).font(.system(.body, design: .monospaced))
                }
                Text("Only applications on this Mac can connect to the server.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Timeouts") {
                LabeledContent("Startup") {
                    HStack {
                        TextField("300", text: $state.draft.startupTimeout).labelsHidden().textFieldStyle(
                            .roundedBorder
                        ).frame(width: 100)
                            .accessibilityLabel("Startup timeout in seconds, 10 to 1800")
                        Text("seconds").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Shutdown") {
                    HStack {
                        TextField("5", text: $state.draft.shutdownTimeout).labelsHidden().textFieldStyle(
                            .roundedBorder
                        ).frame(width: 100)
                            .accessibilityLabel("Shutdown timeout in seconds, 1 to 30")
                        Text("seconds").foregroundStyle(.secondary)
                    }
                }
                Text("Allow more startup time for larger models. Stop remains available while a model loads.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .disabled(!editable)
    }

    private var models: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $editingID) {
                    ForEach(state.draft.settings.profiles) { profile in
                        HStack {
                            Label(profile.name, systemImage: "doc").lineLimit(1).help(profile.name)
                            Spacer()
                            if profile.id == state.draft.settings.selectedID {
                                Image(systemName: "checkmark").accessibilityLabel("Selected for next start")
                            }
                        }
                        .tag(profile.id)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            profile.name
                                + (profile.id == state.draft.settings.selectedID
                                    ? ", selected for next start" : ""))
                    }
                }
                .accessibilityLabel("Model profiles")
                HStack {
                    Button {
                        addModel()
                    } label: {
                        Label("Add Model…", systemImage: "plus")
                    }
                    .disabled(state.draft.settings.profiles.count >= 100)
                    Spacer()
                    Button {
                        removeModel()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(editingID == nil).accessibilityLabel("Remove selected model profile")
                    .help("Remove the profile; keep the model file")
                }.padding(12)
            }.frame(minWidth: 200, idealWidth: 230, maxWidth: 300)
            Group {
                if let profile = state.draft.settings.profiles.first(where: { $0.id == editingID }) {
                    profileEditor(profile: binding(for: profile))
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "square.stack").font(.system(size: 36)).foregroundStyle(.secondary)
                        Text(
                            state.draft.settings.profiles.isEmpty ? "Add your first model" : "Select a model"
                        )
                        .font(.title3.weight(.semibold))
                        Text(
                            "Choose a local GGUF file to create a profile. Your model stays in its original folder."
                        )
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Add Model…") { addModel() }.buttonStyle(.borderedProminent)
                    }.padding(32).frame(maxWidth: .infinity)
                }
            }.frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
        .disabled(!editable)
    }

    private func profileEditor(profile: Binding<ModelProfile>) -> some View {
        Form {
            Section("Model") {
                TextField("Name", text: profile.name)
                LabeledContent("GGUF file") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(profile.wrappedValue.path).font(.caption).textSelection(.enabled)
                            .lineLimit(2).truncationMode(.middle).help(profile.wrappedValue.path)
                        Button("Choose File…") {
                            if let url = chooseFile(title: "Choose GGUF", gguf: true) {
                                profile.wrappedValue.path = url.path
                            }
                        }
                    }
                }
                Button(
                    state.draft.settings.selectedID == profile.wrappedValue.id
                        ? "Selected for Next Start" : "Use for Next Start"
                ) {
                    state.draft.settings.selectedID = profile.wrappedValue.id
                }.disabled(state.draft.settings.selectedID == profile.wrappedValue.id)
            }
            Section("CPU settings") {
                Stepper(value: profile.context, in: 512...8192, step: 512) {
                    LabeledContent("Context", value: "\(profile.wrappedValue.context) tokens")
                }.accessibilityValue("\(profile.wrappedValue.context) tokens")
                Stepper(value: profile.threads, in: 1...ModelProfile.threadLimit) {
                    LabeledContent("Generation threads", value: String(profile.wrappedValue.threads))
                }
                Stepper(value: profile.batchThreads, in: 1...ModelProfile.threadLimit) {
                    LabeledContent("Prompt threads", value: String(profile.wrappedValue.batchThreads))
                }
                Text(
                    "Larger contexts use more memory. Two threads is the starting setting for this Intel Mac."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Notes") {
                TextField("Add a note…", text: profile.notes, axis: .vertical).labelsHidden().lineLimit(2...4)
                    .accessibilityLabel("Model notes")
            }
        }
        .formStyle(.grouped)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Divider()
            HStack {
                if let removed {
                    Text("Removed “\(removed.name)”.").font(.caption)
                    Button("Undo") { undoRemoval() }
                        .disabled(!editable || state.draft.settings.profiles.count >= 100)
                } else {
                    Text(
                        state.saving
                            ? "Saving changes…"
                            : !editable
                                ? "Stop the server to edit settings."
                                : state.hasUnsavedChanges ? "Unsaved changes" : "All changes saved"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Discard Changes…") { confirmDiscard = true }
                    .disabled(!editable || !state.hasUnsavedChanges)
                Button(state.saving ? "Saving…" : "Save Changes") {
                    Task { if await state.saveDraft() { removed = nil } }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!editable || !state.hasUnsavedChanges || draftError != nil)
                .keyboardShortcut("s")
            }.padding(.horizontal, 20).padding(.bottom, 14).padding(.top, 4)
        }
    }

    private var recovery: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text("Your settings need attention").font(.title3.bold())
            Text(
                "The original file has been preserved. Restore defaults to continue; the app will keep a backup."
            )
            .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Back Up and Restore Defaults…") { confirmRecovery = true }.buttonStyle(.borderedProminent)
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func feedback(_ message: String, symbol: String = "exclamationmark.triangle") -> some View {
        Label(message, systemImage: symbol)
            .font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            .padding(10).background(
                Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func binding(for profile: ModelProfile) -> Binding<ModelProfile> {
        Binding(
            get: { state.draft.settings.profiles.first { $0.id == profile.id } ?? profile },
            set: { updated in
                guard let index = state.draft.settings.profiles.firstIndex(where: { $0.id == profile.id })
                else { return }
                state.draft.settings.profiles[index] = updated
            })
    }

    private func addModel() {
        guard let url = chooseFile(title: "Add a GGUF model", gguf: true) else { return }
        let profile = ModelProfile(name: url.deletingPathExtension().lastPathComponent, path: url.path)
        state.draft.settings.profiles.append(profile)
        editingID = profile.id
        if state.draft.settings.selectedID == nil { state.draft.settings.selectedID = profile.id }
    }

    private func removeModel() {
        guard let index = state.draft.settings.profiles.firstIndex(where: { $0.id == editingID }) else {
            return
        }
        removedIndex = index
        removedSelection = state.draft.settings.selectedID
        removed = state.draft.settings.profiles.remove(at: index)
        if state.draft.settings.selectedID == removed?.id {
            state.draft.settings.selectedID = state.draft.settings.profiles.first?.id
        }
        editingID = state.draft.settings.selectedID
    }

    private func undoRemoval() {
        guard let removed else { return }
        state.draft.settings.profiles.insert(
            removed, at: min(removedIndex, state.draft.settings.profiles.count))
        state.draft.settings.selectedID = removedSelection
        editingID = removed.id
        self.removed = nil
    }

    private func chooseFile(title: String, gguf: Bool = false) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = "Choose"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if gguf { panel.allowedContentTypes = [UTType(filenameExtension: "gguf") ?? .data] }
        return panel.runModal() == .OK ? panel.url : nil
    }
}

private struct WindowDirtyMarker: NSViewRepresentable {
    let edited: Bool
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { view.window?.isDocumentEdited = edited }
    }
}
