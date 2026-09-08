import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import LMCore

@main
struct LMFlightRecorderCommand {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 || arguments.count == 4 else {
            let usage = """
                usage: LMFlightRecorder [--automatic|--p66] <Luminary099.bin> <output.json>
                       LMFlightRecorder --p65-checkpoint <Luminary099.bin> <output.bplist>
                """
            FileHandle.standardError.write(Data((usage + "\n").utf8))
            exit(64)
        }

        let mode = arguments.count == 4 ? arguments[1] : "--p66"
        guard mode == "--automatic" || mode == "--p66" || mode == "--p65-checkpoint" else {
            FileHandle.standardError.write(Data("unknown mode: \(mode)\n".utf8))
            exit(64)
        }
        let pathIndex = arguments.count == 4 ? 2 : 1
        let binFile = URL(fileURLWithPath: arguments[pathIndex])
        let output = URL(fileURLWithPath: arguments[pathIndex + 1])

        if mode == "--p65-checkpoint" {
            try await writeP65Checkpoint(binFile: binFile, output: output)
            return
        }

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

    /// Runs the verified P63→P65 closed loop and writes the runtime checkpoint
    /// at the P65 program transition as a binary property-list fixture.
    private static func writeP65Checkpoint(binFile: URL, output: URL) async throws {
        let scenario = LMPoweredDescentScenario.apollo11SourceBacked
        let runtime = try LMSimulationRuntime(binFile: binFile, scenario: scenario)
        var snapshot = await runtime.bootAndEnterP63()
        let dt = LMSimulationPace.acceleratedDeltaSeconds
        let deadline = Luminary99LandingPadLoad.guidDurnCentiseconds / 100.0 + 240.0

        while snapshot.timeSeconds < deadline,
              snapshot.agc.dsky.programNumber != 65,
              !snapshot.vehicleState.flightOutcome.isTerminal {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .autoLand(from: snapshot.vehicleState)
            )
        }
        guard snapshot.agc.dsky.programNumber == 65, !snapshot.vehicleState.flightOutcome.isTerminal
        else {
            FileHandle.standardError.write(
                Data("closed loop did not reach P65 (program \(snapshot.agc.dsky.programNumber ?? -1))\n".utf8)
            )
            exit(70)
        }

        let checkpoint = await runtime.captureCheckpoint(scenarioID: scenario.id)
        let fixture = try checkpoint.encodedFixture()
        try fixture.write(to: output, options: .atomic)

        let altitudeFeet = snapshot.vehicleState.altitudeMeters * 3.280_839_895
        print(
            String(
                format: "captured P65 at t=%.2f s, altitude=%.0f ft (%.1f m), cycle=%llu, fixture=%d bytes",
                checkpoint.simulationTimeSeconds,
                altitudeFeet,
                snapshot.vehicleState.altitudeMeters,
                checkpoint.agc.cycleCounter,
                fixture.count
            )
        )
    }
}
