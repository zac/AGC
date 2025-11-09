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
    private(set) var latestSnapshot: RegisterSnapshot?
    private(set) var latestDSKY: DSKYState?

    @ObservationIgnored private var agc: AGC?
    @ObservationIgnored private var tickerTask: Task<Void, Never>?
    
    var registerSnapshot: RegisterSnapshot? {
        latestSnapshot
    }
    
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
            updateSnapshots(from: agc?.state)
        } catch {
            agc = nil
            status = .error(error.localizedDescription)
            clearSnapshots()
        }
    }
    
    func clearProgram() {
        stop()
        agc = nil
        selectedURL = nil
        status = .empty
        programSummary = "No program loaded"
        clearSnapshots()
    }
    
    func start() {
        guard canStart else { return }
        agc?.start()
        isRunning = true
        status = .running
        startTicker()
    }
    
    func stop() {
        guard canStop else { return }
        agc?.stop()
        tickerTask?.cancel()
        tickerTask = nil
        isRunning = false
        status = .stopped
    }
    
    func reset() {
        guard let url = selectedURL else { return }
        stop()
        loadProgram(from: url)
    }
    
    private func startTicker() {
        tickerTask?.cancel()
        guard let agc else { return }
        tickerTask = Task { [weak self] in
            while !(Task.isCancelled) {
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                guard let self else { break }
                updateSnapshots(from: agc.state)
            }
        }
    }

    func pressKey(channel: Int, value: Int) {
        agc?.writeChannel(address: channel, value: value)
    }

    private func updateSnapshots(from state: AGCState?) {
        if let state {
            latestSnapshot = RegisterSnapshot(state: state)
            latestDSKY = DSKYState(state: state)
        }
    }

    private func clearSnapshots() {
        latestSnapshot = nil
        latestDSKY = nil
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

struct MissionControlRootView: View {
    @State var viewModel: MissionControlViewModel
    @State private var isImporterPresented = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            programSection
            controlSection
            statusSection
            Divider()
            dskySection
            registersSection
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

    private var dskySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DSKY")
                .font(.headline)
            if let dsky = viewModel.latestDSKY {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Channel 10: \(octal(dsky.channel10))")
                        Text("Channel 11: \(String(format: "%05o", dsky.input11))")
                        Text("Channel 13: \(String(format: "%05o", dsky.input13))")
                        Text("Ch 163: \(String(format: "%05o", dsky.output163))")
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(dskyKeys, id: \.label) { key in
                            Button {
                                viewModel.pressKey(channel: key.channel, value: key.value)
                            } label: {
                                Text(key.label)
                                    .font(.caption)
                                    .padding(6)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(6)
                            }
                        }
                    }
                }
                .font(.system(.body, design: .monospaced))
            } else {
                Text("Program inactive")
                    .foregroundColor(.secondary)
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

    private var dskyKeys: [DSKYKey] {
        [
            DSKYKey(label: "VERB", channel: 0o15, value: 0o040),
            DSKYKey(label: "NOUN", channel: 0o15, value: 0o020),
            DSKYKey(label: "PRO", channel: 0o15, value: 0o010),
            DSKYKey(label: "KEY REL", channel: 0o15, value: 0o100),
            DSKYKey(label: "EXEC", channel: 0o15, value: 0o200),
        ]
    }
}

#Preview {
    MissionControlRootView(viewModel: MissionControlViewModel())
}

struct DSKYState {
    let channel10: Int
    let input11: Int
    let input13: Int
    let output163: Int
    let cycle: UInt64
    init(state: AGCState) {
        channel10 = state.outputChannels[0o10]
        input11 = state.inputChannels[0o11]
        input13 = state.inputChannels[0o13]
        output163 = state.dskyChannel163
        cycle = state.cycleCounter
    }
}

struct DSKYKey {
    let label: String
    let channel: Int
    let value: Int
}
#Preview {
    MissionControlRootView(viewModel: MissionControlViewModel())
}
