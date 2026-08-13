# Apollo Guidance Computer (AGC)

A cycle-accurate Swift simulation of the Apollo Guidance Computer, driven as `AGCRuntime` rather than by poking `AGCEngine` directly. Luminary 099 boot and keyed DSKY sequences match yaAGC. `LMCore` closes a sourced LM vehicle loop around that runtime. `MissionControl` is a macOS operator console.

## What’s proven

- Idle Luminary 099 from `Z=04000` through 1,000,000 MCTs against a committed yaAGC JSONL fixture (391 samples). Live compare runs when `Tools/yaagc-trace` is built.
- Keyed `V35E` and `V37E63E` after a 1e6-MCT boot at 50,000 MCT/key.
- Instruction fetch/execute for `CA`, switched-E `XCH`, `MASK`, `AD`, `CS`, `INCR`, `ADS`, `TCF`, and `BZF` (via `EXTEND`).
- Sourced DPS throttle, all 16 RCS jets, PIPA/CDU pulses, landing-radar low-scale conversion, and 1/ACCS diagonal inertia.
- Sourced Apollo 11 PDI kinematics from NASA TN D-6846 Table I (5560 fps inertial, −4 fps altitude rate, 48,814 ft) and TN D-4131 (95° pitch from local vertical). Channel 12 gimbal trim slews DPS thrust at 0.2 deg/s within ±6 deg.

After idle boot, `bootAndEnterP63` loads NASA Luminary 99 landing-guidance pad-loads (TLAND through TAUVERT), a PDI-relative GET clock (`TLAND − GUIDDURN − ZOOMTIME`), the modeled moon-centered RN/VN/RLS/REFSMMAT/MASS, and MODE CONTROL AUTO / auto-throttle / LR POS1. The frame loop answers P63’s remaining crew flashes: ENTER on V50N25 skips R51 fine-align, and PROCEED is held 150 ms on V50N18 and V99. That is still not a real Apollo ephemeris or PDI range-to-go. Body angular rates, IGNALG convergence with the modeled state, and the DPS engine-to-CG moment arm are still unmodeled. Do not invent those just to animate a landing.

## Run

```bash
swift test
```

Open `MissionControl/MissionControl.xcodeproj` in Xcode and run the MissionControl scheme (macOS 14+). Load `Tests/AGCTests/Luminary099.bin` from the app, or use **AGC → Load Luminary099**.

Integration entry points:

- `AGCRuntime` — bounded `step(cycles:)`, DSKY scripts, debugger, golden-trace capture
- `LMSimulationRuntime` — frame steps that enqueue sensors, step the AGC, then apply DPS/RCS

## Opcode coverage

Parity with yaAGC by instruction group (octal opcodes). Golden traces are the live-mix proof; named tests below are unit checks.

| Opcode(s) | Mnemonic(s) | Status | Notes |
|-----------|-------------|--------|-------|
| `00kk` | `TC`, `RELINT`, `INHINT`, `EXTEND` | ✅ | Core TC path logs backtraces; `EXTEND` used by fetch-path `BZF` |
| `010-011` | `CCS` | ✅ | `ccsAdjustsNextZ…` |
| `012-017` | `TCF` | ✅ | `executePathTCFBranchesThroughFetch`, `tcfAddsBacktraceEntry` |
| `020-021` | `DAS` / `DDOUBL` | ✅ | `dasDouble…` |
| `022-023` | `LXCH` | ✅ | `lxchZeroClearsL` / `lxchSwapsWithErasable…` |
| `024-025` | `INCR` | ✅ | `executePathINCRAddsOneThroughFetch`, `incrAddsOneToRegister` |
| `026-027` | `ADS` | ✅ | `executePathADSAddsAndStoresThroughFetch`, `adsAddsAndStoresResult` |
| `030-037` | `CA` | ✅ | `executePathCALoadsErasableThroughFetch`, `caLoadsRegisterIntoAccumulator` |
| `040-047` | `CS` | ✅ | `executePathCSComplementsRegisterThroughFetch`, `csComplementsRegisterValue` |
| `050-051`, `150-157` | `INDEX`, `RESUME` | ✅ | `indexInstructionLoads…`, `extracodeIndex…`, resume |
| `052-053` | `DXCH` | ✅ | `dxchSwapsDoublePrecisionWords` |
| `054-055` | `TS` (`OVSK`, `TCAA`) | ✅ | `tsOvsk…` / `tsTCAA…` |
| `056-057` | `XCH` | ✅ | `executePathXCHWritesSwitchedErasableBank`, `xchSwapsWithMemory…` |
| `060-067` | `AD` / `DOUBLE` | ✅ | `executePathADAddsErasableThroughFetch`, `adAddsErasable…` |
| `070-077` | `MASK` | ✅ | `executePathMASKUsesErasableThroughFetch`, `maskInstructionUsesErasableMemory` |
| `100` | `READ` | ✅ | `readAndWriteIoChannels` |
| `101` | `WRITE` | ✅ | `readAndWriteIoChannels` |
| `102` | `RAND` | ✅ | `randAndWandCombine…` |
| `103` | `WAND` | ✅ | `randAndWandCombine…` |
| `104` | `ROR` | ✅ | `rorCombinesAccumulator…` |
| `105` | `WOR` | ✅ | `worWritesBackToRegister` |
| `106` | `RXOR` | ✅ | `rxorCombinesWithIoChannel` |
| `107` | `EDRUPT` | ✅ | `edruptVectorsToAddressZero` |
| `110-111` | `DV` | ✅ | Hardware fallback plus edge cases |
| `112-117` | `BZF` | ✅ | `executePathBZFBranchesThroughFetch`; helper branch/backtrace tests |
| `120-121` | `MSU` | ✅ | `msuWith…` |
| `122-123` | `QXCH` | ✅ | ZQ and register swapping |
| `124-125` | `AUG` | ✅ | `augIncrementsPositiveValues` |
| `126-127` | `DIM` | ✅ | `dimDecrementsUntilZero` |
| `130-137` | `DCA` | ✅ | `dcaLoadsDoublePrecision…` |
| `140-147` | `DCS` | ✅ | `dcsComplementsDouble…` |
| `160-161` | `SU` | ✅ | `suSubtractsUnit…` |
| `162-167` | `BZMF` | ✅ | Branch logic and backtrace |
| `170-177` | `MP` | ✅ | `mpZeroOperand…` / `mpMultipliesPositive…` |
| Counter opcodes | `PINC`, `MINC`, `DINC`, `PCDU/MCDU`, `SHINC/SHANC` | ✅ | Helper parity + DINC test |

Legend: ✅ = parity verified by unit tests and/or yaAGC golden traces.

## Acknowledgements

Special thanks to the Virtual AGC project for yaAGC:

- https://virtualagc.github.io/
- https://github.com/virtualagc/virtualagc
