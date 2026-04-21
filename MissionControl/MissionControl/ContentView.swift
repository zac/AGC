//
//  ContentView.swift
//  MissionControl
//
//  Created by Zac White on 11/7/25.
//

import SwiftUI
import UniformTypeIdentifiers
import AGC

@MainActor
@Observable
final class MissionControlViewModel {
    fileprivate static let idleSingleKeyValidationCycles: UInt64 = 12_000
    fileprivate static let idleSequenceValidationCycles: UInt64 = 120_000
    fileprivate static let scriptedKeySettleCycles: UInt64 = 50_000

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
    fileprivate(set) var status: Status = .empty
    private(set) var isRunning = false
    private(set) var programSummary = "No program loaded"
    private(set) var latestSnapshot: RegisterSnapshot?
    private(set) var latestDSKY: DSKYState?
    private(set) var engineHealth: EngineHealthSnapshot?
    private(set) var radarHookInvocations: UInt64 = 0
    private(set) var recentEvents: [MissionControlEvent] = []
    private(set) var backtraceTail: [BacktraceSnapshot] = []

    @ObservationIgnored private var agc: AGC?
    @ObservationIgnored private var dsky: DSKY?
    @ObservationIgnored private var compositeIO: CompositeAGCIO?
    @ObservationIgnored private var lmVehicleIO: LMVehicleIO?
    @ObservationIgnored private var simulationTask: Task<Void, Never>?
    @ObservationIgnored private var dskySequenceTask: Task<Void, Never>?
    @ObservationIgnored private var lastHealthWall: CFAbsoluteTime = 0
    @ObservationIgnored private var lastHealthCycle: UInt64 = 0
    @ObservationIgnored private var smoothedCyclesPerSec: Double = 0
    @ObservationIgnored private var previousCycleForAdvance: UInt64 = 0
    
    var registerSnapshot: RegisterSnapshot? {
        latestSnapshot
    }
    
    var canStart: Bool { agc != nil && !isRunning }
    var canStop: Bool { isRunning }
    var canReset: Bool { agc != nil }
    var canStep: Bool { agc != nil && !isRunning }
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
            let loaded = try AGC(binFile: url)
            agc = loaded

            let dskyInstance = DSKY(agcEngine: loaded.engine)
            let lmIO = LMVehicleIO(agcEngine: loaded.engine) { [weak self] in
                Task { @MainActor in
                    self?.radarHookInvocations += 1
                }
            }
            lmVehicleIO = lmIO
            let composite = CompositeAGCIO(children: [dskyInstance, lmIO])
            compositeIO = composite
            dsky = dskyInstance
            loaded.engine.ioDelegate = composite

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
            updateSnapshots(from: loaded.state, dsky: dskyInstance)
            refreshEngineHealth(cycle: loaded.state.cycleCounter)
            recordEvent("Loaded \(url.lastPathComponent)")
        } catch {
            agc = nil
            dsky = nil
            compositeIO = nil
            lmVehicleIO = nil
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
        agc = nil
        dsky = nil
        compositeIO = nil
        lmVehicleIO = nil
        selectedURL = nil
        status = .empty
        programSummary = "No program loaded"
        clearSnapshots()
        recordEvent("Cleared program")
    }
    
    func start() {
        guard canStart, let agc, let dsky else { return }
        dskySequenceTask?.cancel()
        dskySequenceTask = nil
        simulationTask?.cancel()
        isRunning = true
        status = .running
        lastHealthWall = CFAbsoluteTimeGetCurrent()
        lastHealthCycle = agc.state.cycleCounter
        previousCycleForAdvance = agc.state.cycleCounter
        smoothedCyclesPerSec = 0
        let cyclesPerBatch: UInt64 = 30_000
        recordEvent("Started continuous run")
        simulationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await agc.run(for: cyclesPerBatch)
                updateSnapshots(from: agc.state, dsky: dsky)
                refreshEngineHealth(cycle: agc.state.cycleCounter)
                await Task.yield()
            }
            self.isRunning = false
            self.simulationTask = nil
            if case .running = self.status {
                self.status = .stopped
            }
            self.updateSnapshots(from: agc.state, dsky: dsky)
            self.refreshEngineHealth(cycle: agc.state.cycleCounter)
            self.recordEvent("Continuous run stopped at cycle \(agc.state.cycleCounter)")
        }
    }

    func runCycles(_ cycles: UInt64) {
        guard canStep, let agc, let dsky else { return }
        dskySequenceTask?.cancel()
        dskySequenceTask = nil
        simulationTask?.cancel()
        isRunning = true
        status = .running
        lastHealthWall = CFAbsoluteTimeGetCurrent()
        lastHealthCycle = agc.state.cycleCounter
        previousCycleForAdvance = agc.state.cycleCounter
        recordEvent("Running \(cycles.formatted()) cycles")
        simulationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await agc.run(for: cycles)
            self.isRunning = false
            self.simulationTask = nil
            self.status = .stopped
            self.updateSnapshots(from: agc.state, dsky: dsky)
            self.refreshEngineHealth(cycle: agc.state.cycleCounter)
            self.recordEvent("Finished \(cycles.formatted()) cycles at cycle \(agc.state.cycleCounter)")
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
        if let agc, let dsky {
            updateSnapshots(from: agc.state, dsky: dsky)
            refreshEngineHealth(cycle: agc.state.cycleCounter)
            recordEvent("Stopped at cycle \(agc.state.cycleCounter)")
        }
    }
    
    func reset() {
        guard let url = selectedURL else { return }
        stop()
        loadProgram(from: url)
    }
    
    private func refreshEngineHealth(cycle: UInt64) {
        let batchDelta = cycle &- previousCycleForAdvance
        previousCycleForAdvance = cycle
        let now = CFAbsoluteTimeGetCurrent()
        if lastHealthWall == 0 {
            lastHealthWall = now
            lastHealthCycle = cycle
            engineHealth = EngineHealthSnapshot(
                cycle: cycle,
                cyclesPerSecond: 0,
                isAdvancing: false,
                lmOutputs: lmVehicleIO?.jetEngineOutputs
            )
            return
        }
        let dt = now - lastHealthWall
        let delta = cycle &- lastHealthCycle
        if dt > 0.05, delta > 0 {
            let instant = Double(delta) / dt
            smoothedCyclesPerSec = smoothedCyclesPerSec == 0
                ? instant
                : smoothedCyclesPerSec * 0.88 + instant * 0.12
            lastHealthWall = now
            lastHealthCycle = cycle
        }
        engineHealth = EngineHealthSnapshot(
            cycle: cycle,
            cyclesPerSecond: smoothedCyclesPerSec,
            isAdvancing: isRunning && batchDelta > 0,
            lmOutputs: lmVehicleIO?.jetEngineOutputs
        )
    }

    func pressKey(channel: Int, value: Int) {
        sendDSKYSequence(
            label: "Key \(String(format: "%03o", value))",
            keys: [DSKYKey(label: "", channel: channel, value: value, accent: false)],
            autoRunCyclesWhenIdle: Self.idleSingleKeyValidationCycles
        )
    }

    func sendDSKYSequence(label: String, keys: [DSKYKey], autoRunCyclesWhenIdle: UInt64? = nil) {
        guard let agc, let dsky else { return }
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
                    await self.sendDSKYKey(key, to: dsky)
                    if settleCycles > 0 {
                        await self.waitForCycleAdvance(settleCycles, agc: agc)
                    }
                }
                self.dskySequenceTask = nil
                self.updateSnapshots(from: agc.state, dsky: dsky)
                self.refreshEngineHealth(cycle: agc.state.cycleCounter)
                self.recordEvent("Sent \(label) into live run")
            }
            return
        }

        simulationTask?.cancel()
        simulationTask = nil
        isRunning = true
        status = .running
        lastHealthWall = CFAbsoluteTimeGetCurrent()
        lastHealthCycle = agc.state.cycleCounter
        previousCycleForAdvance = agc.state.cycleCounter
        simulationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for key in keys {
                if Task.isCancelled { break }
                await self.sendDSKYKey(key, to: dsky)

                if settleCycles > 0 {
                    await agc.run(for: settleCycles)
                    self.updateSnapshots(from: agc.state, dsky: dsky)
                    self.refreshEngineHealth(cycle: agc.state.cycleCounter)
                }
            }
            self.isRunning = false
            self.simulationTask = nil
            self.status = .stopped
            self.updateSnapshots(from: agc.state, dsky: dsky)
            self.refreshEngineHealth(cycle: agc.state.cycleCounter)
            self.recordEvent("Sent \(label)")
        }
    }

    private func sendDSKYKey(_ key: DSKYKey, to dsky: DSKY) async {
        if key.channel == 0o13 {
            await dsky.sendProKey(true)
            await dsky.sendProKey(false)
        } else {
            await dsky.sendKeycode(key.value)
        }
    }

    private func waitForCycleAdvance(_ cycles: UInt64, agc: AGC) async {
        guard cycles > 0 else { return }
        let targetCycle = agc.state.cycleCounter &+ cycles
        while !Task.isCancelled && agc.state.cycleCounter < targetCycle {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func updateSnapshots(from state: AGCState?, dsky: DSKY?) {
        if let state {
            latestSnapshot = RegisterSnapshot(state: state)
            if let dsky {
                latestDSKY = DSKYState(state: state, dsky: dsky)
            } else {
                latestDSKY = DSKYState(state: state)
            }
            backtraceTail = state.backtrace.suffix(8).map(BacktraceSnapshot.init)
        }
    }

    private func clearSnapshots() {
        latestSnapshot = nil
        latestDSKY = nil
        engineHealth = nil
        backtraceTail = []
    }

    private func recordEvent(_ message: String) {
        recentEvents.insert(MissionControlEvent(message: message), at: 0)
        if recentEvents.count > 12 {
            recentEvents.removeLast(recentEvents.count - 12)
        }
    }
}

struct RegisterSnapshot {
    let cycle: UInt64
    let accumulator: Int
    let l: Int
    let q: Int
    let z: Int
    let index: Int
    let statusFlags: String
    
    init(state: AGCState) {
        self.cycle = state.cycleCounter
        self.accumulator = state.accumulator
        self.l = state.erasableMemory[0][Register.regL.rawValue]
        self.q = state.erasableMemory[0][Register.regQ.rawValue]
        self.z = state.erasableMemory[0][Register.regZ.rawValue]
        self.index = state.indexValue
        var flags: [String] = []
        if state.extraCode { flags.append("EXTRA") }
        if state.inIsr { flags.append("ISR") }
        if state.pendFlag { flags.append("PEND") }
        statusFlags = flags.isEmpty ? "—" : flags.joined(separator: ", ")
    }
}

struct EngineHealthSnapshot: Equatable {
    var cycle: UInt64
    var cyclesPerSecond: Double
    var isAdvancing: Bool
    var lmOutputs: LMJetEngineOutputs?
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

struct MissionControlRootView: View {
    @State var viewModel: MissionControlViewModel
    @State private var isImporterPresented = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                dskySection
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                keypadSection
                    .frame(width: 320, alignment: .topLeading)
            }
            .padding(24)

            Divider()

            ScrollView {
                dashboardSection
                    .padding(24)
            }
        }
        .frame(minWidth: 860, minHeight: 640)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Load Luminary099") {
                    viewModel.loadSampleProgram()
                }
                .disabled(!viewModel.hasSampleProgram)

                Button(viewModel.selectedURL == nil ? "Open…" : "Change…") {
                    isImporterPresented = true
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewModel.isRunning ? viewModel.stop() : viewModel.start()
                } label: {
                    Label(viewModel.isRunning ? "Stop" : "Start",
                          systemImage: viewModel.isRunning ? "stop.fill" : "play.fill")
                }
                .disabled(viewModel.selectedURL == nil)

                Button("Step 1K") {
                    viewModel.runCycles(1_000)
                }
                .disabled(!viewModel.canStep)

                Button("Run 100K") {
                    viewModel.runCycles(100_000)
                }
                .disabled(!viewModel.canStep)

                Button {
                    viewModel.reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .disabled(!viewModel.canReset)
            }
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.init(filenameExtension: "bin") ?? .data]) { result in
            switch result {
            case .success(let url):
                viewModel.loadProgram(from: url)
            case .failure(let error):
                viewModel.clearProgram()
                viewModel.status = .error(error.localizedDescription)
            }
        }
    }

    private var dashboardSection: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 20) {
                programSection
                statusSection
                engineTelemetrySection
                validationSection
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            registersSection
                .frame(minWidth: 280, alignment: .topLeading)
        }
    }
    
    private var programSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Program")
                .font(.headline)
            HStack {
                if let url = viewModel.selectedURL {
                    VStack(alignment: .leading) {
                        Text(url.lastPathComponent)
                            .font(.title3)
                            .bold()
                        Text(viewModel.programSummary)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No program selected")
                            .foregroundColor(.secondary)
                        Text("Use any Luminary/Colossus core image (.bin). After Start, cycles and DSKY should update on the main thread without racing the CPU.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.headline)
            Text(viewModel.status.label)
                .font(.body)
                .foregroundStyle(statusColor)
        }
    }

    private var engineTelemetrySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Engine telemetry")
                .font(.headline)
            if let health = viewModel.engineHealth {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                    gridRow(label: "Cycle counter", value: "\(health.cycle)")
                    gridRow(
                        label: "Throughput",
                        value: health.cyclesPerSecond > 0
                            ? String(format: "%.2f M cycles/s", health.cyclesPerSecond / 1_000_000)
                            : "—"
                    )
                    gridRow(
                        label: "Stepping",
                        value: viewModel.isRunning
                            ? (health.isAdvancing ? "Batches advancing" : "No advance (unexpected)")
                            : "CPU idle"
                    )
                    if let lm = health.lmOutputs {
                        gridRow(label: "LM CH5", value: String(format: "%05o", lm.channel5))
                        gridRow(label: "LM CH6", value: String(format: "%05o", lm.channel6))
                    }
                    gridRow(label: "Radar data hooks", value: "\(viewModel.radarHookInvocations)")
                }
                .font(.system(.body, design: .monospaced))
            } else {
                Text("Load a binary and press Start to see cycle throughput, LM jet/engine channels, and radar integration callbacks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var validationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Validation")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                validationRow(
                    label: "Program loaded",
                    isPassing: viewModel.selectedURL != nil,
                    detail: viewModel.selectedURL?.lastPathComponent ?? "No core image"
                )
                validationRow(
                    label: "CPU cycle source",
                    isPassing: (viewModel.engineHealth?.cycle ?? 0) > 0,
                    detail: viewModel.engineHealth.map { "\($0.cycle) cycles" } ?? "No cycles run"
                )
                validationRow(
                    label: "DSKY delegate",
                    isPassing: viewModel.latestDSKY != nil,
                    detail: viewModel.latestDSKY == nil ? "Not connected" : "Connected"
                )
                validationRow(
                    label: "Backtrace",
                    isPassing: !viewModel.backtraceTail.isEmpty,
                    detail: viewModel.backtraceTail.isEmpty ? "No branches observed yet" : "\(viewModel.backtraceTail.count) recent entries"
                )
            }
            .font(.system(.caption, design: .monospaced))

            VStack(alignment: .leading, spacing: 6) {
                Text("Recent branches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if viewModel.backtraceTail.isEmpty {
                    Text("Run cycles to populate branch trace.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(viewModel.backtraceTail) { entry in
                        Text("\(entry.cycle)  \(octal(entry.source)) -> \(octal(entry.target))  tag \(String(format: "%03o", entry.tag))")
                    }
                }
            }
            .font(.system(.caption2, design: .monospaced))
        }
    }

    private var dskySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("DSKY")
                    .font(.headline)
                Spacer()
                if let dsky = viewModel.latestDSKY {
                    HStack(spacing: 6) {
                        Circle()
                            .frame(width: 12, height: 12)
                            .foregroundColor(dsky.lampTest ? .yellow : .gray.opacity(0.5))
                        Text(dsky.lampTest ? "Lamp test" : "Normal")
                            .font(.caption2)
                            .foregroundColor(dsky.lampTest ? .yellow : .secondary)
                    }
                }
            }
            Text("Verb 35 (after Start) is a lamp test: expect the yellow status lamps and “Lamp test” / ch 163 activity, not R1–R3. To see register lines change, try Verb 16 Noun 36 then Entr (monitor-style display; depends on your core image).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let dsky = viewModel.latestDSKY {
                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(indicatorRows.enumerated()), id: \.offset) { _, row in
                                HStack(spacing: 12) {
                                    indicatorCell(for: row.left, state: dsky)
                                    indicatorCell(for: row.right, state: dsky)
                                }
                            }
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Register display")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("R1 \(dsky.r1Text)")
                                Text("R2 \(dsky.r2Text)")
                                Text("R3 \(dsky.r3Text)")
                            }
                            .font(.system(.title3, design: .monospaced))
                            HStack(spacing: 12) {
                                Text(dsky.compActy ? "COMP ACTY" : "COMP idle")
                                    .font(.caption2)
                                    .foregroundColor(dsky.compActy ? .green : .secondary)
                            }
                            HStack(spacing: 16) {
                                VStack(alignment: .leading) {
                                    Text("VERB")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(dsky.verbDigits)
                                        .font(.system(.title3, design: .monospaced))
                                        .foregroundColor(dsky.verbNounFlash ? .yellow : .primary)
                                }
                                VStack(alignment: .leading) {
                                    Text("NOUN")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(dsky.nounDigits)
                                        .font(.system(.title3, design: .monospaced))
                                        .foregroundColor(dsky.verbNounFlash ? .yellow : .primary)
                                }
                                Spacer()
                                VStack(alignment: .leading) {
                                    Text(dsky.proOn ? "PRO ON" : "PRO")
                                        .font(.caption2)
                                        .foregroundColor(dsky.proOn ? .green : .secondary)
                                    Text(dsky.keyRelOn ? "KEY REL ON" : "KEY REL")
                                        .font(.caption2)
                                        .foregroundColor(dsky.keyRelOn ? .yellow : .secondary)
                                }
                            }
                        }
                    }
                    HStack(spacing: 12) {
                        Text("Cycle \(dsky.cycle)")
                        Text("Ch 10: \(octal(dsky.channel10))")
                        Text("Ch 11: \(String(format: "%05o", dsky.input11))")
                        Text("Ch 13: \(String(format: "%05o", dsky.input13))")
                        Text("Ch 163: \(String(format: "%05o", dsky.output163))")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
            } else {
                Text("Program inactive")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var keypadSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keypad")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(quickSequences) { sequence in
                    Button(sequence.label) {
                        viewModel.sendDSKYSequence(
                            label: sequence.label,
                            keys: sequence.keys,
                            autoRunCyclesWhenIdle: MissionControlViewModel.idleSequenceValidationCycles
                        )
                    }
                    .disabled(viewModel.selectedURL == nil)
                }
            }
            .font(.caption)
            Text("When the CPU is idle, DSKY key presses auto-run a short validation burst so the result is visible immediately.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                ForEach(Array(keypadRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        ForEach(row) { key in
                            Button {
                                viewModel.pressKey(channel: key.channel, value: key.value)
                            } label: {
                                Text(key.label)
                                    .font(.body)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(key.backgroundColor))
                                    .foregroundColor(key.foregroundColor)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.primary.opacity(0.1))
                                    )
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var registersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Processor Snapshot")
                .font(.headline)
            if let snapshot = viewModel.registerSnapshot {
                Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 8) {
                    gridRow(label: "Cycle", value: "\(snapshot.cycle)")
                    gridRow(label: "A", value: octal(snapshot.accumulator))
                    gridRow(label: "L", value: octal(snapshot.l))
                    gridRow(label: "Q", value: octal(snapshot.q))
                    gridRow(label: "Z", value: octal(snapshot.z))
                    gridRow(label: "Index", value: octal(snapshot.index))
                    gridRow(label: "Flags", value: snapshot.statusFlags)
                }
                .font(.system(.body, design: .monospaced))
            } else {
                Text("No runtime data yet")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func gridRow(label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
        }
    }

    private func validationRow(label: String, isPassing: Bool, detail: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(isPassing ? "OK" : "WAIT")
                .foregroundStyle(isPassing ? .green : .orange)
            Text(detail)
        }
    }
    
    private func octal(_ value: Int) -> String {
        String(format: "%06o", value & 0o177777)
    }
    
    private var statusColor: Color {
        switch viewModel.status {
        case .running:
            return .green
        case .stopped:
            return .orange
        case .error:
            return .red
        default:
            return .primary
        }
    }

    private var quickSequences: [QuickDSKYSequence] {
        [
            QuickDSKYSequence(
                label: "V35E lamp",
                keys: [
                    DSKYKey(label: "VERB", channel: 0o15, value: 0o21, accent: true),
                    DSKYKey(label: "3", channel: 0o15, value: 0o3, accent: false),
                    DSKYKey(label: "5", channel: 0o15, value: 0o5, accent: false),
                    DSKYKey(label: "ENTR", channel: 0o15, value: 0o34, accent: true),
                ]
            ),
            QuickDSKYSequence(
                label: "V16N36E",
                keys: [
                    DSKYKey(label: "VERB", channel: 0o15, value: 0o21, accent: true),
                    DSKYKey(label: "1", channel: 0o15, value: 0o1, accent: false),
                    DSKYKey(label: "6", channel: 0o15, value: 0o6, accent: false),
                    DSKYKey(label: "NOUN", channel: 0o15, value: 0o37, accent: true),
                    DSKYKey(label: "3", channel: 0o15, value: 0o3, accent: false),
                    DSKYKey(label: "6", channel: 0o15, value: 0o6, accent: false),
                    DSKYKey(label: "ENTR", channel: 0o15, value: 0o34, accent: true),
                ]
            ),
            QuickDSKYSequence(
                label: "RSET",
                keys: [
                    DSKYKey(label: "RSET", channel: 0o15, value: 0o22, accent: true),
                ]
            ),
        ]
    }

    private var keypadRows: [[DSKYKey]] {
        [
            [
                DSKYKey(label: "VERB", channel: 0o15, value: 0o21, accent: true),
                DSKYKey(label: "NOUN", channel: 0o15, value: 0o37, accent: true),
                DSKYKey(label: "PRO", channel: 0o13, value: 0o2000, accent: true),
                DSKYKey(label: "KEY REL", channel: 0o15, value: 0o31, accent: true),
            ],
            [
                DSKYKey(label: "7", channel: 0o15, value: 0o7, accent: false),
                DSKYKey(label: "8", channel: 0o15, value: 8, accent: false),
                DSKYKey(label: "9", channel: 0o15, value: 9, accent: false),
                DSKYKey(label: "+", channel: 0o15, value: 0o32, accent: true),
            ],
            [
                DSKYKey(label: "4", channel: 0o15, value: 0o4, accent: false),
                DSKYKey(label: "5", channel: 0o15, value: 0o5, accent: false),
                DSKYKey(label: "6", channel: 0o15, value: 0o6, accent: false),
                DSKYKey(label: "-", channel: 0o15, value: 0o33, accent: true),
            ],
            [
                DSKYKey(label: "1", channel: 0o15, value: 0o1, accent: false),
                DSKYKey(label: "2", channel: 0o15, value: 0o2, accent: false),
                DSKYKey(label: "3", channel: 0o15, value: 0o3, accent: false),
                DSKYKey(label: "ENTR", channel: 0o15, value: 0o34, accent: true),
            ],
            [
                DSKYKey(label: "CLR", channel: 0o15, value: 0o36, accent: true),
                DSKYKey(label: "0", channel: 0o15, value: 0o20, accent: false),
                DSKYKey(label: "RSET", channel: 0o15, value: 0o22, accent: true),
            ]
        ]
    }

    private var indicatorRows: [(left: Int?, right: Int?)] {
        [
            (11, 21),
            (12, 22),
            (13, 23),
            (14, 24),
            (15, 25),
            (16, 26),
            (17, 27),
        ]
    }

    @ViewBuilder
    private func indicatorCell(for id: Int?, state: DSKYState) -> some View {
        if let id, let definition = DSKYIndicatorDefinition.luminaryByID[id] {
            let isOn = state.indicatorIsOn(id)
            HStack(spacing: 6) {
                Circle()
                    .frame(width: 10, height: 10)
                    .foregroundColor(state.lampTest ? .yellow : (isOn ? .yellow : .gray.opacity(0.5)))
                    .opacity(definition.label == nil ? 0.3 : 1)
                Text(definition.label ?? "")
                    .font(.caption2)
                    .foregroundColor(definition.label == nil ? .secondary : .primary)
                    .opacity(definition.label == nil ? 0.4 : 1)
            }
        } else {
            Spacer(minLength: 64)
        }
    }
}

struct DSKYKey: Identifiable {
    let label: String
    let channel: Int
    let value: Int
    let accent: Bool

    var id: String {
        "\(label)-\(channel)-\(value)"
    }

    var backgroundColor: Color {
        if accent {
            return Color.accentColor.opacity(0.25)
        }
        return Color.secondary.opacity(0.17)
    }

    var foregroundColor: Color {
        accent ? Color.accentColor : .primary
    }
}

struct QuickDSKYSequence: Identifiable {
    let label: String
    let keys: [DSKYKey]

    var id: String { label }
}

struct DSKYState {
    let channel10: Int
    let input11: Int
    let input13: Int
    let output163: Int
    let cycle: UInt64
    let r1Text: String
    let r2Text: String
    let r3Text: String
    let verbDigits: String
    let nounDigits: String
    let plusSign: Bool
    let verbNounFlash: Bool
    let proOn: Bool
    let keyRelOn: Bool
    let lampTest: Bool
    let compActy: Bool
    private let indicatorStatuses: [Int: Bool]

    init(state: AGCState) {
        channel10 = state.outputChannels[0o10]
        input11 = state.inputChannels[0o11]
        input13 = state.inputChannels[0o13]
        output163 = state.dskyChannel163
        cycle = state.cycleCounter

        let digits = String(format: "%05o", channel10 & 0o77777)
        plusSign = (channel10 & 0o40000) == 0
        r1Text = (plusSign ? "+" : "-") + digits
        r2Text = "—"
        r3Text = "—"
        verbDigits = String(digits.prefix(2))
        nounDigits = String(digits.dropFirst(2).prefix(2))
        verbNounFlash = (state.inputChannels[0o11] & 0o40) != 0
        proOn = (state.inputChannels[0o13] & 0o40000) != 0
        keyRelOn = (state.inputChannels[0o11] & 0o20) != 0
        lampTest = (state.inputChannels[0o13] & 0o1000) != 0
        compActy = (input11 & 0o2) != 0

        var statuses: [Int: Bool] = [:]
        for definition in DSKYIndicatorDefinition.luminaryDefinitions {
            statuses[definition.id] = DSKYIndicatorDefinition.evaluate(definition, state: state)
        }
        indicatorStatuses = statuses
    }

    init(state: AGCState, dsky: DSKY) {
        channel10 = state.outputChannels[0o10]
        input11 = dsky.channel11
        input13 = dsky.channel13
        output163 = dsky.channel163
        cycle = state.cycleCounter
        r1Text = dsky.formatRegister(dsky.r1)
        r2Text = dsky.formatRegister(dsky.r2)
        r3Text = dsky.formatRegister(dsky.r3)
        verbDigits = dsky.formatVerb()
        nounDigits = dsky.formatNoun()
        plusSign = dsky.r1.sign == "+"
        verbNounFlash = dsky.verbNounFlash
        proOn = !dsky.proKeyPressed
        keyRelOn = dsky.indicatorIsOn(14)
        lampTest = dsky.lampTest
        compActy = dsky.compActy

        var statuses: [Int: Bool] = [:]
        for id in [11, 12, 13, 14, 15, 16, 17, 21, 22, 23, 24, 25, 26, 27] {
            statuses[id] = dsky.indicatorIsOn(id)
        }
        indicatorStatuses = statuses
    }

    func indicatorIsOn(_ id: Int) -> Bool {
        indicatorStatuses[id] ?? false
    }
}

struct DSKYIndicatorDefinition {
    let id: Int
    let label: String?
    let channel: Int
    let bitPosition: Int
    let polarity: Int
    let mask: Int?
    let match: Int?

    static let luminaryDefinitions: [DSKYIndicatorDefinition] = [
        DSKYIndicatorDefinition(id: 11, label: "UPLINK ACTY", channel: 0o11, bitPosition: 3, polarity: 0, mask: nil, match: nil),
        DSKYIndicatorDefinition(id: 12, label: "NO ATT", channel: 0o10, bitPosition: 4, polarity: 0, mask: 0o74000, match: 0o60000),
        DSKYIndicatorDefinition(id: 13, label: "STBY", channel: 0o163, bitPosition: 9, polarity: 0, mask: nil, match: nil),
        DSKYIndicatorDefinition(id: 14, label: "KEY REL", channel: 0o163, bitPosition: 5, polarity: 0, mask: nil, match: nil),
        DSKYIndicatorDefinition(id: 15, label: "OPER ERR", channel: 0o163, bitPosition: 7, polarity: 0, mask: nil, match: nil),
        DSKYIndicatorDefinition(id: 16, label: nil, channel: 0o10, bitPosition: 1, polarity: 0, mask: 0o74000, match: 0o60000),
        DSKYIndicatorDefinition(id: 17, label: nil, channel: 0o10, bitPosition: 2, polarity: 0, mask: 0o74000, match: 0o60000),
        DSKYIndicatorDefinition(id: 21, label: "TEMP", channel: 0o163, bitPosition: 4, polarity: 0, mask: nil, match: nil),
        DSKYIndicatorDefinition(id: 22, label: "GIMBAL LOCK", channel: 0o10, bitPosition: 6, polarity: 0, mask: 0o74000, match: 0o60000),
        DSKYIndicatorDefinition(id: 23, label: "PROG", channel: 0o10, bitPosition: 9, polarity: 0, mask: 0o74000, match: 0o60000),
        DSKYIndicatorDefinition(id: 24, label: "RESTART", channel: 0o163, bitPosition: 8, polarity: 0, mask: nil, match: nil),
        DSKYIndicatorDefinition(id: 25, label: "TRACKER", channel: 0o10, bitPosition: 8, polarity: 0, mask: 0o74000, match: 0o60000),
        DSKYIndicatorDefinition(id: 26, label: "ALT", channel: 0o10, bitPosition: 5, polarity: 0, mask: 0o74000, match: 0o60000),
        DSKYIndicatorDefinition(id: 27, label: "VEL", channel: 0o10, bitPosition: 3, polarity: 0, mask: 0o74000, match: 0o60000),
    ]

    static let luminaryByID: [Int: DSKYIndicatorDefinition] = .init(uniqueKeysWithValues: luminaryDefinitions.map { ($0.id, $0) })

    static func evaluate(_ definition: DSKYIndicatorDefinition, state: AGCState) -> Bool {
        let channelValue: Int
        if definition.channel == 0o163 {
            channelValue = state.dskyChannel163
        } else {
            channelValue = state.outputChannels[definition.channel]
        }

        if let mask = definition.mask, let match = definition.match {
            guard (channelValue & mask) == match else {
                return false
            }
        }

        let bitMask = 1 << (definition.bitPosition - 1)
        var isOn = (channelValue & bitMask) != 0
        if definition.polarity != 0 {
            isOn.toggle()
        }
        return isOn
    }
}
#Preview {
    MissionControlRootView(viewModel: MissionControlViewModel())
}
