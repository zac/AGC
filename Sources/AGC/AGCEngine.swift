import Foundation

public enum AGCError: Error {
    case invalidBinFile
    case memoryError
}

/// AGC Register addresses (in octal)
public enum Register: Int {
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

/// IMU CDU drive timing constants
private struct IMUTiming {
    static let COARSE_SMOOTH = 8
    static let BURST_CYCLES: UInt64 = (600 * 1024000) / (1000 * 12 * UInt64(COARSE_SMOOTH))

    var cycleCount: UInt64 = 0
    var channel14: Int = 0
    
    mutating func shouldEmitBurst(state: AGCState, currentCycle: UInt64) -> Bool {
        let imuBits = state.inputChannels[0o14] & 0o70000  // Check IMU CDU drive bits
        
        // If suddenly active, start drive
        if channel14 == 0 && imuBits != 0 {
            cycleCount = currentCycle - IMUTiming.BURST_CYCLES
        }
        
        // Time for next burst?
        if imuBits != 0 && (currentCycle - cycleCount) >= IMUTiming.BURST_CYCLES {
            // Adjust cycle counter
            cycleCount += IMUTiming.BURST_CYCLES
            
            // Determine pulses wanted on each axis
            channel14 = IMUBurst.burstOutput(state: state,
                                           driveBitMask: 0o40000,
                                           counterRegister: .regCDUXCMD,
                                           channel: 0o174)
            channel14 |= IMUBurst.burstOutput(state: state,
                                            driveBitMask: 0o20000,
                                            counterRegister: .regCDUYCMD,
                                            channel: 0o175)
            channel14 |= IMUBurst.burstOutput(state: state,
                                            driveBitMask: 0o10000,
                                            counterRegister: .regCDUZCMD,
                                            channel: 0o176)
            return true
        }
        
        return false
    }
}

/// Gyro timing and state management
private struct GyroTiming {
    // Constants
    static let BURST = 800
    static let BURST2 = 1024
    static let OVERFLOW = 160  // Same as SCALER_OVERFLOW
    static let DIVIDER = 160/3 // Same as SCALER_DIVIDER
    
    // State
    var timer: Int = 0
    var count: Int = 0
    var oldChannel14: Int = 0
    
    /// Process any pending gyro operations
    mutating func processBurst(state: AGCState) -> Bool {
        // Check if gyro torquing is enabled
        guard (state.inputChannels[0o14] & 0o1000) != 0 else {
            return false
        }
        
        // Check if there's a new torque value
        let gyroCounter = state.erasableMemory[0][Register.regGYROCTR.rawValue]
        if gyroCounter != 0 {
            // Process any pending torques first
            while count > 0 {
                var burstSize = count
                if burstSize > 0o3777 {
                    burstSize = 0o3777
                }
                state.outputChannels[0o177] = oldChannel14 | burstSize
                count -= burstSize
            }
            
            // Set up new torque counter
            count = gyroCounter
            state.erasableMemory[0][Register.regGYROCTR.rawValue] = 0
            oldChannel14 = ((state.inputChannels[0o14] & 0o740) << 6)
            timer = Self.OVERFLOW * Self.BURST - Self.DIVIDER
        }
        
        // Update 3200 pps gyro pulse counter
        timer += Self.DIVIDER
        var didOutput = false
        
        while timer >= Self.BURST * Self.OVERFLOW {
            timer -= Self.BURST * Self.OVERFLOW
            if count > 0 {
                var burstSize = count
                if burstSize > Self.BURST2 {
                    burstSize = Self.BURST2
                }
                state.outputChannels[0o177] = oldChannel14 | burstSize
                count -= burstSize
                didOutput = true
            }
        }
        
        return didOutput
    }
}

/// Handles coarse-alignment output pulses for IMU CDU drive axes
private struct IMUBurst {
    // Actor-protected counts for each axis (in target CPU format)
    nonisolated(unsafe) private static var countCDUX = 0
    nonisolated(unsafe) private static var countCDUY = 0
    nonisolated(unsafe) private static var countCDUZ = 0
    
    /// Process burst output for one IMU CDU drive axis
    /// Returns non-0 if a non-zero count remains on the axis, 0 otherwise
    static func burstOutput(state: AGCState, 
                    driveBitMask: Int, 
                    counterRegister: Register,
                    channel: Int) -> Int {
        // Get the saved count for this axis
        var driveCountSaved: Int
        switch counterRegister {
        case .regCDUXCMD: driveCountSaved = countCDUX
        case .regCDUYCMD: driveCountSaved = countCDUY
        case .regCDUZCMD: driveCountSaved = countCDUZ
        default: return 0
        }
        
        var driveCount = 0
        var direction = 0
        
        // Check if driving this axis
        let driveBit = state.inputChannels[0o14] & driveBitMask
        if driveBit != 0 {
            // Retrieve count from counter register
            driveCount = state.erasableMemory[0][counterRegister.rawValue]
            state.erasableMemory[0][counterRegister.rawValue] = 0
        }
        
        // Handle negative counts
        direction = driveCount & 0o40000
        if direction != 0 {
            driveCount ^= 0o77777
            driveCountSaved -= driveCount
        } else {
            driveCountSaved += driveCount
        }
        
        if driveCountSaved < 0 {
            driveCountSaved = -driveCountSaved
            direction = 0o40000
        } else {
            direction = 0
        }
        
        // Calculate pulses to output (max 192 per burst)
        var delta = driveCountSaved
        if delta >= 192 / IMUTiming.COARSE_SMOOTH {
            delta = 192 / IMUTiming.COARSE_SMOOTH
        }
        
        // Output pulses if count is non-zero
        if delta > 0 {
            state.outputChannels[channel] = direction | delta
            driveCountSaved -= delta
        }
        
        if direction != 0 {
            driveCountSaved = -driveCountSaved
        }
        
        // Save updated count
        switch counterRegister {
        case .regCDUXCMD: countCDUX = driveCountSaved
        case .regCDUYCMD: countCDUY = driveCountSaved
        case .regCDUZCMD: countCDUZ = driveCountSaved
        default: break
        }
        
        return driveCountSaved
    }
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
    private let BACKTRACE_LIMIT = 256            // Max stored entries

    // Channel 77 alarm bits
    private let CH77_PARITY_FAIL    = 0o000001  // Parity alarm
    private let CH77_TC_TRAP        = 0o000004  // TC Trap alarm
    private let CH77_RUPT_LOCK      = 0o000010  // Rupt Lock alarm  
    private let CH77_NIGHT_WATCHMAN = 0o000020  // Night Watchman alarm

    // Add these constants to the class:
    private let SCALER_OVERFLOW = 80   // 1/3200 second in machine cycles
    private let ChanSCALER1 = 0o24     // Channel 024
    private let ChanSCALER2 = 0o25     // Channel 025
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
    
    private var imuTiming = IMUTiming()
    private var gyroTiming = GyroTiming()
    
    // Add these constants to AGCEngine:
    private let MASK9 = 0o777        // 9-bit mask
    private let MASK10 = 0o1777      // 10-bit mask
    private let MASK12 = 0o7777      // 12-bit mask
    
    // Number of interrupt types supported by the AGC
    private let NUM_INTERRUPT_TYPES = 10
    
    // ** NEW constant added for I/O channels **
    private let NUM_CHANNELS = 512   // Total number of channels
    
    // AGC numerical constants in AGC 1's complement format
    private let AGC_P0 = 0                // Positive zero
    private let AGC_M0 = 0o77777         // Negative zero 
    private let AGC_P1 = 1               // Positive one
    private let AGC_M1 = 0o77776         // Negative one
    
    // Add near the top with other constants:
    private let AGC_PER_SECOND: UInt64 = 11_700  // Machine cycles per second

    public init(state: AGCState) throws {
        self.state = state
        
        // Initialize I/O channels
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
        
        // Set initial program counter (RegZ) to 04000
        writeRegister(.regZ, 0o4000)
        
        // Initialize CPU state variables
        state.cycleCounter = 0
        state.extraCode = false
        state.allowInterrupt = true // The GOJAM sequence enables interrupts
        state.interruptRequests[8] = 1 // DOWNRUPT
        state.pendFlag = false
        state.pendDelay = 0
        state.extraDelay = 0
        
        state.outputChannel7 = 0
        for j in 0..<16 {
            state.outputChannel10[j] = 0
        }
        state.indexValue = 0
        for j in 0...NUM_INTERRUPT_TYPES {
            state.interruptRequests[j] = 0
        }
        state.inIsr = false
        state.substituteInstruction = false
        state.downruptTimeValid = true
        state.downruptTime = 0
        state.downlink = 0
        
        // Initialize alarm and warning state
        state.nightWatchman = 0
        state.nightWatchmanTripped = false
        state.ruptLock = false
        state.noRupt = false
        state.tcTrap = false
        state.noTC = false
        state.parityFail = false
        
        state.warningFilter = 0
        state.generatedWarning = false
        
        // Initialize DSKY state
        state.restartLight = false
        state.standby = false
        state.sbyPressed = false
        state.sbyStillPressed = false
        
        // Initialize other state
        state.nextZ = 0
        state.scalerCounter = 0
        state.channelRoutineCount = 0
        
        state.dskyTimer = 0
        state.dskyFlash = false
        state.dskyChannel163 = 0
        
        state.tookBZF = false
        state.tookBZMF = false
        
        // Initialize HANDRUPT traps
        state.trap31A = false
        state.trap31B = false
        state.trap32 = false
        
        // Initialize radar state
        state.radarGateCounter = 0
        
        // Load bin file if provided
        try loadBinFile()
    }
    
    /// Convert AGC-format word to internal format
    private func convertToAGCWord(_ word: Int) -> Int {
        // AGC words are 15 bits, right-aligned
        return (word >> 1) & 0o37777
    }
    
    private func loadBinFile() throws {
        guard let data = state.binFile else {
            throw AGCError.invalidBinFile // File not found
        }
        
        // Must be an integral number of words
        guard data.count % 2 == 0 else {
            throw AGCError.invalidBinFile 
        }
        
        let wordCount = data.count / 2
        
        // Check if file is too large
        guard wordCount <= 36 * 0o2000 else {
            throw AGCError.invalidBinFile
        }
        
        // Reset parity checking state
        state.checkParity = false
        state.parities = Array(repeating: 0, count: state.parities.count)
        
        var bank = 2
        var offset = 0
        
        // Process each word in the binary
        for i in stride(from: 0, to: data.count, by: 2) {
            guard bank <= 35 else {
                throw AGCError.invalidBinFile
            }
            
            // Read raw 16-bit word (big endian)
            let rawWord = (Int(data[i]) << 8) | Int(data[i + 1])
            let parity = rawWord & 1
            
            // Store word and parity
            state.fixedMemory[bank][offset] = rawWord >> 1
            let parityIndex = (bank * 0o2000 + offset) / 32
            state.parities[parityIndex] |= parity << (offset % 32)
            
            // Enable parity checking if any parity bits are set
            if parity != 0 {
                state.checkParity = true
            }
            
            offset += 1
            if offset >= 0o2000 {
                offset = 0
                // Advance to next bank following original ordering: 2,3,0,1,4,5,6,...,35
                bank = switch bank {
                case 2: 3
                case 3: 0
                case 0: 1
                case 1: 4
                default: bank + 1
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
    
    /// Fetch an instruction word using AGC bank-selection rules (test hook)
    func fetchInstructionWord(at address: Int) -> Int {
        return findMemoryWord(address & 0o7777)
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

    /// Check if address is the accumulator register
    private func isA(_ address: Int) -> Bool {
        return address == Register.regA.rawValue
    }
    
    /// Check if address is the L register
    private func isL(_ address: Int) -> Bool {
        return address == Register.regL.rawValue
    }
    
    /// Check if address is the Q register 
    private func isQ(_ address: Int) -> Bool {
        return address == Register.regQ.rawValue
    }
    
    /// Check if address is the EB register
    private func isEB(_ address: Int) -> Bool {
        return address == Register.regEB.rawValue
    }
    
    /// Check if address is the Z register
    private func isZ(_ address: Int) -> Bool {
        return address == Register.regZ.rawValue
    }
    
    /// Check if address matches the given register
    private func isReg(_ address: Int, _ register: Register) -> Bool {
        return address == register.rawValue
    }
    
    /// Write a word to a specific register, applying editing rules via assign()
    func writeRegister(_ register: Register, _ value: Int) {
        assign(bank: 0, offset: register.rawValue, value: value)
    }

    /// Write a value to an I/O channel with special handling for certain channels
    private func cpuWriteIO(address: Int, value: Int) {
        var modifiedValue = value
        
        if address == 0o13 {
            // Handle HANDRUPT trap settings
            if (value & 0o4000) != 0 {
                state.trap31A = true
            }
            if (value & 0o10000) != 0 {
                state.trap31B = true  
            }
            if (value & 0o20000) != 0 {
                state.trap32 = true
            }
            
            modifiedValue &= 0o43777
        }
        
        if address == 0o33 {
            // Reset bits 11-15 to 1 for channel 33
            state.inputChannels[address] |= 0o76000
            
            // Don't allow warning reset if light still on
            if state.warningFilter > WARNING_FILTER_THRESHOLD {
                state.inputChannels[address] &= 0o57777
            }
            
            // Use existing channel value
            modifiedValue = state.inputChannels[address]
        }
        else if address == 0o77 {
            // Reset CH77 alarm codes
            modifiedValue = 0
            
            // Set night watchman bit if tripped
            if state.nightWatchmanTripped {
                modifiedValue |= CH77_NIGHT_WATCHMAN
            }
        }
        else if address == 0o11 && (value & 0o1000) != 0 {
            // Reset DSKY restart light
            state.restartLight = false
        }
        
        writeIO(address: address, value: modifiedValue)
        channelOutput(channel: address, value: modifiedValue & 0o77777)

        // Handle downlink timing
        if address == 0o34 {
            state.downlink |= 1
        }
        else if address == 0o35 {
            state.downlink |= 2
        }
        
        if state.downlink == 3 {
            state.downruptTimeValid = true
            state.downruptTime = state.cycleCounter + (AGC_PER_SECOND / 50)
            state.downlink = 0
        }
    }
        
    /// Execute an extended instruction based on the opcode
    func executeExtendedInstruction(_ instruction: Int, opcode: Int, overflow: Bool) {
        // Track if we took certain branch instructions
        var justTookBZF = false
        var justTookBZMF = false
        var executedTC = false
        var tcTransient = false
        var keepExtraCode = false

        let currentBB = readRegister(.regBB)
        let currentEB = readRegister(.regEB)
        let currentFB = readRegister(.regFB)
        let opCode = opcode & 0o177
        let address12 = (instruction >> 6) & 0o777
        let address10 = (instruction >> 3) & 0o777
        let address9 = instruction & 0o777

        // Check for TCF0 transient after BZF
        if state.tookBZF && !(instruction == 0o000 && address12 == 6) {
            tcTransient = true
        }
        
        switch opCode {
        case 0...7: // TC instruction (1 MCT)
            let valueK = address12
            
            switch valueK {
            case 3: // RELINT instruction
                state.allowInterrupt = true
                if state.tookBZF || state.tookBZMF {
                    tcTransient = true
                }
                
            case 4: // INHINT instruction 
                state.allowInterrupt = false
                if state.tookBZF || state.tookBZMF {
                    tcTransient = true
                }
                
            case 6: // EXTEND instruction
                state.extraCode = true
                keepExtraCode = true
                
            default:
                if valueK != Register.regQ.rawValue { // If not RETURN
                    writeRegister(.regQ, state.nextZ & 0o177777)
                }
                backtraceAdd(tag: 0, target: address12)
                state.nextZ = address12
                executedTC = true
            }
            
        case 0o10...0o11: // CCS instruction (2 MCT)
            handleCCS(address10: address10)
            
        // Continue implementing other opcodes...
        case 0o12...0o17: // TCF instruction (1 MCT)
            performTCF(address12: address12)
            executedTC = true
            
        case 0o20...0o21: // DAS instruction (3 MCT)
            var msw: Int
            var lsw: Int
            
            if isL(address10) { // DDOUBL
                doubleRegisters()
            } else {
                let whereWord = findMemoryWord(address10)
                
                if address10 < Register.ramStart {
                    lsw = addSP16(readRegister(.regL) & 0o177777, readRegister(Register(rawValue: address10)!) & 0o177777)
                } else {
                    lsw = addSP16(readRegister(.regL) & 0o177777, signExtend(whereWord))
                }
                
                if address10 < Register.ramStart + 1 {
                    msw = addSP16(state.accumulator, readRegister(Register(rawValue: address10 - 1)!) & 0o177777)
                } else {
                    msw = addSP16(state.accumulator, signExtend(whereWord - 1))
                }
                
                if (0o140000 & lsw) == 0o40000 {
                    msw = addSP16(msw, AGC_P1)
                } else if (0o140000 & lsw) == 0o100000 {
                    msw = addSP16(msw, signExtend(AGC_M1))
                }
                lsw = overflowCorrected(lsw)
                
                if (0o140000 & msw) == 0o100000 {
                    writeRegister(.regA, signExtend(AGC_M1))
                } else if (0o140000 & msw) == 0o40000 {
                    writeRegister(.regA, AGC_P1)
                } else {
                    writeRegister(.regA, AGC_P0)
                }
                writeRegister(.regL, AGC_P0)
                
                if address10 < Register.ramStart {
                    writeRegister(Register(rawValue: address10)!, signExtend(lsw))
                } else {
                    assignFromPointer(address10, lsw)
                }
                
                if address10 < Register.ramStart + 1 {
                    writeRegister(Register(rawValue: address10 - 1)!, msw)
                } else {
                    assignFromPointer(address10 - 1, overflowCorrected(msw))
                }
            }
            
        case 0o22...0o23: // LXCH instruction (2 MCT)
            performLXCH(address10: address10)
            
        case 0o24...0o25: // INCR instruction (2 MCT)
            performINCR(address10: address10)
            
        case 0o26...0o27: // ADS instruction (2 MCT)
            performADS(address10: address10)
            
        case 0o30...0o37: // CA instruction
            performCA(address12: address12)
            
        case 0o40...0o47: // CS instruction
            tcTransient = true // CS causes transients on the TC0 line
            performCS(address12: address12)
            
        case 0o50...0o51: // INDEX instruction
            performIndex(address10: address10)
            
        case 0o150...0o157: // INDEX (continued)
            if performExtracodeIndex(address12: address12) {
                keepExtraCode = true
            }
            
        case 0o52...0o53: // DXCH instruction
            tcTransient = true // DXCH causes transients on the TCF0 line
            handleDXCH(address10: address10)
            
        case 0o54...0o55: // TS instruction
            tcTransient = true // TS causes transients on the TCF0 line
            performTS(address10: address10, overflow: overflow)
            
        case 0o56...0o57: // XCH instruction
            tcTransient = true // XCH causes transients on the TCF0 line
            performXCH(address10: address10)
            
        case 0o60...0o67: // AD instruction
            performAD(address12: address12)
            
        case 0o70...0o77: // MASK instruction
            performMask(address12: address12)
            break
            
        case 0o100: // READ instruction
            performRead(address9: address9)
            break
            
        case 0o101: // WRITE instruction
            performWrite(address9: address9)
            break
            
        case 0o102: // RAND instruction
            performRand(address9: address9)
            break
            
        case 0o103: // WAND instruction
            performWand(address9: address9)
            break
            
        case 0o104: // ROR instruction
            if isL(address9) || isQ(address9) {
                writeRegister(.regA, state.accumulator | readRegister(Register(rawValue: address9)!))
            } else {
                var operand16 = overflowCorrected(state.accumulator)
                operand16 |= readIO(address: address9)
                writeRegister(.regA, signExtend(operand16))
            }
            
        case 0o105: // WOR instruction
            if isL(address9) || isQ(address9) {
                let result = state.accumulator | readRegister(Register(rawValue: address9)!)
                writeRegister(.regA, result)
                writeRegister(Register(rawValue: address9)!, result)
            } else {
                var operand16 = overflowCorrected(state.accumulator)
                operand16 |= readIO(address: address9)
                cpuWriteIO(address: address9, value: operand16)
                writeRegister(.regA, signExtend(operand16))
            }
            
        case 0o106: // RXOR instruction
            if isL(address9) || isQ(address9) {
                writeRegister(.regA, state.accumulator ^ readRegister(Register(rawValue: address9)!))
            } else {
                var operand16 = overflowCorrected(state.accumulator)
                operand16 ^= readIO(address: address9)
                writeRegister(.regA, signExtend(operand16))
            }
            
        case 0o107: // EDRUPT instruction
            // Should not be possible to get here since EDRUPT is treated as interrupt
            break
            
        case 0o110...0o111: // DV instruction
            performDV(address10: address10)
        case 0o112...0o117: // BZF instruction
            if performBZF(address12: address12) {
                justTookBZF = true
            }
            break
            
        case 0o120...0o121: // MSU instruction
            performMSU(address10: address10)
        case 0o122...0o123: // QXCH instruction
            performQXCH(address10: address10)
        case 0o124...0o125: // AUG instruction
            performAUG(address10: address10)
            
        case 0o126...0o127: // DIM instruction
            performDIM(address10: address10)
            
        case 0o130...0o137: // DCA instruction
            performDCA(address12: address12)
            
        case 0o140...0o147: // DCS instruction
            performDCS(address12: address12)
            
        case 0o160...0o161: // SU instruction
            performSU(address10: address10)
            
        case 0o162...0o167: // BZMF instruction
            if performBZMF(address12: address12) {
                justTookBZMF = true
            }
            break
        case 0o170...0o177: // MP instruction
            performMP(address12: address12)
            
        default:
            break // Unrecognized instruction
        }
        
        // Update state after instruction execution
        if !state.pendFlag {
            writeRegister(.regZERO, AGC_P0)
            state.inputChannels[7] = state.outputChannel7 & 0o160
            writeRegister(.regZ, state.nextZ)
            
            // In all cases except for RESUME, Z will be truncated to 12 bits between instructions
            if !state.substituteInstruction {
                writeRegister(.regZ, readRegister(.regZ) & 0o7777)
            }
            
            if !keepExtraCode {
                state.extraCode = false
            }
            
            // Values written to EB and FB are automatically mirrored to BB, and vice versa
            if currentBB != readRegister(.regBB) {
                writeRegister(.regFB, readRegister(.regBB) & 0o76000)
                writeRegister(.regEB, (readRegister(.regBB) & 0o7) << 8)
            } else if currentEB != readRegister(.regEB) || currentFB != readRegister(.regFB) {
                writeRegister(.regBB, (readRegister(.regFB) & 0o76000) | ((readRegister(.regEB) & 0o3400) >> 8))
            }
            
            writeRegister(.regEB, readRegister(.regEB) & 0o3400)
            writeRegister(.regFB, readRegister(.regFB) & 0o76000)
            writeRegister(.regBB, readRegister(.regBB) & 0o76007)
            
            // Correct overflow in the L register
            writeRegister(.regL, signExtend(overflowCorrected(readRegister(.regL))))
            
            // Check ISR status and clear Rupt Lock flags accordingly
            if state.inIsr {
                state.noRupt = false
            } else {
                state.ruptLock = false
            }
            
            // Update TC Trap flags according to the instruction we just executed
            if executedTC || tcTransient {
                state.noTC = false
            }
            if !executedTC {
                state.tcTrap = false
            }
            
            state.tookBZF = justTookBZF
            state.tookBZMF = justTookBZMF
        }
    }
    
    // Helper functions for MP instruction
    private func calculateMultiplyResult(_ operand1: Int, _ operand2: Int) -> (msWord: Int, lsWord: Int) {
        if operand2 == AGC_P0 || operand2 == AGC_M0 {
            return (AGC_P0, AGC_P0)
        }
        
        if operand1 == AGC_P0 || operand1 == AGC_M0 {
            if (operand1 == AGC_P0 && (0o40000 & operand2) != 0) ||
               (operand1 == AGC_M0 && (0o40000 & operand2) == 0) {
                return (AGC_M0, AGC_M0)
            } else {
                return (AGC_P0, AGC_P0)
            }
        }
        
        let product = agc2cpu(signExtend(operand1)) * agc2cpu(signExtend(operand2))
        let agcProduct = cpu2agc2(product)
        
        // Convert to double precision
        let wordPair = decentToSp(agcProduct)
        return (wordPair.0, wordPair.1)
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
        var overflow: Bool = false

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
        let SCALER_DIVIDER = 3
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

        /*
        //----------------------------------------------------------------------
  // Take care of any PCDU or MCDU operations that are lingering in CDU
  // FIFOs.
  if (ServiceCduFifo(State)) {
    // A CDU counter was serviced, so a cycle was used up, and we must
    // return.
    return (0);
  }
        */
        
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
                    if counterPINC(register: .regTIME1) {
                        state.extraDelay += 1
                        _ = counterPINC(register: .regTIME2)
                    }
                    
                    state.extraDelay += 1
                    if counterPINC(register: .regTIME3) {
                        state.interruptRequests[3] = 1
                    }
                }
                
                // TIME5 (5ms out of phase with TIME3)
                if 0o000 == (0o037 & state.inputChannels[ChanSCALER1]) {
                    state.extraDelay += 1
                    if counterPINC(register: .regTIME5) {
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
                    if counterPINC(register: .regTIME4) {
                        state.interruptRequests[4] = 1
                    }
                }
                
                // TIME6 (increments 0.3125ms after TIME1/TIME3 if enabled)
                if (state.inputChannels[0o13] & 0o40000) != 0 && 
                   (state.inputChannels[ChanSCALER1] & 0o1) == 0o1 {
                    state.extraDelay += 1
                    if counterDINC(register: .regTIME6, counterNumber: 0) {
                        state.interruptRequests[1] = 1
                        // Disable T6 by clearing CH13 bit
                        cpuWriteIO(address: 0o13, value: state.inputChannels[0o13] & 0o37777)
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
                    cpuWriteIO(address: channel, value: 0)
                }
                
                // Clear UPLINK TOO FAST bit in channel 33
                state.inputChannels[0o33] |= 0o2000
                
                // Clear channels 34 and 35 without generating downrupt
                cpuWriteIO(address: 0o34, value: 0)
                cpuWriteIO(address: 0o35, value: 0)
                state.downruptTimeValid = false
                
                // Clear internal state
                state.indexValue = 0  // AGC_P0
                state.extraCode = false
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

            // Handle extra delay
            if state.extraDelay > 0 {
                state.extraDelay -= 1
                return false
            }
        }
        
        // If we're in standby mode, this is all we can accomplish --
        // everything else is switched off.
        if state.standby {
            return false
        }
        
        // Process gyro bursts
        if gyroTiming.processBurst(state: state) {
            // If gyro output occurred, notify I/O delegate
            channelOutput(channel: 0o177, value: state.outputChannels[0o177])
        }

        // After updating cycle counter:
        if imuTiming.shouldEmitBurst(state: state, currentCycle: state.cycleCounter) {
            cpuWriteIO(address: 0o14, value: imuTiming.channel14)
        }

        // Handle optics shaft & trunnion CDUs
        // Simple direct output of counter values
        if state.erasableMemory[0][Register.regOPTX.rawValue] != 0 && 
           (state.inputChannels[0o14] & 0o2000) != 0 {
            channelOutput(channel: 0o172, 
                         value: state.erasableMemory[0][Register.regOPTX.rawValue])
            state.erasableMemory[0][Register.regOPTX.rawValue] = 0
        }

        if state.erasableMemory[0][Register.regOPTY.rawValue] != 0 && 
           (state.inputChannels[0o14] & 0o4000) != 0 {
            channelOutput(channel: 0o171, 
                         value: state.erasableMemory[0][Register.regOPTY.rawValue])
            state.erasableMemory[0][Register.regOPTY.rawValue] = 0
        }

        // Instruction decoding setup

        // Reform 16-bit accumulator and check for overflow
        let accumulator = readRegister(.regA) & 0o177777
        state.accumulator = accumulator
        overflow = valueOverflowed(accumulator) != 0

        // Get program counter from Z register (12 bits)
        let programCounter = readRegister(.regZ) & 0o7777

        // Fetch the instruction
        var instruction: Int
        if state.substituteInstruction {
            instruction = readRegister(.regBRUPT)
        } else {
            // Handle indexed instructions using full AGC bank mapping
            let baseInstruction = fetchInstructionWord(at: programCounter)
            instruction = applyIndex(to: baseInstruction)
        }
        instruction &= 0o77777

        let isExtracode = state.extraCode

        // Parse instruction components
        let extendedOpcode = (instruction >> 9) | (isExtracode ? 0o100 : 0)
        let quarterCode = instruction & ~MASK10

        // Handle interrupts
        let canInterrupt = (!state.inIsr && state.allowInterrupt && 
                           !state.extraCode && !state.pendFlag && !overflow && 
                           instruction != 3 && instruction != 4 && instruction != 6) ||
                           extendedOpcode == 0o107  // Always check for EDRUPT

        if canInterrupt {
            var interruptRequested = false
            var interruptVector = 0
            
            // Search for next interrupt request in priority order
            for i in 1...10 {  // NUM_INTERRUPT_TYPES
                if state.interruptRequests[i] != 0 && debuggerInterruptMasks[i] != 0 {
                    // Clear the interrupt request
                    state.interruptRequests[i] = 0
                    state.interruptRequests[0] = i
                    
                    state.nextZ = 0o4000 + 4 * i
                    
                    interruptRequested = true
                    interruptVector = i
                    break
                }
            }
            
            // Handle EDRUPT fallback to vector 0
            if !interruptRequested && extendedOpcode == 0o107 {
                state.nextZ = 0
                interruptRequested = true
                interruptVector = 0
            }
            
            if interruptRequested {
                backtraceAdd(tag: interruptVector, target: state.nextZ)
                // Set up return state
                writeRegister(.regZRUPT, programCounter + 1)
                writeRegister(.regBRUPT, instruction)
                
                // Clear metadata
                state.extraCode = false
                state.indexValue = AGC_P0
                state.substituteInstruction = false
                
                // Vector to interrupt
                state.inIsr = true
                state.extraDelay += 1
                return false
            }
        }

        // Handle multi-MCT instruction timing
        // (except for EDRUPT, BZF, and BZMF)
        if !state.pendFlag {
            let timingIndex = quarterCode >> 10
            let extraCycles = if state.extraCode {
                extracodeTiming[timingIndex]
            } else {
                instructionTiming[timingIndex]
            }
            
            if extraCycles > 0 {
                state.pendFlag = true
                state.pendDelay = extraCycles - 1
                return false
            }
        } else {
            state.pendFlag = false
        }

        // Clear index value and substitute instruction
        state.indexValue = 0  // AGC_P0
        state.substituteInstruction = false

        // Update program counter (Z register)
        // Only lower 12 bits are used in most cases
        state.nextZ = 1 + readRegister(.regZ)
        writeRegister(.regZ, state.nextZ)

        // Execute the instruction
        executeExtendedInstruction(instruction, opcode: extendedOpcode, overflow: overflow)

        // Continue with instruction execution
        return true
    }

    /// Get input from peripherals for a channel
    private func channelInput() async -> Bool {
        guard let input = await ioDelegate?.channelInput() else {
            return false
        }

        var servicedCounter = false

        for (channel, value) in input {
            if (channel & 0o200) != 0 {
                if handleUnprogrammedIncrement(counterChannel: channel, incrementType: value) {
                    servicedCounter = true
                }
            } else {
                let normalizedChannel = channel & 0o777
                state.inputChannels[normalizedChannel] = value & 0o77777
            }
        }

        return servicedCounter
    }

    private func handleUnprogrammedIncrement(counterChannel: Int, incrementType: Int) -> Bool {
        guard (counterChannel & 0o200) != 0 else {
            return false
        }

        let counter = counterChannel & 0o177
        guard counter >= 0 && counter < state.erasableMemory[0].count else {
            return false
        }

        let type = incrementType & 0o77
        switch type {
        case 0:
            _ = counterPINC(at: counter)
            return true
        case 1, 0o21:
            _ = counterPCDU(at: counter)
            return true
        case 2:
            _ = counterMINC(at: counter)
            return true
        case 3, 0o23:
            _ = counterMCDU(at: counter)
            return true
        case 4:
            _ = counterDINC(at: counter, counterNumber: counter)
            return true
        case 5:
            _ = counterSHINC(at: counter)
            return true
        case 6:
            _ = counterSHANC(at: counter)
            return true
        default:
            return false
        }
    }

    /// Start the simulation engine.
    /// This initializes the AGC state and starts the main execution loop running at 11.7 microsecond intervals
    public func startEngine() {
        // Initialize state
        state.cycleCounter = 0
        state.extraCode = false
        state.allowInterrupt = false
        state.pendFlag = false 
        state.pendDelay = 0
        state.extraDelay = 0
        
        // Set initial program counter to 04000
        writeRegister(.regZ, 0o4000)
        
        // Clear I/O channels
        for channel in 0..<NUM_CHANNELS {
            state.inputChannels[channel] = 0
        }
        
        // Set initial values for certain channels
        state.inputChannels[0o30] = 0o37777
        state.inputChannels[0o31] = 0o77777 
        state.inputChannels[0o32] = 0o77777
        state.inputChannels[0o33] = 0o77777
        
        // Clear erasable memory
        for bank in 0..<8 {
            for addr in 0..<0o400 {
                state.erasableMemory[bank][addr] = 0
            }
        }
        
        // Start main execution loop
        engineTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // Run one machine cycle
                let result = await self.executeCycle()
                // Wait 11.7 microseconds between cycles
                try? await Task.sleep(nanoseconds: 11_700)
            }
        }
    }

    /// Run the engine for a specified number of cycles
    public func runEngine(for cycles: UInt64) async {
        for _ in 0..<cycles {
            _ = await self.executeCycle()
        }
    }

    /// Stop the simulation engine
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

    private func backtraceAdd(tag: Int, target: Int) {
        let source = readRegister(.regZ) & 0o177777
        let entry = AGCBacktraceEntry(
            cycle: state.cycleCounter,
            source: source,
            target: target & 0o177777,
            tag: tag & 0o777
        )
        state.backtrace.append(entry)
        if state.backtrace.count > BACKTRACE_LIMIT {
            state.backtrace.removeFirst(state.backtrace.count - BACKTRACE_LIMIT)
        }
    }

    private func readCounter(at offset: Int) -> Int? {
        guard offset >= 0 && offset < state.erasableMemory[0].count else {
            return nil
        }
        return state.erasableMemory[0][offset] & 0o77777
    }

    private func writeCounter(at offset: Int, _ value: Int) {
        guard offset >= 0 && offset < state.erasableMemory[0].count else {
            return
        }
        state.erasableMemory[0][offset] = value & 0o77777
    }

    @discardableResult
    func counterPINC(register: Register) -> Bool {
        return counterPINC(at: register.rawValue)
    }

    @discardableResult
    func counterMINC(register: Register) -> Bool {
        return counterMINC(at: register.rawValue)
    }

    @discardableResult
    func counterDINC(register: Register, counterNumber: Int = 0) -> Bool {
        return counterDINC(at: register.rawValue, counterNumber: counterNumber)
    }

    private func counterPINC(at offset: Int) -> Bool {
        guard var value = readCounter(at: offset) else { return false }
        if value == 0o37777 {
            writeCounter(at: offset, AGC_P0)
            return true
        }
        value = (value + 1) & 0o77777
        if value == AGC_P0 {
            value = (value + 1) & 0o77777
        }
        writeCounter(at: offset, value)
        return false
    }

    private func counterMINC(at offset: Int) -> Bool {
        guard var value = readCounter(at: offset) else { return false }
        if value == 0o40000 {
            writeCounter(at: offset, AGC_M0)
            return true
        }
        value = (value &- 1) & 0o77777
        if value == AGC_M0 {
            value = (value &- 1) & 0o77777
        }
        writeCounter(at: offset, value)
        return false
    }

    private func counterPCDU(at offset: Int) -> Bool {
        guard var value = readCounter(at: offset) else { return false }
        let overflow = value == 0o77777
        value = (value + 1) & 0o77777
        writeCounter(at: offset, value)
        return overflow
    }

    private func counterMCDU(at offset: Int) -> Bool {
        guard var value = readCounter(at: offset) else { return false }
        let overflow = value == 0
        value = (value &- 1) & 0o77777
        writeCounter(at: offset, value)
        return overflow
    }

    private func counterSHINC(at offset: Int) -> Bool {
        guard var value = readCounter(at: offset) else { return false }
        let overflow = (value & 0o20000) != 0
        value = (value << 1) & 0o37777
        writeCounter(at: offset, value)
        return overflow
    }

    private func counterSHANC(at offset: Int) -> Bool {
        guard var value = readCounter(at: offset) else { return false }
        let overflow = (value & 0o20000) != 0
        value = ((value << 1) + 1) & 0o37777
        writeCounter(at: offset, value)
        return overflow
    }

    private func counterDINC(at offset: Int, counterNumber: Int) -> Bool {
        guard var value = readCounter(at: offset) else { return false }
        var overflow = false

        if value == AGC_P0 || value == AGC_M0 {
            overflow = true
            emitCounterPulse(counterNumber: counterNumber, code: 0o17)
        } else if (value & 0o40000) != 0 {
            value = addSP16(signExtend(value), signExtend(AGC_P1)) & 0o77777
            emitCounterPulse(counterNumber: counterNumber, code: 0o16)
        } else {
            value = addSP16(signExtend(value), signExtend(AGC_M1)) & 0o77777
            emitCounterPulse(counterNumber: counterNumber, code: 0o15)
        }

        writeCounter(at: offset, value)
        return overflow
    }

    private func emitCounterPulse(counterNumber: Int, code: Int) {
        guard counterNumber != 0 else { return }
        let channel = 0o200 | (counterNumber & 0o177)
        channelOutput(channel: channel, value: code & 0o17)
    }

    /// Check if a value has overflowed
    private func valueOverflowed(_ value: Int) -> Int {
        if (value & 0o140000) == 0o040000 {
            return 1  // Positive overflow
        }
        if (value & 0o140000) == 0o100000 {
            return -1 // Negative overflow
        }
        return 0     // No overflow
    }
    
    /// Sign extend an SP value into AGC's 17-bit accumulator format
    private func signExtend(_ value: Int) -> Int {
        return (value & 0o77777) | ((value << 1) & 0o100000)
    }

    /// Convert a double-precision value to two single-precision values
    private func decentToSp(_ decent: Int) -> (msb: Int, lsb: Int) {
        let sign = decent & 0o4000000000
        var lsb = decent & 0o37777
        if sign != 0 {
            lsb |= 0o40000
        }
        let msb = overflowCorrected((decent >> 14) & 0o177777)
        return (msb, lsb)
    }
    
    /// Add two 16-bit values with 1's complement arithmetic
    private func addSP16(_ a: Int, _ b: Int) -> Int {
        var sum = (a & 0o177777) + (b & 0o177777)
        if (sum & 0o200000) != 0 {
            sum = (sum + 1) & 0o177777
        } else {
            sum &= 0o177777
        }
        return sum
    }

    private func readRawWord(_ address: Int) -> Int {
        if address < Register.ramStart, let reg = Register(rawValue: address) {
            return readRegister(reg) & 0o177777
        }
        return findMemoryWord(address) & 0o77777
    }
    
    /// Correct overflow in a 16-bit value
    private func overflowCorrected(_ value: Int) -> Int {
        switch valueOverflowed(value) {
        case 1:  return value & 0o37777  // Positive overflow
        case -1: return value | 0o40000  // Negative overflow
        default: return value
        }
    }
    
    /// Find the memory word for a given 12-bit address, taking bank selection into account
    private func findMemoryWord(_ address12: Int) -> Int {
        // Make sure the address is 12 bits
        let address = address12 & 0o7777
        
        // Check for NEWJOB access (address 67) for Night Watchman
        if address == 0o67 {
            state.nightWatchman = 0
        }
        
        // Handle different memory regions
        if address < 0o400 {
            // Unswitched erasable
            return state.erasableMemory[0][address & 0o377]
        } else if address < 0o1000 {
            // Unswitched erasable (continued)
            return state.erasableMemory[1][address & 0o377]
        } else if address < 0o1400 {
            // Unswitched erasable (continued)
            return state.erasableMemory[2][address & 0o377]
        } else if address < 0o2000 {
            // Switched erasable
            let adjustmentEB = 7 & (readRegister(.regEB) >> 8)
            return state.erasableMemory[adjustmentEB][address & 0o377]
        }
        
        // Handle fixed memory regions
        var adjustmentFB: Int
        if address < 0o4000 {
            // Fixed-switchable
            adjustmentFB = 0o37 & (readRegister(.regFB) >> 10)
            // Account for superbank bit
            if (0o30 == (adjustmentFB & 0o30)) && ((state.outputChannel7 & 0o100) != 0) {
                adjustmentFB += 0o10
            }
        } else if address < 0o6000 {
            // Fixed-fixed
            adjustmentFB = 2
        } else {
            // Fixed-fixed (continued)
            adjustmentFB = 3
        }
        
        let value = state.fixedMemory[adjustmentFB][address & 0o1777]
        
        // Check parity if enabled
        if state.checkParity {
            let linearAddr = adjustmentFB * 0o2000 + (address & 0o1777)
            let expectedParity = (state.parities[linearAddr / 32] >> (linearAddr % 32)) & 1
            var word = (value << 1) | expectedParity
            
            // Calculate parity
            word ^= (word >> 8)
            word ^= (word >> 4)
            word ^= (word >> 2)
            word ^= (word >> 1)
            word &= 1
            
            if word != 1 {
                // Accessing unused fixed memory triggers parity alarm
                state.parityFail = true
                state.inputChannels[0o77] |= CH77_PARITY_FAIL
            }
        }
        
        return value
    }
    
    /// Compute the "diminished absolute value" for a 15-bit value in AGC 1's-complement format
    private func dabs(_ input: Int) -> Int {
        var value = input
        
        // If input is negative, convert to positive by taking 1's complement
        if (0o40000 & value) != 0 {
            value = 0o37777 & ~value
        }
        
        // "Diminish" if greater than 1, otherwise return +0
        if value > 1 {
            value -= 1
        } else {
            value = AGC_P0
        }
        
        return value
    }
    
    /// Compute the "diminished absolute value" for a 16-bit register value
    private func odabs(_ input: Int) -> Int {
        var value = input
        
        // If input is negative, convert to positive by taking 1's complement
        if (0o100000 & value) != 0 {
            value = 0o177777 & ~value
        }
        
        // "Diminish" if greater than 1, otherwise return +0 
        if value > 1 {
            value -= 1
        } else {
            value = AGC_P0
        }
        
        return value
    }

    /// Convert an AGC-formatted word to CPU-native format
    private func agc2cpu(_ input: Int) -> Int {
        if (0o40000 & input) != 0 {
            return -(0o37777 & ~input)
        } else {
            return 0o37777 & input
        }
    }
    
    /// Convert a native CPU-formatted word to AGC format
    /// If the input value is out of range, it is truncated by discarding high-order bits
    private func cpu2agc(_ input: Int) -> Int {
        if input < 0 {
            return 0o77777 & ~(-input)
        } else {
            return 0o77777 & input
        }
    }
    
    /// Double-length version of agc2cpu
    private func agc2cpu2(_ input: Int) -> Int {
        if (0o2000000000 & input) != 0 {
            return -(0o1777777777 & ~input)
        } else {
            return 0o1777777777 & input
        }
    }
    
    /// Double-length version of cpu2agc
    private func cpu2agc2(_ input: Int) -> Int {
        if input < 0 {
            return 0o3777777777 & ~(0o1777777777 & (-input))
        } else {
            return 0o1777777777 & input
        }
    }

    /// Assign a value to erasable memory at the given address
    private func assignFromPointer(_ address: Int, _ value: Int) {
        // Only handle erasable memory (addresses 0-3777)
        if address >= 0 && address < 0o4000 {
            let bank = address / 0o400
            let offset = address & 0o377
            assign(bank: bank, offset: offset, value: value)
        }
    }

    /// Assign a value to erasable memory with editing for special registers
    private func assign(bank: Int, offset: Int, value: Int) {
        // Validate bank range
        guard bank >= 0 && bank < 8 else {
            return // Non-erasable memory
        }
        
        // Validate offset range
        guard offset >= 0 && offset < 0o400 else {
            return
        }
        
        var newValue = value
        
        // Handle special registers in bank 0
        if bank == 0 {
            switch offset {
            case Register.regZ.rawValue:
                state.nextZ = newValue
                
            case Register.regCYR.rawValue:
                newValue &= 0o77777
                if (newValue & 1) != 0 {
                    newValue = (newValue >> 1) | 0o40000
                } else {
                    newValue >>= 1
                }
                
            case Register.regSR.rawValue:
                newValue &= 0o77777
                if (newValue & 0o40000) != 0 {
                    newValue = (newValue >> 1) | 0o40000
                } else {
                    newValue >>= 1
                }
                
            case Register.regCYL.rawValue:
                newValue &= 0o77777
                if (newValue & 0o40000) != 0 {
                    newValue = (newValue << 1) + 1
                } else {
                    newValue <<= 1
                }
                
            case Register.regEDOP.rawValue:
                newValue = ((newValue & 0o77777) >> 7) & 0o177
                
            case Register.regZERO.rawValue:
                newValue = AGC_P0
                
            default:
                break
            }
        }
        
        // Apply appropriate masking rules
        let mask: Int
        if bank == 0 && offset < Register.ramStart && !(offset >= 0o20 && offset <= 0o23) {
            mask = 0o177777
        } else {
            mask = 0o77777
        }
        
        state.erasableMemory[bank][offset] = newValue & mask
    }


    /// Process channel I/O routines
    private func channelRoutine() {
        // Update DSKY display
        updateDSKY()
        
        // Process radar data if needed
        if state.radarGateCounter == 9 && 
           (0o36 == (0o37 & state.inputChannels[ChanSCALER1])) {
            
            // Reset radar gate counter
            state.radarGateCounter = 0
            
            // Reset radar activity bit
            state.inputChannels[0o13] &= ~0o10
            
            // Request new radar data
            requestRadarData()
            
            // Set RADARUPT pending
            state.interruptRequests[9] = 1
        }
        
        // TODO: Implement DEDA shift register
//        // Process DEDA shift register
//        if let dedaData = state.dedaShiftRegister {
//            shiftToDeda(dedaData)
//            state.dedaShiftRegister = nil
//        }
    }

    /// Request new radar data from peripherals
    private func requestRadarData() {
        ioDelegate?.requestRadarData()
    }

    /// Shift data to DEDA display
    private func shiftToDeda(_ data: Int) {
        ioDelegate?.shiftToDeda(data: data)
    }

    /// Read a value from an I/O channel or register
    private func readIO(address: Int) -> Int {
        // Validate address range
        guard address >= 0 && address <= 0o777 else {
            return 0
        }
        
        // Handle special registers that appear in both memory and I/O space
        if address == Register.regL.rawValue || address == Register.regQ.rawValue {
            return state.erasableMemory[0][address]
        }
        
        return state.inputChannels[address]
    }

    /// Write a value to an I/O channel or register with special handling
    private func writeIO(address: Int, value: Int) {
        // Validate address range
        guard address >= 0 && address <= 0o777 else {
            return
        }
        
        // Mask value to 15 bits
        let maskedValue = value & 0o77777
        
        // Handle special registers that appear in both memory and I/O space
        if address == Register.regL.rawValue || address == Register.regQ.rawValue {
            state.erasableMemory[0][address] = maskedValue
            return
        }
        
        // Handle special cases for certain channels
        var modifiedValue = maskedValue
        
        if address == 0o10 {
            // Channel 10 is converted externally into up to 16 ports via latching relays
            state.outputChannel10[(maskedValue >> 11) & 0o17] = maskedValue
        }
        else if address == 0o15 || address == 0o16 {
            // RSET being pressed on either DSKY clears RESTART light directly
            if maskedValue == 0o22 {
                state.restartLight = false
            }
        }
        else if address == 0o33 {
            // Reset bits 11-15 to 1 for channel 33
            state.inputChannels[address] |= 0o76000
            
            // Don't allow warning reset if light still on
            if state.warningFilter > WARNING_FILTER_THRESHOLD {
                state.inputChannels[address] &= 0o57777
            }
            
            // Use existing channel value
            modifiedValue = state.inputChannels[address]
        }
        else if address == 0o77 {
            // Reset CH77 alarm codes
            modifiedValue = 0
            
            // Set night watchman bit if tripped
            if state.nightWatchmanTripped {
                modifiedValue |= CH77_NIGHT_WATCHMAN
            }
        }
        else if address == 0o11 && (maskedValue & 0o1000) != 0 {
            // Reset DSKY restart light when CH11 bit 10 is written with 1
            state.restartLight = false
        }
        
        // Store final value
        state.inputChannels[address] = modifiedValue
        
        // Notify I/O delegate
        channelOutput(channel: address, value: modifiedValue & 0o77777)
        
        // Handle downlink timing
        if address == 0o34 {
            state.downlink |= 1
        }
        else if address == 0o35 {
            state.downlink |= 2
        }
        
        if state.downlink == 3 {
            state.downruptTimeValid = true
            state.downruptTime = state.cycleCounter + (AGC_PER_SECOND / 50)
            state.downlink = 0
        }
    }

    /// Public helper for sending keypresses into the AGC
    func writeIOChannel(address: Int, value: Int) {
        cpuWriteIO(address: address, value: value)
    }
    
    /// Handle CCS instruction logic
    func handleCCS(address10: Int) {
        var operand16: Int
        var valueK: Int = 0

        if address10 < Register.ramStart {
            valueK = readRegister(Register(rawValue: address10)!) & 0o177777
            operand16 = overflowCorrected(valueK)
            writeRegister(.regA, odabs(valueK))
        } else {
            let whereWord = findMemoryWord(address10)
            operand16 = whereWord & 0o77777
            writeRegister(.regA, dabs(operand16))
            assignFromPointer(address10, operand16)
        }
        
        if address10 < Register.ramStart && valueOverflowed(valueK) == 1 {
            // No change
        } else if address10 < Register.ramStart && valueOverflowed(valueK) == -1 {
            state.nextZ += 2
        } else if operand16 == AGC_P0 {
            state.nextZ += 1
        } else if operand16 == AGC_M0 {
            state.nextZ += 3
        } else if (operand16 & 0o40000) != 0 {
            state.nextZ += 2
        }
    }
    
    /// Handle DDOUBL behavior of DAS instruction
    func doubleRegisters() {
        var lsw = addSP16(readRegister(.regL) & 0o177777, readRegister(.regL) & 0o177777)
        var msw = addSP16(state.accumulator, state.accumulator)
        
        if (0o140000 & lsw) == 0o40000 {
            msw = addSP16(msw, AGC_P1)
        } else if (0o140000 & lsw) == 0o100000 {
            msw = addSP16(msw, signExtend(AGC_M1))
        }
        lsw = overflowCorrected(lsw)
        writeRegister(.regA, msw & 0o177777)
        writeRegister(.regL, signExtend(lsw) & 0o177777)
    }
    
    /// Handle DXCH swaps
    func handleDXCH(address10: Int) {
        if isL(address10) {
            writeRegister(.regL, signExtend(overflowCorrected(readRegister(.regL))))
            return
        }
        
        let liveWord = findMemoryWord(address10)
        
        if address10 < Register.ramStart {
            let operand16 = readRegister(Register(rawValue: address10)!)
            writeRegister(Register(rawValue: address10)!, readRegister(.regL))
            writeRegister(.regL, operand16)
            
            if address10 == Register.regZ.rawValue {
                state.nextZ = readRegister(.regZ)
            }
        } else {
            let operand16 = signExtend(liveWord)
            assignFromPointer(address10, overflowCorrected(readRegister(.regL)))
            writeRegister(.regL, operand16)
        }
        
        writeRegister(.regL, signExtend(overflowCorrected(readRegister(.regL))))
        
        let bottomAddress = (address10 &- 1) & 0o7777
        
        if address10 < Register.ramStart + 1 {
            let operand16 = readRegister(Register(rawValue: bottomAddress)!)
            writeRegister(Register(rawValue: bottomAddress)!, readRegister(.regA))
            writeRegister(.regA, operand16)
            
            if address10 == Register.regZ.rawValue + 1 {
                state.nextZ = readRegister(.regZ)
            }
        } else {
            let lowerWord = findMemoryWord(bottomAddress)
            let operand16 = signExtend(lowerWord)
            assignFromPointer(bottomAddress, overflowCorrected(readRegister(.regA)))
            writeRegister(.regA, operand16)
        }
    }

    func performResume() {
        state.nextZ = (readRegister(.regZRUPT) - 1) & 0o177777
        let tag = state.inIsr ? 255 : 0
        backtraceAdd(tag: tag, target: state.nextZ)
        state.inIsr = false
        state.substituteInstruction = true
    }

    func performMask(address12: Int) {
        if address12 < Register.ramStart {
            writeRegister(.regA, state.accumulator & readRegister(Register(rawValue: address12)!))
        } else {
            writeRegister(.regA, overflowCorrected(state.accumulator))
            let whereWord = findMemoryWord(address12)
            writeRegister(.regA, signExtend(readRegister(.regA) & whereWord))
        }
    }

    func performTCF(address12: Int) {
        backtraceAdd(tag: 0, target: address12)
        state.nextZ = address12
    }

    func applyIndex(to baseInstruction: Int) -> Int {
        return overflowCorrected(
            addSP16(signExtend(state.indexValue),
                    signExtend(baseInstruction))
        )
    }

    func performRead(address9: Int) {
        if isL(address9) || isQ(address9) {
            writeRegister(.regA, readRegister(Register(rawValue: address9)!))
        } else {
            writeRegister(.regA, signExtend(readIO(address: address9)))
        }
    }

    func performWrite(address9: Int) {
        if isL(address9) || isQ(address9) {
            writeRegister(Register(rawValue: address9)!, state.accumulator)
        } else {
            cpuWriteIO(address: address9, value: overflowCorrected(state.accumulator))
        }
    }

    func performRand(address9: Int) {
        if isL(address9) || isQ(address9) {
            writeRegister(.regA, state.accumulator & readRegister(Register(rawValue: address9)!))
        } else {
            var operand16 = overflowCorrected(state.accumulator)
            operand16 &= readIO(address: address9)
            writeRegister(.regA, signExtend(operand16))
        }
    }

    func performWand(address9: Int) {
        if isL(address9) || isQ(address9) {
            let result = state.accumulator & readRegister(Register(rawValue: address9)!)
            writeRegister(.regA, result)
            writeRegister(Register(rawValue: address9)!, result)
        } else {
            var operand16 = overflowCorrected(state.accumulator)
            operand16 &= readIO(address: address9)
            cpuWriteIO(address: address9, value: operand16)
            writeRegister(.regA, signExtend(operand16))
        }
    }

    func performLXCH(address10: Int) {
        if isL(address10) {
            return
        }

        if isReg(address10, .regZERO) {
            writeRegister(.regL, AGC_P0)
            return
        }

        if address10 < Register.ramStart {
            let operand16 = readRegister(.regL)
            writeRegister(.regL, readRegister(Register(rawValue: address10)!))

            if address10 >= 0o20 && address10 <= 0o23 {
                assignFromPointer(address10, overflowCorrected(operand16 & 0o177777))
            } else {
                writeRegister(Register(rawValue: address10)!, operand16)
            }

            if address10 == Register.regZ.rawValue {
                state.nextZ = readRegister(.regZ)
            }
        } else {
            let whereWord = findMemoryWord(address10)
            let operand16 = overflowCorrected(readRegister(.regL) & 0o177777)
            assignFromPointer(address10, operand16)
            writeRegister(.regL, signExtend(whereWord))
        }
    }

    func performINCR(address10: Int) {
        let whereWord = findMemoryWord(address10)

        if address10 < Register.ramStart {
            let current = readRegister(Register(rawValue: address10)!) & 0o177777
            writeRegister(Register(rawValue: address10)!, addSP16(AGC_P1, current))
        } else {
            let sum = addSP16(AGC_P1, signExtend(whereWord))
            assignFromPointer(address10, overflowCorrected(sum))
            interruptRequests(address10, sum)
        }
    }

    func performADS(address10: Int) {
        if isA(address10) {
            state.accumulator = addSP16(state.accumulator, state.accumulator)
        } else if address10 < Register.ramStart {
            let operand = readRegister(Register(rawValue: address10)!) & 0o177777
            state.accumulator = addSP16(state.accumulator, operand)
            writeRegister(Register(rawValue: address10)!, state.accumulator)
        } else {
            let whereWord = findMemoryWord(address10)
            state.accumulator = addSP16(state.accumulator, signExtend(whereWord))
            assignFromPointer(address10, overflowCorrected(state.accumulator))
        }
        writeRegister(.regA, state.accumulator)
    }

    func performCA(address12: Int) {
        if isA(address12) {
            return
        }

        if address12 < Register.ramStart {
            writeRegister(.regA, readRegister(Register(rawValue: address12)!))
            return
        }

        let whereWord = findMemoryWord(address12)
        writeRegister(.regA, signExtend(whereWord))
        assignFromPointer(address12, whereWord)
    }

    func performCS(address12: Int) {
        if isA(address12) {
            writeRegister(.regA, ~state.accumulator)
            return
        }

        if address12 < Register.ramStart {
            writeRegister(.regA, ~readRegister(Register(rawValue: address12)!))
            return
        }

        let whereWord = findMemoryWord(address12)
        writeRegister(.regA, signExtend(negateSP(whereWord)))
        assignFromPointer(address12, whereWord)
    }

    func performTS(address10: Int, overflow: Bool) {
        if isA(address10) {
            if overflow {
                state.nextZ += AGC_P1
            }
            return
        }

        if isZ(address10) {
            state.nextZ = state.accumulator & 0o77777
            if overflow {
                writeRegister(.regA, signExtend(valueOverflowed(state.accumulator)))
            }
            return
        }

        _ = findMemoryWord(address10)

        if address10 < Register.ramStart {
            writeRegister(Register(rawValue: address10)!, state.accumulator)
        } else {
            assignFromPointer(address10, overflowCorrected(state.accumulator))
        }

        if address10 == Register.regZ.rawValue {
            state.nextZ = readRegister(.regZ)
        }

        if overflow {
            writeRegister(.regA, signExtend(valueOverflowed(state.accumulator)))
            state.nextZ += AGC_P1
        }
    }

    func performIndex(address10: Int) {
        if address10 == 0o17 {
            performResume()
            return
        }
        loadIndexValue(address: address10)
    }

    func performExtracodeIndex(address12: Int) -> Bool {
        if address12 == (0o17 << 1) {
            performResume()
            return false
        }
        loadIndexValue(address: address12)
        return true
    }

    private func loadIndexValue(address: Int) {
        if address < Register.ramStart {
            state.indexValue = overflowCorrected(readRegister(Register(rawValue: address)!) & 0o177777)
        } else {
            state.indexValue = findMemoryWord(address)
        }
    }

    func performXCH(address10: Int) {
        if isA(address10) {
            return
        }

        if address10 < Register.ramStart {
            writeRegister(.regA, readRegister(Register(rawValue: address10)!))
            writeRegister(Register(rawValue: address10)!, state.accumulator)

            if address10 == Register.regZ.rawValue {
                state.nextZ = readRegister(.regZ)
            }
            return
        }

        let whereWord = findMemoryWord(address10)
        writeRegister(.regA, signExtend(whereWord))
        assignFromPointer(address10, overflowCorrected(state.accumulator))
    }

    func performAD(address12: Int) {
        if isA(address12) {
            state.accumulator = addSP16(state.accumulator, state.accumulator)
        } else if address12 < Register.ramStart {
            let operand = readRegister(Register(rawValue: address12)!) & 0o177777
            state.accumulator = addSP16(state.accumulator, operand)
        } else {
            let whereWord = findMemoryWord(address12)
            state.accumulator = addSP16(state.accumulator, signExtend(whereWord))
            assignFromPointer(address12, whereWord)
        }
        writeRegister(.regA, state.accumulator)
    }

    func performBZF(address12: Int) -> Bool {
        if state.accumulator == 0 || state.accumulator == 0o177777 {
            state.nextZ = address12
            state.extraDelay += 1
            backtraceAdd(tag: 0, target: address12)
            return true
        }
        return false
    }

    func performBZMF(address12: Int) -> Bool {
        if state.accumulator == 0 || (state.accumulator & 0o100000) != 0 {
            state.nextZ = address12
            state.extraDelay += 1
            backtraceAdd(tag: 0, target: address12)
            return true
        }
        return false
    }

    func performDV(address10: Int) {
        let accMSW = overflowCorrected(state.accumulator)
        let accLSW = readRegister(.regL) & 0o177777
        let dividend = spToDecent(msw: accMSW, lsw: accLSW)

        let absA = absSP(accMSW)
        let absL = absSP(accLSW)

        var div16: Int
        if isA(address10) {
            div16 = readRegister(.regA)
            if (readRegister(.regA) & 0o100000) == 0 {
                div16 = 0o177777 & ~div16
            }
        } else if isL(address10) {
            div16 = readRegister(.regL)
            if ((absA == 0 && (0o100000 & readRegister(.regL)) != 0) ||
                (absA != 0 && (0o100000 & readRegister(.regA)) != 0)) {
                div16 = 0o177777 & ~div16
            }
            div16 = signExtend(overflowCorrected(addSP16(div16, 0o40000)))
        } else if isZ(address10) {
            div16 = readRegister(.regZ)
            if ((absA == 0 && (0o100000 & readRegister(.regL)) != 0) ||
                (absA != 0 && (0o100000 & readRegister(.regA)) != 0)) {
                div16 |= 0o100000
            }
        } else if address10 < Register.ramStart {
            div16 = readRegister(Register(rawValue: address10)!)
        } else {
            div16 = signExtend(findMemoryWord(address10))
        }

        let absK = absSP(overflowCorrected(div16))

        if absA > absK || (absA == absK && absL != AGC_P0) ||
            valueOverflowed(div16) != AGC_P0 {
            simulateDV(div16)
        } else if absA == 0 && absL == 0 {
            let operand16: Int
            if (0o40000 & accLSW) == (0o40000 & overflowCorrected(div16)) {
                operand16 = absK == 0 ? 0o37777 : AGC_P0
            } else {
                operand16 = absK == 0 ? (0o77777 & ~0o37777) : AGC_M0
            }
            writeRegister(.regA, signExtend(operand16))
        } else if absA == absK && absL == AGC_P0 {
            let operand16 = accMSW == overflowCorrected(div16) ?
                0o37777 : (0o77777 & ~0o37777)
            writeRegister(.regL, signExtend(accMSW))
            writeRegister(.regA, signExtend(operand16))
        } else {
            let dividendCPU = agc2cpu2(dividend)
            let divisorCPU = agc2cpu(overflowCorrected(div16))
            let quotient = dividendCPU / divisorCPU
            let remainder = dividendCPU % divisorCPU

            writeRegister(.regA, signExtend(cpu2agc(quotient)))

            if remainder == 0 {
                writeRegister(.regL, dividendCPU >= 0 ? AGC_P0 : signExtend(AGC_M0))
            } else {
                writeRegister(.regL, signExtend(cpu2agc(remainder)))
            }
        }
    }

    func performQXCH(address10: Int) {
        if isQ(address10) {
            return
        }

        if isReg(address10, .regZERO) {
            writeRegister(.regQ, AGC_P0)
        } else if address10 < Register.ramStart {
            let operand16 = readRegister(.regQ)
            writeRegister(.regQ, readRegister(Register(rawValue: address10)!))
            writeRegister(Register(rawValue: address10)!, operand16)

            if address10 == Register.regZ.rawValue {
                state.nextZ = readRegister(.regZ)
            }
        } else {
            let whereWord = findMemoryWord(address10)
            let operand16 = overflowCorrected(readRegister(.regQ))
            writeRegister(.regQ, signExtend(whereWord))
            assignFromPointer(address10, operand16)
        }
    }

    func performMSU(address10: Int) {
        let whereWord = findMemoryWord(address10)
        let operand = address10 < Register.ramStart ?
            readRegister(Register(rawValue: address10)!) :
            signExtend(whereWord)

        let ui = 0o177777 & state.accumulator
        let uj = 0o177777 & ~operand
        var diff = ui + uj + 1

        if (diff & 0o40000) != 0 {
            diff |= 0o100000
            diff -= 1
        }

        if isQ(address10) {
            writeRegister(.regA, diff & 0o177777)
        } else {
            writeRegister(.regA, signExtend(diff & 0o177777))
        }

        if address10 >= 0o20 && address10 <= 0o23 {
            assignFromPointer(address10, whereWord)
        }
    }

    func performAUG(address10: Int) {
        let whereWord = findMemoryWord(address10)
        var operand = address10 < Register.ramStart ?
            readRegister(Register(rawValue: address10)!) :
            signExtend(whereWord)

        operand &= 0o177777
        let increment = (operand & 0o100000) == 0 ? AGC_P1 : signExtend(AGC_M1)
        let sum = addSP16(increment & 0o177777, operand)

        if address10 < Register.ramStart {
            writeRegister(Register(rawValue: address10)!, sum)
        } else {
            assignFromPointer(address10, overflowCorrected(sum))
            interruptRequests(address10, sum)
        }
    }

    func performDIM(address10: Int) {
        let whereWord = findMemoryWord(address10)
        var operand = address10 < Register.ramStart ?
            readRegister(Register(rawValue: address10)!) :
            signExtend(whereWord)

        operand &= 0o177777
        if operand == AGC_P0 || operand == signExtend(AGC_M0) {
            return
        }

        let increment = (operand & 0o100000) == 0 ? signExtend(AGC_M1) : AGC_P1
        let sum = addSP16(increment & 0o177777, operand)

        if address10 < Register.ramStart {
            writeRegister(Register(rawValue: address10)!, sum)
        } else {
            assignFromPointer(address10, overflowCorrected(sum))
        }
    }

    func performRor(address9: Int) {
        if isL(address9) || isQ(address9) {
            writeRegister(.regA, state.accumulator | readRegister(Register(rawValue: address9)!))
        } else {
            var operand16 = overflowCorrected(state.accumulator)
            operand16 |= readIO(address: address9)
            writeRegister(.regA, signExtend(operand16))
        }
    }

    func performWor(address9: Int) {
        if isL(address9) || isQ(address9) {
            let result = state.accumulator | readRegister(Register(rawValue: address9)!)
            writeRegister(.regA, result)
            writeRegister(Register(rawValue: address9)!, result)
        } else {
            var operand16 = overflowCorrected(state.accumulator)
            operand16 |= readIO(address: address9)
            cpuWriteIO(address: address9, value: operand16)
            writeRegister(.regA, signExtend(operand16))
        }
    }

    func performRxor(address9: Int) {
        if isL(address9) || isQ(address9) {
            writeRegister(.regA, state.accumulator ^ readRegister(Register(rawValue: address9)!))
        } else {
            var operand16 = overflowCorrected(state.accumulator)
            operand16 ^= readIO(address: address9)
            writeRegister(.regA, signExtend(operand16))
        }
    }

    func performDCA(address12: Int) {
        if isL(address12) {
            writeRegister(.regL, signExtend(overflowCorrected(readRegister(.regL))))
            return
        }

        let topOriginal = readRawWord(address12)
        let topSigned = signExtend(topOriginal)
        writeRegister(.regL, signExtend(overflowCorrected(topSigned)))

        let bottomAddress = (address12 &- 1) & 0o7777
        let bottomOriginal = readRawWord(bottomAddress)
        writeRegister(.regA, signExtend(bottomOriginal))

        if address12 >= 0o20 && address12 <= 0o23 {
            assignFromPointer(address12, topOriginal)
        }
        if bottomAddress >= 0o21 && bottomAddress <= 0o24 {
            assignFromPointer(bottomAddress, bottomOriginal)
        }
    }

    func performDCS(address12: Int) {
        if isL(address12) {
            writeRegister(.regA, ~state.accumulator)
            let complementedL = (~readRegister(.regL)) & 0o177777
            writeRegister(.regL, signExtend(overflowCorrected(complementedL)))
            return
        }

        let topOriginal = readRawWord(address12)
        let topSigned = signExtend(topOriginal)
        let complementedTop = (~topSigned) & 0o177777
        writeRegister(.regL, signExtend(overflowCorrected(complementedTop)))

        let bottomAddress = (address12 &- 1) & 0o7777
        let bottomOriginal = readRawWord(bottomAddress)
        let bottomSigned = signExtend(bottomOriginal)
        let complementedBottom = (~bottomSigned) & 0o177777
        writeRegister(.regA, signExtend(complementedBottom))

        if address12 >= 0o20 && address12 <= 0o23 {
            assignFromPointer(address12, topOriginal)
        }
        if bottomAddress >= 0o21 && bottomAddress <= 0o24 {
            assignFromPointer(bottomAddress, bottomOriginal)
        }
    }

    func performSU(address10: Int) {
        if isA(address10) {
            state.accumulator = signExtend(AGC_M0)
        } else if address10 < Register.ramStart {
            let operand = readRegister(Register(rawValue: address10)!)
            state.accumulator = addSP16(state.accumulator, 0o177777 & ~operand)
        } else {
            let whereWord = findMemoryWord(address10)
            state.accumulator = addSP16(state.accumulator, signExtend(negateSP(whereWord)))
            assignFromPointer(address10, whereWord)
        }
        writeRegister(.regA, state.accumulator)
    }

    func performMP(address12: Int) {
        let operand16 = overflowCorrected(state.accumulator)
        let otherOperand16: Int

        if address12 < Register.ramStart {
            otherOperand16 = overflowCorrected(readRegister(Register(rawValue: address12)!))
        } else {
            otherOperand16 = findMemoryWord(address12)
        }

        let (msWord, lsWord) = calculateMultiplyResult(operand16, otherOperand16)
        writeRegister(.regA, signExtend(msWord))
        writeRegister(.regL, signExtend(lsWord))
    }

    // Add these helper functions:
    /// Convert SP value to negative
    private func negateSP(_ value: Int) -> Int {
        return 0o77777 & ~value
    }

    /// Get absolute value in SP format
    private func absSP(_ value: Int) -> Int {
        if (value & 0o40000) != 0 {
            return 0o37777 & ~value
        }
        return value & 0o37777
    }

    /// Convert SP value pair to decent format (29-bit 1's complement)
    private func spToDecent(msw: Int, lsw: Int) -> Int {
        var msw = msw & 0o177777
        var lsw = lsw & 0o177777

        if msw == AGC_P0 || msw == AGC_M0 {
            var value = signExtend(lsw)
            if (value & 0o100000) != 0 {
                value |= ~0o177777
            }
            return value & 0o7777777777
        }

        if (0o40000 & lsw) != (0o40000 & msw) {
            if lsw == AGC_P0 || lsw == AGC_M0 {
                lsw = (0o40000 & msw) == 0 ? AGC_P0 : AGC_M0
            } else {
                let complement = (0o40000 & msw) != 0
                if complement {
                    msw = 0o77777 & ~msw
                    lsw = 0o77777 & ~lsw
                }
                msw -= 1
                lsw = (lsw + 0o40000 + AGC_P1) & 0o77777
                if complement {
                    msw = 0o77777 & ~msw
                    lsw = 0o77777 & ~lsw
                }
            }
        }

        var value = (0o3777740000 & (msw << 14)) | (0o37777 & lsw)
        if (value & 0o2000000000) != 0 {
            value |= 0o4000000000
        }
        return value
    }

    /// Simulate DV hardware behavior to match yaAGC's "total nonsense" cases
    func simulateDV(_ divisorInput: Int) {
        var a = readRegister(.regA) & 0o177777
        var l = readRegister(.regL) & 0o177777
        var divisor = divisorInput & 0o177777
        
        var dividendSign = a & 0o100000
        
        if dividendSign == 0 {
            a = 0o177777 & ~a
        }
        if a == 0o177777 {
            dividendSign = l & 0o100000
        }
        if dividendSign != 0 {
            l = 0o177777 & ~l
        }
        
        l = addSP16(l, 0o40000)
        if valueOverflowed(l) != AGC_P1 {
            a = addSP16(a, AGC_P1)
        }
        var remainder = a
        
        let divisorSign = divisor & 0o100000
        if divisorSign != 0 {
            divisor = 0o177777 & ~divisor
        }
        
        let quotientSign = l & 0o100000
        var quotient = quotientSign | ((l & 0o37777) << 1) | (quotientSign >> 15)
        quotient &= 0o177777
        
        for _ in 0..<14 {
            quotient = (quotient << 1) & 0o177777
            let remainderSign = remainder & 0o100000
            remainder = remainderSign | ((remainder & 0o37777) << 1)
            remainder &= 0o177777
            
            if (quotient & 0o100000) == 0 {
                remainder |= (remainderSign >> 15)
            }
            
            let sum = addSP16(remainder, divisor)
            if (sum & 0o100000) != 0 {
                quotient |= 1
                remainder = sum
            }
        }
        
        var newA = quotientSign | (quotient & 0o77777)
        if dividendSign != divisorSign {
            newA = 0o177777 & ~newA
        }
        
        var newL = remainder
        if dividendSign == 0 {
            newL = 0o177777 & ~remainder
        }
        
        writeRegister(.regA, signExtend(newA))
        writeRegister(.regL, signExtend(newL))
    }

    /// Handle interrupt requests generated by counter instructions
    func interruptRequests(_ address: Int, _ value: Int) {
        // Only care about values that overflowed
        if valueOverflowed(value) == AGC_P0 {
            return
        }
        
        switch address {
        case Register.regTIME1.rawValue:
            // Overflowing TIME1 increments TIME2 via PINC
            _ = counterPINC(register: .regTIME2)
        case Register.regTIME5.rawValue:
            state.interruptRequests[2] = 1
        case Register.regTIME3.rawValue:
            state.interruptRequests[3] = 1
        case Register.regTIME4.rawValue:
            state.interruptRequests[4] = 1
        default:
            // TIME6 requires hardware ZOUT side-effects which are handled elsewhere
            break
        }
    }
}

extension AGCEngine: @unchecked Sendable { } 
