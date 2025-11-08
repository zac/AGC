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

    @ObservationIgnored
    private var agc: AGC?
    
    var canStart: Bool { agc != nil && !isRunning }
    var canStop: Bool { isRunning }
    var canReset: Bool { agc != nil }
    
    func loadProgram(from url: URL) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer {
            if needsAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            agc = try AGC(binFile: url)
            selectedURL = url
            let data = try Data(contentsOf: url)
            let wordCount = data.count / 2
            programSummary = "\(url.lastPathComponent) – \(wordCount) words (\(data.count) bytes)"
            status = .idle
            isRunning = false
        } catch {
            agc = nil
            status = .error(error.localizedDescription)
        }
    }
    
    func clearProgram() {
        stop()
        agc = nil
        selectedURL = nil
        status = .empty
        programSummary = "No program loaded"
    }
    
    func start() {
        guard canStart else { return }
        agc?.start()
        isRunning = true
        status = .running
    }
    
    func stop() {
        guard canStop else { return }
        agc?.stop()
        isRunning = false
        status = .stopped
    }
    
    func reset() {
        guard let url = selectedURL else { return }
        stop()
        loadProgram(from: url)
    }
}

struct MissionControlRootView: View {
    @State var viewModel: MissionControlViewModel
    @State private var isImporterPresented = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            programSection
            controlSection
            statusSection
            Spacer()
        }
        .frame(minWidth: 520, minHeight: 360)
        .padding(24)
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
                    Text("No program selected")
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(viewModel.selectedURL == nil ? "Open…" : "Change…") {
                    isImporterPresented = true
                }
                if viewModel.selectedURL != nil {
                    Button(role: .destructive) {
                        viewModel.clearProgram()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var controlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Controls")
                .font(.headline)
            HStack(spacing: 16) {
                Button {
                    viewModel.start()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .disabled(!viewModel.canStart)
                
                Button {
                    viewModel.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(!viewModel.canStop)
                
                Button {
                    viewModel.reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .disabled(!viewModel.canReset)
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
}

#Preview {
    MissionControlRootView(viewModel: MissionControlViewModel())
}
