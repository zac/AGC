import Testing
import Foundation

@testable import AGC

@Suite("AGC Tests")
class AGCTests {

    private var luminaryURL: URL? {
        Bundle.module.url(forResource: "Luminary099", withExtension: "bin")
    }

    private func makeEngine() throws -> (AGCEngine, AGCState) {
        let state = AGCState()
        state.binFile = Data()
        let engine = try AGCEngine(state: state)
        return (engine, state)
    }

    private func makeRuntime() throws -> AGCRuntime {
        let url = try #require(luminaryURL)
        return try AGCRuntime(binFile: url)
    }

    private func makeLuminaryEngine() throws -> (AGCEngine, AGCState) {
        let url = try #require(luminaryURL)
        let state = AGCState()
        state.binFile = try Data(contentsOf: url)
        return (try AGCEngine(state: state), state)
    }

    private func setAccumulator(_ value: Int, engine: AGCEngine) {
        engine.state.accumulator = value & 0o177777
        engine.writeRegister(.regA, engine.state.accumulator)
    }

    private func prepareBareInstructionRun(_ engine: AGCEngine) {
        let state = engine.state
        state.interruptRequests = Array(repeating: 0, count: 11)
        state.downruptTimeValid = false
        state.allowInterrupt = false
        state.extraCode = false
        state.pendFlag = false
        state.pendDelay = 0
        state.extraDelay = 0
        state.indexValue = 0
        state.substituteInstruction = false
        state.inIsr = false
    }

    private func erasableLocation(for address: Int) -> (bank: Int, offset: Int) {
        precondition(address >= 0 && address < 0o1400, "Address out of unswitched range")
        if address < 0o400 {
            return (0, address & 0o377)
        } else if address < 0o1000 {
            return (1, address & 0o377)
        } else {
            return (2, address & 0o377)
        }
    }

    private func addSP(_ lhs: Int, _ rhs: Int) -> Int {
        var sum = (lhs & 0o177777) + (rhs & 0o177777)
        if (sum & 0o200000) != 0 {
            sum = (sum + 1) & 0o177777
        } else {
            sum &= 0o177777
        }
        return sum
    }

    private func signExtend(_ value: Int) -> Int {
        return (value & 0o77777) | ((value << 1) & 0o100000)
    }

    private final class TestIO: AGCIOProtocol {
        var pendingInputs: [[AGCChannelInput]] = []
        var outputs: [(Int, Int)] = []

        func channelOutput(channel: Int, value: Int) {
            outputs.append((channel, value))
        }

        func channelInput() -> [AGCChannelInput]? {
            guard !pendingInputs.isEmpty else { return nil }
            return pendingInputs.removeFirst()
        }

        func requestRadarData() {}
        func shiftToDeda(data: Int) {}
        func channelRoutine() {}
    }

    @Test func engineCreation() async throws {
        let runtime = try makeRuntime()
        let snapshot = await runtime.snapshot()
        #expect(snapshot.registers.z == 0o4000)
    }

    @Test func bootResetUsesYaAGCStartupDefaults() async throws {
        let runtime = try AGCRuntime(coreImage: Data())
        let snapshot = try await runtime.reset()

        #expect(snapshot.registers.z == 0o4000)
        #expect(snapshot.inputChannels[0o30] == 0o37777)
        #expect(snapshot.inputChannels[0o31] == 0o77777)
        #expect(snapshot.inputChannels[0o32] == 0o77777)
        #expect(snapshot.inputChannels[0o33] == 0o77777)
        #expect(snapshot.interruptRequests[8] == 0, "yaAGC clears InterruptRequests at init; first MCT raises DOWNRUPT")
    }

    @Test func repeatedRuntimeResetProducesIdenticalSnapshots() async throws {
        let runtime = try AGCRuntime(coreImage: Data())
        let first = try await runtime.reset()
        _ = await runtime.step(cycles: 50)
        let second = try await runtime.reset()

        #expect(second == first)
    }

    @Test func runEngineFor1000Cycles() async throws {
        let runtime = try makeRuntime()
        let snapshot = await runtime.step(cycles: 1000)
        #expect(snapshot.cycle == 1000)
    }

    @Test func runtimeStepAdvancesDeterministically() async throws {
        let runtime = try AGCRuntime(coreImage: Data())
        let first = await runtime.step(cycles: 10)
        let second = await runtime.step(cycles: 10)

        #expect(first.cycle == 10)
        #expect(second.cycle == 20)
    }

    @Test func runtimeCancellationLeavesSnapshotReadable() async throws {
        let runtime = try AGCRuntime(coreImage: Data())
        let task = Task {
            await runtime.step(cycles: UInt64.max)
        }
        task.cancel()
        let cancelledSnapshot = await task.value
        let currentSnapshot = await runtime.snapshot()

        #expect(currentSnapshot.cycle == cancelledSnapshot.cycle)
    }

    @Test func instructionFetchRespectsBankSelection() async throws {
        let (engine, state) = try makeEngine()

        // Encode CA 024 in bank 2, ensure bank 1 has a different instruction
        state.fixedMemory[2][0] = 0o30024
        state.fixedMemory[1][0] = 0o00000
        state.erasableMemory[0][Register.regTIME2.rawValue] = 0o54321

        let fetched = engine.fetchInstructionWord(at: 0o4000)
        #expect(fetched == 0o30024, "Instruction fetch should honor FB/BB bank selection")
    }

    @Test func writeRegisterAppliesEditingRules() throws {
        let (engine, state) = try makeEngine()

        engine.writeRegister(.regCYR, 0o40003)
        #expect(state.erasableMemory[0][Register.regCYR.rawValue] == 0o60001)

        engine.writeRegister(.regZ, 0o1234)
        #expect(state.nextZ == 0o1234)
        #expect(state.erasableMemory[0][Register.regZ.rawValue] == 0o1234)
    }

    @Test func switchedErasableWritesUseEBBank() throws {
        let (engine, state) = try makeEngine()
        let switchedAddress = 0o1400
        engine.writeRegister(.regEB, 0o2400) // EB = 5
        state.erasableMemory[5][0] = 0o22222
        state.erasableMemory[3][0] = 0o33333
        setAccumulator(0o11111, engine: engine)

        engine.performXCH(address10: switchedAddress)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o22222)
        #expect(state.erasableMemory[5][0] == 0o11111, "XCH into 01400 must write the EB-selected bank")
        #expect(state.erasableMemory[3][0] == 0o33333, "Unselected bank 3 must not be used as a stand-in for switched E")
    }

    @Test func switchedErasableCADoesNotCorruptUnselectedBank() throws {
        let (engine, state) = try makeEngine()
        engine.writeRegister(.regEB, 0o2400) // EB = 5
        state.erasableMemory[5][0] = 0o12345
        state.erasableMemory[3][0] = 0

        engine.performCA(address12: 0o1400)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o12345)
        #expect(state.erasableMemory[5][0] == 0o12345)
        #expect(state.erasableMemory[3][0] == 0, "CA of switched E must not write bank 3")
    }

    @Test func assignFromPointerDoesNotWriteFixedMemoryAsErasable() throws {
        let (engine, state) = try makeEngine()
        state.erasableMemory[4][0] = 0o77777

        engine.assignFromPointer(0o2000, 0o11111)

        #expect(state.erasableMemory[4][0] == 0o77777)
    }

    @Test func readMemoryUsesEBForSwitchedErasable() throws {
        let (engine, state) = try makeEngine()
        engine.writeRegister(.regEB, 0o2400) // bank 5
        state.erasableMemory[5][0] = 0o12345
        state.erasableMemory[3][0] = 0o33333

        #expect(engine.readMemory(0o1400) == 0o12345)
        #expect(engine.readMemory(0o1400) != 0o33333)
    }

    @Test func gojamMatchesYaAGCRestartState() throws {
        let (engine, state) = try makeEngine()
        prepareBareInstructionRun(engine)
        engine.writeRegister(.regZ, 0o1234)
        engine.cpuWriteIO(address: 0o5, value: 0o377)
        engine.cpuWriteIO(address: 0o6, value: 0o125)
        state.indexValue = 0o77
        state.extraCode = true
        state.substituteInstruction = true
        state.pendFlag = true
        state.tookBZF = true
        state.tookBZMF = true
        state.interruptRequests[5] = 1
        state.parityFail = true
        state.scalerCounter = 80

        let executed = engine.executeCycle()

        #expect(!executed)
        #expect(state.erasableMemory[0][Register.regZ.rawValue] == 0o4000)
        #expect(state.erasableMemory[0][Register.regQ.rawValue] == 0o1234)
        #expect(state.indexValue == 0)
        #expect(!state.extraCode)
        #expect(!state.substituteInstruction)
        #expect(!state.pendFlag)
        #expect(!state.tookBZF)
        #expect(!state.tookBZMF)
        #expect(!state.parityFail)
        #expect(!state.inIsr)
        #expect(state.allowInterrupt)
        #expect(state.interruptRequests[5] == 0)
        #expect(state.outputChannels[0o5] == 0)
        #expect(state.outputChannels[0o6] == 0)
        #expect(state.extraDelay == 1)
        #expect(state.restartLight)
    }

    @Test func executePathCALoadsErasableThroughFetch() async throws {
        let (engine, state) = try makeEngine()
        prepareBareInstructionRun(engine)
        state.erasableMemory[0][0o60] = 0o12345
        state.fixedMemory[2][0] = 0o30060 // CA 060 at 04000
        engine.writeRegister(.regZ, 0o4000)

        await engine.runEngine(for: 16)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o12345)
    }

    @Test func executePathXCHWritesSwitchedErasableBank() async throws {
        let (engine, state) = try makeEngine()
        prepareBareInstructionRun(engine)
        engine.writeRegister(.regEB, 0o2400) // bank 5
        engine.writeRegister(.regBB, 0o5)
        state.erasableMemory[5][0] = 0o22222
        state.erasableMemory[3][0] = 0o33333
        setAccumulator(0o11111, engine: engine)
        state.fixedMemory[2][0] = 0o57400 // XCH 01400
        engine.writeRegister(.regZ, 0o4000)

        await engine.runEngine(for: 16)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o22222)
        #expect(state.erasableMemory[5][0] == 0o11111)
        #expect(state.erasableMemory[3][0] == 0o33333)
    }

    @Test func executePathMASKUsesErasableThroughFetch() async throws {
        let (engine, state) = try makeEngine()
        prepareBareInstructionRun(engine)
        setAccumulator(0o76543, engine: engine)
        state.erasableMemory[0][0o60] = 0o12345
        state.fixedMemory[2][0] = 0o70060 // MASK 060
        state.fixedMemory[2][1] = 0o4001 // TC 04001
        engine.writeRegister(.regZ, 0o4000)

        await engine.runEngine(for: 16)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o12141)
    }

    @Test func executePathADAddsErasableThroughFetch() async throws {
        let (engine, state) = try makeEngine()
        prepareBareInstructionRun(engine)
        setAccumulator(0o1000, engine: engine)
        let target = 0o205
        let (bank, offset) = erasableLocation(for: target)
        state.erasableMemory[bank][offset] = 0o7000
        state.fixedMemory[2][0] = 0o60205 // AD 0205
        state.fixedMemory[2][1] = 0o4001 // TC 04001
        engine.writeRegister(.regZ, 0o4000)

        await engine.runEngine(for: 16)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == signExtend(0o10000))
    }

    @Test func executePathCSComplementsRegisterThroughFetch() async throws {
        let (engine, state) = try makeEngine()
        prepareBareInstructionRun(engine)
        engine.writeRegister(.regL, 0o12345)
        state.fixedMemory[2][0] = 0o40001 // CS L
        state.fixedMemory[2][1] = 0o4001 // TC 04001
        engine.writeRegister(.regZ, 0o4000)

        await engine.runEngine(for: 16)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == signExtend((~0o12345) & 0o77777))
    }

    @Test func executePathINCRAddsOneThroughFetch() async throws {
        let (engine, state) = try makeEngine()
        prepareBareInstructionRun(engine)
        engine.writeRegister(.regL, 0o10)
        state.fixedMemory[2][0] = 0o24001 // INCR L
        state.fixedMemory[2][1] = 0o4001 // TC 04001
        engine.writeRegister(.regZ, 0o4000)

        await engine.runEngine(for: 16)

        #expect(state.erasableMemory[0][Register.regL.rawValue] == 0o11)
    }

    @Test func executePathADSAddsAndStoresThroughFetch() async throws {
        let (engine, state) = try makeEngine()
        prepareBareInstructionRun(engine)
        setAccumulator(0o5000, engine: engine)
        engine.writeRegister(.regL, 0o3000)
        state.fixedMemory[2][0] = 0o26001 // ADS L
        state.fixedMemory[2][1] = 0o4001 // TC 04001
        engine.writeRegister(.regZ, 0o4000)

        await engine.runEngine(for: 16)

        #expect(state.erasableMemory[0][Register.regL.rawValue] == 0o10000)
        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o10000)
    }

    @Test func executePathTCFBranchesThroughFetch() async throws {
        let (engine, state) = try makeEngine()
        prepareBareInstructionRun(engine)
        state.backtrace.removeAll()
        state.fixedMemory[2][0] = 0o14567 // TCF 04567
        state.fixedMemory[2][0o567] = 0o4567 // TC 04567
        engine.writeRegister(.regZ, 0o4000)

        await engine.runEngine(for: 16)

        #expect(state.erasableMemory[0][Register.regZ.rawValue] == 0o4567)
        #expect(state.backtrace.contains { $0.target == 0o4567 })
    }

    @Test func executePathBZFBranchesThroughFetch() async throws {
        let (engine, state) = try makeEngine()
        prepareBareInstructionRun(engine)
        setAccumulator(0, engine: engine)
        state.fixedMemory[2][0] = 0o6 // EXTEND
        state.fixedMemory[2][1] = 0o14321 // BZF 04321
        state.fixedMemory[2][0o321] = 0o4321 // TC 04321
        engine.writeRegister(.regZ, 0o4000)

        await engine.runEngine(for: 16)

        #expect(state.erasableMemory[0][Register.regZ.rawValue] == 0o4321)
        #expect(!state.extraCode)
    }

    @Test func simulateDVMatchesHardwareFallback() throws {
        let (engine, state) = try makeEngine()

        engine.writeRegister(.regA, 0o6215)
        engine.writeRegister(.regL, 0o15163)

        engine.simulateDV(0o146660)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o170010)
        #expect(state.erasableMemory[0][Register.regL.rawValue] == 0o27472)
    }

    @Test func counterOverflowsRaiseInterruptRequests() throws {
        let (engine, state) = try makeEngine()

        state.erasableMemory[0][Register.regTIME2.rawValue] = 0o00001
        engine.interruptRequests(Register.regTIME1.rawValue, 0o40000)
        #expect(state.erasableMemory[0][Register.regTIME2.rawValue] == 0o00002)

        engine.interruptRequests(Register.regTIME5.rawValue, 0o40000)
        #expect(state.interruptRequests[2] == 1)
    }

    @Test func counterPINCHandlesPositiveOverflow() throws {
        let (engine, state) = try makeEngine()
        state.erasableMemory[0][Register.regTIME1.rawValue] = 0o37777

        let overflowed = engine.counterPINC(register: .regTIME1)

        #expect(overflowed)
        #expect(state.erasableMemory[0][Register.regTIME1.rawValue] == 0)
    }

    @Test func counterMINCHandlesNegativeOverflow() throws {
        let (engine, state) = try makeEngine()
        state.erasableMemory[0][Register.regTIME1.rawValue] = 0o40000

        let overflowed = engine.counterMINC(register: .regTIME1)

        #expect(overflowed)
        #expect(state.erasableMemory[0][Register.regTIME1.rawValue] == 0o77777)
    }

    @Test func dxchSwapsDoublePrecisionWords() async throws {
        let (engine, state) = try makeEngine()
        let topAddress = 0o200
        let bottomAddress = (topAddress &- 1) & 0o7777
        let (topBank, topOffset) = erasableLocation(for: topAddress)
        let (bottomBank, bottomOffset) = erasableLocation(for: bottomAddress)

        let initialMemTop = 0o11111
        let initialMemBottom = 0o22222
        let initialRegL = 0o33333
        let initialRegA = 0o12345

        state.erasableMemory[topBank][topOffset] = initialMemTop
        state.erasableMemory[bottomBank][bottomOffset] = initialMemBottom
        engine.writeRegister(.regL, initialRegL)
        engine.writeRegister(.regA, initialRegA)

        state.accumulator = state.erasableMemory[0][Register.regA.rawValue]
        state.nextZ = 0
        engine.handleDXCH(address10: topAddress)

        #expect(state.erasableMemory[topBank][topOffset] == initialRegL)
        #expect(state.erasableMemory[bottomBank][bottomOffset] == initialRegA)
        #expect(state.erasableMemory[0][Register.regL.rawValue] == initialMemTop)
        #expect(state.erasableMemory[0][Register.regA.rawValue] == initialMemBottom)
    }

    @Test func dasDoubleRegistersWhenAddressIsL() async throws {
        let (engine, state) = try makeEngine()
        engine.writeRegister(.regA, 0o1000)
        engine.writeRegister(.regL, 0o2000)
        state.accumulator = state.erasableMemory[0][Register.regA.rawValue]
        state.nextZ = 0
        engine.doubleRegisters()

        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o2000)
        #expect(state.erasableMemory[0][Register.regL.rawValue] == 0o4000)
    }

    @Test func dasUsesPreviousMemoryWordForMostSignificantResult() throws {
        let (engine, state) = try makeEngine()
        let topAddress = 0o200
        let bottomAddress = (topAddress &- 1) & 0o7777
        let topLoc = erasableLocation(for: topAddress)
        let bottomLoc = erasableLocation(for: bottomAddress)

        engine.writeRegister(.regA, 0o2)
        engine.writeRegister(.regL, 0o1)
        state.accumulator = state.erasableMemory[0][Register.regA.rawValue]
        state.erasableMemory[topLoc.bank][topLoc.offset] = 0o3
        state.erasableMemory[bottomLoc.bank][bottomLoc.offset] = 0o4

        let instruction = (0o20 << 9) | topAddress
        engine.executeExtendedInstruction(instruction, opcode: instruction >> 9, overflow: false)

        #expect(state.erasableMemory[topLoc.bank][topLoc.offset] == 0o4)
        #expect(state.erasableMemory[bottomLoc.bank][bottomLoc.offset] == 0o6)
    }

    @Test func luminaryRootFinderConvergesOnCapturedP64TimeToGoPolynomial() throws {
        let (engine, _) = try makeLuminaryEngine()
        prepareBareInstructionRun(engine)

        // Luminary 099 ROOTPSRS is in fixed bank 31 at 3553. Its caller passes
        // A = TABLTTF+3, L = degree-1, and the initial TTF/8 guess in MPAC.
        engine.writeRegister(.regEB, 0o3400) // Erasable bank 7.
        engine.writeRegister(.regFB, 0o62000) // Fixed bank 31 (octal).
        engine.writeRegister(.regBB, 0o62007)
        engine.writeRegister(.regA, 0o1565)
        engine.writeRegister(.regL, 0o2)
        engine.writeRegister(.regQ, 0o3770)
        engine.writeRegister(.regZ, 0o3553)

        #expect(engine.fetchInstructionWord(at: 0o3557) == 0o33676)
        #expect(engine.findMemoryWord(0o3676) == 0o147)

        let capturedTable = [
            0o77777, 0o00130, // A0
            0o00000, 0o11324, // A1
            0o77747, 0o56422, // A2
            0o00022, 0o35646, // A3
            0o00200,          // PRECROOT at TABLTTF+10
        ]
        for (offset, word) in capturedTable.enumerated() {
            engine.writeErasableECADR(0o3562 + offset, word)
        }

        let initialGuess = AGCDoublePrecision.encode(value: -1_320, scale: 17)
        engine.writeErasableECADR(0o154, initialGuess.high)
        engine.writeErasableECADR(0o155, initialGuess.low)

        var executedInstructions = 0
        var failed = false
        while executedInstructions < 20_000 {
            if engine.executeCycle() {
                executedInstructions += 1
            }
            let z = engine.readRegister(.regZ) & 0o7777
            if executedInstructions >= 100 && z == 0o132 {
                failed = true
                break
            }
            if executedInstructions >= 100 && z == 0o3772 {
                break
            }
        }

        let returnAddress = failed ? 0o3770 : engine.readRegister(.regZ) & 0o7777
        let root = AGCDoublePrecision(
            high: engine.readErasableECADR(0o154),
            low: engine.readErasableECADR(0o155)
        ).decoded(scale: 17)

        #expect(returnAddress == 0o3772, "ROOTPSRS took its failure return after \(executedInstructions) instructions")
        #expect(abs(root - -1_320) < 0.001, "ROOTPSRS returned \(root) centiseconds")
        #expect(engine.readErasableECADR(0o156) == 1, "The captured polynomial should converge in one pass")
    }

    @Test func ccsAdjustsNextZForNegativeValues() async throws {
        let (engine, state) = try makeEngine()
        engine.writeRegister(.regA, 0o100000) // Negative overflow
        state.accumulator = state.erasableMemory[0][Register.regA.rawValue]
        state.nextZ = 1
        engine.handleCCS(address10: Register.regA.rawValue)

        #expect(state.nextZ == 3)
        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o77776)
    }

    @Test func maskInstructionUsesErasableMemory() throws {
        let (engine, state) = try makeEngine()
        setAccumulator(0o76543, engine: engine)
        state.erasableMemory[0][0o60] = 0o12345
        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o76543)

        engine.performMask(address12: 0o60)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o12141)
    }

    @Test func readAndWriteIoChannels() throws {
        let (engine, state) = try makeEngine()

        state.inputChannels[0o45] = 0o23456
        setAccumulator(0, engine: engine)
        engine.performRead(address9: 0o45)
        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o23456)

        setAccumulator(0o12345, engine: engine)
        engine.performWrite(address9: 0o45)
        #expect(state.inputChannels[0o45] == 0o12345)
    }

    @Test func cpuIoWriteEmitsOneOutputCallback() throws {
        let (engine, _) = try makeEngine()
        let io = TestIO()
        engine.ioDelegate = io

        engine.writeIOChannel(address: 0o5, value: 0o12345)

        #expect(io.outputs.filter { $0.0 == 0o5 && $0.1 == 0o12345 }.count == 1)
    }

    @Test func channel7WriteUpdatesSuperbankInternally() throws {
        let (engine, state) = try makeEngine()
        let io = TestIO()
        engine.ioDelegate = io

        engine.writeIOChannel(address: 0o7, value: 0o177)

        #expect(state.outputChannel7 == 0o160)
        #expect(state.inputChannels[0o7] == 0o160)
        #expect(state.outputChannels[0o7] == 0o160)
        #expect(!io.outputs.contains { $0.0 == 0o7 })
    }

    @Test func channelInputAppliesUBitMasks() async throws {
        let (engine, state) = try makeEngine()
        let io = TestIO()
        engine.ioDelegate = io
        state.downruptTimeValid = false
        state.inputChannels[0o32] = 0o77777
        io.pendingInputs = [
            [AGCChannelInput(channel: 0o432, value: 0o20000)],
            [AGCChannelInput(channel: 0o32, value: 0)]
        ]

        await engine.runEngine(for: 2)

        #expect((state.inputChannels[0o32] & 0o20000) == 0)
        #expect((state.inputChannels[0o32] & 0o57777) == 0o57777)
    }

    @Test func channelTracePreservesOrderedRepeatedInputs() async throws {
        let runtime = try AGCRuntime(coreImage: Data())
        await runtime.enqueueInputs([
            AGCChannelInput(channel: 0o15, value: 0o21),
            AGCChannelInput(channel: 0o15, value: 0o3),
            AGCChannelInput(channel: 0o15, value: 0o5)
        ])

        let snapshot = await runtime.step(cycles: 1)
        let inputs = snapshot.channelTrace.filter { $0.direction == .input && $0.channel == 0o15 }

        #expect(inputs.map(\.value) == [0o21, 0o3, 0o5])
        #expect(snapshot.inputChannels[0o15] == 0o5)
    }

    @Test func channelInputRaisesUplinkInterrupt() async throws {
        let (engine, state) = try makeEngine()
        let io = TestIO()
        engine.ioDelegate = io
        state.downruptTimeValid = false
        state.allowInterrupt = false
        io.pendingInputs = [[AGCChannelInput(channel: 0o173, value: 0o12345)]]

        await engine.runEngine(for: 1)

        #expect(state.erasableMemory[0][Register.regINLINK.rawValue] == 0o12345)
        #expect(state.interruptRequests[7] == 1)
    }

    @Test func dskyKeypressRaisesKeyruptWhenEngineConsumesQueue() async throws {
        let runtime = try makeRuntime()
        await runtime.sendDSKYKey(.verb)
        let snapshot = await runtime.step(cycles: 1)

        #expect(snapshot.interruptRequests[5] == 1)
        #expect(snapshot.inputChannels[0o15] == 0o21)
    }

    @Test func channel16RaisesKeyrupt2() async throws {
        let (engine, state) = try makeEngine()
        let io = TestIO()
        engine.ioDelegate = io
        state.downruptTimeValid = false
        state.allowInterrupt = false
        io.pendingInputs = [[AGCChannelInput(channel: 0o16, value: 0o40)]]

        await engine.runEngine(for: 1)

        #expect(state.interruptRequests[6] == 1)
        #expect(state.inputChannels[0o16] == 0o40)
    }

    @Test func channel16ReleaseClearsDiscreteWithoutRaisingKeyrupt2() async throws {
        let (engine, state) = try makeEngine()
        let io = TestIO()
        engine.ioDelegate = io
        state.downruptTimeValid = false
        state.allowInterrupt = false
        state.inputChannels[0o16] = 0o100
        io.pendingInputs = [[AGCChannelInput(channel: 0o16, value: 0, interrupt: false)]]

        await engine.runEngine(for: 1)

        #expect(state.inputChannels[0o16] == 0)
        #expect(state.interruptRequests[6] == 0)
    }

    @Test func luminaryDescentMinusInterruptReachesRodCount() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.step(cycles: 1_000_000)
        let before = await runtime.readErasable(ecadr: 0o3746)

        await runtime.enqueueInput(AGCChannelInput(channel: 0o16, value: 0o100))
        _ = await runtime.step(cycles: 20_000)
        let after = await runtime.readErasable(ecadr: 0o3746)

        #expect(after != before, "MARKRUPT DESCEND- should decrement RODCOUNT")
    }

    @Test func proKeyClearsChannel32Bit14() async throws {
        let runtime = try AGCRuntime(coreImage: Data())
        let before = await runtime.snapshot()
        #expect((before.inputChannels[0o32] ?? 0) & 0o20000 != 0)

        await runtime.sendDSKYKey(.pro)
        let snapshot = await runtime.step(cycles: 2)

        #expect((snapshot.inputChannels[0o32] ?? 0) & 0o20000 == 0, "PROCEED is inverted bit 14 of channel 032")
        #expect(snapshot.dsky.proKeyPressed)
        #expect((snapshot.inputChannels[0o13] ?? 0) & 0o20000 == 0, "PRO must not poke channel 013")
    }

    @Test func luminaryPacedV35EDrivesLampTestDisplay() async throws {
        let runtime = try makeRuntime()
        let runner = AGCScenarioRunner(runtime: runtime)

        var snapshot = await runtime.step(cycles: 1_000_000)

        #expect(((snapshot.inputChannels[0o77] ?? 0) & 0o000010) == 0, "Boot should not trip the RUPT LOCK alarm")

        let rsetResult = await runner.rset()
        #expect(!rsetResult.finalSnapshot.dsky.indicatorIsOn(24), "RSET should clear the RESTART light")

        let v35eResult = await runner.v35e()
        snapshot = v35eResult.finalSnapshot

        #expect(snapshot.dsky.lampTest, "Verb 35 should drive the DSKY lamp test when keys are paced at the API level")
        #expect(snapshot.dsky.verb == "88")
        #expect(snapshot.dsky.noun == "88")
        #expect(snapshot.dsky.r1.contains("88888"))
        #expect(snapshot.dsky.indicatorIsOn(24), "RESTART annunciator should light during lamp test")
        #expect(snapshot.dsky.indicatorIsOn(13), "STBY annunciator should light during lamp test")
    }

    @Test func luminaryPacedV16N36ECapturesDSKYActivity() async throws {
        let runtime = try makeRuntime()
        let runner = AGCScenarioRunner(runtime: runtime)

        _ = await runtime.step(cycles: 1_000_000)
        let result = await runner.v16n36e()
        let channel15Values = result.channelTrace
            .filter { $0.direction == .input && $0.channel == 0o15 }
            .map(\.value)

        #expect(Array(channel15Values.suffix(DSKYScript.v16n36e.keys.count)) == DSKYScript.v16n36e.keys.map(\.rawValue))
        #expect(result.channelTrace.contains { $0.direction == .output && ($0.channel == 0o10 || $0.channel == 0o163) })
    }

    @Test func rotationalHandControllerInputsLatchWhenRequested() async throws {
        let (engine, state) = try makeEngine()
        let io = TestIO()
        engine.ioDelegate = io
        state.downruptTimeValid = false
        io.pendingInputs = [
            [AGCChannelInput(channel: 0o166, value: 0o1)],
            [AGCChannelInput(channel: 0o167, value: 0o2)],
            [AGCChannelInput(channel: 0o170, value: 0o3)]
        ]

        await engine.runEngine(for: 3)
        engine.writeIOChannel(address: 0o13, value: 0o600)

        #expect(state.erasableMemory[0][Register.regRHCP.rawValue] == 0o1)
        #expect(state.erasableMemory[0][Register.regRHCY.rawValue] == 0o2)
        #expect(state.erasableMemory[0][Register.regRHCR.rawValue] == 0o3)
    }

    @Test func unprogrammedDincEmitsZoutPulse() async throws {
        let (engine, state) = try makeEngine()
        let io = TestIO()
        engine.ioDelegate = io

        let counterAddress = 0o37
        state.erasableMemory[0][counterAddress] = 0
        io.pendingInputs = [[AGCChannelInput(channel: 0o200 | counterAddress, value: 4)]]

        await engine.runEngine(for: 1)

        let expectedChannel = 0o200 | counterAddress
        #expect(io.outputs.contains { $0.0 == expectedChannel && $0.1 == 0o17 })
        #expect(state.erasableMemory[0][counterAddress] == 0)
    }

    @Test func randAndWandCombineAccumulatorWithRegisters() throws {
        let (engine, state) = try makeEngine()

        engine.writeRegister(.regL, 0o77777)
        setAccumulator(0o12345, engine: engine)
        engine.performRand(address9: Register.regL.rawValue)
        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o12345)
        #expect(state.erasableMemory[0][Register.regL.rawValue] == 0o77777)

        engine.writeRegister(.regL, 0o70000)
        setAccumulator(0o40000, engine: engine)
        engine.performWand(address9: Register.regL.rawValue)
        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o40000)
        #expect(state.erasableMemory[0][Register.regL.rawValue] == 0o40000)
    }

    @Test func rorCombinesAccumulatorWithRegister() throws {
        let (engine, state) = try makeEngine()
        setAccumulator(0o12345, engine: engine)
        engine.writeRegister(.regL, 0o70000)

        engine.performRor(address9: Register.regL.rawValue)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o72345)
    }

    @Test func worWritesBackToRegister() throws {
        let (engine, state) = try makeEngine()
        setAccumulator(0o40000, engine: engine)
        engine.writeRegister(.regL, 0o20000)

        engine.performWor(address9: Register.regL.rawValue)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o60000)
        #expect(state.erasableMemory[0][Register.regL.rawValue] == 0o60000)
    }

    @Test func lxchZeroClearsL() throws {
        let (engine, state) = try makeEngine()
        engine.writeRegister(.regL, 0o12345)

        engine.performLXCH(address10: Register.regZERO.rawValue)

        #expect(state.erasableMemory[0][Register.regL.rawValue] == 0)
    }

    @Test func lxchSwapsWithErasableMemory() throws {
        let (engine, state) = try makeEngine()
        let target = 0o210
        let (bank, offset) = erasableLocation(for: target)
        state.erasableMemory[bank][offset] = 0o45670
        engine.writeRegister(.regL, 0o12345)

        engine.performLXCH(address10: target)

        #expect(state.erasableMemory[0][Register.regL.rawValue] == signExtend(0o45670))
        #expect(state.erasableMemory[bank][offset] == 0o12345)
    }

    @Test func tsOvskIncrementsNextZOnOverflow() throws {
        let (engine, state) = try makeEngine()
        state.nextZ = 0o10

        engine.performTS(address10: Register.regA.rawValue, overflow: true)

        #expect(state.nextZ == 0o11)
    }

    @Test func tsPropagatesNegativeOverflowAsAGCMinusOne() throws {
        let (engine, state) = try makeEngine()
        setAccumulator(0o137777, engine: engine)
        state.nextZ = 0o10

        engine.performTS(address10: 0o60, overflow: true)

        #expect(engine.valueOverflowed(0o137777) == 0o77776)
        #expect(state.erasableMemory[0][0o60] == 0o77777)
        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o177776)
        #expect(state.nextZ == 0o11)
    }

    @Test func tsTCAAStoresAccumulatorIntoZ() throws {
        let (engine, state) = try makeEngine()
        setAccumulator(0o54321, engine: engine)
        state.nextZ = 0

        engine.performTS(address10: Register.regZ.rawValue, overflow: false)

        #expect(state.nextZ == 0o54321)
    }

    @Test func xchSwapsWithMemoryAndUpdatesZ() throws {
        let (engine, state) = try makeEngine()
        setAccumulator(0o12345, engine: engine)
        let target = Register.regZ.rawValue
        engine.writeRegister(.regZ, 0o77777)

        engine.performXCH(address10: target)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == signExtend(0o77777))
        #expect(state.erasableMemory[0][Register.regZ.rawValue] == 0o12345)
        #expect(state.nextZ == 0o12345)
    }

    @Test func adAddsErasableValueToAccumulator() throws {
        let (engine, state) = try makeEngine()
        setAccumulator(0o1000, engine: engine)
        let target = 0o205
        let (bank, offset) = erasableLocation(for: target)
        state.erasableMemory[bank][offset] = 0o7000

        engine.performAD(address12: target)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == signExtend(0o10000))
    }

    @Test func adsAddsAndStoresResult() throws {
        let (engine, state) = try makeEngine()
        setAccumulator(0o5000, engine: engine)
        engine.writeRegister(.regL, 0o3000)

        engine.performADS(address10: Register.regL.rawValue)

        #expect(state.erasableMemory[0][Register.regL.rawValue] == 0o10000)
        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o10000)
    }

    @Test func incrAddsOneToRegister() throws {
        let (engine, state) = try makeEngine()
        engine.writeRegister(.regL, 0o10)

        engine.performINCR(address10: Register.regL.rawValue)

        #expect(state.erasableMemory[0][Register.regL.rawValue] == 0o11)
    }

    @Test func dcaLoadsDoublePrecisionFromMemory() throws {
        let (engine, state) = try makeEngine()
        let top = 0o220
        let bottom = (top &- 1) & 0o7777
        let topLoc = erasableLocation(for: top)
        let bottomLoc = erasableLocation(for: bottom)
        state.erasableMemory[topLoc.bank][topLoc.offset] = 0o12345
        state.erasableMemory[bottomLoc.bank][bottomLoc.offset] = 0o65432
        setAccumulator(0o77777, engine: engine)
        engine.writeRegister(.regL, 0o77777)

        engine.performDCA(address12: top)

        #expect(state.erasableMemory[0][Register.regL.rawValue] == signExtend(0o12345))
        #expect(state.erasableMemory[0][Register.regA.rawValue] == signExtend(0o65432))
        #expect(state.erasableMemory[topLoc.bank][topLoc.offset] == 0o12345)
        #expect(state.erasableMemory[bottomLoc.bank][bottomLoc.offset] == 0o65432)
    }

    @Test func dcsComplementsDoublePrecisionValue() throws {
        let (engine, state) = try makeEngine()
        let top = 0o230
        let bottom = (top &- 1) & 0o7777
        let topLoc = erasableLocation(for: top)
        let bottomLoc = erasableLocation(for: bottom)
        state.erasableMemory[topLoc.bank][topLoc.offset] = 0o10000
        state.erasableMemory[bottomLoc.bank][bottomLoc.offset] = 0o20000

        engine.performDCS(address12: top)

        #expect(state.erasableMemory[0][Register.regL.rawValue] == signExtend(0o67777))
        #expect(state.erasableMemory[0][Register.regA.rawValue] == signExtend(0o57777))
        #expect(state.erasableMemory[topLoc.bank][topLoc.offset] == 0o10000)
        #expect(state.erasableMemory[bottomLoc.bank][bottomLoc.offset] == 0o20000)
    }

    @Test func suSubtractsUnitFromMemoryOperand() throws {
        let (engine, state) = try makeEngine()
        setAccumulator(0o3000, engine: engine)
        let address = 0o240
        let loc = erasableLocation(for: address)
        state.erasableMemory[loc.bank][loc.offset] = 0o1000
        state.extraCode = true

        engine.performSU(address10: address)

        let expected = signExtend(0o2000)
        #expect(state.erasableMemory[0][Register.regA.rawValue] == expected)
        #expect(state.erasableMemory[loc.bank][loc.offset] == 0o1000)
    }

    @Test func mpZeroOperandClearsProduct() throws {
        let (engine, state) = try makeEngine()
        setAccumulator(0, engine: engine)
        let address = 0o250
        let loc = erasableLocation(for: address)
        state.erasableMemory[loc.bank][loc.offset] = 0o12345

        engine.performMP(address12: address)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0)
        #expect(state.erasableMemory[0][Register.regL.rawValue] == 0)
    }

    @Test func mpMultipliesPositiveNumbers() throws {
        let (engine, state) = try makeEngine()
        setAccumulator(0o2, engine: engine)
        let address = 0o260
        let loc = erasableLocation(for: address)
        state.erasableMemory[loc.bank][loc.offset] = 0o3

        engine.performMP(address12: address)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0)
        #expect(state.erasableMemory[0][Register.regL.rawValue] == 0o6)
    }

    @Test func mpNegativeZeroTimesPositiveYieldsNegativeZero() throws {
        let (engine, state) = try makeEngine()
        setAccumulator(0o177777, engine: engine)
        let address = 0o261
        let loc = erasableLocation(for: address)
        state.erasableMemory[loc.bank][loc.offset] = 0o1

        engine.performMP(address12: address)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o177777)
        #expect(state.erasableMemory[0][Register.regL.rawValue] == 0o177777)
    }

    @Test func mpNegativeTimesPositiveSignExtendsProduct() throws {
        let (engine, state) = try makeEngine()
        setAccumulator(signExtend(0o77775), engine: engine) // -2
        let address = 0o262
        let loc = erasableLocation(for: address)
        state.erasableMemory[loc.bank][loc.offset] = 0o3

        engine.performMP(address12: address)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == signExtend(0o77777))
        #expect(state.erasableMemory[0][Register.regL.rawValue] == signExtend(0o77771)) // -6
    }
    @Test func qxchZeroClearsQRegister() throws {
        let (engine, state) = try makeEngine()
        engine.writeRegister(.regQ, 0o12345)

        engine.performQXCH(address10: Register.regZERO.rawValue)

        #expect(state.erasableMemory[0][Register.regQ.rawValue] == 0)
    }

    @Test func caLoadsRegisterIntoAccumulator() throws {
        let (engine, state) = try makeEngine()
        engine.writeRegister(.regL, 0o12345)

        engine.performCA(address12: Register.regL.rawValue)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == signExtend(0o12345))
    }

    @Test func csComplementsRegisterValue() throws {
        let (engine, state) = try makeEngine()
        engine.writeRegister(.regL, 0o12345)

        engine.performCS(address12: Register.regL.rawValue)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == signExtend((~0o12345) & 0o77777))
    }

    @Test func qxchWithZSwapsAndUpdatesNextZ() throws {
        let (engine, state) = try makeEngine()
        engine.writeRegister(.regQ, 0o11111)
        engine.writeRegister(.regZ, 0o22222)
        state.nextZ = 0o33333

        engine.performQXCH(address10: Register.regZ.rawValue)

        #expect(state.erasableMemory[0][Register.regQ.rawValue] == 0o22222)
        #expect(state.erasableMemory[0][Register.regZ.rawValue] == 0o11111)
        #expect(state.nextZ == 0o11111)
    }

    @Test func dvEqualDividendAndDivisorProducesSaturatedQuotient() throws {
        let (engine, state) = try makeEngine()
        let value = 0o37777
        setAccumulator(value, engine: engine)
        engine.writeRegister(.regL, 0)
        let address = 0o60
        state.erasableMemory[0][address] = value

        engine.performDV(address10: address)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o37777)
        #expect(state.erasableMemory[0][Register.regL.rawValue] == value)
    }

    @Test func dvZeroDividendProducesSignedZero() throws {
        let (engine, state) = try makeEngine()
        engine.writeRegister(.regA, 0)
        engine.writeRegister(.regL, 0)
        let address = 0o61
        state.erasableMemory[0][address] = 0o12345

        engine.performDV(address10: address)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0)
        #expect(state.erasableMemory[0][Register.regL.rawValue] == 0)
    }

    @Test func dvNormalizesMixedSignDividendBeforeBoundaryCheck() throws {
        let (engine, state) = try makeEngine()
        setAccumulator(0o1, engine: engine)
        engine.writeRegister(.regL, signExtend(0o77776))
        let address = 0o62
        state.erasableMemory[0][address] = 0o1

        engine.performDV(address10: address)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o37777)
        #expect(state.erasableMemory[0][Register.regL.rawValue] == 0)
    }

    @Test func backtraceCapturesTcAndBranches() throws {
        let (engine, state) = try makeEngine()
        state.backtrace.removeAll()

        let tcTarget = 0o200
        let tcInstruction = tcTarget
        engine.executeExtendedInstruction(tcInstruction, opcode: tcInstruction >> 9, overflow: false)

        #expect(state.backtrace.last?.target == tcTarget)

        setAccumulator(0, engine: engine)
        _ = engine.performBZF(address12: 0o377)

        #expect(state.backtrace.last?.target == 0o377)

        setAccumulator(0o100000, engine: engine)
        _ = engine.performBZMF(address12: 0o444)
        #expect(state.backtrace.last?.target == 0o444)
    }

    @Test func executeInstructionUsesActualLowBitOperandFields() throws {
        let (engine, state) = try makeEngine()

        let tcInstruction = 0o1234
        state.nextZ = 0o4321
        engine.executeExtendedInstruction(tcInstruction, opcode: tcInstruction >> 9, overflow: false)
        #expect(state.nextZ == 0o1234)
        #expect(state.erasableMemory[0][Register.regQ.rawValue] == 0o4321)

        engine.writeRegister(.regL, 0o24642)
        let caLInstruction = (0o30 << 9) | Register.regL.rawValue
        engine.executeExtendedInstruction(caLInstruction, opcode: caLInstruction >> 9, overflow: false)
        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o24642)
    }

    @Test func executeIncrUsesTenBitOperandField() throws {
        let (engine, state) = try makeEngine()

        state.erasableMemory[0][Register.regTIME1.rawValue] = 0o37777
        state.erasableMemory[0][Register.regTIME2.rawValue] = 0

        let instruction = (0o24 << 9) | Register.regTIME1.rawValue
        engine.executeExtendedInstruction(instruction, opcode: instruction >> 9, overflow: false)

        #expect(state.erasableMemory[0][Register.regTIME1.rawValue] == 0)
        #expect(state.erasableMemory[0][Register.regTIME2.rawValue] == 1)
    }

    @Test func edruptVectorsToAddressZero() async throws {
        let (engine, state) = try makeEngine()
        engine.ioDelegate = nil
        engine.writeRegister(.regZ, 0)
        let instruction = 0o7000
        state.erasableMemory[0][0] = instruction
        state.allowInterrupt = true
        state.extraCode = true
        state.inIsr = false
        state.downruptTimeValid = false
        state.backtrace.removeAll()
        for i in 0..<state.interruptRequests.count {
            state.interruptRequests[i] = 0
        }

        await engine.runEngine(for: 1)

        #expect(state.inIsr)
        #expect(state.nextZ == 0)
        #expect(state.erasableMemory[0][Register.regZRUPT.rawValue] == 0o1)
        #expect(state.erasableMemory[0][Register.regBRUPT.rawValue] == instruction)
        #expect(state.backtrace.last?.target == 0)
    }

    @Test func rxorCombinesWithIoChannel() throws {
        let (engine, state) = try makeEngine()
        state.inputChannels[0o47] = 0o77777
        setAccumulator(0o12345, engine: engine)

        engine.performRxor(address9: 0o47)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o165432)
        #expect(state.inputChannels[0o47] == 0o77777)
    }

    @Test func bzfBranchesWhenAccumulatorZero() throws {
        let (engine, state) = try makeEngine()
        setAccumulator(0, engine: engine)

        #expect(engine.performBZF(address12: 0o321))
        #expect(state.nextZ == 0o321)
    }

    @Test func bzmfBranchesOnNegativeAccumulator() throws {
        let (engine, state) = try makeEngine()
        setAccumulator(0o100000, engine: engine)

        #expect(engine.performBZMF(address12: 0o654))
        #expect(state.nextZ == 0o654)
    }

    @Test func indexResumeRestoresZrupt() throws {
        let (engine, state) = try makeEngine()
        engine.writeRegister(.regZRUPT, 0o1234)
        state.inIsr = true
        state.substituteInstruction = false

        engine.performResume()

        #expect(state.nextZ == 0o1233)
        #expect(state.substituteInstruction)
        #expect(!state.inIsr)
    }

    @Test func indexInstructionLoadsRegisterValue() throws {
        let (engine, state) = try makeEngine()
        engine.writeRegister(.regL, 0o12345)

        engine.performIndex(address10: Register.regL.rawValue)

        #expect(state.indexValue == 0o12345)
    }

    @Test func indexInstructionLoadsMemoryValue() throws {
        let (engine, state) = try makeEngine()
        let address = 0o400
        state.erasableMemory[1][0] = 0o54321

        engine.performIndex(address10: address)

        #expect(state.indexValue == 0o54321)
    }

    @Test func extracodeIndexKeepsExtraCodeFlag() throws {
        let (engine, state) = try makeEngine()
        state.extraCode = true
        state.erasableMemory[1][0] = 0o11111

        let keep = engine.performExtracodeIndex(address12: 0o400)

        #expect(keep)
        #expect(state.extraCode)
        #expect(state.indexValue == 0o11111)
    }

    @Test func extracodeIndexResumeInvokesResume() throws {
        let (engine, state) = try makeEngine()
        engine.writeRegister(.regZRUPT, 0o2000)
        state.inIsr = true

        let keep = engine.performExtracodeIndex(address12: 0o17 << 1)

        #expect(!keep)
        #expect(state.substituteInstruction)
        #expect(!state.inIsr)
    }

    @Test func tcfAddsBacktraceEntry() throws {
        let (engine, state) = try makeEngine()
        state.backtrace.removeAll()

        engine.performTCF(address12: 0o4567)

        #expect(state.backtrace.last?.target == 0o4567)
    }

    @Test func indexAppliesPositiveOffset() throws {
        let (engine, state) = try makeEngine()
        let base = 0o30000
        state.indexValue = 0o5

        let result = engine.applyIndex(to: base) & 0o77777

        #expect(result == addSP(base, 0o5))
    }

    @Test func indexAppliesNegativeOffset() throws {
        let (engine, state) = try makeEngine()
        let base = 0o30000
        state.indexValue = 0o77776

        let result = engine.applyIndex(to: base) & 0o77777

        let expected = (base & 0o77777 &- 1) & 0o77777
        #expect(result == expected)
    }

    @Test func msuWithMatchingValuesClearsAccumulator() throws {
        let (engine, state) = try makeEngine()
        let register = Register.regOPTX.rawValue
        engine.writeRegister(Register(rawValue: register)!, 0o12345)
        setAccumulator(0o12345, engine: engine)

        engine.performMSU(address10: register)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0)
    }

    @Test func msuWithMemoryOperandSubtractsZero() throws {
        let (engine, state) = try makeEngine()
        let address = 0o400
        state.erasableMemory[1][0] = 0
        setAccumulator(0, engine: engine)

        engine.performMSU(address10: address)

        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0)
    }

    @Test func augIncrementsPositiveValues() throws {
        let (engine, state) = try makeEngine()
        let reg = Register.regOPTY.rawValue
        engine.writeRegister(Register(rawValue: reg)!, 0o5)

        engine.performAUG(address10: reg)

        #expect(state.erasableMemory[0][reg] == 0o6)
    }

    @Test func dimDecrementsUntilZero() throws {
        let (engine, state) = try makeEngine()
        let reg = Register.regOPTY.rawValue
        engine.writeRegister(Register(rawValue: reg)!, 0o3)

        engine.performDIM(address10: reg)
        #expect(state.erasableMemory[0][reg] == 0o2)

        engine.writeRegister(Register(rawValue: reg)!, 0)
        engine.performDIM(address10: reg)
        #expect(state.erasableMemory[0][reg] == 0)
    }

    @Test func `runtime instruction step and erasable watch`() async throws {
        let runtime = try makeRuntime()
        await runtime.watchErasable(Register.regZ.rawValue)
        await runtime.setBreakpoint(0o4000)
        let before = await runtime.snapshot()
        let after = await runtime.stepInstruction()
        let debug = await runtime.debuggerSnapshot()

        #expect(after.cycle > before.cycle)
        #expect(!debug.current.mnemonic.isEmpty)
        #expect(!debug.listing.isEmpty)
        #expect(debug.watches.contains { $0.address == Register.regZ.rawValue })
        #expect(debug.breakpoints.contains(0o4000))
    }
}

// MARK: - AGC integration (scaler parity, composite delegate)

@Suite("AGC integration")
struct AGCIntegrationTests {
    @Test func `Scaler tick updates input channel four`() async throws {
        let state = AGCState()
        state.binFile = Data()
        let engine = try AGCEngine(state: state)
        await engine.runEngine(for: 40)
        #expect(state.inputChannels[4] > 0)
    }

    @Test func `DSKY program scripts generate V37E program entry`() {
        #expect(DSKYScript.program(63).keys == [.verb, .digit3, .digit7, .enter, .digit6, .digit3, .enter])
        #expect(DSKYScript.v37e64e.keys == [.verb, .digit3, .digit7, .enter, .digit6, .digit4, .enter])
        #expect(DSKYScript.v37e65e.id == "V37E65E")
        #expect(DSKYScript.v37e66e.id == "V37E66E")
    }

    @Test func `disassembler names EXTEND RELINT and TC`() {
        #expect(AGCDisassembler.disassemble(word: 0o00006, at: 0o4000, extraCode: false).mnemonic == "EXTEND")
        #expect(AGCDisassembler.disassemble(word: 0o00003, at: 0, extraCode: false).mnemonic == "RELINT")
        #expect(AGCDisassembler.disassemble(word: 0o02000, at: 0o4000, extraCode: false).mnemonic == "TC")
        #expect(AGCDisassembler.disassemble(word: 0o01015, at: 0, extraCode: true).mnemonic == "WRITE")
    }

    @Test func `Composite merges channel input`() async throws {
        final class PartA: AGCIOProtocol, @unchecked Sendable {
            func channelOutput(channel: Int, value: Int) {}
            func channelInput() -> [AGCChannelInput]? { [AGCChannelInput(channel: 0o15, value: 0o11)] }
            func requestRadarData() {}
            func shiftToDeda(data: Int) {}
            func channelRoutine() {}
        }
        final class PartB: AGCIOProtocol, @unchecked Sendable {
            func channelOutput(channel: Int, value: Int) {}
            func channelInput() -> [AGCChannelInput]? { [AGCChannelInput(channel: 0o16, value: 0o22)] }
            func requestRadarData() {}
            func shiftToDeda(data: Int) {}
            func channelRoutine() {}
        }
        let composite = CompositeAGCIO(children: [PartA(), PartB()])
        let merged = composite.channelInput()
        #expect(merged == [
            AGCChannelInput(channel: 0o15, value: 0o11),
            AGCChannelInput(channel: 0o16, value: 0o22)
        ])
    }

    @Test func `AGC per second matches yaAGC macro`() {
        // C / Swift integer division: (1024000 + 6) / 12 → 85333 (yaAGC `AGC_PER_SECOND`).
        #expect(UInt64((1_024_000 + 6) / 12) == 85_333)
    }

    @Test func `Downlink arms downrupt when channels 34 and 35 written`() throws {
        let state = AGCState()
        state.binFile = Data()
        let engine = try AGCEngine(state: state)
        state.downruptTimeValid = false
        state.downruptTime = 0
        state.downlink = 0
        let agcPerSecond = UInt64((1_024_000 + 6) / 12)
        let expectedDelta = agcPerSecond / 50
        #expect(expectedDelta == 1706)
        engine.writeIOChannel(address: 0o34, value: 1)
        engine.writeIOChannel(address: 0o35, value: 2)
        #expect(state.downruptTimeValid)
        #expect(state.downruptTime == expectedDelta)
    }

    @Test func `Scaler two advances when scaler one overflows`() async throws {
        let state = AGCState()
        state.binFile = Data()
        let engine = try AGCEngine(state: state)
        state.downruptTimeValid = false
        await engine.runEngine(for: 600_000)
        #expect(state.inputChannels[3] > 0)
    }

    @Test func `CDU FIFO delays PCDU on CDUX`() async throws {
        let state = AGCState()
        state.binFile = Data()
        let engine = try makeEngineForLMTests(state: state)
        let io = LMTestIO()
        engine.ioDelegate = io
        state.erasableMemory[0][Register.regCDUX.rawValue] = 0
        io.pendingInputs = [[AGCChannelInput(channel: 0o200 | Register.regCDUX.rawValue, value: 1)]]
        await engine.runEngine(for: 1)
        #expect(state.erasableMemory[0][Register.regCDUX.rawValue] == 0)
        await engine.runEngine(for: 400)
        #expect(state.erasableMemory[0][Register.regCDUX.rawValue] == 1)
    }

    @Test func `Non-CDU immediate PCDU does not use FIFO`() async throws {
        let state = AGCState()
        state.binFile = Data()
        let engine = try makeEngineForLMTests(state: state)
        let io = LMTestIO()
        engine.ioDelegate = io
        let cmd = Register.regCDUXCMD.rawValue
        state.erasableMemory[0][cmd] = 0
        io.pendingInputs = [[AGCChannelInput(channel: 0o200 | cmd, value: 1)]]
        await engine.runEngine(for: 1)
        #expect(state.erasableMemory[0][cmd] == 1)
    }

    @Test func `Radar completion calls delegate and RADARUPT`() throws {
        let state = AGCState()
        state.binFile = Data()
        let engine = try AGCEngine(state: state)
        let spy = RadarSpyIO()
        engine.ioDelegate = spy
        state.interruptRequests[9] = 0
        engine.integrationTestCompleteRadarSampleGate()
        #expect(spy.radarCallCount == 1)
        #expect(state.interruptRequests[9] == 1)
        #expect(state.radarGateCounter == 0)
        #expect((state.inputChannels[0o13] & 0o10) == 0)
    }

    @Test func `Radar gate advances when activity bit set`() async throws {
        let state = AGCState()
        state.binFile = Data()
        let engine = try AGCEngine(state: state)
        state.downruptTimeValid = false
        state.inputChannels[0o13] |= 0o10
        let before = state.radarGateCounter
        await engine.runEngine(for: 80_000)
        #expect(state.radarGateCounter > before)
    }

    @Test func `Run engine UInt64 max respects task cancellation`() async throws {
        let cycles = await withTaskGroup(of: UInt64.self) { group in
            group.addTask {
                let state = AGCState()
                state.binFile = Data()
                let engine = try! AGCEngine(state: state)
                await engine.runEngine(for: UInt64.max)
                return engine.state.cycleCounter
            }
            group.cancelAll()
            return await group.next() ?? 0
        }
        #expect(cycles < 200_000)
    }

    @Test func `Composite fans out channel output and radar`() {
        final class CountIO: AGCIOProtocol, @unchecked Sendable {
            var outputs = 0
            var radars = 0
            var routines = 0
            func channelOutput(channel: Int, value: Int) { outputs += 1 }
            func channelInput() -> [AGCChannelInput]? { nil }
            func requestRadarData() { radars += 1 }
            func shiftToDeda(data: Int) {}
            func channelRoutine() { routines += 1 }
        }
        let a = CountIO()
        let b = CountIO()
        let c = CompositeAGCIO(children: [a, b])
        c.channelOutput(channel: 0o5, value: 1)
        #expect(a.outputs == 1 && b.outputs == 1)
        c.requestRadarData()
        #expect(a.radars == 1 && b.radars == 1)
    }

    @Test func `Composite fans out channel routine`() {
        final class RoutineIO: AGCIOProtocol, @unchecked Sendable {
            var count = 0
            func channelOutput(channel: Int, value: Int) {}
            func channelInput() -> [AGCChannelInput]? { nil }
            func requestRadarData() {}
            func shiftToDeda(data: Int) {}
            func channelRoutine() { count += 1 }
        }
        let a = RoutineIO()
        let b = RoutineIO()
        let c = CompositeAGCIO(children: [a, b])
        c.channelRoutine()
        #expect(a.count == 1 && b.count == 1)
    }

}

// MARK: - LM test helpers

private func makeEngineForLMTests(state: AGCState) throws -> AGCEngine {
    let engine = try AGCEngine(state: state)
    state.downruptTimeValid = false
    return engine
}

private final class LMTestIO: AGCIOProtocol, @unchecked Sendable {
    var pendingInputs: [[AGCChannelInput]] = []

    func channelOutput(channel: Int, value: Int) {}

    func channelInput() -> [AGCChannelInput]? {
        guard !pendingInputs.isEmpty else { return nil }
        return pendingInputs.removeFirst()
    }

    func requestRadarData() {}
    func shiftToDeda(data: Int) {}
    func channelRoutine() {}
}

private final class RadarSpyIO: AGCIOProtocol, @unchecked Sendable {
    private(set) var radarCallCount = 0

    func channelOutput(channel: Int, value: Int) {}
    func channelInput() -> [AGCChannelInput]? { nil }
    func requestRadarData() { radarCallCount += 1 }
    func shiftToDeda(data: Int) {}
    func channelRoutine() {}
}
