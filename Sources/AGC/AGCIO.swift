import Foundation

/// Protocol for AGC I/O communication with peripherals
public protocol AGCIOProtocol {
    /// Output a value to a channel
    func channelOutput(channel: Int, value: Int)
    
    /// Get input from peripherals
    func channelInput() async -> [Int:Int]?
    
    /// Called when a radar sample gate completes (before RADARUPT). Implementations should
    /// load erasable address octal 046 (`Register.regRNRAD`) on the owning engine’s state,
    /// matching yaAGC `RequestRadarData`.
    func requestRadarData()
    
    /// Shift data to DEDA display
    func shiftToDeda(data: Int)

    /// Channel routine
    func channelRoutine() async
}

/// Default implementation of AGC I/O
public class AGCIO: AGCIOProtocol {
    public init() {}
    
    public func channelOutput(channel: Int, value: Int) {
        // Default implementation - can be overridden by clients
    }
    
    public func channelInput() async -> [Int:Int]? {
        // Default implementation returns no input
        return nil
    }
    
    public func requestRadarData() {
        // Default implementation - can be overridden by clients
    }
    
    public func shiftToDeda(data: Int) {
        // Default implementation - can be overridden by clients
    }

    public func channelRoutine() async {
        // Default implementation - can be overridden by clients
    }
} 