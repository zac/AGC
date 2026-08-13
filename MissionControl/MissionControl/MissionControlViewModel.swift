import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AGC
import LMCore

@MainActor
@Observable
final class MissionControlViewModel {
    static let idleSingleKeyValidationCycles: UInt64 = 12_000
    static let idleSequenceValidationCycles: UInt64 = 120_000
    static let scriptedKeySettleCycles: UInt64 = 50_000

    enum Status: Equatable {
        case empty
        case idle
        case running
        case stopped
        case error(String)
        
        var label: String {
            switch self {
            case .empty:
                return "Load a Luminary/Colossus binary to begin."
            case .idle:
                return "Ready"
            case .running:
                return "Running"
            case .stopped:
                return "Stopped"
            case .error(let message):
                return "Error: \(message)"
            }
        }
    }
    
    private(set) var selectedURL: URL?
    var status: Status = .empty
    private(set) var isRunning = false
    private(set) var programSummary = "No program loaded"
    private(set) var latestSnapshot: RegisterSnapshot?
    private(set) var latestDSKY: DSKYSnapshot?
    private(set) var latestLMSimulation: LMSimulationSnapshot?
    private(set) var poweredDescentScenario = LMPoweredDescentScenario.apollo11SourceBacked
    private(set) var engineHealth: EngineHealthSnapshot?
    private(set) var radarHookInvocations: UInt64 = 0
    private(set) var recentEvents: [MissionControlEvent] = []
    private(set) var backtraceTail: [BacktraceSnapshot] = []
    private(set) var latestChannelTrace: [AGCChannelTraceEntry] = []
    private(set) var latestSimulationTrace: [LMSimulationTraceSample] = []
    private(set) var latestValidationResult: LMPoweredDescentValidationResult?
    private(set) var latestDebugger: AGCDebuggerSnapshot?
    var breakpointOctal = "04000"
    var watchOctal = "00067"

    @ObservationIgnored private var runtime: LMSimulationRuntime?
    @ObservationIgnored private var simulationTask: Task<Void, Never>?
    @ObservationIgnored private var dskySequenceTask: Task<Void, Never>?
    @ObservationIgnored private var lastHealthWall: CFAbsoluteTime = 0
    @ObservationIgnored private var lastHealthCycle: UInt64 = 0
    @ObservationIgnored private var smoothedCyclesPerSec: Double = 0
    @ObservationIgnored private var previousCycleForAdvance: UInt64 = 0
    
    var registerSnapshot: RegisterSnapshot? {
        latestSnapshot
    }
    
    var canStart: Bool { runtime != nil && !isRunning }
    var canStop: Bool { isRunning }
    var canReset: Bool { runtime != nil }
    var canStep: Bool { runtime != nil && !isRunning }
    var hasSampleProgram: Bool {
        Bundle.main.url(forResource: "Luminary099", withExtension: "bin") != nil
    }
    
    func loadProgram(from url: URL) {
        simulationTask?.cancel()
        simulationTask = nil
        isRunning = false
        dskySequenceTask?.cancel()
        dskySequenceTask = nil
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer {
            if needsAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            let scenario = LMPoweredDescentScenario.apollo11SourceBacked
            let loaded = try LMSimulationRuntime(binFile: url, scenario: scenario)
            runtime = loaded
            poweredDescentScenario = scenario

            selectedURL = url
            let data = try Data(contentsOf: url)
            let wordCount = data.count / 2
            programSummary = "\(url.lastPathComponent) – \(wordCount) words (\(data.count) bytes)"
            status = .idle
            isRunning = false
            radarHookInvocations = 0
            engineHealth = nil
            lastHealthWall = 0
            lastHealthCycle = 0
            previousCycleForAdvance = 0
            smoothedCyclesPerSec = 0
            resetValidationTrace()
            recordEvent("Loaded \(url.lastPathComponent)")
            Task { @MainActor [weak self] in
                guard let self else { return }
                let snapshot = await loaded.snapshot()
                self.applySnapshot(snapshot)
            }
        } catch {
            runtime = nil
            status = .error(error.localizedDescription)
            clearSnapshots()
            recordEvent("Load failed: \(error.localizedDescription)")
        }
    }

    func loadSampleProgram() {
        guard let url = Bundle.main.url(forResource: "Luminary099", withExtension: "bin") else {
            status = .error("Bundled Luminary099.bin is missing.")
            recordEvent("Sample binary missing")
            return
        }
        loadProgram(from: url)
    }
    
    func clearProgram() {
        stop()
        dskySequenceTask?.cancel()
        dskySequenceTask = nil
        runtime = nil
        selectedURL = nil
        status = .empty
        programSummary = "No program loaded"
        clearSnapshots()
        recordEvent("Cleared program")
    }
    
    func start() {
        guard canStart, let runtime else { return }
        dskySequenceTask?.cancel()
        dskySequenceTask = nil
        simulationTask?.cancel()
        isRunning = true
        status = .running
        lastHealthWall = CFAbsoluteTimeGetCurrent()
        lastHealthCycle = latestSnapshot?.cycle ?? 0
        previousCycleForAdvance = latestSnapshot?.cycle ?? 0
        smoothedCyclesPerSec = 0
        let cyclesPerBatch: UInt64 = 30_000
        recordEvent("Started continuous run")
        simulationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let snapshot = await runtime.step(cycles: cyclesPerBatch, input: .none)
                self.applySnapshot(snapshot)
                await Task.yield()
            }
            self.isRunning = false
            self.simulationTask = nil
            if case .running = self.status {
                self.status = .stopped
            }
            let snapshot = await runtime.snapshot()
            self.applySnapshot(snapshot)
            self.recordEvent("Continuous run stopped at cycle \(snapshot.agc.cycle)")
        }
    }

    func runCycles(_ cycles: UInt64) {
        guard canStep, let runtime else { return }
        dskySequenceTask?.cancel()
        dskySequenceTask = nil
        simulationTask?.cancel()
        isRunning = true
        status = .running
        lastHealthWall = CFAbsoluteTimeGetCurrent()
        lastHealthCycle = latestSnapshot?.cycle ?? 0
        previousCycleForAdvance = latestSnapshot?.cycle ?? 0
        recordEvent("Running \(cycles.formatted()) cycles")
        simulationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = await runtime.step(cycles: cycles, input: .none)
            self.isRunning = false
            self.simulationTask = nil
            self.status = .stopped
            self.applySnapshot(snapshot)
            self.recordEvent("Finished \(cycles.formatted()) cycles at cycle \(snapshot.agc.cycle)")
        }
    }

    func stepPoweredDescentFrame() {
        guard canStep, let runtime else { return }
        dskySequenceTask?.cancel()
        dskySequenceTask = nil
        simulationTask?.cancel()
        isRunning = true
        status = .running
        recordEvent("Stepping LM frame")
        simulationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = await runtime.step(deltaTime: 1.0 / 60.0, input: .none)
            self.isRunning = false
            self.simulationTask = nil
            self.status = .stopped
            self.applySnapshot(snapshot)
            self.recordEvent("LM frame stepped to cycle \(snapshot.agc.cycle)")
        }
    }

    func runPoweredDescentSegment(seconds: Double = 10) {
        guard canStep, let runtime else { return }
        dskySequenceTask?.cancel()
        dskySequenceTask = nil
        simulationTask?.cancel()
        isRunning = true
        status = .running
        lastHealthWall = CFAbsoluteTimeGetCurrent()
        lastHealthCycle = latestSnapshot?.cycle ?? 0
        previousCycleForAdvance = latestSnapshot?.cycle ?? 0
        let frameDelta = 1.0 / 30.0
        let frames = max(1, Int((seconds / frameDelta).rounded()))
        recordEvent("Running LM segment \(String(format: "%.1f", seconds)) s")
        simulationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var snapshot = await runtime.snapshot()
            for _ in 0..<frames {
                if Task.isCancelled { break }
                snapshot = await runtime.step(deltaTime: frameDelta, input: .none)
                self.applySnapshot(snapshot)
                await Task.yield()
            }
            self.isRunning = false
            self.simulationTask = nil
            self.status = .stopped
            self.applySnapshot(snapshot)
            self.recordEvent("Finished LM segment at cycle \(snapshot.agc.cycle)")
        }
    }

    func resetPoweredDescentScenario() {
        guard let runtime else { return }
        dskySequenceTask?.cancel()
        dskySequenceTask = nil
        simulationTask?.cancel()
        simulationTask = nil
        isRunning = true
        status = .running
        recordEvent("Resetting powered descent scenario")
        simulationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await runtime.reset()
                self.resetValidationTrace()
                self.isRunning = false
                self.simulationTask = nil
                self.status = .stopped
                self.applySnapshot(snapshot)
                self.recordEvent("Powered descent reset")
            } catch {
                self.isRunning = false
                self.simulationTask = nil
                self.status = .error(error.localizedDescription)
                self.recordEvent("Powered descent reset failed: \(error.localizedDescription)")
            }
        }
    }

    func sendPoweredDescentProgram(_ checkpoint: LMPoweredDescentCheckpoint) {
        sendDSKYScript(
            checkpoint.expectedScript,
            autoRunCyclesWhenIdle: Self.idleSequenceValidationCycles
        )
    }

    func exportChannelTrace() {
        let rows = latestChannelTrace.map { entry in
            "\(entry.direction.rawValue.uppercased()) \(String(format: "%03o", entry.channel)) \(String(format: "%05o", entry.value))"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rows.joined(separator: "\n"), forType: .string)
        recordEvent("Copied \(latestChannelTrace.count) channel trace rows")
    }

    func exportSimulationTraceJSON() {
        let export = MissionControlTraceExport(
            program: selectedURL?.lastPathComponent ?? "No core image",
            samples: latestSimulationTrace,
            validation: latestValidationResult
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(export)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string)
            recordEvent("Copied \(latestSimulationTrace.count) structured trace samples")
        } catch {
            recordEvent("Trace JSON export failed: \(error.localizedDescription)")
        }
    }
    
    func stop() {
        guard canStop || dskySequenceTask != nil else { return }
        dskySequenceTask?.cancel()
        dskySequenceTask = nil
        simulationTask?.cancel()
        simulationTask = nil
        isRunning = false
        status = .stopped
        if let runtime {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let snapshot = await runtime.snapshot()
                self.applySnapshot(snapshot)
                self.recordEvent("Stopped at cycle \(snapshot.agc.cycle)")
            }
        }
    }
    
    func reset() {
        guard let url = selectedURL else { return }
        stop()
        loadProgram(from: url)
    }
    
    private func refreshEngineHealth(snapshot: LMSimulationSnapshot) {
        let agc = snapshot.agc
        let batchDelta = agc.cycle &- previousCycleForAdvance
        previousCycleForAdvance = agc.cycle
        let now = CFAbsoluteTimeGetCurrent()
        if lastHealthWall == 0 {
            lastHealthWall = now
            lastHealthCycle = agc.cycle
            engineHealth = EngineHealthSnapshot(
                cycle: agc.cycle,
                cyclesPerSecond: 0,
                isAdvancing: false,
                lmOutputs: snapshot.vehicleCommands
            )
            return
        }
        let dt = now - lastHealthWall
        let delta = agc.cycle &- lastHealthCycle
        if dt > 0.05, delta > 0 {
            let instant = Double(delta) / dt
            smoothedCyclesPerSec = smoothedCyclesPerSec == 0
                ? instant
                : smoothedCyclesPerSec * 0.88 + instant * 0.12
            lastHealthWall = now
            lastHealthCycle = agc.cycle
        }
        engineHealth = EngineHealthSnapshot(
            cycle: agc.cycle,
            cyclesPerSecond: smoothedCyclesPerSec,
            isAdvancing: isRunning && batchDelta > 0,
            lmOutputs: snapshot.vehicleCommands
        )
    }

    func pressKey(_ key: DSKYKeyCode) {
        sendDSKYSequence(
            label: "Key \(key.label)",
            keys: [key],
            autoRunCyclesWhenIdle: Self.idleSingleKeyValidationCycles
        )
    }

    func sendDSKYScript(_ script: DSKYScript, autoRunCyclesWhenIdle: UInt64? = nil) {
        sendDSKYSequence(label: script.id, keys: script.keys, autoRunCyclesWhenIdle: autoRunCyclesWhenIdle)
    }

    func sendDSKYSequence(label: String, keys: [DSKYKeyCode], autoRunCyclesWhenIdle: UInt64? = nil) {
        guard let runtime else { return }
        recordEvent("Queued \(label)")
        let settleCycles = if keys.count > 1 {
            max(
                Self.scriptedKeySettleCycles,
                (autoRunCyclesWhenIdle ?? 0) / UInt64(max(keys.count, 1))
            )
        } else {
            autoRunCyclesWhenIdle ?? 0
        }

        dskySequenceTask?.cancel()
        dskySequenceTask = nil
        if isRunning {
            dskySequenceTask = Task { @MainActor [weak self] in
                guard let self else { return }
                for key in keys {
                    if Task.isCancelled { break }
                    let startCycle: UInt64
                    if let cycle = self.latestSnapshot?.cycle {
                        startCycle = cycle
                    } else {
                        let currentSnapshot = await runtime.snapshot()
                        startCycle = currentSnapshot.agc.cycle
                    }
                    await runtime.sendDSKYKey(key)
                    if settleCycles > 0 {
                        await self.waitForCycleAdvance(settleCycles, runtime: runtime, startCycle: startCycle)
                    }
                }
                self.dskySequenceTask = nil
                let snapshot = await runtime.snapshot()
                self.applySnapshot(snapshot)
                self.recordEvent("Sent \(label) into live run")
            }
            return
        }

        simulationTask?.cancel()
        simulationTask = nil
        isRunning = true
        status = .running
        lastHealthWall = CFAbsoluteTimeGetCurrent()
        lastHealthCycle = latestSnapshot?.cycle ?? 0
        previousCycleForAdvance = latestSnapshot?.cycle ?? 0
        simulationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for key in keys {
                if Task.isCancelled { break }
                await runtime.sendDSKYKey(key)
                if settleCycles > 0 {
                    let snapshot = await runtime.step(cycles: settleCycles, input: .none)
                    self.applySnapshot(snapshot)
                }
            }
            let snapshot = await runtime.snapshot()
            self.isRunning = false
            self.simulationTask = nil
            self.status = .stopped
            self.applySnapshot(snapshot)
            self.recordEvent("Sent \(label)")
        }
    }

    private func waitForCycleAdvance(_ cycles: UInt64, runtime: LMSimulationRuntime, startCycle: UInt64) async {
        guard cycles > 0 else { return }
        let targetCycle = startCycle &+ cycles
        while !Task.isCancelled {
            let snapshot = await runtime.snapshot()
            if snapshot.agc.cycle >= targetCycle {
                applySnapshot(snapshot)
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func applySnapshot(_ snapshot: LMSimulationSnapshot) {
        latestLMSimulation = snapshot
        appendTraceSample(snapshot.traceSample)
        latestSnapshot = RegisterSnapshot(snapshot: snapshot.agc)
        latestDSKY = snapshot.agc.dsky
        latestChannelTrace = Array(snapshot.channelTrace.suffix(80))
        backtraceTail = snapshot.agc.backtrace.suffix(8).map(BacktraceSnapshot.init)
        latestValidationResult = LMPoweredDescentValidationResult(
            scenario: poweredDescentScenario,
            samples: latestSimulationTrace,
            finalSnapshot: snapshot
        )
        refreshEngineHealth(snapshot: snapshot)
        Task { @MainActor [weak self] in
            guard let self, let runtime = self.runtime else { return }
            self.latestDebugger = await runtime.debuggerSnapshot()
        }
    }

    private func clearSnapshots() {
        latestSnapshot = nil
        latestDSKY = nil
        latestLMSimulation = nil
        engineHealth = nil
        backtraceTail = []
        latestChannelTrace = []
        latestDebugger = nil
        resetValidationTrace()
    }

    private func appendTraceSample(_ sample: LMSimulationTraceSample) {
        guard latestSimulationTrace.last != sample else { return }
        latestSimulationTrace.append(sample)
        if latestSimulationTrace.count > 2_048 {
            latestSimulationTrace.removeFirst(latestSimulationTrace.count - 2_048)
        }
    }

    private func resetValidationTrace() {
        latestSimulationTrace = []
        latestValidationResult = nil
        latestDebugger = nil
    }

    private func recordEvent(_ message: String) {
        recentEvents.insert(MissionControlEvent(message: message), at: 0)
        if recentEvents.count > 12 {
            recentEvents.removeLast(recentEvents.count - 12)
        }
    }

    func stepInstruction() {
        guard canStep, let runtime else { return }
        dskySequenceTask?.cancel()
        simulationTask?.cancel()
        isRunning = true
        status = .running
        simulationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = await runtime.stepInstruction()
            self.isRunning = false
            self.simulationTask = nil
            self.status = .stopped
            self.applySnapshot(snapshot)
            self.recordEvent("Stepped instruction at \(snapshot.agc.registers.z.octal4)")
        }
    }

    func addBreakpointFromField() {
        guard let runtime, let address = Int(breakpointOctal, radix: 8) else { return }
        Task { @MainActor [weak self] in
            await runtime.setBreakpoint(address)
            self?.latestDebugger = await runtime.debuggerSnapshot()
            self?.recordEvent("Breakpoint \(String(format: "%04o", address & 0o7777))")
        }
    }

    func addWatchFromField() {
        guard let runtime, let address = Int(watchOctal, radix: 8) else { return }
        Task { @MainActor [weak self] in
            await runtime.watchErasable(address)
            self?.latestDebugger = await runtime.debuggerSnapshot()
            self?.recordEvent("Watch E\(String(format: "%04o", address & 0o1777))")
        }
    }

    func clearDebuggerBreakpoints() {
        guard let runtime else { return }
        Task { @MainActor [weak self] in
            await runtime.clearBreakpoints()
            self?.latestDebugger = await runtime.debuggerSnapshot()
        }
    }
}

private extension Int {
    var octal4: String { String(format: "%04o", self & 0o7777) }
}

struct RegisterSnapshot {
    let cycle: UInt64
    let accumulator: Int
    let l: Int
    let q: Int
    let z: Int
    let index: Int
    let statusFlags: String
    
    init(snapshot: AGCSnapshot) {
        self.cycle = snapshot.cycle
        self.accumulator = snapshot.registers.a
        self.l = snapshot.registers.l
        self.q = snapshot.registers.q
        self.z = snapshot.registers.z
        self.index = snapshot.registers.bb
        statusFlags = snapshot.interruptRequests.contains(1) ? "RUPT" : "-"
    }
}

struct EngineHealthSnapshot: Equatable {
    var cycle: UInt64
    var cyclesPerSecond: Double
    var isAdvancing: Bool
    var lmOutputs: LMVehicleSnapshot?
}

struct BacktraceSnapshot: Identifiable, Equatable {
    let id = UUID()
    let cycle: UInt64
    let source: Int
    let target: Int
    let tag: Int

    init(entry: AGCBacktraceEntry) {
        cycle = entry.cycle
        source = entry.source
        target = entry.target
        tag = entry.tag
    }
}

struct MissionControlEvent: Identifiable, Equatable {
    let id = UUID()
    let timestamp = Date()
    let message: String

    var label: String {
        "\(timestamp.formatted(date: .omitted, time: .standard))  \(message)"
    }
}

private struct MissionControlTraceExport: Codable {
    let schema: String
    let program: String
    let samples: [LMSimulationTraceSample]
    let validation: LMPoweredDescentValidationResult?

    init(
        program: String,
        samples: [LMSimulationTraceSample],
        validation: LMPoweredDescentValidationResult?
    ) {
        self.schema = "mission-control-lmcore-trace-v1"
        self.program = program
        self.samples = samples
        self.validation = validation
    }
}

struct EventLogWindow: View {
    @State var viewModel: MissionControlViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Event Log")
                .font(.title2)
                .bold()

            if viewModel.recentEvents.isEmpty {
                Text("Load a program, run cycles, or send DSKY input to record events.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.recentEvents) { event in
                            Text(event.label)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 360)
    }
}
