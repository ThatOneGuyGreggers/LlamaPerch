# Llama.cpp macOS Menu Bar App

A planned native macOS menu bar app for starting and stopping a local `llama-server` instance and switching between GGUF models.

## Project status

**Planning stage.** This repository currently contains the build plan; an application has not been implemented yet.

## Planned features

- Menu bar status for stopped, starting, running, stopping, and failed states.
- Start, stop, and restart a managed llama.cpp server.
- Register local GGUF models and switch the active model.
- Configure the server executable, port, context size, and GPU offload.
- View server logs and copy the local API URL.
- Save settings and model profiles between launches.

## Proposed stack

- Swift and SwiftUI, with `MenuBarExtra` and a Settings window.
- macOS 13 Ventura or later, initially validated on Apple Silicon.
- Foundation `Process` for managing an externally installed `llama-server`.
- Local GGUF model files supplied by the user.

## Build plan

See [PLAN.md](PLAN.md) for scope, architecture, milestones, acceptance criteria, and testing strategy.

The first implementation milestone is an Xcode app target with a menu bar interface and persistent settings. Build and installation instructions will be added when that target exists.
