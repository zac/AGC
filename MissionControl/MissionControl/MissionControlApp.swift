//
//  MissionControlApp.swift
//  MissionControl
//
//  Created by Zac White on 11/7/25.
//

import SwiftUI

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
            MissionControlCommands()
        }
    }
}

struct MissionControlCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button("Event Log") {
                openWindow(id: "event-log")
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}
