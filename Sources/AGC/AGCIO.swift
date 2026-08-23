import Foundation

/// One ordered AGC channel input event from an external peripheral.
///
/// Channel values may include the AGC "u-bit" (`0o400`) for mask packets. Keeping inputs
/// as an ordered list prevents repeated writes to the same channel from collapsing.
public struct AGCChannelInput: Equatable, Sendable, Codable {
    public let channel: Int
    public let value: Int
    /// Whether this external event also raises the channel's associated interrupt.
    /// Momentary-switch releases update the channel level without a second interrupt.
    public let interrupt: Bool

    public init(channel: Int, value: Int, interrupt: Bool = true) {
        self.channel = channel
        self.value = value
        self.interrupt = interrupt
    }
}

/// Protocol for AGC I/O communication with peripherals
public protocol AGCIOProtocol {
    /// Output a value to a channel
    func channelOutput(channel: Int, value: Int)
    
    /// Get input from peripherals
    func channelInput() -> [AGCChannelInput]?
    
    /// Called when a radar sample gate completes (before RADARUPT). Implementations should
    /// load erasable address octal 046 (`Register.regRNRAD`) on the owning engine’s state,
    /// matching yaAGC `RequestRadarData`.
    func requestRadarData()
    
    /// Shift data to DEDA display
    func shiftToDeda(data: Int)

    /// Channel routine
    func channelRoutine()
}
 
