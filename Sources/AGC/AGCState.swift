import Foundation

public struct AGCBacktraceEntry: Equatable {
    public let cycle: UInt64
    public let source: Int
    public let target: Int
    public let tag: Int
}

/// AGC simulation state
public final class AGCState {
    // Memory banks
    public var erasableMemory: [[Int]] = Array(repeating: Array(repeating: 0, count: 0x400), count: 8)
    public var fixedMemory: [[Int]] = Array(repeating: Array(repeating: 0, count: 0x2000), count: 40)

    // Parity checking
    public var parities: [Int] = Array(repeating: 0, count: 40 * 0x2000 / 32)
    
    // Registers
    public var accumulator: Int = 0  // A register
    public var programCounter: Int = 0 // Z register
    public var returnAddress: Int = 0  // Q register
    public var index: Int = 0 // B register
    
    // I/O channels
    public var inputChannels: [Int] = Array(repeating: 0, count: 512)
    public var outputChannels: [Int] = Array(repeating: 0, count: 512)
    public var outputChannel7: Int = 0
    public var outputChannel10: [Int] = Array(repeating: 0, count: 16)
    
    // CPU state
    public var cycleCounter: UInt64 = 0
    public var extraCode: Bool = false
    public var allowInterrupt: Bool = true
    public var pendFlag: Bool = false
    public var pendDelay: Int = 0
    public var extraDelay: Int = 0
    public var indexValue: Int = 0
    public var inIsr: Bool = false
    public var substituteInstruction: Bool = false
    
    // Interrupt state
    public var interruptRequests: [Int] = Array(repeating: 0, count: 11)  // NUM_INTERRUPT_TYPES + 1
    
    // Downlink state
    public var downruptTimeValid: Bool = true
    public var downruptTime: UInt64 = 0
    public var downlink: Int = 0
    
    // Night watchman
    public var nightWatchman: Int = 0
    public var nightWatchmanTripped: Bool = false
    
    // Interrupt control
    public var ruptLock: Bool = false
    public var noRupt: Bool = false
    public var tcTrap: Bool = false
    public var noTC: Bool = false
    
    // Error states
    public var parityFail: Bool = false
    public var checkParity: Bool = false
    public var warningFilter: Int = 0
    public var generatedWarning: Bool = false
    
    // Display/Standby state
    public var restartLight: Bool = false
    public var standby: Bool = false
    public var sbyPressed: Bool = false
    public var sbyStillPressed: Bool = false
    public var backtrace: [AGCBacktraceEntry] = []
    
    // Misc state
    public var nextZ: Int = 0
    public var scalerCounter: Int = 0
    public var channelRoutineCount: Int = 0
    public var dskyTimer: Int = 0
    public var dskyFlash: Int = 0
    public var dskyChannel163: Int = 0
    public var tookBZF: Bool = false
    public var tookBZMF: Bool = false
    public var trap31A: Bool = false
    public var trap31B: Bool = false
    public var trap32: Bool = false
    public var radarGateCounter: Int = 0
    
    /// Holds the binary image loaded from a file
    public var binFile: Data?
    
    public init() {
        // Clear I/O channels
        for i in 0..<inputChannels.count {
            inputChannels[i] = 0
        }
        
        // Set specific input channels
        inputChannels[0o30] = 0o37777
        inputChannels[0o31] = 0o77777
        inputChannels[0o32] = 0o77777
        inputChannels[0o33] = 0o77777
        
        // Clear erasable memory
        for bank in 0..<8 {
            for addr in 0..<0o400 {
                erasableMemory[bank][addr] = 0
            }
        }
        
        // Set initial program counter (RegZ)
        erasableMemory[0][0o7] = 0o4000  // RegZ = 04000
        
        // Initialize CPU state
        cycleCounter = 0
        extraCode = false
        allowInterrupt = true  // The GOJAM sequence enables interrupts
        interruptRequests[8] = 1  // DOWNRUPT
        pendFlag = false
        pendDelay = 0
        extraDelay = 0
        
        // Initialize I/O state
        outputChannel7 = 0
        outputChannel10 = Array(repeating: 0, count: 16)
        indexValue = 0
        
        // Initialize interrupt state
        interruptRequests = Array(repeating: 0, count: 11)
        inIsr = false
        substituteInstruction = false
        
        // Initialize downlink state
        downruptTimeValid = true
        downruptTime = 0
        downlink = 0
        
        // Initialize night watchman
        nightWatchman = 0
        nightWatchmanTripped = false
        ruptLock = false
        noRupt = false
        tcTrap = false
        noTC = false
        parityFail = false
        
        // Initialize warning state
        warningFilter = 0
        generatedWarning = false
        
        // Initialize display/standby state
        restartLight = false
        standby = false
        sbyPressed = false
        sbyStillPressed = false
        
        // Initialize misc state
        nextZ = 0
        scalerCounter = 0
        channelRoutineCount = 0
        dskyTimer = 0
        dskyFlash = 0
        dskyChannel163 = 0
        tookBZF = false
        tookBZMF = false
        trap31A = false
        trap31B = false
        trap32 = false
        radarGateCounter = 0
        backtrace = []
    }
}
