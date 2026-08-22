import Foundation
import Darwin
import LMCore

@main
struct LMFlightRecorderCommand {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            FileHandle.standardError.write(
                Data("usage: LMFlightRecorder <Luminary099.bin> <output.json>\n".utf8)
            )
            exit(64)
        }

        let binFile = URL(fileURLWithPath: arguments[1])
        let output = URL(fileURLWithPath: arguments[2])
        let recording = try await LMP66FlightRecorder.record(binFile: binFile)
        try recording.encoded().write(to: output, options: .atomic)

        let final = recording.frames.last?.vehicleState
        print(
            "recorded \(recording.frames.count) frames, "
                + String(format: "%.1f seconds, outcome=%@", recording.durationSeconds,
                         final?.flightOutcome.rawValue ?? "missing")
        )
    }
}
