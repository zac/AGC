import Foundation

public struct AGCRegisterSnapshot: Equatable, Sendable {
    public let a: Int
    public let l: Int
    public let q: Int
    public let z: Int
    public let eb: Int
    public let fb: Int
    public let bb: Int
    public let rendezvousRadar: Int
    public let altitudeMeter: Int
    public let thrust: Int

    public init(state: AGCState) {
        self.a = state.erasableMemory[0][Register.regA.rawValue] & 0o177777
        self.l = state.erasableMemory[0][Register.regL.rawValue] & 0o177777
        self.q = state.erasableMemory[0][Register.regQ.rawValue] & 0o177777
        self.z = state.erasableMemory[0][Register.regZ.rawValue] & 0o177777
        self.eb = state.erasableMemory[0][Register.regEB.rawValue] & 0o177777
        self.fb = state.erasableMemory[0][Register.regFB.rawValue] & 0o177777
        self.bb = state.erasableMemory[0][Register.regBB.rawValue] & 0o177777
        self.rendezvousRadar = state.erasableMemory[0][Register.regRNRAD.rawValue] & 0o177777
        self.altitudeMeter = state.erasableMemory[0][Register.regALTM.rawValue] & 0o177777
        self.thrust = state.erasableMemory[0][Register.regTHRUST.rawValue] & 0o77777
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
    public let channelTrace: [AGCChannelTraceEntry]

    public init(
        cycle: UInt64,
        registers: AGCRegisterSnapshot,
        inputChannels: [Int: Int],
        outputChannels: [Int: Int],
        interruptRequests: [Int],
        backtrace: [AGCBacktraceEntry],
        dsky: DSKYSnapshot,
        channelTrace: [AGCChannelTraceEntry]
    ) {
        self.cycle = cycle
        self.registers = registers
        self.inputChannels = inputChannels
        self.outputChannels = outputChannels
        self.interruptRequests = interruptRequests
        self.backtrace = backtrace
        self.dsky = dsky
        self.channelTrace = channelTrace
    }
}

public struct AGCRadarInput: Equatable, Sendable {
    public let rendezvousRadar: Int?
    public let altitudeMeter: Int?
    /// RNRAD word for LRVELX after CH13 activity is cleared (select 4).
    public let landingRadarVelocityX: Int?
    /// RNRAD word for LRVELY (select 5).
    public let landingRadarVelocityY: Int?
    /// RNRAD word for LRVELZ (select 6).
    public let landingRadarVelocityZ: Int?
    /// RNRAD word for LRALT (select 7). Falls back to `altitudeMeter`.
    public let landingRadarAltitude: Int?
    /// CH33 bit 9: 1 = LR altitude high scale (`LRSCK` converts ×5 to low scale).
    public let landingRadarAltitudeHighScale: Bool

    public init(
        rendezvousRadar: Int? = nil,
        altitudeMeter: Int? = nil,
        landingRadarVelocityX: Int? = nil,
        landingRadarVelocityY: Int? = nil,
        landingRadarVelocityZ: Int? = nil,
        landingRadarAltitude: Int? = nil,
        landingRadarAltitudeHighScale: Bool = false
    ) {
        self.rendezvousRadar = rendezvousRadar
        self.altitudeMeter = altitudeMeter
        self.landingRadarVelocityX = landingRadarVelocityX
        self.landingRadarVelocityY = landingRadarVelocityY
        self.landingRadarVelocityZ = landingRadarVelocityZ
        self.landingRadarAltitude = landingRadarAltitude
        self.landingRadarAltitudeHighScale = landingRadarAltitudeHighScale
    }

    /// CH13 bits 1–3 after the radar-activity bit is cleared at gate end.
    public func rnradWord(channel13Low3: Int) -> Int? {
        switch channel13Low3 & 0o7 {
        case 0o4: return landingRadarVelocityX
        case 0o5: return landingRadarVelocityY
        case 0o6: return landingRadarVelocityZ
        case 0o7: return landingRadarAltitude ?? altitudeMeter
        default: return rendezvousRadar
        }
    }
}

public struct AGCRotationalHandControllerInput: Equatable, Sendable {
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
    private var input: AGCRadarInput?

    func set(_ input: AGCRadarInput?) {
        lock.lock()
        self.input = input
        lock.unlock()
    }

    func snapshot() -> AGCRadarInput? {
        lock.lock()
        defer { lock.unlock() }
        return input
    }
}

private final class AGCRadarIO: AGCIOProtocol {
    var onRequestRadarData: (() -> Void)?

    init(onRequestRadarData: (() -> Void)? = nil) {
        self.onRequestRadarData = onRequestRadarData
    }

    func channelOutput(channel: Int, value: Int) {}
    func channelInput() -> [AGCChannelInput]? { nil }
    func requestRadarData() {
        onRequestRadarData?()
    }
    func shiftToDeda(data: Int) {}
    func channelRoutine() {}
}

private final class AGCRuntimeInputQueue: AGCIOProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [AGCChannelInput] = []

    func enqueue(_ input: AGCChannelInput) {
        lock.lock()
        queue.append(input)
        lock.unlock()
    }

    func enqueue(_ inputs: [AGCChannelInput]) {
        lock.lock()
        queue.append(contentsOf: inputs)
        lock.unlock()
    }

    func channelOutput(channel: Int, value: Int) {}

    func channelInput() -> [AGCChannelInput]? {
        lock.lock()
        defer { lock.unlock() }
        guard !queue.isEmpty else { return nil }
        let inputs = queue
        queue.removeAll()
        return inputs
    }

    func requestRadarData() {}
    func shiftToDeda(data: Int) {}
    func channelRoutine() {}
}

private struct AGCRuntimeComponents {
    let state: AGCState
    let engine: AGCEngine
    let dsky: DSKY
    let externalInput: AGCRuntimeInputQueue
    let compositeIO: CompositeAGCIO
}

/// Deterministic, frame-driven AGC runtime suitable for RealityKit/visionOS integration.
///
/// The runtime owns the engine, state, DSKY, raw peripheral hooks, and channel routing.
/// Drive it from a simulation/frame loop with bounded ``step(cycles:)`` calls.
public actor AGCRuntime {
    private let coreImage: Data
    private let radarInputBox = AGCRadarInputBox()
    private var components: AGCRuntimeComponents
    private var breakpoints: Set<Int> = []
    private var watchAddresses: [Int] = []
    private var hitBreakpoint = false

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
        await runCycles(cycles)
        return makeSnapshot()
    }

    public func snapshot() -> AGCSnapshot {
        makeSnapshot()
    }

    public func goldenTraceSample() -> AGCGoldenTraceSample {
        AGCGoldenTraceSample(state: components.state)
    }

    /// Step through `maxCycle` MCTs, capturing samples on the yaAGC golden-trace schedule.
    /// Optional DSKY keys are injected so `ChannelInput` sees them when `cycleCounter` equals `event.cycle`.
    public func collectGoldenTrace(
        throughCycle maxCycle: UInt64 = AGCGoldenTraceSchedule.defaultHorizon,
        keys: [AGCGoldenTraceKeyEvent] = []
    ) async -> [AGCGoldenTraceSample] {
        var samples: [AGCGoldenTraceSample] = []
        var keyIndex = 0
        var lastSampled: UInt64?
        func captureIfNeeded(_ cycle: UInt64, force: Bool = false) {
            guard lastSampled != cycle else { return }
            if force || AGCGoldenTraceSchedule.shouldSample(cycle) {
                samples.append(goldenTraceSample())
                lastSampled = cycle
            }
        }

        captureIfNeeded(0, force: AGCGoldenTraceSchedule.shouldSample(0))

        var current = components.state.cycleCounter
        while current < maxCycle {
            let nextKey = keyIndex < keys.count ? keys[keyIndex].cycle : nil
            let nextSample = AGCGoldenTraceSchedule.nextSample(after: current, through: maxCycle)

            var runUntil = maxCycle
            if let nextSample {
                runUntil = min(runUntil, nextSample)
            }
            if let nextKey, nextKey > 0 {
                runUntil = min(runUntil, nextKey - 1)
            }

            if runUntil > current {
                await runCycles(runUntil - current)
                current = components.state.cycleCounter
                captureIfNeeded(current, force: keys.contains(where: { $0.cycle == current }))
                continue
            }

            if let nextKey, current + 1 == nextKey, keyIndex < keys.count {
                await components.dsky.send(keys[keyIndex].key)
                keyIndex += 1
                await runCycles(1)
                current = components.state.cycleCounter
                captureIfNeeded(current, force: true)
                continue
            }

            await runCycles(1)
            current = components.state.cycleCounter
            captureIfNeeded(current)
        }
        return samples
    }

    public func debuggerSnapshot() -> AGCDebuggerSnapshot {
        makeDebuggerSnapshot()
    }

    public func setBreakpoint(_ address: Int) {
        breakpoints.insert(address & 0o7777)
    }

    public func clearBreakpoints() {
        breakpoints.removeAll()
        hitBreakpoint = false
    }

    public func watchErasable(_ address: Int) {
        let word = address & 0o1777
        if !watchAddresses.contains(word) {
            watchAddresses.append(word)
        }
    }

    /// Run MCTs until one instruction executes, or a breakpoint on Z is hit.
    public func stepInstruction() -> AGCSnapshot {
        hitBreakpoint = false
        var safety = 0
        while safety < 128 {
            let executed = components.engine.executeCycle()
            safety += 1
            let z = components.state.erasableMemory[0][Register.regZ.rawValue] & 0o7777
            if breakpoints.contains(z) {
                hitBreakpoint = true
                break
            }
            if executed { break }
        }
        return makeSnapshot()
    }

    public func sendDSKYKey(_ key: DSKYKeyCode) async {
        await components.dsky.send(key)
    }

    /// PROCEED is inverted CH32 bit 14. Hold `pressed` across at least one T4RUPT (~120 ms).
    public func sendPRO(pressed: Bool) async {
        await components.dsky.sendProKey(pressed)
    }

    @discardableResult
    public func sendDSKYScript(_ script: DSKYScript, cyclesPerKey: UInt64 = 50_000) async -> AGCSnapshot {
        for key in script.keys {
            await components.dsky.send(key)
            await runCycles(cyclesPerKey)
            if Task.isCancelled { break }
        }
        return makeSnapshot()
    }

    public func enqueueInput(_ input: AGCChannelInput) async {
        components.externalInput.enqueue(input)
    }

    public func enqueueInputs(_ inputs: [AGCChannelInput]) async {
        components.externalInput.enqueue(inputs)
    }

    public func setRadarInput(_ input: AGCRadarInput?) {
        radarInputBox.set(input)
    }

    /// Write a 15-bit word at an 11-bit ECADR (direct bank, not the current EB).
    public func writeErasable(ecadr: Int, value: Int) {
        components.engine.writeErasableECADR(ecadr, value)
    }

    public func writeErasable(_ words: [AGCErasableWord]) {
        for word in words {
            components.engine.writeErasableECADR(word.ecadr, word.value)
        }
    }

    public func writeDoublePrecision(ecadr: Int, _ value: AGCDoublePrecision) {
        components.engine.writeErasableECADR(ecadr, value.high)
        components.engine.writeErasableECADR(ecadr + 1, value.low)
    }

    public func readErasable(ecadr: Int) -> Int {
        components.engine.readErasableECADR(ecadr)
    }

    public func readDoublePrecision(ecadr: Int) -> AGCDoublePrecision {
        AGCDoublePrecision(
            high: components.engine.readErasableECADR(ecadr),
            low: components.engine.readErasableECADR(ecadr + 1)
        )
    }

    /// Set bit `bit` (AGC numbering, 1 = LSB … 15 = sign) at `ecadr` without clearing other bits.
    public func setErasableBit(ecadr: Int, bit: Int) {
        let clampedBit = min(max(bit, 1), 15)
        let mask = 1 << (clampedBit - 1)
        let current = components.engine.readErasableECADR(ecadr)
        components.engine.writeErasableECADR(ecadr, current | mask)
    }

    /// Clear bit `bit` (AGC numbering, 1 = LSB … 15 = sign) at `ecadr`.
    public func clearErasableBit(ecadr: Int, bit: Int) {
        let clampedBit = min(max(bit, 1), 15)
        let mask = 1 << (clampedBit - 1)
        let current = components.engine.readErasableECADR(ecadr)
        components.engine.writeErasableECADR(ecadr, current & ~mask)
    }


    public func setRotationalHandControllerInput(_ input: AGCRotationalHandControllerInput) async {
        components.externalInput.enqueue([
            AGCChannelInput(channel: 0o166, value: input.pitch),
            AGCChannelInput(channel: 0o167, value: input.yaw),
            AGCChannelInput(channel: 0o170, value: input.roll)
        ])
    }

    func integrationTestCompleteRadarSampleGate() -> AGCSnapshot {
        components.engine.integrationTestCompleteRadarSampleGate()
        return makeSnapshot()
    }

    private func runCycles(_ cycles: UInt64) async {
        let yieldEvery: UInt64 = 4_096
        var remaining = cycles
        while remaining > 0 {
            if Task.isCancelled { break }
            let batch = min(remaining, yieldEvery)
            for _ in 0..<batch {
                _ = components.engine.executeCycle()
            }
            remaining -= batch
            if remaining > 0 {
                await Task.yield()
            }
        }
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
        let radarIO = AGCRadarIO()
        let externalInput = AGCRuntimeInputQueue()

        radarIO.onRequestRadarData = { [weak state] in
            guard let state, let input = radarInputBox.snapshot() else { return }
            let select = state.inputChannels[0o13] & 0o7
            if let rnrad = input.rnradWord(channel13Low3: select) {
                state.erasableMemory[0][Register.regRNRAD.rawValue] = rnrad & 0o77777
            }
            if let altitudeMeter = input.altitudeMeter {
                state.erasableMemory[0][Register.regALTM.rawValue] = altitudeMeter & 0o77777
            }
        }

        let compositeIO = CompositeAGCIO(children: [dsky, radarIO, externalInput])
        engine.ioDelegate = compositeIO

        return AGCRuntimeComponents(
            state: state,
            engine: engine,
            dsky: dsky,
            externalInput: externalInput,
            compositeIO: compositeIO
        )
    }

    private func makeSnapshot() -> AGCSnapshot {
        let state = components.state
        let monitoredChannels = [0o5, 0o6, 0o10, 0o11, 0o12, 0o13, 0o14, 0o15, 0o16, 0o30, 0o31, 0o32, 0o33, 0o77, 0o163]
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
            channelTrace: components.compositeIO.channelTrace()
        )
    }

    private func makeDebuggerSnapshot() -> AGCDebuggerSnapshot {
        let state = components.state
        let engine = components.engine
        let extraCode = state.extraCode
        let z = state.erasableMemory[0][Register.regZ.rawValue] & 0o7777
        let word = engine.fetchInstructionWord(at: z)
        let current = AGCDisassembler.disassemble(word: word, at: z, extraCode: extraCode)
        var listing: [AGCDisassembledInstruction] = []
        listing.reserveCapacity(13)
        for offset in -4...8 {
            let address = (z + offset) & 0o7777
            let listed = engine.fetchInstructionWord(at: address)
            listing.append(
                AGCDisassembler.disassemble(word: listed, at: address, extraCode: offset == 0 && extraCode)
            )
        }
        var watches: [AGCErasableWatch] = []
        watches.reserveCapacity(watchAddresses.count)
        for address in watchAddresses {
            watches.append(AGCErasableWatch(address: address, value: engine.findMemoryWord(address)))
        }
        let packets = components.compositeIO.channelTrace().suffix(16).compactMap { entry -> String? in
            guard let data = AGCPacket.encode(channel: entry.channel, value: entry.value) else { return nil }
            let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            return "\(entry.direction.rawValue) \(hex)"
        }
        return AGCDebuggerSnapshot(
            current: current,
            extraCode: extraCode,
            inIsr: state.inIsr,
            breakpoints: breakpoints.sorted(),
            watches: watches,
            hitBreakpoint: hitBreakpoint,
            listing: listing,
            yaAGCPackets: Array(packets)
        )
    }
}
