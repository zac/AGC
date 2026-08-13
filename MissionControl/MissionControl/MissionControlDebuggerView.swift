import SwiftUI
import AGC

struct MissionControlDebuggerView: View {
    @Bindable var viewModel: MissionControlViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            controls
            if let debug = viewModel.latestDebugger {
                currentInstruction(debug)
                listing(debug)
                watches(debug)
                packets(debug)
            } else {
                Text("Load a core image to disassemble Z and step instructions.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Step instruction") {
                    viewModel.stepInstruction()
                }
                .disabled(!viewModel.canStep)

                Button("Clear breakpoints") {
                    viewModel.clearDebuggerBreakpoints()
                }
                .disabled(viewModel.runtimeMissing)
            }

            HStack {
                TextField("Breakpoint Z", text: $viewModel.breakpointOctal)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .font(.system(.body, design: .monospaced))
                Button("Add") { viewModel.addBreakpointFromField() }
                    .disabled(viewModel.runtimeMissing)
            }

            HStack {
                TextField("Watch E", text: $viewModel.watchOctal)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .font(.system(.body, design: .monospaced))
                Button("Watch") { viewModel.addWatchFromField() }
                    .disabled(viewModel.runtimeMissing)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func currentInstruction(_ debug: AGCDebuggerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Current")
                .font(.headline)
            Text(debug.current.text)
                .font(.system(.title3, design: .monospaced))
            Text("extraCode \(debug.extraCode ? "yes" : "no")   ISR \(debug.inIsr ? "yes" : "no")   hit \(debug.hitBreakpoint ? "yes" : "no")")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !debug.breakpoints.isEmpty {
                Text("Breakpoints: " + debug.breakpoints.map { String(format: "%04o", $0) }.joined(separator: "  "))
                    .font(.system(.caption, design: .monospaced))
            }
        }
    }

    private func listing(_ debug: AGCDebuggerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Listing around Z")
                .font(.headline)
            ForEach(debug.listing, id: \.address) { line in
                Text(line.text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(line.address == debug.current.address ? Color.primary : Color.secondary)
            }
        }
    }

    private func watches(_ debug: AGCDebuggerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Erasable watches")
                .font(.headline)
            if debug.watches.isEmpty {
                Text("No watches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(debug.watches) { watch in
                    Text(String(format: "E%04o  %06o", watch.address, watch.value))
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
    }

    private func packets(_ debug: AGCDebuggerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("yaAGC packets")
                .font(.headline)
            if debug.yaAGCPackets.isEmpty {
                Text("No recent channel traffic.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(debug.yaAGCPackets.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
    }
}

extension MissionControlViewModel {
    var runtimeMissing: Bool { selectedURL == nil }
}
