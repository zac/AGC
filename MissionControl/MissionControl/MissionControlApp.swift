//
//  MissionControlApp.swift
//  MissionControl
//
//  Created by Zac White on 11/7/25.
//

import SwiftUI
import AGC
import LMCore

@main
struct MissionControlApp: App {
    @State private var viewModel = MissionControlViewModel()
    
    var body: some Scene {
        WindowGroup {
            MissionControlRootView(viewModel: viewModel)
        }
        .windowStyle(.automatic)

        Window("Event Log", id: "event-log") {
            EventLogWindow(viewModel: viewModel)
        }

        .commands {
            MissionControlCommands(viewModel: viewModel)
        }
    }
}

@MainActor
struct MissionControlCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let viewModel: MissionControlViewModel

    var body: some Commands {
        CommandMenu("AGC") {
            Button("Load Luminary099") {
                viewModel.loadSampleProgram()
            }
            .disabled(!viewModel.hasSampleProgram)
            .keyboardShortcut("l", modifiers: [.command, .option])

            Divider()

            Button(viewModel.isRunning ? "Stop" : "Start") {
                viewModel.isRunning ? viewModel.stop() : viewModel.start()
            }
            .disabled(viewModel.selectedURL == nil)
            .keyboardShortcut(.return, modifiers: [.command])

            Button("Step 1K") {
                viewModel.runCycles(1_000)
            }
            .disabled(!viewModel.canStep)
            .keyboardShortcut("1", modifiers: [.command])

            Button("Run 100K") {
                viewModel.runCycles(100_000)
            }
            .disabled(!viewModel.canStep)
            .keyboardShortcut("2", modifiers: [.command])

            Divider()

            Button("Reset Runtime") {
                viewModel.reset()
            }
            .disabled(!viewModel.canReset)
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        CommandMenu("LM") {
            Button("Reset Powered Descent") {
                viewModel.resetPoweredDescentScenario()
            }
            .disabled(!viewModel.canReset)

            Button("Step LM Frame") {
                viewModel.stepPoweredDescentFrame()
            }
            .disabled(!viewModel.canStep)
            .keyboardShortcut("]", modifiers: [.command])

            Button("Run LM Segment") {
                viewModel.runPoweredDescentSegment()
            }
            .disabled(!viewModel.canStep)
            .keyboardShortcut("]", modifiers: [.command, .shift])

            Button("Export Trace JSON") {
                viewModel.exportSimulationTraceJSON()
            }
            .disabled(viewModel.latestSimulationTrace.isEmpty)

            Button("Export Channel Trace Text") {
                viewModel.exportChannelTrace()
            }
            .disabled(viewModel.latestChannelTrace.isEmpty)

            Divider()

            ForEach(viewModel.poweredDescentScenario.checkpoints) { checkpoint in
                Button("Enter P\(checkpoint.program)") {
                    viewModel.sendPoweredDescentProgram(checkpoint)
                }
                .disabled(viewModel.selectedURL == nil)
            }
        }

        CommandGroup(after: .windowArrangement) {
            Button("Event Log") {
                openWindow(id: "event-log")
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}
