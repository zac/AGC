import Foundation

public enum LMP66FlightRecorderError: Error, Equatable, Sendable {
    case didNotReachP65(program: Int?)
    case didNotReachP66(program: Int?)
    case noSurfaceContact
    case landingFailed(LMFlightOutcome)
}

public enum LMP66FlightRecorder {
    /// Runs the verified automatic approach through P65, switches the modeled
    /// panel to ATT HOLD, and records the deterministic ACA/ROD-controlled P66
    /// terminal descent through physical surface contact.
    public static func record(
        binFile: URL,
        scenario: LMPoweredDescentScenario = .apollo11SourceBacked,
        pilot: LMP66Pilot = LMP66Pilot()
    ) async throws -> LMFlightRecording {
        let runtime = try LMSimulationRuntime(binFile: binFile, scenario: scenario)
        var snapshot = await runtime.bootAndEnterP63()
        let dt = LMSimulationPace.acceleratedDeltaSeconds
        let p65Deadline = Luminary99LandingPadLoad.guidDurnCentiseconds / 100.0 + 180.0

        while snapshot.timeSeconds < p65Deadline,
              snapshot.agc.dsky.programNumber != 65,
              !snapshot.vehicleState.flightOutcome.isTerminal {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .autoLand(from: snapshot.vehicleState)
            )
        }
        guard snapshot.agc.dsky.programNumber == 65 else {
            throw LMP66FlightRecorderError.didNotReachP65(
                program: snapshot.agc.dsky.programNumber
            )
        }

        var frames = [LMFlightFrame(snapshot: snapshot)]
        var handController = pilot.attitudeController(for: snapshot.vehicleState)
        snapshot = await runtime.step(
            deltaTime: dt,
            input: .astronautLand(
                from: snapshot.vehicleState,
                panelState: .p66AttitudeHold,
                attitudeController: handController,
                descendPlus: true
            )
        )
        frames.append(LMFlightFrame(snapshot: snapshot))

        for _ in 0..<80 where snapshot.agc.dsky.programNumber != 66 {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .astronautLand(
                    from: snapshot.vehicleState,
                    panelState: .p66AttitudeHold,
                    attitudeController: handController
                )
            )
            frames.append(LMFlightFrame(snapshot: snapshot))
        }
        guard snapshot.agc.dsky.programNumber == 66 else {
            throw LMP66FlightRecorderError.didNotReachP66(
                program: snapshot.agc.dsky.programNumber
            )
        }

        // Give GUILDENSTERN time to establish P66, then exercise one explicit
        // ROD closure and release before the closed-loop terminal profile.
        for _ in 0..<4 {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .astronautLand(
                    from: snapshot.vehicleState,
                    panelState: .p66AttitudeHold,
                    attitudeController: handController
                )
            )
            frames.append(LMFlightFrame(snapshot: snapshot))
        }
        snapshot = await runtime.step(
            deltaTime: dt,
            input: .astronautLand(
                from: snapshot.vehicleState,
                panelState: .p66AttitudeHold,
                attitudeController: handController,
                descendPlus: true
            )
        )
        frames.append(LMFlightFrame(snapshot: snapshot))
        for _ in 0..<20 {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .astronautLand(
                    from: snapshot.vehicleState,
                    panelState: .p66AttitudeHold,
                    attitudeController: handController
                )
            )
            frames.append(LMFlightFrame(snapshot: snapshot))
        }

        let contactDeadline = snapshot.timeSeconds + 180
        var manualStep = 0
        while snapshot.timeSeconds < contactDeadline,
              !snapshot.vehicleState.flightOutcome.isTerminal {
            handController = pilot.attitudeController(
                for: snapshot.vehicleState,
                frameIndex: manualStep
            )
            let descentRateController = pilot.descentRateController(
                for: snapshot.vehicleState,
                frameIndex: manualStep
            )
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .astronautLand(
                    from: snapshot.vehicleState,
                    panelState: .p66AttitudeHold,
                    attitudeController: handController,
                    descendPlus: descentRateController.descendPlus,
                    descendMinus: descentRateController.descendMinus
                )
            )
            frames.append(LMFlightFrame(snapshot: snapshot))
            manualStep += 1
        }

        guard snapshot.vehicleState.surfaceContact != nil else {
            throw LMP66FlightRecorderError.noSurfaceContact
        }
        guard snapshot.vehicleState.flightOutcome == .softLanding else {
            throw LMP66FlightRecorderError.landingFailed(snapshot.vehicleState.flightOutcome)
        }
        return LMFlightRecording(controlMode: .astronautP66, frames: frames)
    }
}
