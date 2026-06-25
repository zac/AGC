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

public final class AGCEngine {
    /// The simulation state.
    public var state: AGCState
    
    /// The I/O delegate (using the protocol defined in AGCIO.swift).
    public var ioDelegate: AGCIOProtocol?
    
    /// Task that runs the simulation engine loop.
    var engineTask: Task<Void, Never>? = nil
    
    /// Simulated program counter.
    public var programCounter: Int = 0
    
    /// Instructions loaded from the core image (each word is a 16-bit value).
    var instructions: [UInt16] = []
    
    // AGC instruction masks and constants
    let EXTRACODE: Int = 0o7 
    let INDEX: Int = 0o7777
    let BASIC: Int = 0o7777
    let FIXED_BANK_SIZE = 0o2000
    let ERASABLE_BANK_SIZE = 0o400
    
    /// Instruction timing tables (cycles needed minus 1)
    let instructionTiming: [Int] = [
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
    let extracodeTiming: [Int] = [
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
    var debuggerInterruptMasks: [Int] = Array(repeating: 1, count: 11)
    
    // Add these constants near the top of AGCEngine class:
    let DSKY_OVERFLOW = 81920      // Timer overflow value
    let DSKY_FLASH_PERIOD = 4      // Flash period for DSKY lights

    // Replace the individual DSKY constants with an OptionSet
    struct DSKYFlags: OptionSet {
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
    
    let WARNING_FILTER_THRESHOLD = 125   // Warning threshold
    let BACKTRACE_LIMIT = 256            // Max stored entries

    // Channel 77 alarm bits
    let CH77_PARITY_FAIL    = 0o000001  // Parity alarm
    let CH77_TC_TRAP        = 0o000004  // TC Trap alarm
    let CH77_RUPT_LOCK      = 0o000010  // Rupt Lock alarm  
    let CH77_NIGHT_WATCHMAN = 0o000020  // Night Watchman alarm

    // Add these constants to the class:
    let SCALER_OVERFLOW = 80   // 1/3200 second in machine cycles
    /// Scaler input channels (matches yaAGC `ChanSCALER1`/`ChanSCALER2` in agc_engine.h: octal 04 and 03).
    let ChanSCALER1 = 0o4
    let ChanSCALER2 = 0o3
    let WARNING_FILTER_INCREMENT = 25
    let WARNING_FILTER_MAX = 250
    let WARNING_FILTER_DECREMENT = 2
    
    var imuTiming = IMUTiming()
    var gyroTiming = GyroTiming()
    var cduFifoStates: [CDUFifoState] = Array(repeating: CDUFifoState(), count: CDUFifoConstants.fifoCount)
    var cduChecker: Int = 0
    var channelMasks: [Int] = Array(repeating: 0o77777, count: 256)
    var lastRhcPitch = 0
    var lastRhcYaw = 0
    var lastRhcRoll = 0
    
    // Add these constants to AGCEngine:
    let MASK9 = 0o777        // 9-bit mask
    let MASK10 = 0o1777      // 10-bit mask
    let MASK12 = 0o7777      // 12-bit mask
    let REG16 = 0o3          // A, L, and Q are the 16-bit registers
    
    // Number of interrupt types supported by the AGC
    let NUM_INTERRUPT_TYPES = 10
    
    // ** NEW constant added for I/O channels **
    let NUM_CHANNELS = 512   // Total number of channels
    
    // AGC numerical constants in AGC 1's complement format
    let AGC_P0 = 0                // Positive zero
    let AGC_M0 = 0o77777         // Negative zero 
    let AGC_P1 = 1               // Positive one
    let AGC_M1 = 0o77776         // Negative one
    
    /// Simulated machine cycles per second (yaAGC `AGC_PER_SECOND`: (1024000+6)/12).
    let AGC_PER_SECOND: UInt64 = UInt64((1_024_000 + 6) / 12)

    public init(state: AGCState) throws {
        self.state = state
        state.resetForBoot()
        resetPeripheralTiming()
        try loadBinFile()
    }

    func resetPeripheralTiming() {
        cduFifoStates = Array(repeating: CDUFifoState(), count: CDUFifoConstants.fifoCount)
        cduChecker = 0
        channelMasks = Array(repeating: 0o77777, count: 256)
        lastRhcPitch = 0
        lastRhcYaw = 0
        lastRhcRoll = 0
        imuTiming = IMUTiming()
        gyroTiming = GyroTiming()
        IMUBurst.reset()
    }
    

}

extension AGCEngine: @unchecked Sendable { } 
