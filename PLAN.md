# Build Plan: Llama.cpp macOS Menu Bar App

## 1. Goal

Build a small native macOS menu bar app that makes running a local llama.cpp server straightforward: select a model, start the server, see its status, and stop or switch models without using a terminal.

**Current status:** planning only.

## 2. MVP scope and assumptions

### Included

- One app-managed `llama-server` process at a time.
- A user-selected, externally installed llama.cpp server executable.
- A library of user-selected local GGUF files, with named model profiles.
- Start, stop, restart, and switch-model controls.
- Status, health checks, startup errors, and a bounded live log viewer.
- Persistent global settings and per-model launch settings.
- A local API endpoint that other tools can use.

### Initial technical decisions

- **UI:** SwiftUI `MenuBarExtra`, a Settings window, and a logs window; use AppKit only where needed.
- **Minimum system:** macOS 13 Ventura, which supports `MenuBarExtra`.
- **Hardware:** Apple Silicon first; assess Intel support after the MVP.
- **Distribution:** direct distribution initially, without App Sandbox, to support launching a user-selected executable and reading local model files. Evaluate signing and notarization for releases.
- **Server installation:** users install llama.cpp separately, for example through Homebrew or a local build. Select the actual `llama-server` executable rather than relying on an interactive shell's PATH.
- **Network:** bind to `127.0.0.1` by default, with port `8080` proposed as the initial default.
- **Process ownership:** only control the process started by this app. Do not adopt or terminate unrelated servers.
- **Quit behavior:** stop the managed server and wait for cleanup before exiting. No detached-server mode in the MVP.
- **Startup behavior:** do not automatically start the server on app launch in the MVP.

These are implementation defaults and can be revisited as real usage reveals requirements.

### Later enhancements

- Launch at login and optional server auto-start.
- Model downloading and discovery of models in chosen folders.
- Bundled or automatically updated llama.cpp binaries.
- Multiple simultaneous servers, remote hosts, or LAN access.
- Rich sampling presets and additional model-specific options.
- Built-in chat or benchmarking interfaces.
- Intel compatibility and Mac App Store feasibility.

## 3. User experience

### First launch

1. Open Settings from the menu bar.
2. Choose the `llama-server` executable and validate that it exists and is executable.
3. Add a local GGUF model using a file picker and give the profile a name.
4. Review the default port, context size, and GPU offload settings.
5. Select Start Server and watch the status progress from Starting to Running.
6. Copy the API base URL, such as `http://127.0.0.1:8080/v1`, for use in another client.

### Menu bar layout

```text
Llama Server — Running
Model: My Local Model

Start Server / Stop Server
Restart Server
Models >
  ✓ My Local Model
    Another Model
    Manage Models…

Copy API Base URL
Open Server Page
View Logs…
Settings…
Quit
```

- Indicate status with both text and an icon, not color alone.
- Disable conflicting actions during start, stop, and switch operations.
- Show selected and currently running models distinctly when necessary.
- When stopped, selecting a model only changes the selection.
- When running, selecting another model performs a controlled stop and start.
- Removing a running profile requires stopping its server first; removing a profile never deletes its GGUF file.
- Open Server Page targets the root URL and is useful when the installed server provides a web UI; API access does not depend on that UI.

## 4. Proposed architecture

Use an Xcode macOS app project with a small set of focused components. Suggested layout once implementation begins:

```text
LlamaMenuBar.xcodeproj/
LlamaMenuBar/
  App/                  # Entry point, app lifecycle, shared state
  Models/               # ModelProfile, ServerConfiguration, ServerState
  Services/             # Process, health, persistence, validation, logs
  Views/                # Menu bar, settings, profiles, log viewer
  Resources/            # Icons and asset catalog
LlamaMenuBarTests/
```

### Components

| Component | Responsibility |
| --- | --- |
| AppState | Main-actor UI state, selected profile, user actions |
| ServerController | Serialize lifecycle operations and own the child process |
| LaunchConfigurationBuilder | Validate settings and build an executable URL plus argument array |
| HealthMonitor | Poll the local health endpoint with deadlines and cancellation |
| ModelStore | Persist profile metadata and selected profile ID |
| SettingsStore | Persist executable path and global settings |
| LogStore | Continuously drain stdout/stderr and retain a bounded log history |

Use actor isolation or a dedicated serial executor for process lifecycle operations. Keep blocking work off the main thread and publish UI updates on the main actor. Use APIs available on macOS 13, such as `ObservableObject` and `@Published`, unless the minimum deployment target is deliberately raised.

### Data model

**Global settings**

- Server executable path.
- Host fixed to loopback for the MVP, plus a configurable port.
- Startup timeout and graceful-shutdown timeout.
- Selected profile ID.
- Persistence schema version.

**Model profile**

- Stable UUID and display name.
- GGUF path; MVP supports single-file GGUF models. Split GGUF sets require explicit later validation and support.
- Context size, validated as a positive integer.
- GPU layer setting: an explicit count or an automatic mode mapped to the validated server version's supported behavior.
- Optional thread count, validated as a positive integer.
- Optional notes.

Store profiles and settings in Application Support using Codable and atomic writes. Handle missing or malformed settings with a recoverable error and defaults; do not silently overwrite damaged data. Revalidate file paths at launch time because files may have moved or been removed.

### Server compatibility

- During implementation, choose and document a tested llama.cpp release or commit.
- Inspect that executable's `--version` and `--help` with bounded execution time.
- Confirm supported CLI flags and health endpoint semantics against the tested version.
- Build a Foundation `Process` argument array rather than invoking a shell or concatenating command strings.
- Basic launch inputs map to model, host, port, context size, GPU layers, and optional threads. Exact flags must be verified before implementation is declared complete.
- Retain the detected server version and effective launch configuration in diagnostics.
- Defer unrestricted custom flags until conflict handling and validation are designed.

## 5. Process lifecycle and model switching

### States

```text
Stopped -> Starting -> Running -> Stopping -> Stopped
               |          |           |
               +----------+-----------+-> Failed

Failed -> Starting   (only after the previous child has been reaped)
```

Failed is a user-visible error state, not permission to abandon an existing child process. A hung shutdown must retain ownership and prevent another launch until cleanup finishes.

### Start

1. Validate the executable, profile, model readability, and numeric settings.
2. Check for an occupied port for an early diagnostic; still handle bind failure from the child because a preflight check can race.
3. Configure stdout/stderr readers before launch and start the process directly.
4. Mark Starting and poll the tested health endpoint until ready, exited, cancelled, or timed out. A live PID alone does not mean the server is ready.
5. Ensure readiness belongs to the current launch attempt and that the child remains alive; do not treat an unrelated listener as the managed server.
6. Mark Running only after readiness. On failure, stop/reap the child and present a concise error with recent logs.

### Stop and quit

1. Cancel startup and health polling for the current launch attempt.
2. Mark Stopping and send a graceful termination request to the owned process.
3. Wait for a configurable deadline, then force termination of that same owned process if necessary.
4. Wait for process exit, drain logs, release process resources, and update state.
5. For app quit, finish cleanup before terminating the app.

Use a per-launch identifier so callbacks from an old process cannot mutate a new process's state. Do not persist and blindly kill PIDs across app launches. If the app crashes and leaves a server behind, report the occupied port on next launch and provide guidance rather than killing an unverified process.

### Switch model

1. Validate the target profile before stopping the current server.
2. Serialize the switch and temporarily disable competing controls.
3. Stop and reap the existing process completely.
4. Start the new profile and wait for readiness.
5. If startup fails, show the error and keep the previous profile available for an explicit retry. No automatic rollback loop in the MVP.

## 6. Implementation milestones

### Milestone 1 — Native app foundation

- [ ] Create the Xcode project, app target, and meaningful unit-test target.
- [ ] Configure the menu-bar-only app lifecycle and macOS 13 deployment target.
- [ ] Implement the menu bar, Settings window, and basic status presentation.
- [ ] Add versioned persistence for settings and profile selection.

**Done when:** the app launches in the menu bar, opens Settings, and preserves settings across relaunches.

### Milestone 2 — Model library and configuration

- [ ] Add executable and GGUF file pickers.
- [ ] Add, edit, select, and remove named profiles.
- [ ] Add port, context size, GPU layers, and optional thread controls.
- [ ] Validate missing files, executable permissions, invalid values, and duplicate entries.
- [ ] Select and record a supported llama.cpp version and its CLI contract.

**Done when:** multiple model profiles persist, configuration errors are actionable, and argument generation is covered by focused tests.

### Milestone 3 — Reliable server management

- [ ] Implement serialized start, stop, restart, and termination handling.
- [ ] Drain both output streams continuously and retain bounded logs.
- [ ] Add startup health checks, cancellation, and timeout cleanup.
- [ ] Handle startup failure, port conflicts, unexpected exits, and shutdown timeouts.
- [ ] Stop the managed server on normal app quit.

**Done when:** a real server can be started and stopped repeatedly, the status reflects readiness, and ordinary failure paths leave no unmanaged child behind.

### Milestone 4 — Model switching and usability

- [ ] Implement stop-then-start model switching.
- [ ] Guard rapid clicks and stale asynchronous callbacks.
- [ ] Add the log viewer, API URL copy action, and server-page action.
- [ ] Provide clear selected/running profile indicators and accessible status labels.
- [ ] Make startup and switching failures recoverable through the UI.

**Done when:** switching between two local models works repeatedly, including when the target model fails to load.

### Milestone 5 — Validation and first release

- [ ] Complete the automated and manual verification below.
- [ ] Document the supported macOS, architecture, and tested llama.cpp version.
- [ ] Add real build, installation, configuration, and troubleshooting instructions.
- [ ] Add screenshots and choose an application icon.
- [ ] Choose a license before wider distribution.
- [ ] Configure code signing and notarization for a distributed release, subject to Apple Developer credentials.
- [ ] Package a versioned release and record known limitations.

**Done when:** a user can follow the README on a supported Mac to install the app, configure their own server and model, and use the full MVP workflow.

## 7. Verification strategy

### Automated checks

- Argument generation: spaces and Unicode in paths, valid bounds, omitted optional flags, and invalid configurations.
- Persistence: round trips, schema handling, missing files, and malformed stored data.
- Lifecycle: use a controllable fixture process to exercise delayed readiness, early exit, large stdout/stderr output, and ignored graceful termination.
- Switching: verify only one managed child exists, old callbacks are ignored, and failed switches clean up.
- Health monitoring: test timeout, cancellation, unhealthy responses, and child exit during polling.

Use fixtures and local mock health endpoints for routine tests rather than requiring large GGUF downloads in CI. Add a macOS build/test workflow once the Xcode project and shared scheme exist.

### Manual checks with a real server

- Start a small known-good GGUF and make an OpenAI-compatible API request.
- Switch between two models and verify the new model serves requests.
- Stop during startup, restart repeatedly, and quit while running.
- Try a missing executable, missing/unreadable model, invalid model, occupied port, and a model too large for available memory.
- Verify external server exit is detected and the UI permits recovery.
- Check paths containing spaces and non-ASCII characters.
- Relaunch the app and verify settings persist without starting a server automatically.
- Confirm unrelated server processes are unaffected.
- Check sleep/wake behavior, keyboard navigation, VoiceOver labels, and light/dark appearance.

## 8. Main risks and mitigations

| Risk | Planned mitigation |
| --- | --- |
| llama.cpp CLI and endpoint changes | Pin a tested compatibility baseline and show version information in diagnostics |
| Large models load slowly or exhaust memory | Configurable startup timeout, responsive UI, visible logs, and clean failure recovery |
| Pipe buffers block server execution | Drain stdout and stderr continuously and bound retained log memory |
| Concurrent actions create duplicate processes | Serialize lifecycle transitions and disable conflicting UI actions |
| App crash leaves a server running | Detect port conflicts on relaunch; avoid terminating processes without verified ownership |
| GUI applications have a different PATH | Store a user-selected absolute executable path |
| Model files move | Revalidate paths and provide a file-picker repair flow |

## 9. Next action

Begin Milestone 1: create the native SwiftUI menu bar app, its Settings window, and persistent application state. Then implement model profiles before introducing process management.
