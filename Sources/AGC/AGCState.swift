import Foundation

/// AGC simulation state
public final class AGCState {
    // Memory banks
    public var erasableMemory: [[Int]] = Array(repeating: Array(repeating: 0, count: 0x400), count: 8)
    public var fixedMemory: [[Int]] = Array(repeating: Array(repeating: 0, count: 0x2000), count: 40)
    
    // Registers
    public var accumulator: Int = 0  // A register
    public var programCounter: Int = 0 // Z register
    public var returnAddress: Int = 0  // Q register
    public var index: Int = 0 // B register
    
    // I/O channels
    public var inputChannels: [Int] = Array(repeating: 0, count: 0x100)
    public var outputChannels: [Int] = Array(repeating: 0, count: 0x100)
    
    // Status flags
    public var extracode: Bool = false
    public var overflow: Bool = false
    public var cycleCounter: UInt64 = 0
    
    /// Holds the core binary image loaded from a file
    public var coreImage: Data?
    
    public init() { }
} 