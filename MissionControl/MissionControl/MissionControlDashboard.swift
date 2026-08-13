import SwiftUI
import AGC
import LMCore

struct MissionControlDashboard: View {
    @Bindable var viewModel: MissionControlViewModel
    var section: MissionControlSection
    @Binding var isImporterPresented: Bool

    var body: some View {
        switch section {
        case .overview:
            overviewSection
        case .dsky:
            dskyDetailSection
        case .telemetry:
            telemetrySection
        case .lmDynamics:
            lmDynamicsSection
        case .validation:
            validationDetailSection
        case .debugger:
            MissionControlDebuggerView(viewModel: viewModel)
        case .trace:
            traceDetailSection
        }
    }

    private var overviewSection: some View {
        LazyVGrid(columns: MissionControlChrome.dashboardColumns, alignment: .leading, spacing: 16) {
            programPanel
            engineTelemetryPanel
            validationPanel
            lmVehiclePanel
            lmDynamicsPanel
        }
    }

    private var dskyDetailSection: some View {
        LazyVGrid(columns: MissionControlChrome.dashboardColumns, alignment: .leading, spacing: 16) {
            channelTracePanel(limit: 18)
            validationPanel
        }
    }

    private var telemetrySection: some View {
        LazyVGrid(columns: MissionControlChrome.dashboardColumns, alignment: .leading, spacing: 16) {
            engineTelemetryPanel
            lmVehiclePanel
            lmDynamicsPanel
            processorPanel
            recentBranchesPanel
        }
    }

    private var lmDynamicsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: MissionControlChrome.dashboardColumns, alignment: .leading, spacing: 16) {
                lmDynamicsPanel
                poweredDescentPanel
                lmVehiclePanel
                sourceStatusPanel
            }
            channelTracePanel(limit: 30)
        }
    }

    private var validationDetailSection: some View {
        LazyVGrid(columns: MissionControlChrome.dashboardColumns, alignment: .leading, spacing: 16) {
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

    var inspector: some View {
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
        MissionControlChrome.missionPanel(title: "Program", systemImage: "shippingbox") {
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
        MissionControlChrome.missionPanel(title: "Engine Telemetry", systemImage: "waveform.path.ecg") {
            if let health = viewModel.engineHealth {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) {
                    MissionControlChrome.gridRow(label: "Cycle counter", value: health.cycle.formatted())
                    MissionControlChrome.gridRow(
                        label: "Throughput",
                        value: health.cyclesPerSecond > 0
                            ? String(format: "%.2f M cycles/s", health.cyclesPerSecond / 1_000_000)
                            : "-"
                    )
                    MissionControlChrome.gridRow(
                        label: "Stepping",
                        value: viewModel.isRunning
                            ? (health.isAdvancing ? "Batches advancing" : "No advance")
                            : "CPU idle"
                    )
                    if let lm = health.lmOutputs {
                        MissionControlChrome.gridRow(label: "LM OUT0", value: MissionControlChrome.octalWord(lm.out0))
                        MissionControlChrome.gridRow(label: "LM OUT1", value: MissionControlChrome.octalWord(lm.out1))
                        MissionControlChrome.gridRow(label: "RCS commands", value: "\(lm.rcsJets.count)")
                    }
                    MissionControlChrome.gridRow(label: "Radar data hooks", value: "\(viewModel.radarHookInvocations)")
                }
                .font(.system(.body, design: .monospaced))
            } else {
                Text("Run cycles to see throughput, vehicle outputs, and integration callbacks.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var validationPanel: some View {
        MissionControlChrome.missionPanel(title: "Validation", systemImage: "checkmark.seal") {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 7) {
                MissionControlChrome.validationRow(
                    label: "Program loaded",
                    isPassing: viewModel.selectedURL != nil,
                    detail: viewModel.selectedURL?.lastPathComponent ?? "No core image"
                )
                MissionControlChrome.validationRow(
                    label: "CPU cycle source",
                    isPassing: (viewModel.engineHealth?.cycle ?? 0) > 0,
                    detail: viewModel.engineHealth.map { "\($0.cycle.formatted()) cycles" } ?? "No cycles run"
                )
                MissionControlChrome.validationRow(
                    label: "DSKY delegate",
                    isPassing: viewModel.latestDSKY != nil,
                    detail: viewModel.latestDSKY == nil ? "Not connected" : "Connected"
                )
                MissionControlChrome.validationRow(
                    label: "Backtrace",
                    isPassing: !viewModel.backtraceTail.isEmpty,
                    detail: viewModel.backtraceTail.isEmpty ? "No branches observed" : "\(viewModel.backtraceTail.count) recent entries"
                )
            }
            .font(.system(.caption, design: .monospaced))
        }
    }

    private var lmVehiclePanel: some View {
        MissionControlChrome.missionPanel(title: "LM Vehicle Outputs", systemImage: "gyroscope") {
            if let lm = viewModel.engineHealth?.lmOutputs {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        MissionControlChrome.gridRow(label: "OUT0 / ch 005", value: MissionControlChrome.octalWord(lm.out0))
                        MissionControlChrome.gridRow(label: "OUT1 / ch 006", value: MissionControlChrome.octalWord(lm.out1))
                        MissionControlChrome.gridRow(label: "Ch 011", value: MissionControlChrome.octalWord(lm.outputChannel11))
                        MissionControlChrome.gridRow(label: "Ch 012", value: MissionControlChrome.octalWord(lm.outputChannel12))
                        MissionControlChrome.gridRow(label: "Ch 013", value: MissionControlChrome.octalWord(lm.outputChannel13))
                        MissionControlChrome.gridRow(label: "Ch 014", value: MissionControlChrome.octalWord(lm.outputChannel14))
                        MissionControlChrome.gridRow(label: "Input ch 016", value: MissionControlChrome.octalWord(lm.inputChannel16))
                        MissionControlChrome.gridRow(label: "Main engine", value: lm.mainEngineOn ? "ON command" : (lm.mainEngineOff ? "OFF command" : "No command"))
                        MissionControlChrome.gridRow(label: "Thrust drive", value: lm.thrustDriveActive ? "Active" : "Inactive")
                        MissionControlChrome.gridRow(label: "Throttle map", value: lm.dps.throttleMappingStatus.isSourceBacked ? "source-backed" : "unmodeled")
                        MissionControlChrome.gridRow(
                            label: "Commanded thrust",
                            value: lm.dps.commandedThrustNewtons.map { String(format: "%.0f N", $0) } ?? "engine off / 0"
                        )
                        MissionControlChrome.gridRow(label: "Unmapped bits", value: "\(lm.unmappedBits.count)")
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
                                Text("Jet \(command.jet.rawValue)  \(command.axis.rawValue)  ch \(MissionControlChrome.octalChannel(command.channel)) bit \(command.bit)")
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
                                Text("\(group.name)  \(MissionControlChrome.octalWord(group.mask))")
                            }
                        }
                        .font(.system(.caption, design: .monospaced))
                    }

                    let namedCommands = lm.mainEngineCommands + lm.gimbalTrimCommands + lm.controlCommands + lm.descentRateCommands
                    if !namedCommands.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Named commands")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(Array(namedCommands.enumerated()), id: \.offset) { _, command in
                                Text("\(command.name)  ch \(MissionControlChrome.octalChannel(command.channel)) bit \(command.bit)")
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

    private var lmDynamicsPanel: some View {
        MissionControlChrome.missionPanel(title: "LM Dynamics", systemImage: "scope") {
            if let simulation = viewModel.latestLMSimulation {
                let state = simulation.vehicleState
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        MissionControlChrome.gridRow(label: "Altitude", value: MissionControlChrome.meters(state.altitudeMeters))
                        MissionControlChrome.gridRow(label: "Vertical speed", value: MissionControlChrome.metersPerSecond(state.verticalSpeedMetersPerSecond))
                        MissionControlChrome.gridRow(label: "Position", value: MissionControlChrome.vector(state.positionMeters))
                        MissionControlChrome.gridRow(label: "Velocity", value: MissionControlChrome.vector(state.velocityMetersPerSecond))
                        MissionControlChrome.gridRow(label: "Angular rate", value: MissionControlChrome.vector(state.angularVelocityRadiansPerSecond))
                        MissionControlChrome.gridRow(label: "Attitude q", value: MissionControlChrome.quaternion(state.attitude))
                        MissionControlChrome.gridRow(label: "Mass", value: state.massKilograms.map(MissionControlChrome.kilograms) ?? "unmodeled")
                        MissionControlChrome.gridRow(label: "Propellant", value: state.propellantMassKilograms.map(MissionControlChrome.kilograms) ?? "unmodeled")
                        MissionControlChrome.gridRow(label: "Contact", value: state.isLanded ? "landed" : "in flight")
                    }
                    .font(.system(.caption, design: .monospaced))

                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        MissionControlChrome.gridRow(label: "Radar RNDZ", value: rawRadarWord(simulation.sensorState.radarInput, keyPath: \.rendezvousRadarWord))
                        MissionControlChrome.gridRow(label: "Radar ALT", value: rawRadarWord(simulation.sensorState.radarInput, keyPath: \.altitudeMeterWord))
                        MissionControlChrome.gridRow(label: "Radar input", value: radarInputDescription(simulation.sensorState.radarInput))
                        MissionControlChrome.gridRow(label: "Radar conversion", value: radarStatusDescription(simulation.sensorState.radarInput))
                        MissionControlChrome.gridRow(
                            label: "RHC",
                            value: "\(simulation.sensorState.rotationalHandControllerInput.pitch), \(simulation.sensorState.rotationalHandControllerInput.yaw), \(simulation.sensorState.rotationalHandControllerInput.roll)"
                        )
                        MissionControlChrome.gridRow(label: "Ch 016", value: MissionControlChrome.octalWord(simulation.sensorState.descentRateChannel16))
                    }
                    .font(.system(.caption, design: .monospaced))
                }
            } else {
                Text("Load a core image to initialize LM dynamics.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var poweredDescentPanel: some View {
        MissionControlChrome.missionPanel(title: "Powered Descent", systemImage: "arrow.down.to.line.compact") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Button("Reset Scenario") {
                        viewModel.resetPoweredDescentScenario()
                    }
                    .disabled(!viewModel.canReset)

                    Button("Step Frame") {
                        viewModel.stepPoweredDescentFrame()
                    }
                    .disabled(!viewModel.canStep)

                    Button("Run 10s") {
                        viewModel.runPoweredDescentSegment()
                    }
                    .disabled(!viewModel.canStep)

                    Button("Export JSON") {
                        viewModel.exportSimulationTraceJSON()
                    }
                    .disabled(viewModel.latestSimulationTrace.isEmpty)

                    Button("Export Ch Text") {
                        viewModel.exportChannelTrace()
                    }
                    .disabled(viewModel.latestChannelTrace.isEmpty)
                }
                .controlSize(.small)

                Text(viewModel.poweredDescentScenario.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.poweredDescentScenario.checkpoints) { checkpoint in
                        HStack(spacing: 10) {
                            Button("P\(checkpoint.program)") {
                                viewModel.sendPoweredDescentProgram(checkpoint)
                            }
                            .disabled(viewModel.selectedURL == nil)
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(checkpoint.expectedScript.id)
                                    .font(.system(.caption, design: .monospaced))
                                Text(checkpointActualStatus(checkpoint))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var sourceStatusPanel: some View {
        MissionControlChrome.missionPanel(title: "Source Status", systemImage: "doc.text.magnifyingglass") {
            if let simulation = viewModel.latestLMSimulation {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sources")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(simulation.sourceStatus.sources.prefix(5)) { source in
                            Text(source.title)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        if simulation.sourceStatus.sources.count > 5 {
                            Text("+ \(simulation.sourceStatus.sources.count - 5) more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Unmodeled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if simulation.sourceStatus.unmodeledItems.isEmpty {
                            Text("No unmodeled items reported for this snapshot.")
                                .font(.caption)
                        } else {
                            ForEach(Array(simulation.sourceStatus.unmodeledItems.prefix(7).enumerated()), id: \.offset) { _, item in
                                Text(item)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            } else {
                Text("No source status yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var processorPanel: some View {
        MissionControlChrome.missionPanel(title: "Processor Snapshot", systemImage: "cpu") {
            processorContent
        }
    }

    private func channelTracePanel(limit: Int?) -> some View {
        MissionControlChrome.missionPanel(title: "Channel Trace", systemImage: "list.bullet.rectangle") {
            channelTraceContent(limit: limit)
        }
    }

    private var recentBranchesPanel: some View {
        MissionControlChrome.missionPanel(title: "Recent Branches", systemImage: "arrow.triangle.branch") {
            recentBranchesContent
        }
    }

    @ViewBuilder
    private var processorContent: some View {
        if let snapshot = viewModel.registerSnapshot {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) {
                MissionControlChrome.gridRow(label: "Cycle", value: snapshot.cycle.formatted())
                MissionControlChrome.gridRow(label: "A", value: MissionControlChrome.octalRegister(snapshot.accumulator))
                MissionControlChrome.gridRow(label: "L", value: MissionControlChrome.octalRegister(snapshot.l))
                MissionControlChrome.gridRow(label: "Q", value: MissionControlChrome.octalRegister(snapshot.q))
                MissionControlChrome.gridRow(label: "Z", value: MissionControlChrome.octalRegister(snapshot.z))
                MissionControlChrome.gridRow(label: "BB", value: MissionControlChrome.octalRegister(snapshot.index))
                MissionControlChrome.gridRow(label: "Flags", value: snapshot.statusFlags)
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
                        Text(MissionControlChrome.octalChannel(entry.channel))
                        Text(MissionControlChrome.octalWord(entry.value))
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
                    Text("\(entry.cycle.formatted())  \(MissionControlChrome.octalRegister(entry.source)) -> \(MissionControlChrome.octalRegister(entry.target))  tag \(String(format: "%03o", entry.tag))")
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

    private func checkpointActualStatus(_ checkpoint: LMPoweredDescentCheckpoint) -> String {
        guard let result = viewModel.latestValidationResult?.checkpointResults.first(where: { $0.id == checkpoint.id }) else {
            return "Expected \(checkpoint.expectedScript.id); no validation samples yet"
        }

        let prefix: String
        switch result.status {
        case .observed:
            prefix = "Observed"
        case .partial:
            prefix = "Partial"
        case .notObserved:
            prefix = "Waiting"
        }
        return ([prefix] + result.evidence).joined(separator: ": ")
    }

    private func radarInputDescription(_ input: LMRadarInput?) -> String {
        guard let input else { return "-" }
        switch input {
        case .raw:
            return "raw AGC words"
        case .measurement:
            return "SI measurement"
        }
    }

    private func radarStatusDescription(_ input: LMRadarInput?) -> String {
        guard let input else { return "-" }
        return input.conversionStatus.isSourceBacked ? "source-backed" : "unmodeled"
    }

    private func rawRadarWord(_ input: LMRadarInput?, keyPath: KeyPath<LMRadarRawInput, Int?>) -> String {
        guard case .raw(let raw) = input else { return "-" }
        return raw[keyPath: keyPath].map(MissionControlChrome.octalWord) ?? "-"
    }

    private func traceEntries(limit: Int?) -> [AGCChannelTraceEntry] {
        guard let limit else { return viewModel.latestChannelTrace }
        return Array(viewModel.latestChannelTrace.suffix(limit))
    }
}
