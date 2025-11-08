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
    }
}
