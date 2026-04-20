import Foundation

/// High-level facade around ``AGCEngine`` and default ``AGCIO``.
///
/// **Timing:** ``run(for:)`` / ``start()`` advance the CPU as fast as possible (bounded by
/// ``Task`` cancellation when using ``UInt64.max`` cycles). For wall-clock–paced simulation
/// (~11.7µs per machine cycle), use ``AGCEngine/startEngine()`` instead, or drive a fixed
/// number of cycles each frame from your RealityKit update loop.
public final class AGC {
    public private(set) var state: AGCState
    public private(set) var io: AGCIO
    public private(set) var engine: AGCEngine
    private var runTask: Task<Void, Never>?
    
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

    /// Begin simulation (runs until ``stop()`` cancels the underlying task).
    public func start() {
        guard runTask == nil else { return }
        let engine = self.engine
        runTask = Task.detached {
            await engine.runEngine(for: UInt64.max)
        }
    }

    /// Stop simulation (cancels the detached run loop started by ``start()``).
    public func stop() {
        runTask?.cancel()
        runTask = nil
    }

    public func writeChannel(address: Int, value: Int) {
        engine.writeIOChannel(address: address, value: value)
    }
}
