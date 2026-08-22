import Foundation
import Darwin
import LMCore

@main
struct LMFlightRecorderCommand {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 || arguments.count == 4 else {
            FileHandle.standardError.write(
                Data("usage: LMFlightRecorder [--automatic|--p66] <Luminary099.bin> <output.json>\n".utf8)
            )
            exit(64)
        }

        let mode = arguments.count == 4 ? arguments[1] : "--p66"
        guard mode == "--automatic" || mode == "--p66" else {
            FileHandle.standardError.write(Data("unknown mode: \(mode)\n".utf8))
            exit(64)
        }
        let pathIndex = arguments.count == 4 ? 2 : 1
        let binFile = URL(fileURLWithPath: arguments[pathIndex])
        let output = URL(fileURLWithPath: arguments[pathIndex + 1])
        let recording: LMFlightRecording
        if mode == "--automatic" {
            recording = try await LMAutomaticFlightRecorder.record(binFile: binFile)
        } else {
            recording = try await LMP66FlightRecorder.record(binFile: binFile)
        }
        try recording.encoded().write(to: output, options: .atomic)

        let final = recording.frames.last?.vehicleState
        print(
            "recorded \(recording.frames.count) frames, "
                + String(format: "%.1f seconds, outcome=%@", recording.durationSeconds,
                         final?.flightOutcome.rawValue ?? "missing")
        )
    }
}
