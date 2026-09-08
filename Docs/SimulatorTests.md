# Package tests on visionOS Simulator

Run from the package root using the aggregate `AGC-Package` scheme. The
generated `LMCore` library scheme has no test action.

```sh
xcodebuild -scheme AGC-Package \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro' \
  -derivedDataPath /tmp/AGC-Simulator-DerivedData \
  -resultBundlePath /tmp/AGC-Simulator-Tests.xcresult \
  -only-testing:LMCoreTests/LMFlightReplaySiteTests \
  -only-testing:LMCoreTests/LMSiteIMUDiagnosticTests \
  -only-testing:AGCTests/YaAGCGoldenTraceTests test
```

Use a fresh result-bundle path for each run. Select a device ID instead of its
name when multiple installed simulators have the same name.

The optional live yaAGC comparisons launch an external executable using
`Foundation.Process`, so they compile only on macOS/Linux. All three committed
golden-trace fixture comparisons remain available on Simulator. On desktop,
live comparisons retain their existing executable-availability condition.

The recorder's `@main` declaration lives in `LMFlightRecorderCommand.swift`.
Naming it `main.swift` made Xcode's package build treat the module as containing
top-level code and reject `@main`. The rename changes no executable code.

Validated on 2026-09-05 using Xcode 26.6.0 and visionOS Simulator 26.5 (23O470):

- `/tmp/AGC-Site-Fixes/Package-Simulator-Final.xcresult`: seven tests pass,
  zero failures/skips; four site replay/IMU regressions and three committed
  golden-trace comparisons. Summary: `simulator-summary.json` in the same
  directory. Build and test log: `package-simulator-final.log`.
- `/tmp/AGC-Site-Fixes/portability-macos.log`: the same seven tests pass on
  macOS; two optional live-tracer comparisons are skipped because the tracer
  is absent in the clean export. `recorder-usage.json` verifies the linked
  recorder prints usage and exits with status 64 when invoked without arguments.
- Both runs use `/tmp/AGC-Site-Fixes/replay-export`, a clean tracked-tree
  export plus the focused changes. The owner's uncommitted gear/panel work
  is excluded. Broader dynamics and descent evidence is in
  [LunarLandingSite.md](LunarLandingSite.md).

These are package tests, not rendered cockpit captures or physical Vision Pro
validation. They establish no new frame-time, memory, stereo, or comfort result.
