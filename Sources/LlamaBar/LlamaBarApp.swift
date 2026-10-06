import AppKit
import SwiftUI
#if canImport(LlamaBarCore)
    import LlamaBarCore
#endif

@main
struct LlamaBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuView(state: state).onAppear { delegate.state = state }
        } label: {
            Image(nsImage: LlamaBarIcon.image)
                .renderingMode(.template)
                .accessibilityLabel("LlamaBar, \(state.server.state.rawValue)")
                .help("LlamaBar — \(state.server.state.rawValue)")
        }
        .menuBarExtraStyle(.menu)
        Window("LlamaBar Settings", id: "settings") {
            SettingsView(state: state).onAppear { delegate.state = state }
        }
        .defaultSize(width: 820, height: 720)
        Window("LlamaBar Logs", id: "logs") { LogsView(state: state) }
            .defaultSize(width: 820, height: 520)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?
    private var terminating = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let state else { return .terminateNow }
        guard !terminating else { return .terminateLater }
        if state.hasUnsavedChanges && !confirmDiscard() { return .terminateCancel }
        terminating = true
        Task {
            let cleaned = await state.server.stop()
            terminating = false
            sender.reply(toApplicationShouldTerminate: cleaned)
            if !cleaned {
                state.message =
                    "Quit was cancelled because server cleanup is incomplete. Stop the server and retry."
            }
        }
        return .terminateLater
    }

    private func confirmDiscard() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Discard unsaved changes and quit?"
        alert.informativeText = "Your saved settings and model files will stay in place."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit Without Saving")
        alert.addButton(withTitle: "Cancel")
        // Keep the safe choice as the default so Return cannot discard work by accident.
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"
        return alert.runModal() == .alertFirstButtonReturn
    }
}

extension ServerState {
    var symbol: String {
        switch self {
        case .stopped: return "stop.circle"
        case .starting, .stopping: return "hourglass"
        case .running: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle"
        }
    }
    var tint: Color {
        switch self {
        case .running: return .green
        case .failed: return .red
        default: return .secondary
        }
    }
}

struct ServerSummary: View {
    @ObservedObject var state: AppState
    private var description: String {
        if !state.ready { return "Loading your saved settings…" }
        if state.storageNeedsRecovery { return "Restore your settings to continue." }
        switch state.server.state {
        case .starting: return "Loading the model. You can cancel at any time."
        case .stopping: return "Waiting for the server to finish and release its resources."
        case .running: return state.apiURL
        case .failed: return "Review the details below or open Logs to recover."
        case .stopped:
            if state.hasUnsavedChanges { return "Save your changes before starting the server." }
            return state.selected.map { "Ready to start \($0.name)." }
                ?? "Add a model in the Models tab to get started."
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: state.server.state.symbol).font(.title).foregroundStyle(state.server.state.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Server \(state.server.state.rawValue.lowercased())").font(.title3.weight(.semibold))
                    if state.server.isBusy {
                        ProgressView().controlSize(.small).accessibilityLabel(state.server.state.rawValue)
                    }
                }
                Text(description).foregroundStyle(.secondary).font(.callout).textSelection(.enabled)
            }
            Spacer(minLength: 12)
            if state.server.hasOwnedChild || state.server.state == .starting {
                Button(state.server.state == .starting ? "Cancel Startup" : "Stop Server") { state.stop() }
                    .disabled(state.server.state == .stopping)
                    .help("Stop only the server started by this app")
            } else {
                Button("Start Server") { state.start() }.buttonStyle(.borderedProminent)
                    .disabled(!state.canStart).keyboardShortcut(.return, modifiers: .command)
            }
        }
    }
}

struct MenuView: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }

    var body: some View {
        Label("Server \(state.server.state.rawValue.lowercased())", systemImage: state.server.state.symbol)
        Text("Model: \(state.selected?.name ?? "None selected")")
        if let running = state.configuration.profiles.first(where: { $0.id == state.server.runningProfileID }
        ), running.id != state.selected?.id {
            Text("Running: \(running.name)")
        }
        if state.message != nil || state.server.errorMessage != nil {
            Button("Show Details…") { showWindow("settings") }
        }
        Divider()
        if state.server.hasOwnedChild || state.server.state == .starting {
            Button(state.server.state == .starting ? "Cancel Startup" : "Stop Server") { state.stop() }
                .disabled(state.server.state == .stopping)
        } else {
            Button("Start Server") { state.start() }.disabled(!state.canStart)
        }
        Button("Restart Server") { state.restart() }
            .disabled(
                !state.ready || state.selected == nil || state.server.isBusy || state.changingModel
                    || state.saving || state.hasUnsavedChanges)
        Menu("Models") {
            ForEach(state.configuration.profiles) { profile in
                // A native toggle provides selection feedback without embedding checkmarks in names.
                Toggle(
                    profile.name,
                    isOn: Binding(
                        get: { profile.id == state.configuration.selectedID },
                        set: { selected in
                            if selected { state.select(profile) }
                        })
                ).disabled(!state.canEdit || state.hasUnsavedChanges)
            }
            Divider()
            Button("Manage Models…") { showWindow("settings") }
        }
        if state.hasUnsavedChanges { Text("Unsaved changes — open Settings to save") }
        Divider()
        Button("Copy API Address") { state.copyAPIURL() }.disabled(!state.ready)
        Button("Open Server Page") { state.openServerPage() }.disabled(state.server.state != .running)
        Button("View Logs…") { showWindow("logs") }
        Button("Settings…") { showWindow("settings") }.keyboardShortcut(",")
        Divider()
        Text("LlamaBar \(appVersion)")
        Button("Quit LlamaBar") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }

    private func showWindow(_ id: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }
}

struct LogsView: View {
    @ObservedObject var state: AppState
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(state.server.state.rawValue, systemImage: state.server.state.symbol)
                Spacer()
                Button(copied ? "Copied" : "Copy Logs") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(state.server.logs, forType: .string)
                    copied = true
                }.disabled(state.server.logs.isEmpty)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            DisclosureGroup("Server Information") {
                Text(state.server.version).font(.caption).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            if state.server.logs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.alignleft").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No server output yet").font(.headline)
                    Text("Start a server to see loading progress and diagnostic details here.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    Text(state.server.logs).font(.system(.body, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Server output")
                }
            }
            Text("Older output is removed automatically when the log reaches its size limit.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .onChange(of: state.server.logs) { _ in copied = false }
    }
}
