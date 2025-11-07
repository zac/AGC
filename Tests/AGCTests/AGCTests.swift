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

        #expect(state.erasableMemory[0][Register.regA.rawValue] == (0o12345 | 0o70000))
    }

    @Test func worWritesBackToRegister() throws {
        let (engine, state) = try makeEngine()
        setAccumulator(0o40000, engine: engine)
        engine.writeRegister(.regL, 0o20000)

        engine.performWor(address9: Register.regL.rawValue)

        let expected = 0o60000
        #expect(state.erasableMemory[0][Register.regA.rawValue] == expected)
        #expect(state.erasableMemory[0][Register.regL.rawValue] == expected)
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
