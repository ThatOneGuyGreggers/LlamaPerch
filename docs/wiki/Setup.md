# LlamaBar setup and development

A native macOS menu bar app for starting a local `llama-server`, managing GGUF profiles, and switching models. Intel (`x86_64`) first; macOS 13 or later.

## Build and run

Requires full Xcode with its command line tools. No third-party Swift packages are required.

```sh
./Scripts/build.sh
open build/LlamaBar.app
```

The script uses `/Applications/Xcode.app` when present, without changing your system's developer-tool selection. Set `DEVELOPER_DIR` if Xcode is elsewhere. The output is a locally ad-hoc signed development app plus `build/LlamaBar-0.0.3-macOS-Intel.zip`; Developer ID signing and notarization are pending. To avoid Desktop file-provider metadata invalidating the signature, `build/LlamaBar.app` links to the signed bundle in `/private/tmp`. Rebuild if that temporary bundle is removed, or use the ZIP for a durable copy.

You can also open `LlamaBar.xcodeproj`, select the shared **LlamaBar** scheme, and run it. The Swift package provides a second build/test route; the Xcode project creates the `.app` bundle.

## Set up a server

1. Click the server icon in the menu bar and open **Settings…**.
2. In **General**, choose your installed `llama-server`; the initial path is `/usr/local/bin/llama-server`.
3. In **Models**, choose **Add Model…**, name the profile, and choose **Use for Next Start**. For a cached Hugging Face model, press Command-Shift-G in the picker and enter `~/.cache/huggingface/hub/`.
4. Choose **Save Changes**, then **Start Server**.
5. Wait for **Running**, then choose **Copy API Address** in the menu and paste it into your client.

CPU defaults: 2 generation threads, 2 prompt threads, 2048-token context, one slot, and GPU offload disabled. The default API URL is `http://127.0.0.1:8080/v1`. Server installation and model downloads are separate from the app.

Selecting a different model in the menu stops and reaps the current server before loading the target. Stop/Cancel remains available during loading. Settings editing requires a stopped server; changed settings apply on the next start. Removing a profile keeps the model file and offers **Undo** before saving. Unsaved drafts survive closing Settings; **Discard Changes…** restores saved values, and quitting asks before discarding edits. Save changes before starting or switching the server. Normal app quit stops the owned server.

## Data and diagnostics

Settings live in `~/Library/Application Support/LlamaMenuBar/settings.json`. Malformed, oversized, or unsupported settings are preserved; **Back Up Settings and Restore Defaults…** offers explicit recovery. Model files stay in their original locations.

**View Logs…** displays bounded output and detected server version. A failed start reports recent server output. The app checks that its own child owns the listening socket before reporting readiness; it never terminates an unrelated listener or trusts saved process IDs.

- **Port unavailable:** stop your other server or choose another port. The app leaves it alone.
- **Missing model/executable:** repair its path in Settings.
- **Unsupported server options:** select a compatible executable. The initial candidate is llama.cpp build 10621, commit `c1d0e7a00`.
- **Slow load or memory pressure:** start with a smaller GGUF or context. Check logs before increasing the startup timeout.
- **Incomplete cleanup:** use Stop again. Another server cannot start until the owned child exits and its pipes finish draining.

## Verification

```sh
./Scripts/test.sh
./Scripts/format.sh --check
```

Lifecycle tests start local fixture servers and need loopback/socket-inspection access. They cover delayed readiness, repeated start/stop, cancellation, port conflicts, forced termination, oversized health replies, logs, and damaged persistence. Version 0.0.2 passed 17 tests in both Swift and Xcode suites, with the real-model test skipped by default. Native General/Models layouts were inspected in light and dark appearance. VoiceOver and full keyboard interaction still need manual acceptance. The 0.0.1 real-model completion/restart checks passed with cached Granite 350M BF16 and your Granite 4.2 3B Q4_K_M model; see the measured results in [PLAN.md](https://github.com/ThatOneGuyGreggers/LlamaBar/blob/main/PLAN.md). The real-model test is skipped unless explicitly enabled:

```sh
LLAMA_SMOKE_MODEL="/absolute/path/to/model.gguf" \
LLAMA_SMOKE_OUTPUT="$PWD/build/smoke" \
./Scripts/test.sh --filter LifecycleTests/testRealModelWhenRequested
```

This performs an eight-token OpenAI-compatible completion and a second start/stop. It records startup/request timing, the response, effective CPU settings, and server logs under the specified output directory. It does not modify app settings or download models.

## Icon assets

The bundle identifier and legacy Application Support directory are retained so existing settings survive the rename.

The menu bar uses a monochrome llama template. The launcher combines the same llama silhouette with a server stack on a navy tile. The native macOS icon is bundled as `AppIcon.icns`; its 1024-pixel preview is [AppIcon.png](https://github.com/ThatOneGuyGreggers/LlamaBar/blob/main/Resources/Icons/AppIcon.png).

To regenerate the launcher assets from the shared vector mark:

```sh
./Scripts/generate-app-icon.sh
```

## Interface updates in 0.0.2

The redesign applies [Apple's design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles) through native General/Models tabs, grouped forms, consistent server actions, visible progress, recoverable edits, and accessibility labels. Context and thread controls use bounded steppers; invalid port or timeout input is reported before saving. Diagnostics stay in Logs, with an empty state and copy feedback.

Existing 0.0.1 settings remain compatible; the persistence schema is unchanged.

## Current limits

Single local server, single-file GGUF, CPU inference, and no automatic startup. Apple Silicon, GPU controls, downloads, bundled server binaries, and detached operation are deferred. Full accessibility, sleep/wake, and release-signing acceptance remain manual checks.

See [PLAN.md](https://github.com/ThatOneGuyGreggers/LlamaBar/blob/main/PLAN.md) for the consolidated plan and acceptance criteria, and [AI Coding Guidelines.md](https://github.com/ThatOneGuyGreggers/LlamaBar/blob/main/AI%20Coding%20Guidelines.md) for the coding rules.
