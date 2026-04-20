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
    @ObservationIgnored private var dsky: DSKY?
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
            
            // Create and connect DSKY
            let dskyInstance = DSKY(agcEngine: agc?.engine)
            self.dsky = dskyInstance
            agc?.engine.ioDelegate = dskyInstance
            
            selectedURL = url
            let data = try Data(contentsOf: url)
            let wordCount = data.count / 2
            programSummary = "\(url.lastPathComponent) – \(wordCount) words (\(data.count) bytes)"
            status = .idle
            isRunning = false
            updateSnapshots(from: agc?.state, dsky: dskyInstance)
        } catch {
            agc = nil
            dsky = nil
            status = .error(error.localizedDescription)
            clearSnapshots()
        }
    }
    
    func clearProgram() {
        stop()
        agc = nil
        dsky = nil
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
        guard let agc, let dsky else { return }
        tickerTask = Task { [weak self] in
            while !(Task.isCancelled) {
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                guard let self else { break }
                updateSnapshots(from: agc.state, dsky: dsky)
            }
        }
    }

    func pressKey(channel: Int, value: Int) {
        guard let dsky else { return }
        // Map keycodes to DSKY keypress methods
        if channel == 0o15 {
            Task {
                await dsky.sendKeycode(value)
                try? await Task.sleep(nanoseconds: 12_000_000) // 12ms
                await dsky.sendKeycode(0)
            }
        } else if channel == 0o13 {
            Task {
                await dsky.sendProKey(value == 0)
            }
        }
    }

    private func updateSnapshots(from state: AGCState?, dsky: DSKY?) {
        if let state {
            latestSnapshot = RegisterSnapshot(state: state)
            if let dsky {
                latestDSKY = DSKYState(dsky: dsky)
            } else {
                latestDSKY = DSKYState(state: state)
            }
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
            HStack {
                dskySection
                keypadSection
            }
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
                            HStack(spacing: 4) {
                                Text(dsky.plusSign ? "+" : "-")
                                    .font(.system(.title3, design: .monospaced))
                                ForEach(dsky.displays, id: \.self) { segment in
                                    Text(segment)
                                        .font(.system(.title3, design: .monospaced))
                                        .frame(width: 36)
                                }
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

struct DSKYState {
    let channel10: Int
    let input11: Int
    let input13: Int
    let output163: Int
    let cycle: UInt64
    let displays: [String]
    let verbDigits: String
    let nounDigits: String
    let plusSign: Bool
    let verbNounFlash: Bool
    let proOn: Bool
    let keyRelOn: Bool
    let lampTest: Bool
    private let indicatorStatuses: [Int: Bool]

    init(state: AGCState) {
        channel10 = state.outputChannels[0o10]
        input11 = state.inputChannels[0o11]
        input13 = state.inputChannels[0o13]
        output163 = state.dskyChannel163
        cycle = state.cycleCounter

        let digits = String(format: "%05o", channel10 & 0o77777)
        displays = [
            String(digits.prefix(2)),
            String(digits.dropFirst(2).prefix(2)),
            String(digits.suffix(1))
        ]
        verbDigits = String(digits.prefix(2))
        nounDigits = String(digits.dropFirst(2).prefix(2))
        plusSign = (channel10 & 0o40000) == 0
        verbNounFlash = (state.inputChannels[0o11] & 0o40) != 0
        proOn = (state.inputChannels[0o13] & 0o40000) != 0
        keyRelOn = (state.inputChannels[0o11] & 0o20) != 0
        lampTest = (state.inputChannels[0o13] & 0o1000) != 0

        var statuses: [Int: Bool] = [:]
        for definition in DSKYIndicatorDefinition.luminaryDefinitions {
            statuses[definition.id] = DSKYIndicatorDefinition.evaluate(definition, state: state)
        }
        indicatorStatuses = statuses
    }
    
    init(dsky: DSKY) {
        // Get display values from DSKY
        channel10 = 0  // Not directly available, but displays are decoded
        input11 = dsky.channel11
        input13 = dsky.channel13
        output163 = dsky.channel163
        cycle = 0  // Not available from DSKY directly
        
        // Format displays from DSKY registers
        let r1Str = dsky.formatRegister(dsky.r1)
        let r2Str = dsky.formatRegister(dsky.r2)
        let r3Str = dsky.formatRegister(dsky.r3)
        
        // Extract digits from formatted strings (format is "+12345" or "-12345")
        displays = [
            String(r1Str.prefix(1)),  // Sign
            String(r1Str.dropFirst(1).prefix(2)),  // First 2 digits
            String(r1Str.dropFirst(3).prefix(2)),  // Next 2 digits
            String(r1Str.suffix(1))   // Last digit
        ]
        
        verbDigits = dsky.formatVerb()
        nounDigits = dsky.formatNoun()
        plusSign = dsky.r1.sign == "+"
        verbNounFlash = dsky.verbNounFlash
        proOn = !dsky.proKeyPressed
        keyRelOn = dsky.indicatorIsOn(14)
        lampTest = dsky.lampTest
        
        // Get indicator statuses from DSKY
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
