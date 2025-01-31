import Foundation

/// A protocol defining the I/O methods that the AGC engine will call.
public protocol AGCIOProtocol {
    /// Called when a channel output is produced.
    func channelOutput(channel: Int, value: Int)
    
    /// Called when a channel input is requested.
    func channelInput(channel: Int) async -> Int
    
    /// Called periodically for routine I/O processing.
    func channelRoutine() async
}

/// A simple I/O implementation that uses closures to allow the embedder to supply I/O behavior.
public final class AGCIO: AGCIOProtocol {
    /// Closure to be invoked on channel output.
    public var onChannelOutput: ((Int, Int) -> Void)?
    
    /// Closure to be invoked to get channel input.
    public var onChannelInput: ((Int) async -> Int)?
    
    /// Closure to be invoked for routine channel tasks.
    public var onChannelRoutine: (() async -> Void)?
    
    public init() { }
    
    public func channelOutput(channel: Int, value: Int) {
        onChannelOutput?(channel, value)
    }
    
    public func channelInput(channel: Int) async -> Int {
        if let handler = onChannelInput {
            return await handler(channel)
        }
        return 0 // Default value (if no input handler is provided)
    }
    
    public func channelRoutine() async {
        if let routine = onChannelRoutine {
            await routine()
        }
    }
} 