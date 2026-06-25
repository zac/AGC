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
    private(set) var latestDSKY: DSKYSnapshot?
    private(set) var engineHealth: EngineHealthSnapshot?
    private(set) var radarHookInvocations: UInt64 = 0
    private(set) var recentEvents: [MissionControlEvent] = []
    private(set) var backtraceTail: [BacktraceSnapshot] = []
    private(set) var latestChannelTrace: [AGCChannelTraceEntry] = []

    @ObservationIgnored private var runtime: AGCRuntime?
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
            let loaded = try AGCRuntime(binFile: url)
            runtime = loaded

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
                let snapshot = await runtime.step(cycles: cyclesPerBatch)
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
            self.recordEvent("Continuous run stopped at cycle \(snapshot.cycle)")
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
            let snapshot = await runtime.step(cycles: cycles)
            self.isRunning = false
            self.simulationTask = nil
            self.status = .stopped
            self.applySnapshot(snapshot)
            self.recordEvent("Finished \(cycles.formatted()) cycles at cycle \(snapshot.cycle)")
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
                self.recordEvent("Stopped at cycle \(snapshot.cycle)")
            }
        }
    }
    
    func reset() {
        guard let url = selectedURL else { return }
        stop()
        loadProgram(from: url)
    }
    
    private func refreshEngineHealth(snapshot: AGCSnapshot) {
        let batchDelta = snapshot.cycle &- previousCycleForAdvance
        previousCycleForAdvance = snapshot.cycle
        let now = CFAbsoluteTimeGetCurrent()
        if lastHealthWall == 0 {
            lastHealthWall = now
            lastHealthCycle = snapshot.cycle
            engineHealth = EngineHealthSnapshot(
                cycle: snapshot.cycle,
                cyclesPerSecond: 0,
                isAdvancing: false,
                lmOutputs: snapshot.vehicle
            )
            return
        }
        let dt = now - lastHealthWall
        let delta = snapshot.cycle &- lastHealthCycle
        if dt > 0.05, delta > 0 {
            let instant = Double(delta) / dt
            smoothedCyclesPerSec = smoothedCyclesPerSec == 0
                ? instant
                : smoothedCyclesPerSec * 0.88 + instant * 0.12
            lastHealthWall = now
            lastHealthCycle = snapshot.cycle
        }
        engineHealth = EngineHealthSnapshot(
            cycle: snapshot.cycle,
            cyclesPerSecond: smoothedCyclesPerSec,
            isAdvancing: isRunning && batchDelta > 0,
            lmOutputs: snapshot.vehicle
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
                        startCycle = currentSnapshot.cycle
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
                    let snapshot = await runtime.step(cycles: settleCycles)
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

    private func waitForCycleAdvance(_ cycles: UInt64, runtime: AGCRuntime, startCycle: UInt64) async {
        guard cycles > 0 else { return }
        let targetCycle = startCycle &+ cycles
        while !Task.isCancelled {
            let snapshot = await runtime.snapshot()
            if snapshot.cycle >= targetCycle {
                applySnapshot(snapshot)
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func applySnapshot(_ snapshot: AGCSnapshot) {
        latestSnapshot = RegisterSnapshot(snapshot: snapshot)
        latestDSKY = snapshot.dsky
        latestChannelTrace = Array(snapshot.channelTrace.suffix(80))
        backtraceTail = snapshot.backtrace.suffix(8).map(BacktraceSnapshot.init)
        refreshEngineHealth(snapshot: snapshot)
    }

    private func clearSnapshots() {
        latestSnapshot = nil
        latestDSKY = nil
        engineHealth = nil
        backtraceTail = []
        latestChannelTrace = []
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

            VStack(alignment: .leading, spacing: 20) {
                registersSection
                channelTraceSection
            }
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
                        gridRow(label: "LM OUT0", value: String(format: "%05o", lm.out0))
                        gridRow(label: "LM OUT1", value: String(format: "%05o", lm.out1))
                        gridRow(label: "RCS commands", value: "\(lm.rcsJets.count)")
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
                                Text("R1 \(dsky.r1)")
                                Text("R2 \(dsky.r2)")
                                Text("R3 \(dsky.r3)")
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
                                    Text(dsky.verb)
                                        .font(.system(.title3, design: .monospaced))
                                        .foregroundColor(dsky.verbNounFlash ? .yellow : .primary)
                                }
                                VStack(alignment: .leading) {
                                    Text("NOUN")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(dsky.noun)
                                        .font(.system(.title3, design: .monospaced))
                                        .foregroundColor(dsky.verbNounFlash ? .yellow : .primary)
                                }
                                Spacer()
                                VStack(alignment: .leading) {
                                    Text(dsky.proKeyPressed ? "PRO ON" : "PRO")
                                        .font(.caption2)
                                        .foregroundColor(dsky.proKeyPressed ? .green : .secondary)
                                    Text(dsky.indicatorIsOn(14) ? "KEY REL ON" : "KEY REL")
                                        .font(.caption2)
                                        .foregroundColor(dsky.indicatorIsOn(14) ? .yellow : .secondary)
                                }
                            }
                        }
                    }
                    HStack(spacing: 12) {
                        Text("Cycle \(viewModel.latestSnapshot?.cycle ?? 0)")
                        Text("Ch 10 rows: \(dsky.channel10Rows.filter { $0 != 0 }.count)")
                        Text("Ch 11: \(String(format: "%05o", dsky.channel11))")
                        Text("Ch 13: \(String(format: "%05o", dsky.channel13))")
                        Text("Ch 163: \(String(format: "%05o", dsky.channel163))")
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
                        viewModel.sendDSKYScript(
                            sequence.script,
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
                                viewModel.pressKey(key.code)
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
                    gridRow(label: "BB", value: octal(snapshot.index))
                    gridRow(label: "Flags", value: snapshot.statusFlags)
                }
                .font(.system(.body, design: .monospaced))
            } else {
                Text("No runtime data yet")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var channelTraceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Channel Trace")
                .font(.headline)
            if viewModel.latestChannelTrace.isEmpty {
                Text("No channel activity yet")
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.latestChannelTrace.suffix(14)) { entry in
                        Text("\(entry.direction.rawValue.uppercased())  \(String(format: "%03o", entry.channel))  \(String(format: "%05o", entry.value))")
                    }
                }
                .font(.system(.caption, design: .monospaced))
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
            QuickDSKYSequence(script: .v35e),
            QuickDSKYSequence(script: .v16n36e),
            QuickDSKYSequence(script: .reset),
        ]
    }

    private var keypadRows: [[DSKYKey]] {
        [
            [
                DSKYKey(code: .verb, accent: true),
                DSKYKey(code: .noun, accent: true),
                DSKYKey(code: .pro, accent: true),
                DSKYKey(code: .keyRelease, accent: true),
            ],
            [
                DSKYKey(code: .digit7, accent: false),
                DSKYKey(code: .digit8, accent: false),
                DSKYKey(code: .digit9, accent: false),
                DSKYKey(code: .plus, accent: true),
            ],
            [
                DSKYKey(code: .digit4, accent: false),
                DSKYKey(code: .digit5, accent: false),
                DSKYKey(code: .digit6, accent: false),
                DSKYKey(code: .minus, accent: true),
            ],
            [
                DSKYKey(code: .digit1, accent: false),
                DSKYKey(code: .digit2, accent: false),
                DSKYKey(code: .digit3, accent: false),
                DSKYKey(code: .enter, accent: true),
            ],
            [
                DSKYKey(code: .clear, accent: true),
                DSKYKey(code: .digit0, accent: false),
                DSKYKey(code: .reset, accent: true),
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
    private func indicatorCell(for id: Int?, state: DSKYSnapshot) -> some View {
        if let id {
            let isOn = state.indicatorIsOn(id)
            let label = DSKYIndicatorLabel.labels[id]
            HStack(spacing: 6) {
                Circle()
                    .frame(width: 10, height: 10)
                    .foregroundColor(state.lampTest ? .yellow : (isOn ? .yellow : .gray.opacity(0.5)))
                    .opacity(label == nil ? 0.3 : 1)
                Text(label ?? "")
                    .font(.caption2)
                    .foregroundColor(label == nil ? .secondary : .primary)
                    .opacity(label == nil ? 0.4 : 1)
            }
        } else {
            Spacer(minLength: 64)
        }
    }
}

struct DSKYKey: Identifiable {
    let code: DSKYKeyCode
    let accent: Bool

    var id: String {
        code.label
    }

    var label: String {
        code.label
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
    let script: DSKYScript

    var id: String { script.id }
    var label: String { script.id }
}

enum DSKYIndicatorLabel {
    static let labels: [Int: String] = [
        11: "UPLINK ACTY",
        12: "NO ATT",
        13: "STBY",
        14: "KEY REL",
        15: "OPER ERR",
        21: "TEMP",
        22: "GIMBAL LOCK",
        23: "PROG",
        24: "RESTART",
        25: "TRACKER",
        26: "ALT",
        27: "VEL"
    ]
}
#Preview {
    MissionControlRootView(viewModel: MissionControlViewModel())
}
