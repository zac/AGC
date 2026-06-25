import Foundation

/// One ordered AGC channel input event from an external peripheral.
///
/// Channel values may include the AGC "u-bit" (`0o400`) for mask packets. Keeping inputs
/// as an ordered list prevents repeated writes to the same channel from collapsing.
public struct AGCChannelInput: Equatable, Sendable {
    public let channel: Int
    public let value: Int

    public init(channel: Int, value: Int) {
        self.channel = channel
        self.value = value
    }
}

/// Protocol for AGC I/O communication with peripherals
public protocol AGCIOProtocol {
    /// Output a value to a channel
    func channelOutput(channel: Int, value: Int)
    
    /// Get input from peripherals
    func channelInput() async -> [AGCChannelInput]?
    
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
    
    public func channelInput() async -> [AGCChannelInput]? {
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
