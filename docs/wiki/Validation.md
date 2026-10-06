# Validation and known limits

## Intel acceptance machine

- MacBook Air `MacBookAir8,2`, macOS 14.8.9.
- Intel Core i5-8210Y at 1.60 GHz; two physical cores, four logical processors, 16 GiB RAM.
- Full Xcode 16.2, selected per build.
- Tested llama.cpp candidate: build 10621, commit `c1d0e7a00`, Darwin x86_64.

## Automated coverage

The 0.0.2 baseline passed 17 tests in both Swift and native Xcode suites, with one opt-in real-model test skipped by default. The renamed 0.0.3 Swift and native Xcode suites also passed 17 tests with zero failures and one opt-in test skipped. The release bundle was verified as LlamaBar 0.0.3, native x86_64, with a valid ad-hoc signature.

Checks cover settings bounds, Unicode/space-containing paths, symlinked files, clean server environments, single-slot CPU arguments, draft numeric parsing, atomic persistence, schema/size rejection, damaged-data recovery, log limits/partial lines, live output, delayed readiness, cancellation, forced shutdown, unexpected exits, repeated start/stop, port conflicts, and false readiness from a competing listener.

## Real-model smoke checks

Both existing cached models served an eight-token OpenAI-compatible completion, stopped, and restarted using context 2048, two generation/prompt threads, one slot, and no GPU offload.

| Model | Startup | Eight-token request | Server-reported generation |
| --- | --- | --- | --- |
| Granite 4.0 350M BF16 | 7.7 seconds | 15.3 seconds | 1.96 tokens/second |
| Granite 4.2 3B Q4_K_M | 29.3 seconds | 55.9 seconds | 0.17 tokens/second |

These are smoke observations from 0.0.1, not isolated benchmarks. Another existing server was consuming CPU; it was left untouched. No models were downloaded. Provenance, checksums, and exact settings are recorded in the [build plan](https://github.com/ThatOneGuyGreggers/LlamaPerch/blob/main/PLAN.md).

## Native interface and packaging

General and Models were visually inspected in light/dark appearance and at the 740 × 640 minimum window size. The menu bar uses a vector template llama; macOS supplies its appearance tint. The launcher combines the same mark with a server stack, with standard `.icns` representations checked against the icon macOS retrieves from the built bundle.

Release bundles are native x86_64 and locally ad-hoc signed. Developer ID signing and notarization are pending. The ZIP is packaged outside Desktop file-provider metadata so signature verification remains valid; published assets include SHA-256 checksums.

## Remaining manual acceptance

VoiceOver, complete keyboard-only operation, quit dialogs during real use, sleep/wake, sustained memory pressure, first-token latency, and thread-count comparisons remain manual checks. Apple Silicon/GPU support, downloading/bundling models or servers, detached mode, multiple servers, and a project license are deferred.

## Rename compatibility

LlamaPerch 0.0.4 retains the prior bundle identifier and `~/Library/Application Support/LlamaMenuBar/settings.json`. Existing profiles remain readable; no settings migration or model-file moves are performed.

## LlamaPerch 0.0.4

The second rebrand keeps historical releases intact and preserves the same storage/schema compatibility. The renamed Swift and native Xcode suites each passed 17 tests with zero failures and one opt-in real-model test skipped. SwiftPM uses an isolated build cache, and the two fixture suites use separate localhost port ranges. The LlamaPerch 0.0.4 x86_64 app archive and ad-hoc signature were verified before publication.
