# LlamaBar changelog

All work so far is recorded here and in the [GitHub wiki](https://github.com/ThatOneGuyGreggers/LlamaBar/wiki/Changelog). Dates use America/Chicago.

## 0.0.3 — LlamaBar gets its name · October 5, 2026

- Rename the app, executable, Swift targets, Xcode project/scheme, local project folder, and GitHub repository to LlamaBar.
- Keep the existing app bundle identifier and settings directory so model profiles survive the rename.
- Make the README short and friendly, move detailed setup into `docs/SETUP.md`, and add the requested AI development disclosure.
- Consolidate the full history into the changelog and publish wiki pages for history, setup, and validation.
- Package a versioned Intel macOS app archive with a SHA-256 checksum; publish development releases matching source tags.

## 0.0.2 — Native polish and llama identity · October 5, 2026

- Apply Apple's design principles with native General/Models tabs, grouped forms, resizable panes, and bounded CPU steppers.
- Add consistent server status symbols, startup progress, meaningful empty states, copy feedback, accessibility labels, and keyboard shortcuts.
- Retain unsaved drafts when Settings closes; confirm before discarding edits or quitting with unsaved work.
- Add model-profile removal undo, explicit save/discard feedback, and native edited-window indicators.
- Fix numeric fields so invalid port/timeout input cannot silently fall back to a previous saved value; add regression coverage.
- Create a custom vector llama menu bar icon with system appearance tinting, then a llama-and-server launcher icon with all macOS icon sizes and a reproducible generator.
- Inspect the native General/Models layouts in light/dark appearance and at the minimum 740 × 640 window size.
- Verify 17 passing tests in both Swift and Xcode suites; skip one opt-in real-model test in routine runs.

## 0.0.1 — The first working server controller · October 5, 2026

- Build the native Intel macOS menu bar app, Settings/logs windows, Xcode project, Swift package, and focused unit-test targets.
- Persist named GGUF profiles, executable selection, settings, and selected model using versioned atomic storage.
- Add CPU-only start, stop/cancel, restart, and controlled model switching with one app-owned child process.
- Bound logs, partial lines, executable probes, health responses, deadlines, and queued actions; drain stdout/stderr off the main thread.
- Verify child socket ownership before readiness, reject unrelated listeners, handle stale callbacks, and clean up before normal quit.
- Add damaged-settings preservation and explicit backup/recovery.
- Fix restart preflight handling of closed sockets, accept symlinked model/executable files, preserve unresolved probe ownership, and make short log lines appear immediately.
- Test delayed readiness, cancellation, unexpected exits, ignored termination, log flooding, occupied ports, oversized health responses, timeouts, and a listener racing startup.
- Confirm macOS 14.8.9, a 1.6 GHz dual-core i5-8210Y, four logical processors, and 16 GiB RAM on the acceptance Mac.
- Find the existing Granite 350M BF16 and Granite 4.2 3B Q4_K_M files in the Hugging Face cache; verify real API output, stop, and restart without downloads.

## Planning — Before the first build · October 5, 2026

- Review the original plan and coding guidelines, replace Apple Silicon-first assumptions with Intel-first acceptance, and confirm the installed x86_64 llama.cpp candidate: build 10621, commit `c1d0e7a00`.
- Set conservative starting values: two generation/prompt threads, context 2048, one server slot, loopback binding, and no GPU offload.
- Add explicit resource limits, process ownership rules, cancellation, port-race tests, and an Intel feasibility milestone.
- Confirm full Xcode 16.2 is installed and select it per build without changing the system developer directory.
- Merge the plan and review into one concise `PLAN.md`.

## Release status

These are local-server development builds. Developer ID signing, notarization, Apple Silicon/GPU support, a project license, and remaining manual accessibility/sleep-wake checks are pending. The 0.0.1 binary was built before its source was captured in Git; its work is documented here. Published source-backed releases begin with 0.0.2.
