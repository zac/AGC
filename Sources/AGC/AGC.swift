import Foundation

/// A facade for the AGC.
public final class AGC {
    public let state: AGCState
    public let io: AGCIO
    public let engine: AGCEngine
    
    public init(coreFile: URL) throws {

        let data = try Data(contentsOf: coreFile)

        self.state = AGCState()
        state.coreImage = data

        self.io = AGCIO()
        self.engine = try AGCEngine(state: state)

        self.engine.ioDelegate = self.io
    }

    /// Begin simulation.
    public func start() {
        engine.startEngine()
    }

    /// Stop simulation.
    public func stop() {
        engine.stopEngine()
    }
} 
