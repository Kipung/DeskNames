# Contributing to DeskNames

Build with `./build.sh` on an Apple Silicon Mac with Xcode command line tools. Read [the architecture](docs/architecture.md) before changing shared window operations.

Run `--self-test` and `--pane-session-test` from the built executable for relevant changes. Use `--layout-session-test` for native restoration changes when a brief visual test is acceptable. Record your macOS version, display configuration, and whether a result came from a pure test or native interaction.

Preserve existing preferences and layout compatibility. Use isolated temporary files and preference domains in tests. Keep automatic routing new-window-only, respect manual moves, and report missing or ambiguous destinations. Do not introduce automatic simulated-drag fallbacks that steal focus.

For bug reports, include the version/build, macOS version, monitor arrangement, reproduction steps, expected result, and actual result. Review window titles, layouts, diagnostics, and screenshots before attaching them.

Keep changes focused and explain user-visible behavior. Preserve MIT attribution for adapted native code in source and bundle resources. Contributions are provided under the repository's MIT license.
