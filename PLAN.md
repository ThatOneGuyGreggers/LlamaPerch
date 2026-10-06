# Llama.cpp macOS Menu Bar App — Plan

**Status:** version 0.0.2 implements the design update; Intel builds and automated checks pass. Version 0.0.1 real-model smoke tests remain the inference baseline. Updated October 5, 2026.

Build a native menu bar app that lets users choose a local GGUF model, start a llama.cpp server, see its status, and stop or switch models without a terminal. The controller works with real local models; the initial CPU timings below are smoke-test observations, with broader performance tuning still pending.

## Target and scope

- **Primary hardware:** the user's 1.6 GHz dual-core Intel Core i5 laptop. Build native `x86_64` artifacts and use this machine for release acceptance.
- **Platform:** macOS 13+, SwiftUI `MenuBarExtra`, Settings and logs windows, and `LSUIElement` for a menu-bar-only app. Use macOS 13 APIs such as `ObservableObject` and `@Published`. Supporting older macOS would require an AppKit `NSStatusItem` design and revised deployment target.
- **Server:** one app-owned, externally installed `llama-server`, selected by absolute executable path. Users supply single-file GGUF models.
- **Controls:** start, stop/cancel, restart, model switching, named profiles, bounded logs, API URL copying, and opening the server's optional web UI.
- **Network:** loopback only, `127.0.0.1:8080` by default; API base URL ends in `/v1`.
- **Distribution:** direct distribution without App Sandbox; signing and notarization required for a distributed release, subject to credentials.
- **Lifecycle:** stop the managed server before normal app quit; no server auto-start or detached mode in the MVP. Never adopt or terminate unrelated servers.

Defer Apple Silicon validation, automatic GPU offload, downloads, bundled binaries, split GGUF support, custom flags, multiple servers, remote/LAN access, launch at login, built-in chat, richer sampling presets, and Mac App Store support.

## Validation evidence and open checks

The October 5 review verified:

- The environment reports macOS 14.8.9 and `x86_64`.
- `/usr/local/bin/llama-server` is an x86_64 executable. Version/help probes succeeded; it reports version `0.3.0`, build `10621`, commit `c1d0e7a00`, built with AppleClang for Darwin x86_64.
- The system developer directory selects Command Line Tools. Full Xcode 16.2 is installed at `/Applications/Xcode.app`; build scripts select it per process without changing the system setting.

A subsequent hardware check confirmed `MacBookAir8,2`, Intel Core i5-8210Y at 1.60 GHz, 2 physical cores, 4 logical processors, and 16 GiB RAM. CPU speed alone does not establish model throughput.

Version 0.0.1 validation completed:

- Native x86_64 release build and app launch succeeded. The app is locally ad-hoc signed; the portable artifact is `build/LlamaMenuBar-0.0.1.zip`.
- Swift package and native Xcode suites each passed 15 tests with zero failures; the opt-in real-model test was skipped in routine runs. Separate real-model tests passed for both models below, including API output, cleanup, and restart.
- Formatting, shell syntax, plist validation, and diff whitespace checks passed. The executable probes, CPU flags, and health contract work with llama.cpp build 10621.

| Cached model | Size | Startup | Eight-token request | Server-reported generation |
| --- | --- | --- | --- | --- |
| Granite 4.0 350M BF16 | 708,439,456 bytes | 7.7 seconds | 15.3 seconds | 1.96 tokens/second |
| Granite 4.2 3B Q4_K_M | 2,244,011,552 bytes | 29.3 seconds | 55.9 seconds | 0.17 tokens/second |

Both used context 2048, two generation/prompt threads, no GPU offload, and one slot. These were short completions while a pre-existing server consumed CPU; they are not isolated benchmarks or model-quality evaluations. Other servers were left untouched and tests used separate loopback ports. Reports and logs are under `build/smoke-350m/` and `build/smoke-granite-3b/`.

Model provenance: [IBM Granite 350M GGUF](https://huggingface.co/ibm-granite/granite-4.0-350m-GGUF) snapshot `b8208a86a58427e1739265318028eb5895b74bf2`; [IBM Granite 3B GGUF](https://huggingface.co/ibm-granite/granite-4.2-3b-GGUF) snapshot `c40945d71cd90f249a56985e8155551a9188dc30`. Model cards specify Apache-2.0. SHA-256 checksums: `431e956cac90a7e4d36a9b37bb086c413491c598bb51f90ada8e0c75d0219645` (350M); `e0406663965846ae22a403456eb826ccce5f450840491f71952f18a7cb78e7d5` (3B).

Remaining manual acceptance: GUI switching and quit while serving a model, keyboard/VoiceOver, light/dark appearance, sleep/wake, sustained memory pressure, first-token latency, and thread-count comparisons. Developer ID signing, notarization, a project license, and wider distribution are pending.

## Version 0.0.2 design update

Applied [Apple's design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles) to the existing macOS 13 interface:

| Principle | Implementation |
| --- | --- |
| Purpose | Server status and the start/stop action lead the interface. |
| Agency | Drafts persist; removal has undo; discarding edits is explicit. |
| Responsibility | Saved settings remain separate from drafts; quit protects unsaved work. |
| Familiarity | Native tabs, grouped forms, steppers, alerts, and menu selection. |
| Flexibility | Resizable panes, scrolling forms, accessible labels, and shortcuts. |
| Simplicity | General and Models separate tasks; diagnostics stay in Logs. |
| Craft | Validated numeric edits, shared status language, and appearance checks. |
| Delight | Useful empty states, clear progress, and copy/save feedback. |

Validation: 17 tests passed in both Swift and Xcode suites, with one opt-in real-model test skipped in routine runs. Native General and Models layouts were visually checked in light/dark appearance and at the 740 × 640 minimum window size. The persistence schema remains compatible with 0.0.1. Full VoiceOver, keyboard-only operation, and quit-dialog interaction remain manual acceptance items; this is an implementation of the principles, not an Apple certification.

## Configuration and limits

These are initial settings to measure, not proven optimal values or memory-fit guarantees.

| Setting | Default and limit |
| --- | --- |
| Generation / prompt threads | 2 each; range 1 through detected logical processors, or ceiling 2 if detection fails |
| Context | 2048 tokens; MVP range 512–8192 |
| GPU layers | Fixed at 0 in 0.0.2; nonzero offload requires later backend validation |
| Server slots | Fixed at 1 |
| Port | 8080; range 1024–65535 |
| Startup deadline | 300 seconds; range 10–1800 |
| Graceful shutdown | 5 seconds; range 1–30; allow 5 seconds after force termination before reporting unresolved cleanup |
| Version/help probes | 10 seconds and 256 KiB output per probe; terminate and reap on overflow or timeout |
| Health polling | Every 500 ms during startup, 5 seconds while running; one request at a time, 2-second timeout, 16 KiB response cap |
| Retained logs | At most 1 MiB and 10,000 records; truncate records and partial lines at 16 KiB; update UI at most 4 times/second |
| Persistence | At most 100 profiles and 1 MiB per settings/profile file |
| Lifecycle work | One active operation; reject competing starts; Stop/Cancel takes precedence |

Keep memory mapping at the tested server default and memory locking off. Continue draining output even after retained logs reach their limit.

Global settings store the executable path, port, deadlines, selected profile ID, and schema version. Each profile stores a UUID, name, GGUF path, context, generation/prompt threads, and optional notes. GPU layers are fixed at 0 in 0.0.2. Persist with Codable and atomic writes in Application Support. Recover with visible errors and defaults while preserving damaged data; revalidate paths before launch.

## Architecture and server contract

Use an Xcode app and test target, with code grouped into App, Models, Services, Views, and Resources. Follow [AI Coding Guidelines.md](AI%20Coding%20Guidelines.md).

| Component | Responsibility |
| --- | --- |
| AppState | Main-actor UI state, selection, and actions |
| ServerController | Serialized lifecycle operations and child ownership |
| LaunchConfigurationBuilder | Input validation and executable/argument construction |
| HealthMonitor | Bounded polling, deadlines, and cancellation |
| ModelStore / SettingsStore | Versioned persistence |
| LogStore | Continuous stdout/stderr draining and bounded retention |

Keep blocking work off the main thread. Isolate lifecycle operations with an actor or serial executor and identify each launch so stale callbacks cannot change current state.

Launch directly with Foundation `Process` and an argument array. The candidate's help confirms `--model`, `--host`, `--port`, `--ctx-size`, `--n-gpu-layers`, `--threads`, `--threads-batch`, and `--parallel`. Initial CPU mode also uses `--device none` and `--no-op-offload`. Pass managed values explicitly, remove inherited `LLAMA_ARG_*` variables, and leave port reuse disabled.

Confirm the candidate's `/health` contract with a real model: HTTP 503 while loading; HTTP 200 with JSON `status: ok` when ready. Record the tested build, effective arguments, and recent logs in diagnostics; pin commit-specific documentation once validated.

## User flow and process ownership

First launch: choose the executable, add a named GGUF profile, review settings, start the server, and copy the API URL. Show status with text and an icon, distinguish selected and running profiles, and keep Stop/Cancel available during startup. Selecting a model while stopped changes selection; while running it initiates a controlled switch. Stop before removing a running profile; removing metadata never deletes the GGUF.

States: `Stopped → Starting → Running → Stopping → Stopped`, with failures entering `Failed`. A failed state retains ownership of any surviving child and blocks another launch until that child is reaped.

- **Start:** validate inputs and model readability; check port occupancy as an early diagnostic; attach both log readers before launch; poll until ready, exited, cancelled, or timed out. On failure, stop/reap the child and show recent logs.
- **Readiness:** verify the response belongs to the managed child. Port preflight can race, and a launch ID only prevents stale callbacks; neither alone proves listener ownership. Test a competing listener appearing before child bind.
- **Stop/quit:** cancel polling, request graceful termination, force termination of the same owned process after its deadline, then reap, drain logs, and release resources. If cleanup remains unresolved, retain ownership and report it. Complete cleanup before normal app exit.
- **Switch:** validate the target before stopping the current server, fully reap the old child, then start the new model. Show failures with an explicit retry; no automatic rollback loop.
- **Recovery:** detect unexpected exits and reconcile state after sleep/wake. After an app crash, report an occupied port without blindly killing persisted PIDs.

## Milestones and acceptance

| Milestone | Work and completion criterion |
| --- | --- |
| 0 — Intel feasibility | Record RAM, exact hardware, OS, logical processors, and full Xcode selection. Choose a small quantized GGUF (roughly 0.5–1.5B parameters as an experiment), recording origin, license, quantization, size, and checksum. Prove loading, health transitions, a bounded API completion, stop, and restart with the proposed CPU settings. Measure startup, first-token latency, generation speed, resident memory, and memory pressure. Compare 1/2 threads, and 4 only if available. Revise the baseline if it fails or causes sustained swap. |
| 1 — App foundation | Create native x86_64 app/test targets, menu bar, Settings, and versioned persistence. Accept when settings survive relaunch and windows open correctly. |
| 2 — Profiles | Add executable/GGUF pickers, profile management, configuration controls, and actionable validation for files, permissions, numbers, and duplicates. Accept when profiles persist and argument tests pass against the validated server contract. |
| 3 — Server management | Implement serialized lifecycle, logs, health checks, cancellation, and cleanup. Accept when repeated start/stop and ordinary failure paths leave no unmanaged child. |
| 4 — Switching and usability | Add controlled switching, logs window, URL actions, accessible status, and recoverable failures. Accept when switching between two models works repeatedly, including a target that fails to load. |
| 5 — First release | Pass automated and Intel hardware checks; document installation, configuration, troubleshooting, supported OS/architecture/server, and limitations. Choose a license, add screenshots/icon, sign/notarize, and package a versioned release. Accept when a user can complete the MVP from the README. |

## Verification

Use bounded fixture processes and mock health endpoints for routine tests; add macOS CI when the project and shared scheme exist. CI does not replace acceptance on the Intel laptop.

- **Automated:** argument bounds and Unicode/space-containing paths; CPU defaults and clean environment; persistence round trips, schemas, damaged/oversized data; delayed readiness, exit, cancellation, timeouts, ignored termination, log overflow/partial lines, stale callbacks, rapid actions, failed switches, and competing listeners. Verify only one managed child and unaffected unrelated processes.
- **On hardware:** real API output and two-model switching; stop during startup, repeated restart, quit while running; missing/unreadable/invalid models and executables, insufficient memory, port conflicts, unexpected exit; relaunch without auto-start; sleep/wake, keyboard/VoiceOver, and light/dark appearance.

**Next action:** try the packaged 0.0.2 workflow in the menu bar and complete the remaining manual acceptance checks before wider distribution.

## Sources

Review references: [Apple MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra), [Ventura compatibility](https://support.apple.com/en-us/102861), [Early 2015 MacBook Air specifications](https://support.apple.com/en-us/111956), [llama.cpp CPU/Metal build guide](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md), and [server CLI/health documentation](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md). Upstream links track development; verify them against the selected build.
