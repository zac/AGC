import Testing
import Foundation

@testable import AGC

@Suite("AGC Tests")
class AGCTests {

    private var library: AGC? = {
        guard let url = Bundle.module.url(forResource: "Luminary099", withExtension: "bin") else {
            return nil
        }
        return try? AGC(binFile: url)
    }()

    private func makeEngine() throws -> (AGCEngine, AGCState) {
        let state = AGCState()
        state.binFile = Data()
        let engine = try AGCEngine(state: state)
        return (engine, state)
    }

    private func setAccumulator(_ value: Int, engine: AGCEngine) {
        engine.state.accumulator = value & 0o177777
        engine.writeRegister(.regA, engine.state.accumulator)
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
        var pendingInputs: [[Int:Int]] = []
        var outputs: [(Int, Int)] = []

        func channelOutput(channel: Int, value: Int) {
            outputs.append((channel, value))
        }

        func channelInput() async -> [Int:Int]? {
            guard !pendingInputs.isEmpty else { return nil }
            return pendingInputs.removeFirst()
        }

        func requestRadarData() {}
        func shiftToDeda(data: Int) {}
        func channelRoutine() async {}
    }

    @Test func engineCreation() async throws {
        let library = try #require(self.library)
        try library.reset()
    }

    @Test func runEngineFor1000Cycles() async throws {
        let library = try #require(self.library)
        try library.reset()
        await library.run(for: 1000)
        #expect(library.state.cycleCounter == 1000)
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

    @Test func unprogrammedDincEmitsZoutPulse() async throws {
        let (engine, state) = try makeEngine()
        let io = TestIO()
        engine.ioDelegate = io

        let counterAddress = 0o37
        state.erasableMemory[0][counterAddress] = 0
        io.pendingInputs = [[0o200 | counterAddress: 4]]

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

        #expect(state.erasableMemory[0][Register.regA.rawValue] == 0o77777)
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

    @Test func backtraceCapturesTcAndBranches() throws {
        let (engine, state) = try makeEngine()
        state.backtrace.removeAll()

        let tcTarget = 0o200
        let tcInstruction = tcTarget << 6
        engine.executeExtendedInstruction(tcInstruction, opcode: 0, overflow: false)

        #expect(state.backtrace.last?.target == tcTarget)

        setAccumulator(0, engine: engine)
        _ = engine.performBZF(address12: 0o377)

        #expect(state.backtrace.last?.target == 0o377)

        setAccumulator(0o100000, engine: engine)
        _ = engine.performBZMF(address12: 0o444)
        #expect(state.backtrace.last?.target == 0o444)
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
        #expect(state.extraDelay > 0)
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
}

// MARK: - LM integration (scaler parity, vehicle I/O, composite delegate)

@Suite("LM integration")
struct LMIntegrationTests {
    @Test func `Scaler tick updates input channel four`() async throws {
        let state = AGCState()
        state.binFile = Data()
        let engine = try AGCEngine(state: state)
        await engine.runEngine(for: 40)
        #expect(state.inputChannels[4] > 0)
    }

    @Test func `LMVehicleIO captures channels five and six`() throws {
        let state = AGCState()
        state.binFile = Data()
        let engine = try AGCEngine(state: state)
        let lm = LMVehicleIO()
        engine.ioDelegate = lm
        engine.writeIOChannel(address: 0o5, value: 0o12121)
        engine.writeIOChannel(address: 0o6, value: 0o06060)
        #expect(lm.jetEngineOutputs.channel5 == 0o12121)
        #expect(lm.jetEngineOutputs.channel6 == 0o06060)
    }

    @Test func `Composite merges channel input`() async throws {
        final class PartA: AGCIOProtocol, @unchecked Sendable {
            func channelOutput(channel: Int, value: Int) {}
            func channelInput() async -> [Int: Int]? { [0o15: 0o11] }
            func requestRadarData() {}
            func shiftToDeda(data: Int) {}
            func channelRoutine() async {}
        }
        final class PartB: AGCIOProtocol, @unchecked Sendable {
            func channelOutput(channel: Int, value: Int) {}
            func channelInput() async -> [Int: Int]? { [0o16: 0o22] }
            func requestRadarData() {}
            func shiftToDeda(data: Int) {}
            func channelRoutine() async {}
        }
        let composite = CompositeAGCIO(children: [PartA(), PartB()])
        let merged = await composite.channelInput()
        #expect(merged?[0o15] == 0o11)
        #expect(merged?[0o16] == 0o22)
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
        io.pendingInputs = [[0o200 | Register.regCDUX.rawValue: 1]]
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
        io.pendingInputs = [[0o200 | cmd: 1]]
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
        let state = AGCState()
        state.binFile = Data()
        let engine = try AGCEngine(state: state)
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await engine.runEngine(for: UInt64.max)
            }
            group.cancelAll()
        }
        #expect(state.cycleCounter < 200_000)
    }

    @Test func `Composite fans out channel output and radar`() {
        final class CountIO: AGCIOProtocol, @unchecked Sendable {
            var outputs = 0
            var radars = 0
            var routines = 0
            func channelOutput(channel: Int, value: Int) { outputs += 1 }
            func channelInput() async -> [Int: Int]? { nil }
            func requestRadarData() { radars += 1 }
            func shiftToDeda(data: Int) {}
            func channelRoutine() async { routines += 1 }
        }
        let a = CountIO()
        let b = CountIO()
        let c = CompositeAGCIO(children: [a, b])
        c.channelOutput(channel: 0o5, value: 1)
        #expect(a.outputs == 1 && b.outputs == 1)
        c.requestRadarData()
        #expect(a.radars == 1 && b.radars == 1)
    }

    @Test func `Composite awaits channel routine`() async {
        final class RoutineIO: AGCIOProtocol, @unchecked Sendable {
            var count = 0
            func channelOutput(channel: Int, value: Int) {}
            func channelInput() async -> [Int: Int]? { nil }
            func requestRadarData() {}
            func shiftToDeda(data: Int) {}
            func channelRoutine() async { count += 1 }
        }
        let a = RoutineIO()
        let b = RoutineIO()
        let c = CompositeAGCIO(children: [a, b])
        await c.channelRoutine()
        #expect(a.count == 1 && b.count == 1)
    }

    @Test func `LMVehicleIO radar callback fires`() {
        var fired = false
        let lm = LMVehicleIO(onRequestRadarData: { fired = true })
        lm.requestRadarData()
        #expect(fired)
    }
}

// MARK: - LM test helpers

private func makeEngineForLMTests(state: AGCState) throws -> AGCEngine {
    let engine = try AGCEngine(state: state)
    state.downruptTimeValid = false
    return engine
}

private final class LMTestIO: AGCIOProtocol, @unchecked Sendable {
    var pendingInputs: [[Int: Int]] = []

    func channelOutput(channel: Int, value: Int) {}

    func channelInput() async -> [Int: Int]? {
        guard !pendingInputs.isEmpty else { return nil }
        return pendingInputs.removeFirst()
    }

    func requestRadarData() {}
    func shiftToDeda(data: Int) {}
    func channelRoutine() async {}
}

private final class RadarSpyIO: AGCIOProtocol, @unchecked Sendable {
    private(set) var radarCallCount = 0

    func channelOutput(channel: Int, value: Int) {}
    func channelInput() async -> [Int: Int]? { nil }
    func requestRadarData() { radarCallCount += 1 }
    func shiftToDeda(data: Int) {}
    func channelRoutine() async {}
}
