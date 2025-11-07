# Apollo Guidance Computer (AGC) Engine

A cycle-accurate simulation of the Apollo Guidance Computer's core instruction set and timing written in Swift.

## Features

- Complete implementation of the AGC instruction set
- Accurate instruction timing and cycle counting
- Interrupt handling and vectoring
- Memory banking and addressing
- I/O channel simulation
- Support for Counter registers (TIME1-4, CDUX/Y/Z)

## Usage

The engine provides a low-level simulation of the AGC processor, including:

- Instruction execution and timing
- Memory access and banking
- I/O operations
- Interrupt processing
- Counter register updates

## Acknowledgements

Special thanks to the Virtual AGC project for their yaAGC implementation. The Swift implementation was made possible by the following resources:
- Website: https://virtualagc.github.io/
- GitHub: https://github.com/virtualagc/virtualagc

## Opcode Coverage

Current parity with yaAGC by instruction group (octal opcodes):

| Opcode(s) | Mnemonic(s) | Status | Notes |
|-----------|-------------|--------|-------|
| `00kk` | `TC`, `RELINT`, `INHINT`, `EXTEND` | ✅ Core TC path logs backtraces and covered via unit tests |
| `010-011` | `CCS` | ✅ Tested via `ccsAdjustsNextZ…` |
| `012-017` | `TCF` | ✅ `tcfAddsBacktraceEntry`, backtrace parity |
| `020-021` | `DAS` / `DDOUBL` | ✅ Covered by `dasDouble…` |
| `022-023` | `LXCH` | ✅ `lxchZeroClearsL`/`lxchSwapsWithErasable…` |
| `024-025` | `INCR` | ✅ `incrAddsOneToRegister` |
| `026-027` | `ADS` | ✅ `adsAddsAndStoresResult` |
| `030-037` | `CA` | ✅ `caLoadsRegisterIntoAccumulator` |
| `040-047` | `CS` | ✅ `csComplementsRegisterValue` |
| `050-051`, `150-157` | `INDEX`, `RESUME` | ✅ `indexInstructionLoads…`, `extracodeIndex…`, resume |
| `052-053` | `DXCH` | ✅ `dxchSwapsDoublePrecisionWords` |
| `054-055` | `TS` (`OVSK`, `TCAA`) | ✅ `tsOvsk…` / `tsTCAA…` |
| `056-057` | `XCH` | ✅ `xchSwapsWithMemory…` |
| `060-067` | `AD` / `DOUBLE` | ✅ `adAddsErasable…` |
| `070-077` | `MASK` | ✅ `maskInstructionUsesErasableMemory` |
| `100` | `READ` | ✅ `readAndWriteIoChannels` |
| `101` | `WRITE` | ✅ `readAndWriteIoChannels` |
| `102` | `RAND` | ✅ `randAndWandCombine…` |
| `103` | `WAND` | ✅ `randAndWandCombine…` |
| `104` | `ROR` | ✅ `rorCombinesAccumulator…` |
| `105` | `WOR` | ✅ `worWritesBackToRegister` |
| `106` | `RXOR` | ✅ `rxorCombinesWithIoChannel` |
| `107` | `EDRUPT` | ✅ `edruptVectorsToAddressZero` (includes backtrace) |
| `110-111` | `DV` | ✅ Hardware fallback plus edge cases covered in tests |
| `112-117` | `BZF` | ✅ Branch logic tested, emits backtrace entries |
| `120-121` | `MSU` | ✅ `msuWith…` tests |
| `122-123` | `QXCH` | ✅ Helper + tests cover ZQ and register swapping |
| `124-125` | `AUG` | ✅ `augIncrementsPositiveValues` |
| `126-127` | `DIM` | ✅ `dimDecrementsUntilZero` |
| `130-137` | `DCA` | ✅ `dcaLoadsDoublePrecision…` |
| `140-147` | `DCS` | ✅ `dcsComplementsDouble…` |
| `160-161` | `SU` | ✅ `suSubtractsUnit…` |
| `162-167` | `BZMF` | ✅ Branch logic tested, emits backtrace entries |
| `170-177` | `MP` | ✅ `mpZeroOperand…` / `mpMultipliesPositive…` |
| Counter opcodes | `PINC`, `MINC`, `DINC`, `PCDU/MCDU`, `SHINC/SHANC` | ✅ Helper parity + DINC test |

Legend: ✅ = parity verified by unit tests, ⚠️ = implemented but missing parity features/tests.
