import Foundation

public enum AGCError: Error {
    case invalidCoreImage
    case memoryError
}

/// AGC Register addresses (in octal)
private enum Register: Int {
    case regA = 0o00        // Accumulator
    case regL = 0o01        // L Register
    case regQ = 0o02        // Q Register
    case regEB = 0o03       // Erasable Bank
    case regFB = 0o04       // Fixed Bank
    case regZ = 0o05        // Program Counter
    case regBB = 0o06       // Both Banks
    case regZERO = 0o07     // Always reads as zero
    case regARUPT = 0o10    // A Interrupt
    case regLRUPT = 0o11    // L Interrupt
    case regQRUPT = 0o12    // Q Interrupt
    case regZRUPT = 0o15    // Z Interrupt
    case regBBRUPT = 0o16   // BB Interrupt
    case regBRUPT = 0o17    // B Interrupt
    case regCYR = 0o20      // Cycle Right
    case regSR = 0o21       // Shift Right
    case regCYL = 0o22      // Cycle Left
    case regEDOP = 0o23     // Edit Operand
    
    // Counters (024-057)
    case regTIME2 = 0o24    // TIME2 Counter
    case regTIME1 = 0o25    // TIME1 Counter
    case regTIME3 = 0o26    // TIME3 Counter
    case regTIME4 = 0o27    // TIME4 Counter
    case regTIME5 = 0o30    // TIME5 Counter
    case regTIME6 = 0o31    // TIME6 Counter
    case regCDUX = 0o32     // Coupling Data Unit X
    case regCDUY = 0o33     // Coupling Data Unit Y
    case regCDUZ = 0o34     // Coupling Data Unit Z
    case regOPTY = 0o35     // Optics Y
    case regOPTX = 0o36     // Optics X
    case regPIPAX = 0o37    // Pulsed Integrating Pendulous Accelerometer X
    case regPIPAY = 0o40    // PIPA Y
    case regPIPAZ = 0o41    // PIPA Z
    case regRHCP = 0o42     // Rotational Hand Controller Pitch (LM only)
    case regRHCY = 0o43     // RHC Yaw (LM only)
    case regRHCR = 0o44     // RHC Roll (LM only)
    case regINLINK = 0o45   // Uplink Input
    case regRNRAD = 0o46    // Rendezvous Radar
    case regGYROCTR = 0o47  // Gyro Counter
    case regCDUXCMD = 0o50  // CDU X Command
    case regCDUYCMD = 0o51  // CDU Y Command
    case regCDUZCMD = 0o52  // CDU Z Command
    case regOPTYCMD = 0o53  // Optics Y Command
    case regOPTXCMD = 0o54  // Optics X Command
    case regOUTLINK = 0o57  // Downlink Output
    case regALTM = 0o60     // Altitude Meter
    
    // Memory regions
    static let ramStart = 0o60       // Start of general-purpose RAM
    static let coreStart = 0o4000    // Start of ROM (core memory)
    static let end = 0o120000        // End of memory space
}

public final class AGCEngine {
    /// The simulation state.
    public var state: AGCState
    
    /// The I/O delegate (using the protocol defined in AGCIO.swift).
    public var ioDelegate: AGCIOProtocol?
    
    /// Task that runs the simulation engine loop.
    private var engineTask: Task<Void, Never>? = nil
    
    /// Simulated program counter.
    public var programCounter: Int = 0
    
    /// Instructions loaded from the core image (each word is a 16-bit value).
    private var instructions: [UInt16] = []
    
    // AGC instruction masks and constants
    private let EXTRACODE: Int = 0o7 
    private let INDEX: Int = 0o7777
    private let BASIC: Int = 0o7777
    private let FIXED_BANK_SIZE = 0o2000
    private let ERASABLE_BANK_SIZE = 0o400
    
    /// Instruction timing tables (cycles needed minus 1)
    private let instructionTiming: [Int] = [
        0, 0, 0, 0,     // Opcode = 00
        1, 0, 0, 0,     // Opcode = 01
        2, 1, 1, 1,     // Opcode = 02
        1, 1, 1, 1,     // Opcode = 03
        1, 1, 1, 1,     // Opcode = 04
        1, 2, 1, 1,     // Opcode = 05
        1, 1, 1, 1,     // Opcode = 06
        1, 1, 1, 1      // Opcode = 07
    ]
    
    /// Extra timing for extracode instructions
    /// Note: Does not properly handle EDRUPT or BZF/BZMF instructions
    private let extracodeTiming: [Int] = [
        1, 1, 1, 1,     // Opcode = 010
        5, 0, 0, 0,     // Opcode = 011
        1, 1, 1, 1,     // Opcode = 012
        2, 2, 2, 2,     // Opcode = 013
        2, 2, 2, 2,     // Opcode = 014
        1, 1, 1, 1,     // Opcode = 015
        1, 0, 0, 0,     // Opcode = 016
        2, 2, 2, 2      // Opcode = 017
    ]
    
    /// Interrupt masks for debugging (1 = enabled, 0 = disabled)
    private var debuggerInterruptMasks: [Int] = Array(repeating: 1, count: 11)
    
    // Add these constants near the top of AGCEngine class:
    private let DSKY_OVERFLOW = 100        // Timer overflow value
    private let DSKY_FLASH_PERIOD = 4      // Flash period for DSKY lights

    // Replace the individual DSKY constants with an OptionSet
    private struct DSKYFlags: OptionSet {
        let rawValue: Int
        
        static let agcWarning    = DSKYFlags(rawValue: 0o000001)  // AGC Warning
        static let temperature   = DSKYFlags(rawValue: 0o000010)  // Temperature
        static let keyRelease    = DSKYFlags(rawValue: 0o000020)  // Key Release light
        static let verbNounFlash = DSKYFlags(rawValue: 0o000040)  // Verb/Noun Flash
        static let operatorError = DSKYFlags(rawValue: 0o000100)  // Operator Error
        static let restart      = DSKYFlags(rawValue: 0o000200)   // Restart
        static let standby      = DSKYFlags(rawValue: 0o000400)   // Standby
        static let elOff        = DSKYFlags(rawValue: 0o001000)   // EL Off
        
        // Common combinations
        static let allFlags: DSKYFlags = [
            .keyRelease, .verbNounFlash, .operatorError,
            .restart, .standby, .agcWarning, .temperature
        ]
        
        static let lightTest: DSKYFlags = [.restart, .standby]
    }
    
    private let WARNING_FILTER_THRESHOLD = 125   // Warning threshold

    // Add these constants to the class:
    private let SCALER_OVERFLOW = 160   // 1/3200 second in machine cycles
    private let ChanSCALER1 = 0o24     // Channel 024
    private let ChanSCALER2 = 0o25     // Channel 025
    private let CH77_NIGHT_WATCHMAN = 0o20000
    private let CH77_RUPT_LOCK = 0o40000
    private let CH77_TC_TRAP = 0o10000
    private let WARNING_FILTER_INCREMENT = 25
    private let WARNING_FILTER_MAX = 250
    private let WARNING_FILTER_DECREMENT = 2
    
    // Add these register constants
    private let RegTIME1 = 0o24  // TIME1 register address
    private let RegTIME2 = 0o25  // TIME2 register address
    private let RegTIME3 = 0o26  // TIME3 register address
    private let RegTIME4 = 0o27  // TIME4 register address
    private let RegTIME5 = 0o30  // TIME5 register address
    private let RegTIME6 = 0o31  // TIME6 register address
    
    public init(state: AGCState) throws {
        self.state = state
        try loadCoreImage()
        
        // Initialize I/O channels similar to agc_engine_init.c
        for i in 0..<state.inputChannels.count {
            state.inputChannels[i] = 0
        }
        
        // Channels 030-033 default to 077777 (signals inverted)
        for i in 0o30...0o33 {
            state.inputChannels[i] = 0o77777
        }
        
        // Initialize erasable memory
        for bank in 0..<8 {
            for addr in 0..<ERASABLE_BANK_SIZE {
                state.erasableMemory[bank][addr] = 0
            }
        }
        
        // Set initial program counter (RegZ) to 0o4000
        state.programCounter = 0o4000
        
        // Initialize other CPU state
        state.cycleCounter = 0
        state.extracode = false
        state.index = 0
    }
    
    /// Convert AGC-format word to internal format
    private func convertToAGCWord(_ word: Int) -> Int {
        // AGC words are 15 bits, right-aligned
        return (word >> 1) & 0o37777
    }
    
    private func loadCoreImage() throws {
        guard let data = state.coreImage else {
            throw AGCError.invalidCoreImage
        }
        
        // Core image should be a multiple of 2 bytes (16-bit words)
        guard data.count % 2 == 0 else {
            throw AGCError.invalidCoreImage
        }
        
        // Process the core rope binary image
        var bank = 2  // Start with bank 2 as per original code
        var offset = 0
        
        // Read 16-bit words from the binary
        for i in stride(from: 0, to: data.count, by: 2) {
            // Read two bytes and form a 16-bit word (big endian)
            let rawWord = (Int(data[i]) << 8) | Int(data[i + 1])
            let word = convertToAGCWord(rawWord)
            
            // Store in fixed memory following the bank ordering: 2,3,0,1,4,5,6,...,35
            state.fixedMemory[bank][offset] = word
            
            offset += 1
            if offset >= FIXED_BANK_SIZE {
                offset = 0
                // Advance to next bank following original ordering
                bank = switch bank {
                case 2: 3
                case 3: 0
                case 0: 1
                case 1: 4
                default: bank + 1
                }
                
                // Check if we've exceeded available banks
                if bank >= state.fixedMemory.count {
                    throw AGCError.memoryError
                }
            }
        }
    }
    
    /// Read a word from memory at the given address
    private func readMemory(_ address: Int) -> Int {
        if address < 0o2000 {
            // Erasable memory
            let bank = address / ERASABLE_BANK_SIZE
            let offset = address % ERASABLE_BANK_SIZE
            return state.erasableMemory[bank][offset]
        } else {
            // Fixed memory
            let bank = (address - 0o2000) / FIXED_BANK_SIZE
            let offset = (address - 0o2000) % FIXED_BANK_SIZE
            return state.fixedMemory[bank][offset]
        }
    }
    
    /// Write a word to memory at the given address
    private func writeMemory(_ address: Int, _ value: Int) {
        if address < 0o2000 {
            // Only erasable memory is writable
            let bank = address / ERASABLE_BANK_SIZE
            let offset = address % ERASABLE_BANK_SIZE
            state.erasableMemory[bank][offset] = value & 0o37777 // Mask to 15 bits
        }
    }
    
    /// Read a word from a specific register
    private func readRegister(_ register: Register) -> Int {
        return readMemory(register.rawValue)
    }
    
    /// Write a word to a specific register
    private func writeRegister(_ register: Register, _ value: Int) {
        writeMemory(register.rawValue, value)
    }
    
    /// Execute one AGC instruction
    private func executeInstruction(_ instruction: Int) {
        if state.extracode {
            executeExtendedInstruction(instruction)
            state.extracode = false
            return
        }
        
        let opcode = (instruction >> 12) & 0o7
        let address = instruction & 0o7777
        
        switch opcode {
        case 0: // TC - Transfer Control
            state.returnAddress = state.programCounter
            state.programCounter = address
            
        case 1: // CCS - Count, Compare, and Skip
            let value = readMemory(address)
            if value > 0 {
                state.programCounter += 1
            } else if value < 0 {
                state.programCounter += 2
            } else {
                state.programCounter += 3
            }
            state.accumulator = abs(value) - 1
            
        case 2: // INDEX
            state.index = readMemory(address)
            
        case 3: // RESUME
            // Implement RESUME logic
            break
            
        // Add other opcodes...
            
        default:
            break
        }
    }
    
    private func executeExtendedInstruction(_ instruction: Int) {
        // Implement extended instruction set
    }
    
    /// Get the number of extra machine cycles needed for an instruction
    private func getInstructionTiming(instruction: Int, isExtracode: Bool) -> Int {
        // Get the upper 5 bits of the instruction
        let index = (instruction >> 10) & 0o37
        
        // Add special handling for EDRUPT and BZF/BZMF
        if isExtracode {
            // EDRUPT needs special handling
            if (instruction & 0o7777) == 0o1704 {
                return 2  // EDRUPT timing
            }
            return extracodeTiming[Int(index)]
        } else {
            // BZF/BZMF need special handling
            if (instruction & 0o7000) == 0o6000 && (instruction & 0o1400) != 0 {
                return 1  // BZF/BZMF timing
            }
            return instructionTiming[Int(index)]
        }
    }
    
    /// Execute one simulation cycle
    private func executeCycle() async -> Bool {
        // For DOWNRUPT
        if state.downruptTimeValid && state.cycleCounter >= state.downruptTime {
            state.interruptRequests[8] = 1  // Request DOWNRUPT
            state.downruptTimeValid = false
        }
        
        // The first time through the loop, light up the DSKY RESTART light
        if state.cycleCounter == 0 {
            state.restartLight = true
        }
        
        state.cycleCounter += 1
        
        // Update the timer that determines when 1/1600 second has passed.
        // 1/1600 is the basic timing used to drive timer registers.
        // 1/1600 second is 160/3 machine cycles.
        let SCALER_DIVIDER = 160/3
        state.scalerCounter += SCALER_DIVIDER
        state.dskyTimer += SCALER_DIVIDER
        
        // Handle I/O channel communications periodically (nominally every 100ms)
        if state.channelRoutineCount == 0 {
            if let io = ioDelegate {
                await io.channelRoutine()
            }
        }
        state.channelRoutineCount = (state.channelRoutineCount + 1) & 0o17777
        
        // Update the various hardware-driven DSKY lights
        updateDSKY()
        
        // Get data from input channels
        // Return immediately if an unprogrammed counter-increment was performed
        if await channelInput() {
            return false
        }
        
        // Handle extra CPU cycles used by some instructions
        
        // Extra delay needed sometimes after branch instructions
        if state.extraDelay > 0 {
            state.extraDelay -= 1
            return false
        }
        
        // If a multi-cycle instruction is in progress, wait until last cycle
        if state.pendFlag && state.pendDelay > 0 {
            state.pendDelay -= 1
            return false
        }
        
        // Handle standby button state
        if (state.inputChannels[0o32] & 0o20000) != 0 {
            state.sbyPressed = false
            state.sbyStillPressed = false
        }
        
        // Handle counter-timers
        while state.scalerCounter >= SCALER_OVERFLOW {
            var triggeredAlarm = false
            
            // Update SCALER1 and SCALER2
            state.scalerCounter -= SCALER_OVERFLOW
            state.inputChannels[ChanSCALER1] += 1
            if state.inputChannels[ChanSCALER1] == 0o40000 {
                state.inputChannels[ChanSCALER1] = 0
                state.inputChannels[ChanSCALER2] = (state.inputChannels[ChanSCALER2] + 1) & 0o37777
            }
            
            // Check alarms first
            if (0o4000 == (0o7777 & state.inputChannels[ChanSCALER1])) {
                // Night Watchman check (1.28s)
                if !state.standby {
                    state.nightWatchman = 1
                }
                
                // Standby circuit check
                if state.sbyPressed && ((state.inputChannels[0o13] & 0o2000) != 0 || state.standby) {
                    if !state.standby {
                        // Enter standby mode
                        state.standby = true
                        state.sbyStillPressed = true
                        triggeredAlarm = true
                        
                        // Update DSKY lights
                        var flags = DSKYFlags(rawValue: state.dskyChannel163)
                        flags.insert([.standby])
                        flags.insert(.elOff)  // Need to add this to DSKYFlags
                        state.dskyChannel163 = flags.rawValue
                        channelOutput(channel: 0o163, value: state.dskyChannel163)
                    } else if !state.sbyStillPressed {
                        // Exit standby mode
                        state.standby = false
                        
                        // Update DSKY lights
                        var flags = DSKYFlags(rawValue: state.dskyChannel163)
                        flags.remove([.standby, .elOff])
                        state.dskyChannel163 = flags.rawValue
                        channelOutput(channel: 0o163, value: state.dskyChannel163)
                    }
                }
            } else if (0o0000 == (0o7777 & state.inputChannels[ChanSCALER1])) {
                // Check standby button state
                if (state.inputChannels[0o32] & 0o20000) == 0 {
                    state.sbyPressed = true
                }
                
                // Night Watchman completion
                if !state.standby && state.nightWatchman != 0 {
                    triggeredAlarm = true
                    state.inputChannels[0o77] |= CH77_NIGHT_WATCHMAN
                    state.nightWatchmanTripped = true
                } else {
                    state.nightWatchmanTripped = false
                }
            }
            
            // Warning filter updates (every 160ms)
            if (0o00 == (0o07 & state.inputChannels[ChanSCALER1])) {
                if (0o400 == (0o777 & state.inputChannels[ChanSCALER1])) &&
                    (state.generatedWarning || (state.inputChannels[0o13] & 0o1000) != 0) {
                    state.generatedWarning = false
                    state.warningFilter += WARNING_FILTER_INCREMENT
                    if state.warningFilter > WARNING_FILTER_MAX {
                        state.warningFilter = WARNING_FILTER_MAX
                    }
                } else {
                    if state.warningFilter >= WARNING_FILTER_DECREMENT {
                        state.warningFilter -= WARNING_FILTER_DECREMENT
                    } else {
                        state.warningFilter = 0
                    }
                }
            }
            
            // Skip timer updates during standby
            if !state.standby {
                if 0o400 == (0o777 & state.inputChannels[ChanSCALER1]) {
                    // Rupt Lock alarm monitoring (starts every 160ms)
                    state.ruptLock = true
                    state.noRupt = true
                } else if (state.ruptLock || state.noRupt) && 
                          0o300 == (0o777 & state.inputChannels[ChanSCALER1]) {
                    // Alarm after 140ms of no interrupts or stuck in interrupt
                    triggeredAlarm = true
                    state.inputChannels[0o77] |= CH77_RUPT_LOCK
                }
                
                if 0o020 == (0o037 & state.inputChannels[ChanSCALER1]) {
                    // TC Trap alarm monitoring (every 5ms)
                    state.tcTrap = true
                    state.noTC = true
                } else if (state.tcTrap || state.noTC) && 
                          0o000 == (0o037 & state.inputChannels[ChanSCALER1]) {
                    // Alarm after 5ms of only/no TC instructions
                    triggeredAlarm = true
                    state.inputChannels[0o77] |= CH77_TC_TRAP
                }
                
                // Timer updates
                if 0o020 == (0o037 & state.inputChannels[ChanSCALER1]) {
                    state.extraDelay += 1
                    
                    // Update TIME1 and TIME2
                    if incrementCounter(register: Register.regTIME1) {
                        state.extraDelay += 1
                        _ = incrementCounter(register: Register.regTIME2)
                    }
                    
                    state.extraDelay += 1
                    if incrementCounter(register: Register.regTIME3) {
                        state.interruptRequests[3] = 1
                    }
                }
                
                // TIME5 (5ms out of phase with TIME3)
                if 0o000 == (0o037 & state.inputChannels[ChanSCALER1]) {
                    state.extraDelay += 1
                    if incrementCounter(register: Register.regTIME5) {
                        state.interruptRequests[2] = 1
                    }
                    
                    // Update radar gate counter if enabled
                    if (state.inputChannels[0o13] & 0o10) != 0 {
                        state.radarGateCounter += 1
                    }
                }
                
                // TIME4 (7.5ms out of phase with TIME3)
                if 0o010 == (0o037 & state.inputChannels[ChanSCALER1]) {
                    state.extraDelay += 1
                    if incrementCounter(register: Register.regTIME4) {
                        state.interruptRequests[4] = 1
                    }
                }
                
                // TIME6 (increments 0.3125ms after TIME1/TIME3 if enabled)
                if (state.inputChannels[0o13] & 0o40000) != 0 && 
                   (state.inputChannels[ChanSCALER1] & 0o1) == 0o1 {
                    state.extraDelay += 1
                    if decrementCounter(register: Register.regTIME6) {
                        state.interruptRequests[1] = 1
                        // Disable T6 by clearing CH13 bit
                        cpuWriteIO(channel: 0o13, value: state.inputChannels[0o13] & 0o37777)
                    }
                }
            }
            
            // Check for HANDRUPT conditions
            if state.trap31A && ((state.inputChannels[0o31] & 0o000077) != 0o000077) {
                state.trap31A = false
                state.interruptRequests[10] = 1
            }

            if state.trap31B && ((state.inputChannels[0o31] & 0o007700) != 0o007700) {
                state.trap31B = false
                state.interruptRequests[10] = 1
            }

            if state.trap32 && ((state.inputChannels[0o32] & 0o001777) != 0o001777) {
                state.trap32 = false
                state.interruptRequests[10] = 1
            }

            // Check for radar cycle completion
            if (state.radarGateCounter == 9) && 
               (0o36 == (0o37 & state.inputChannels[ChanSCALER1])) {
                // Completion of radar cycle:
                // 1. Reset radar gate counter
                state.radarGateCounter = 0
                // 2. Reset radar activity bit
                state.inputChannels[0o13] &= ~0o10
                // 3. Request radar data (TODO: implement RequestRadarData)
                // 4. Set RADARUPT pending
                state.interruptRequests[9] = 1
            }
            
            // Handle triggered alarms
            if triggeredAlarm || state.parityFail {
                // Simulate GOJAM sequence
                
                // Two single-MCT instruction sequences
                state.extraDelay += 2
                
                // Store current Z in Q, set Z to 4000
                writeRegister(.regQ, readRegister(.regZ))
                writeRegister(.regZ, 0o4000)
                
                // Clear interrupt state
                state.inIsr = false
                state.allowInterrupt = true
                state.parityFail = false
                
                // Disable HANDRUPT traps
                state.trap31A = false
                state.trap31B = false
                state.trap32 = false
                
                // Clear all interrupt requests
                for i in 1...10 {  // NUM_INTERRUPT_TYPES
                    state.interruptRequests[i] = 0
                }
                
                // Clear I/O channels
                for channel in [0o5, 0o6, 0o10, 0o11, 0o12, 0o13, 0o14] {
                    cpuWriteIO(channel: channel, value: 0)
                }
                
                // Clear UPLINK TOO FAST bit in channel 33
                state.inputChannels[0o33] |= 0o2000
                
                // Clear channels 34 and 35 without generating downrupt
                cpuWriteIO(channel: 0o34, value: 0)
                cpuWriteIO(channel: 0o35, value: 0)
                state.downruptTimeValid = false
                
                // Clear internal state
                state.indexValue = 0  // AGC_P0
                state.extracode = false
                state.substituteInstruction = false
                state.pendFlag = false
                state.pendDelay = 0
                state.tookBZF = false
                state.tookBZMF = false
                
                // Light RESTART if not in standby
                if !state.standby {
                    state.restartLight = true
                    state.generatedWarning = true
                }
                
                // Push CH77 updates
                channelOutput(channel: 0o77, value: state.inputChannels[0o77])
            }
        }
        
        // Handle extra delay
        if state.extraDelay > 0 {
            state.extraDelay -= 1
            return false
        }
        
        // Continue with instruction execution
        return true
    }
    
    /// Get data from input channels
    private func channelInput() async -> Bool {
        // TODO: Implement channel input logic
        return false
    }
    
    /// Start the simulation engine.
    public func startEngine() {
        engineTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // Only proceed with instruction execution if cycle processing completes
                if await self.executeCycle() {
                    let instruction = self.readMemory(self.state.programCounter)
                    
                    let extraCycles = self.getInstructionTiming(
                        instruction: instruction,
                        isExtracode: self.state.extracode
                    )
                    
                    self.executeInstruction(instruction)
                    
                    if extraCycles > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(extraCycles) * 11_700)
                    }
                }
                
                try? await Task.sleep(nanoseconds: 11_700)
            }
        }
    }
    
    /// Stop the simulation engine.
    public func stopEngine() {
        engineTask?.cancel()
    }
    
    /// Updates the DSKY display and status lights
    private func updateDSKY() {
        let lastChannel163 = state.dskyChannel163
        
        // Clear all status bits
        var flags = DSKYFlags(rawValue: state.dskyChannel163)
        flags.subtract(DSKYFlags.allFlags)
        
        // Light test active - light RESTART and STBY
        if (state.inputChannels[0o13] & 0o1000) != 0 {
            flags.formUnion(.lightTest)
        }
        
        // Standby light
        if state.standby {
            flags.insert(.standby)
        }
        
        // Restart light
        if state.restartLight {
            flags.insert(.restart)
        }
        
        // Temperature warning
        if (state.inputChannels[0o11] & 0o10) != 0 || 
           (state.inputChannels[0o30] & 0o40000) != 0 {
            flags.insert(.temperature)
        }
        
        // Key Release and Operator Error from channel 11
        if (state.inputChannels[0o11] & DSKYFlags.keyRelease.rawValue) != 0 {
            flags.insert(.keyRelease)
        }
        if (state.inputChannels[0o11] & DSKYFlags.operatorError.rawValue) != 0 {
            flags.insert(.operatorError)
        }
        
        // AGC warning light
        if state.warningFilter > WARNING_FILTER_THRESHOLD {
            flags.insert(.agcWarning)
            // Set AGC Warning input bit in channel 33
            state.inputChannels[0o33] &= 0o57777
        }
        
        // Handle flashing lights (1.28s period, 75% duty cycle)
        if !state.standby && !state.dskyFlash {
            // V/N Flash
            if (state.inputChannels[0o11] & DSKYFlags.verbNounFlash.rawValue) != 0 {
                flags.insert(.verbNounFlash)
            }
            
            // Flash off KEY REL and OPER ERR
            flags.remove(.keyRelease)
            flags.remove(.operatorError)
        }
        
        // Update state and output if changed
        state.dskyChannel163 = flags.rawValue
        if state.dskyChannel163 != lastChannel163 {
            channelOutput(channel: 0o163, value: state.dskyChannel163)
        }
    }
    
    /// Output a value to an I/O channel
    private func channelOutput(channel: Int, value: Int) {
        state.outputChannels[channel] = value
        ioDelegate?.channelOutput(channel: channel, value: value)
    }
    
    /// Increment a counter register
    private func incrementCounter(register: Register) -> Bool {
        let value = readRegister(register)
        let newValue = (value + 1) & 0o37777
        writeRegister(register, newValue)
        return newValue == 0
    }
    
    /// Decrement a counter register
    private func decrementCounter(register: Register) -> Bool {
        let value = readRegister(register)
        let newValue = (value - 1) & 0o37777
        writeRegister(register, newValue)
        return value == 0
    }
    
    /// Write to an I/O channel with side effects
    private func cpuWriteIO(channel: Int, value: Int) {
        state.inputChannels[channel] = value
        channelOutput(channel: channel, value: value)
    }
}

extension AGCEngine: @unchecked Sendable { } 
