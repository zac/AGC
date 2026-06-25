import Foundation

public struct AGCRegisterSnapshot: Equatable, Sendable {
    public let a: Int
    public let l: Int
    public let q: Int
    public let z: Int
    public let eb: Int
    public let fb: Int
    public let bb: Int

    public init(state: AGCState) {
        self.a = state.erasableMemory[0][Register.regA.rawValue] & 0o177777
        self.l = state.erasableMemory[0][Register.regL.rawValue] & 0o177777
        self.q = state.erasableMemory[0][Register.regQ.rawValue] & 0o177777
        self.z = state.erasableMemory[0][Register.regZ.rawValue] & 0o177777
        self.eb = state.erasableMemory[0][Register.regEB.rawValue] & 0o177777
        self.fb = state.erasableMemory[0][Register.regFB.rawValue] & 0o177777
        self.bb = state.erasableMemory[0][Register.regBB.rawValue] & 0o177777
    }
}

public struct AGCSnapshot: Equatable, Sendable {
    public let cycle: UInt64
    public let registers: AGCRegisterSnapshot
    public let inputChannels: [Int: Int]
    public let outputChannels: [Int: Int]
    public let interruptRequests: [Int]
    public let backtrace: [AGCBacktraceEntry]
    public let dsky: DSKYSnapshot
    public let vehicle: LMVehicleSnapshot
    public let channelTrace: [AGCChannelTraceEntry]

    public init(
        cycle: UInt64,
        registers: AGCRegisterSnapshot,
        inputChannels: [Int: Int],
        outputChannels: [Int: Int],
        interruptRequests: [Int],
        backtrace: [AGCBacktraceEntry],
        dsky: DSKYSnapshot,
        vehicle: LMVehicleSnapshot,
        channelTrace: [AGCChannelTraceEntry]
    ) {
        self.cycle = cycle
        self.registers = registers
        self.inputChannels = inputChannels
        self.outputChannels = outputChannels
        self.interruptRequests = interruptRequests
        self.backtrace = backtrace
        self.dsky = dsky
        self.vehicle = vehicle
        self.channelTrace = channelTrace
    }
}

public struct LMRadarInput: Equatable, Sendable {
    public let rendezvousRadar: Int?
    public let altitudeMeter: Int?

    public init(rendezvousRadar: Int? = nil, altitudeMeter: Int? = nil) {
        self.rendezvousRadar = rendezvousRadar
        self.altitudeMeter = altitudeMeter
    }
}

public struct LMRotationalHandControllerInput: Equatable, Sendable {
    public let pitch: Int
    public let yaw: Int
    public let roll: Int

    public init(pitch: Int = 0, yaw: Int = 0, roll: Int = 0) {
        self.pitch = pitch
        self.yaw = yaw
        self.roll = roll
    }
}

private final class AGCRadarInputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var input: LMRadarInput?

    func set(_ input: LMRadarInput?) {
        lock.lock()
        self.input = input
        lock.unlock()
    }

    func snapshot() -> LMRadarInput? {
        lock.lock()
        defer { lock.unlock() }
        return input
    }
}

private final class AGCRuntimeInputQueue: AGCIOProtocol, @unchecked Sendable {
    private actor QueueStorage {
        private var queue: [AGCChannelInput] = []

        func enqueue(_ input: AGCChannelInput) {
            queue.append(input)
        }

        func enqueue(_ inputs: [AGCChannelInput]) {
            queue.append(contentsOf: inputs)
        }

        func drain() -> [AGCChannelInput]? {
            guard !queue.isEmpty else { return nil }
            let inputs = queue
            queue.removeAll()
            return inputs
        }
    }

    private let storage = QueueStorage()

    func enqueue(_ input: AGCChannelInput) async {
        await storage.enqueue(input)
    }

    func enqueue(_ inputs: [AGCChannelInput]) async {
        await storage.enqueue(inputs)
    }

    func channelOutput(channel: Int, value: Int) {}

    func channelInput() async -> [AGCChannelInput]? {
        await storage.drain()
    }

    func requestRadarData() {}
    func shiftToDeda(data: Int) {}
    func channelRoutine() async {}
}

private struct AGCRuntimeComponents {
    let state: AGCState
    let engine: AGCEngine
    let dsky: DSKY
    let vehicleIO: LMVehicleIO
    let externalInput: AGCRuntimeInputQueue
    let compositeIO: CompositeAGCIO
}

/// Deterministic, frame-driven AGC runtime suitable for RealityKit/visionOS integration.
///
/// The runtime owns the engine, state, DSKY, LM vehicle I/O, and peripheral routing. Drive it
/// from a simulation/frame loop with bounded ``step(cycles:)`` calls.
public actor AGCRuntime {
    private let coreImage: Data
    private let radarInputBox = AGCRadarInputBox()
    private var components: AGCRuntimeComponents

    public init(binFile: URL) throws {
        let data = try Data(contentsOf: binFile)
        try AGCRuntime.validateCoreImage(data)
        self.coreImage = data
        self.components = try AGCRuntime.makeComponents(coreImage: data, radarInputBox: radarInputBox)
    }

    public init(coreImage: Data) throws {
        try AGCRuntime.validateCoreImage(coreImage)
        self.coreImage = coreImage
        self.components = try AGCRuntime.makeComponents(coreImage: coreImage, radarInputBox: radarInputBox)
    }

    public func reset() throws -> AGCSnapshot {
        components = try AGCRuntime.makeComponents(coreImage: coreImage, radarInputBox: radarInputBox)
        return makeSnapshot()
    }

    public func step(cycles: UInt64) async -> AGCSnapshot {
        await components.engine.runEngine(for: cycles)
        return makeSnapshot()
    }

    public func snapshot() -> AGCSnapshot {
        makeSnapshot()
    }

    public func sendDSKYKey(_ key: DSKYKeyCode) async {
        await components.dsky.send(key)
    }

    @discardableResult
    public func sendDSKYScript(_ script: DSKYScript, cyclesPerKey: UInt64 = 50_000) async -> AGCSnapshot {
        for key in script.keys {
            await components.dsky.send(key)
            await components.engine.runEngine(for: cyclesPerKey)
            if Task.isCancelled { break }
        }
        return makeSnapshot()
    }

    public func enqueueInput(_ input: AGCChannelInput) async {
        await components.externalInput.enqueue(input)
    }

    public func enqueueInputs(_ inputs: [AGCChannelInput]) async {
        await components.externalInput.enqueue(inputs)
    }

    public func setRadarInput(_ input: LMRadarInput?) {
        radarInputBox.set(input)
    }

    public func setRotationalHandControllerInput(_ input: LMRotationalHandControllerInput) async {
        await components.externalInput.enqueue([
            AGCChannelInput(channel: 0o166, value: input.pitch),
            AGCChannelInput(channel: 0o167, value: input.yaw),
            AGCChannelInput(channel: 0o170, value: input.roll)
        ])
    }

    public func channelTrace() -> [AGCChannelTraceEntry] {
        components.compositeIO.channelTrace()
    }

    private static func validateCoreImage(_ data: Data) throws {
        guard data.count % 2 == 0 else {
            throw AGCError.invalidBinFile
        }
        guard data.count / 2 <= 36 * 0o2000 else {
            throw AGCError.invalidBinFile
        }
    }

    private static func makeComponents(coreImage: Data, radarInputBox: AGCRadarInputBox) throws -> AGCRuntimeComponents {
        let state = AGCState()
        state.binFile = coreImage
        let engine = try AGCEngine(state: state)
        let dsky = DSKY()
        let vehicleIO = LMVehicleIO()
        let externalInput = AGCRuntimeInputQueue()

        vehicleIO.onRequestRadarData = { [weak state] in
            guard let state, let input = radarInputBox.snapshot() else { return }
            if let rendezvousRadar = input.rendezvousRadar {
                state.erasableMemory[0][Register.regRNRAD.rawValue] = rendezvousRadar & 0o77777
            }
            if let altitudeMeter = input.altitudeMeter {
                state.erasableMemory[0][Register.regALTM.rawValue] = altitudeMeter & 0o77777
            }
        }

        let compositeIO = CompositeAGCIO(children: [dsky, vehicleIO, externalInput])
        engine.ioDelegate = compositeIO

        return AGCRuntimeComponents(
            state: state,
            engine: engine,
            dsky: dsky,
            vehicleIO: vehicleIO,
            externalInput: externalInput,
            compositeIO: compositeIO
        )
    }

    private func makeSnapshot() -> AGCSnapshot {
        let state = components.state
        let monitoredChannels = [0o5, 0o6, 0o10, 0o11, 0o13, 0o15, 0o30, 0o31, 0o32, 0o33, 0o77, 0o163]
        var inputChannels: [Int: Int] = [:]
        var outputChannels: [Int: Int] = [:]
        for channel in monitoredChannels {
            inputChannels[channel] = state.inputChannels[channel] & 0o77777
            outputChannels[channel] = state.outputChannels[channel] & 0o77777
        }

        return AGCSnapshot(
            cycle: state.cycleCounter,
            registers: AGCRegisterSnapshot(state: state),
            inputChannels: inputChannels,
            outputChannels: outputChannels,
            interruptRequests: state.interruptRequests,
            backtrace: state.backtrace,
            dsky: components.dsky.snapshot,
            vehicle: components.vehicleIO.snapshot,
            channelTrace: components.compositeIO.channelTrace()
        )
    }
}
