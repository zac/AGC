import SwiftUI
import AGC

struct MissionControlDSKYConsole: View {
    @Bindable var viewModel: MissionControlViewModel

    var body: some View {
        MissionControlChrome.missionPanel(title: "DSKY", systemImage: "rectangle.grid.3x2") {
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
                    Text("Ch11 \(MissionControlChrome.octalWord(dsky.channel11))")
                    Text("Ch13 \(MissionControlChrome.octalWord(dsky.channel13))")
                    Text("Ch163 \(MissionControlChrome.octalWord(dsky.channel163))")
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
