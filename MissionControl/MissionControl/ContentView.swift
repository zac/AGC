//
//  ContentView.swift
//  MissionControl
//
//  Created by Zac White on 11/7/25.
//

import SwiftUI
import UniformTypeIdentifiers

enum MissionControlSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case dsky
    case telemetry
    case lmDynamics
    case validation
    case debugger
    case trace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .dsky: "DSKY"
        case .telemetry: "Telemetry"
        case .lmDynamics: "LM Dynamics"
        case .validation: "Validation"
        case .debugger: "Debugger"
        case .trace: "Channel Trace"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: "Runtime, DSKY, and health"
        case .dsky: "Display and keypad"
        case .telemetry: "Cycles, LM outputs, and registers"
        case .lmDynamics: "Vehicle state and powered descent"
        case .validation: "Smoke checks and branch trace"
        case .debugger: "Disassembly, breakpoints, and watches"
        case .trace: "Ordered AGC channel traffic"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .dsky: "rectangle.grid.3x2"
        case .telemetry: "waveform.path.ecg"
        case .lmDynamics: "gyroscope"
        case .validation: "checkmark.seal"
        case .debugger: "pause.circle"
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
                    MissionControlDSKYConsole(viewModel: viewModel)
                    MissionControlDashboard(
                        viewModel: viewModel,
                        section: activeSection,
                        isImporterPresented: $isImporterPresented
                    )
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
                MissionControlDashboard(
                    viewModel: viewModel,
                    section: activeSection,
                    isImporterPresented: $isImporterPresented
                ).inspector
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
                    viewModel.stepInstruction()
                } label: {
                    Label("Step instruction", systemImage: "arrow.turn.up.right")
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

            MissionControlChrome.metricPill(label: "Cycle", value: viewModel.latestSnapshot.map { $0.cycle.formatted() } ?? "0")
            MissionControlChrome.metricPill(label: "Image", value: viewModel.selectedURL?.lastPathComponent ?? "None")

            Button {
                openWindow(id: "event-log")
            } label: {
                Label("Event Log", systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MissionControlChrome.panelFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(MissionControlChrome.panelStroke)
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
}

#Preview {
    MissionControlRootView(viewModel: MissionControlViewModel())
}
