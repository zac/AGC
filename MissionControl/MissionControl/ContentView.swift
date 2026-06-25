//
//  ContentView.swift
//  MissionControl
//
//  Created by Zac White on 11/7/25.
//

import SwiftUI
import AppKit
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

private enum MissionControlSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case dsky
    case telemetry
    case validation
    case trace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .dsky: "DSKY"
        case .telemetry: "Telemetry"
        case .validation: "Validation"
        case .trace: "Channel Trace"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: "Runtime, DSKY, and health"
        case .dsky: "Display, lamps, and keypad"
        case .telemetry: "Cycles, LM outputs, and registers"
        case .validation: "Smoke checks and branch trace"
        case .trace: "Ordered AGC channel traffic"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .dsky: "rectangle.grid.3x2"
        case .telemetry: "waveform.path.ecg"
        case .validation: "checkmark.seal"
        case .trace: "list.bullet.rectangle"
        }
    }

}

struct MissionControlRootView: View {
    @State var viewModel: MissionControlViewModel
    @State private var isImporterPresented = false
    @State private var selectedSection: MissionControlSection? = .overview
    @State private var isInspectorPresented = true
    @Environment(\.openWindow) private var openWindow

    private var activeSection: MissionControlSection {
        selectedSection ?? .overview
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    runtimeHeader

                    dskyConsoleSection
                    activeDetailSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .navigationTitle(activeSection.title)
            .background(Color(nsColor: .windowBackgroundColor))
            .toolbar {
                mainToolbar
            }
            .inspector(isPresented: $isInspectorPresented) {
                inspectorSection
            }
        }
        .frame(minWidth: 1080, minHeight: 720)
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

    private var sidebar: some View {
        List(selection: $selectedSection) {
            Section("Mission Control") {
                ForEach(MissionControlSection.allCases) { section in
                    NavigationLink(value: section) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.title)
                                Text(section.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } icon: {
                            Image(systemName: section.systemImage)
                        }
                    }
                }
            }

            Section("Runtime") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.selectedURL?.lastPathComponent ?? "No image loaded")
                        .font(.callout)
                        .lineLimit(1)
                    Text(viewModel.status.label)
                        .font(.caption)
                        .foregroundStyle(statusTint)
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Mission Control")
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                viewModel.loadSampleProgram()
            } label: {
                Label("Load Luminary099", systemImage: "shippingbox")
            }
            .disabled(!viewModel.hasSampleProgram)

            Button {
                isImporterPresented = true
            } label: {
                Label(viewModel.selectedURL == nil ? "Open" : "Change", systemImage: "folder")
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            ControlGroup {
                Button {
                    viewModel.isRunning ? viewModel.stop() : viewModel.start()
                } label: {
                    Label(viewModel.isRunning ? "Stop" : "Start",
                          systemImage: viewModel.isRunning ? "stop.fill" : "play.fill")
                }
                .disabled(viewModel.selectedURL == nil)

                Button {
                    viewModel.runCycles(1_000)
                } label: {
                    Label("Step 1K", systemImage: "forward.frame")
                }
                .disabled(!viewModel.canStep)

                Button {
                    viewModel.runCycles(100_000)
                } label: {
                    Label("Run 100K", systemImage: "forward.end")
                }
                .disabled(!viewModel.canStep)
            }

            ControlGroup {
                Button {
                    viewModel.reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .disabled(!viewModel.canReset)

                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Label(isInspectorPresented ? "Hide Inspector" : "Show Inspector",
                          systemImage: "sidebar.right")
                }
            }
        }
    }

    private var runtimeHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            Label(viewModel.status.label, systemImage: statusSymbol)
                .font(.headline)
                .foregroundStyle(statusTint)
                .lineLimit(1)

            Spacer(minLength: 12)

            metricPill(label: "Cycle", value: viewModel.latestSnapshot.map { $0.cycle.formatted() } ?? "0")
            metricPill(label: "Image", value: viewModel.selectedURL?.lastPathComponent ?? "None")

            Button {
                openWindow(id: "event-log")
            } label: {
                Label("Event Log", systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(panelStroke)
    }

    @ViewBuilder
    private var activeDetailSection: some View {
        switch activeSection {
        case .overview:
            overviewSection
        case .dsky:
            dskyDetailSection
        case .telemetry:
            telemetrySection
        case .validation:
            validationDetailSection
        case .trace:
            traceDetailSection
        }
    }

    private var overviewSection: some View {
        LazyVGrid(columns: dashboardColumns, alignment: .leading, spacing: 16) {
            programPanel
            engineTelemetryPanel
            validationPanel
            lmVehiclePanel
        }
    }

    private var dskyDetailSection: some View {
        LazyVGrid(columns: dashboardColumns, alignment: .leading, spacing: 16) {
            channelTracePanel(limit: 18)
            validationPanel
        }
    }

    private var telemetrySection: some View {
        LazyVGrid(columns: dashboardColumns, alignment: .leading, spacing: 16) {
            engineTelemetryPanel
            lmVehiclePanel
            processorPanel
            recentBranchesPanel
        }
    }

    private var validationDetailSection: some View {
        LazyVGrid(columns: dashboardColumns, alignment: .leading, spacing: 16) {
            validationPanel
            recentBranchesPanel
            channelTracePanel(limit: 18)
        }
    }

    private var traceDetailSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            channelTracePanel(limit: nil)
        }
    }

    private var inspectorSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                inspectorGroup(title: "Processor Snapshot", systemImage: "cpu") {
                    processorContent
                }
                inspectorDivider
                inspectorGroup(title: "Channel Trace", systemImage: "list.bullet.rectangle") {
                    channelTraceContent(limit: 16)
                }
                inspectorDivider
                inspectorGroup(title: "Recent Branches", systemImage: "arrow.triangle.branch") {
                    recentBranchesContent
                }
            }
            .padding(.horizontal, 34)
            .padding(.top, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 320, idealWidth: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var programPanel: some View {
        missionPanel(title: "Program", systemImage: "shippingbox") {
            if let url = viewModel.selectedURL {
                VStack(alignment: .leading, spacing: 6) {
                    Text(url.lastPathComponent)
                        .font(.title3)
                        .bold()
                        .lineLimit(1)
                    Text(viewModel.programSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Load a Luminary or Colossus core image.")
                        .foregroundStyle(.secondary)
                    Button("Open Binary...") {
                        isImporterPresented = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var engineTelemetryPanel: some View {
        missionPanel(title: "Engine Telemetry", systemImage: "waveform.path.ecg") {
            if let health = viewModel.engineHealth {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) {
                    gridRow(label: "Cycle counter", value: health.cycle.formatted())
                    gridRow(
                        label: "Throughput",
                        value: health.cyclesPerSecond > 0
                            ? String(format: "%.2f M cycles/s", health.cyclesPerSecond / 1_000_000)
                            : "-"
                    )
                    gridRow(
                        label: "Stepping",
                        value: viewModel.isRunning
                            ? (health.isAdvancing ? "Batches advancing" : "No advance")
                            : "CPU idle"
                    )
                    if let lm = health.lmOutputs {
                        gridRow(label: "LM OUT0", value: octalWord(lm.out0))
                        gridRow(label: "LM OUT1", value: octalWord(lm.out1))
                        gridRow(label: "RCS commands", value: "\(lm.rcsJets.count)")
                    }
                    gridRow(label: "Radar data hooks", value: "\(viewModel.radarHookInvocations)")
                }
                .font(.system(.body, design: .monospaced))
            } else {
                Text("Run cycles to see throughput, vehicle outputs, and integration callbacks.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var validationPanel: some View {
        missionPanel(title: "Validation", systemImage: "checkmark.seal") {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 7) {
                validationRow(
                    label: "Program loaded",
                    isPassing: viewModel.selectedURL != nil,
                    detail: viewModel.selectedURL?.lastPathComponent ?? "No core image"
                )
                validationRow(
                    label: "CPU cycle source",
                    isPassing: (viewModel.engineHealth?.cycle ?? 0) > 0,
                    detail: viewModel.engineHealth.map { "\($0.cycle.formatted()) cycles" } ?? "No cycles run"
                )
                validationRow(
                    label: "DSKY delegate",
                    isPassing: viewModel.latestDSKY != nil,
                    detail: viewModel.latestDSKY == nil ? "Not connected" : "Connected"
                )
                validationRow(
                    label: "Backtrace",
                    isPassing: !viewModel.backtraceTail.isEmpty,
                    detail: viewModel.backtraceTail.isEmpty ? "No branches observed" : "\(viewModel.backtraceTail.count) recent entries"
                )
            }
            .font(.system(.caption, design: .monospaced))
        }
    }

    private var lmVehiclePanel: some View {
        missionPanel(title: "LM Vehicle Outputs", systemImage: "gyroscope") {
            if let lm = viewModel.engineHealth?.lmOutputs {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        gridRow(label: "OUT0 / ch 005", value: octalWord(lm.out0))
                        gridRow(label: "OUT1 / ch 006", value: octalWord(lm.out1))
                        gridRow(label: "Unmapped bits", value: "\(lm.unmappedBits.count)")
                    }
                    .font(.system(.caption, design: .monospaced))

                    if lm.rcsJets.isEmpty {
                        Text("No source-backed RCS jet commands are active.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("RCS commands")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(Array(lm.rcsJets.enumerated()), id: \.offset) { _, command in
                                Text("Jet \(command.jet.rawValue)  \(command.axis.rawValue)  ch \(octalChannel(command.channel)) bit \(command.bit)")
                            }
                        }
                        .font(.system(.caption, design: .monospaced))
                    }

                    if !lm.discreteGroups.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Discrete groups")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(Array(lm.discreteGroups.enumerated()), id: \.offset) { _, group in
                                Text("\(group.name)  \(octalWord(group.mask))")
                            }
                        }
                        .font(.system(.caption, design: .monospaced))
                    }
                }
            } else {
                Text("No vehicle output snapshot yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var processorPanel: some View {
        missionPanel(title: "Processor Snapshot", systemImage: "cpu") {
            processorContent
        }
    }

    private func channelTracePanel(limit: Int?) -> some View {
        missionPanel(title: "Channel Trace", systemImage: "list.bullet.rectangle") {
            channelTraceContent(limit: limit)
        }
    }

    private var recentBranchesPanel: some View {
        missionPanel(title: "Recent Branches", systemImage: "arrow.triangle.branch") {
            recentBranchesContent
        }
    }

    private var dskyConsoleSection: some View {
        missionPanel(title: "DSKY", systemImage: "rectangle.grid.3x2") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    dskyDisplay
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    keypadSection
                        .frame(width: 340, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: 18) {
                    dskyDisplay
                    keypadSection
                }
            }

            Text("V35E runs lamp test. V16N36E requests a monitor-style display when the loaded program supports it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var dskyDisplay: some View {
        if let dsky = viewModel.latestDSKY {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Circle()
                        .frame(width: 12, height: 12)
                        .foregroundStyle(dsky.lampTest ? .yellow : Color.secondary.opacity(0.45))
                    Text(dsky.lampTest ? "Lamp test" : "Normal")
                        .font(.caption)
                        .foregroundStyle(dsky.lampTest ? .yellow : .secondary)
                    Spacer()
                    Text("Cycle \(viewModel.latestSnapshot?.cycle.formatted() ?? "0")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        indicatorGrid(state: dsky)
                        Divider()
                        dskyRegisterDisplay(state: dsky)
                            .frame(minWidth: 220, maxWidth: .infinity, alignment: .topLeading)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        indicatorGrid(state: dsky)
                        Divider()
                        dskyRegisterDisplay(state: dsky)
                    }
                }

                HStack(spacing: 12) {
                    Text("Rows \(dsky.channel10Rows.filter { $0 != 0 }.count)")
                    Text("Ch11 \(octalWord(dsky.channel11))")
                    Text("Ch13 \(octalWord(dsky.channel13))")
                    Text("Ch163 \(octalWord(dsky.channel163))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Program inactive")
                    .foregroundStyle(.secondary)
                Text("Load a core image to initialize DSKY display state.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var keypadSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Keypad")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 8) {
                ForEach(quickSequences) { sequence in
                    Button(sequence.label) {
                        viewModel.sendDSKYScript(
                            sequence.script,
                            autoRunCyclesWhenIdle: MissionControlViewModel.idleSequenceValidationCycles
                        )
                    }
                    .disabled(viewModel.selectedURL == nil)
                    .buttonStyle(.bordered)
                }
            }
            .controlSize(.small)

            Text("Idle key presses run a bounded validation burst so display changes settle immediately.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(Array(keypadRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        ForEach(row) { key in
                            Button {
                                viewModel.pressKey(key.code)
                            } label: {
                                Text(key.label)
                                    .font(.title3)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(DSKYKeyButtonStyle(accent: key.accent))
                            .disabled(viewModel.selectedURL == nil)
                        }
                    }
                }
            }
        }
    }

    private func indicatorGrid(state: DSKYSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(indicatorRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    indicatorCell(for: row.left, state: state)
                    indicatorCell(for: row.right, state: state)
                }
            }
        }
    }

    private func dskyRegisterDisplay(state dsky: DSKYSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Register display")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 5) {
                Text("R1 \(dsky.r1)")
                Text("R2 \(dsky.r2)")
                Text("R3 \(dsky.r3)")
            }
            .font(.system(.title3, design: .monospaced))

            HStack(spacing: 16) {
                dskyReadout(label: "VERB", value: dsky.verb, isFlashing: dsky.verbNounFlash)
                dskyReadout(label: "NOUN", value: dsky.noun, isFlashing: dsky.verbNounFlash)
                Spacer(minLength: 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text(dsky.compActy ? "COMP ACTY" : "COMP idle")
                        .foregroundStyle(dsky.compActy ? .green : .secondary)
                    Text(dsky.proKeyPressed ? "PRO ON" : "PRO")
                        .foregroundStyle(dsky.proKeyPressed ? .green : .secondary)
                    Text(dsky.indicatorIsOn(14) ? "KEY REL ON" : "KEY REL")
                        .foregroundStyle(dsky.indicatorIsOn(14) ? .yellow : .secondary)
                }
                .font(.caption)
            }
        }
    }

    private func dskyReadout(label: String, value: String, isFlashing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(isFlashing ? .yellow : .primary)
        }
    }

    @ViewBuilder
    private var processorContent: some View {
        if let snapshot = viewModel.registerSnapshot {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) {
                gridRow(label: "Cycle", value: snapshot.cycle.formatted())
                gridRow(label: "A", value: octalRegister(snapshot.accumulator))
                gridRow(label: "L", value: octalRegister(snapshot.l))
                gridRow(label: "Q", value: octalRegister(snapshot.q))
                gridRow(label: "Z", value: octalRegister(snapshot.z))
                gridRow(label: "BB", value: octalRegister(snapshot.index))
                gridRow(label: "Flags", value: snapshot.statusFlags)
            }
            .font(.system(.body, design: .monospaced))
        } else {
            Text("No runtime data yet.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func channelTraceContent(limit: Int?) -> some View {
        let entries = traceEntries(limit: limit)
        if entries.isEmpty {
            Text("No channel activity yet.")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(entries) { entry in
                    HStack(spacing: 10) {
                        Text(entry.direction.rawValue.uppercased())
                            .frame(width: 36, alignment: .leading)
                        Text(octalChannel(entry.channel))
                        Text(octalWord(entry.value))
                    }
                }
            }
            .font(.system(.caption, design: .monospaced))
        }
    }

    @ViewBuilder
    private var recentBranchesContent: some View {
        if viewModel.backtraceTail.isEmpty {
            Text("Run cycles to populate the branch trace.")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(viewModel.backtraceTail) { entry in
                    Text("\(entry.cycle.formatted())  \(octalRegister(entry.source)) -> \(octalRegister(entry.target))  tag \(String(format: "%03o", entry.tag))")
                }
            }
            .font(.system(.caption, design: .monospaced))
        }
    }

    private func inspectorGroup<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var inspectorDivider: some View {
        Divider()
            .padding(.vertical, 18)
    }

    private func missionPanel<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(panelFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(panelStroke)
    }

    private func metricPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: 180, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

    private func traceEntries(limit: Int?) -> [AGCChannelTraceEntry] {
        guard let limit else { return viewModel.latestChannelTrace }
        return Array(viewModel.latestChannelTrace.suffix(limit))
    }

    private func octalRegister(_ value: Int) -> String {
        String(format: "%06o", value & 0o177777)
    }

    private func octalWord(_ value: Int) -> String {
        String(format: "%05o", value & 0o77777)
    }

    private func octalChannel(_ value: Int) -> String {
        String(format: "%03o", value)
    }

    private var dashboardColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)]
    }

    private var panelFill: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    private var panelStroke: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
    }

    private var statusSymbol: String {
        switch viewModel.status {
        case .empty: "circle"
        case .idle: "checkmark.circle"
        case .running: "play.circle.fill"
        case .stopped: "pause.circle"
        case .error: "exclamationmark.triangle"
        }
    }

    private var statusTint: Color {
        switch viewModel.status {
        case .running:
            return .green
        case .stopped:
            return .orange
        case .error:
            return .red
        case .idle:
            return .primary
        case .empty:
            return .secondary
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
            HStack(spacing: 7) {
                Circle()
                    .frame(width: 9, height: 9)
                    .foregroundStyle(state.lampTest ? .yellow : (isOn ? .yellow : Color.secondary.opacity(0.45)))
                    .opacity(label == nil ? 0.25 : 1)
                Text(label ?? " ")
                    .font(.caption)
                    .foregroundStyle(label == nil ? .secondary : .primary)
                    .opacity(label == nil ? 0.4 : 1)
            }
            .frame(width: 132, alignment: .leading)
        } else {
            Spacer(minLength: 132)
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
}

struct DSKYKeyButtonStyle: ButtonStyle {
    let accent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(accent ? Color.accentColor : Color.primary)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if accent {
            return Color.accentColor.opacity(isPressed ? 0.35 : 0.22)
        }
        return Color(nsColor: .textBackgroundColor).opacity(isPressed ? 0.75 : 1)
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
