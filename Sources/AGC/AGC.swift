import Foundation

/// A facade for the AGC.
public final class AGC {
    public private(set) var state: AGCState
    public private(set) var io: AGCIO
    public private(set) var engine: AGCEngine
    
    public init(binFile: URL) throws {
        // Load core image data
        let data = try Data(contentsOf: binFile)
        
        // Validate core image size
        guard data.count % 2 == 0 else {
            throw AGCError.invalidBinFile // Must be even number of bytes
        }
        
        guard data.count/2 <= 36 * 0o2000 else {
            throw AGCError.invalidBinFile // Must fit in core memory
        }
        
        // Initialize state and components
        self.state = AGCState()
        state.binFile = data
        
        self.io = AGCIO()
        self.engine = try AGCEngine(state: state)
        
        self.engine.ioDelegate = self.io
    }

    public func run(for cycles: UInt64) async {
        await engine.runEngine(for: cycles)
    }

    public func reset() throws {
        let binFile = state.binFile
        self.state = AGCState()
        state.binFile = binFile

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
