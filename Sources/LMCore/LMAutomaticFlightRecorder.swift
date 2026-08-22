import Foundation

public enum LMAutomaticFlightRecorderError: Error, Equatable, Sendable {
    case didNotReachP65(program: Int?)
    case noSurfaceContact
    case landingFailed(LMFlightOutcome)
}

public enum LMAutomaticFlightRecorder {
    /// Records the deterministic P65 automatic terminal descent through
    /// physical surface contact. P63 and P64 still run closed-loop to establish
    /// the exact initial state for the recording.
    public static func record(
        binFile: URL,
        scenario: LMPoweredDescentScenario = .apollo11SourceBacked
    ) async throws -> LMFlightRecording {
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
        guard snapshot.agc.dsky.programNumber == 65 else {
            throw LMAutomaticFlightRecorderError.didNotReachP65(
                program: snapshot.agc.dsky.programNumber
            )
        }

        var frames = [LMFlightFrame(snapshot: snapshot)]
        while snapshot.timeSeconds < deadline,
              !snapshot.vehicleState.flightOutcome.isTerminal {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .autoLand(from: snapshot.vehicleState)
            )
            frames.append(LMFlightFrame(snapshot: snapshot))
        }

        guard snapshot.vehicleState.surfaceContact != nil else {
            throw LMAutomaticFlightRecorderError.noSurfaceContact
        }
        guard snapshot.vehicleState.flightOutcome == .softLanding else {
            throw LMAutomaticFlightRecorderError.landingFailed(
                snapshot.vehicleState.flightOutcome
            )
        }
        return LMFlightRecording(controlMode: .automatic, frames: frames)
    }
}
