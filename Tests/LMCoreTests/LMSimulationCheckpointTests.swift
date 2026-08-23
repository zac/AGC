import Foundation
import Testing

@testable import AGC
@testable import LMCore

/// Checkpoint-resumed flight must be indistinguishable from uninterrupted
/// flight: same program transitions, same trajectory samples, same outcome.
@Suite("LM simulation checkpoints")
struct LMSimulationCheckpointTests {
    private var luminaryROM: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AGCTests/Luminary099.bin")
    }

    private struct P66Run {
        var frames: [LMVehicleStateSnapshot]
        var final: LMSimulationSnapshot
    }

    @Test func `p65 checkpoint resumes the automatic trajectory bit exactly`() async throws {
        let romURL = luminaryROM
        let baseline = try LMSimulationRuntime(binFile: romURL, scenario: .apollo11SourceBacked)
        let p65Baseline = try await reachP65(baseline)
        let checkpoint = await baseline.captureCheckpoint()

        #expect(checkpoint.schemaVersion == LMSimulationCheckpoint.schemaVersion)
        #expect(checkpoint.scenarioID == LMPoweredDescentScenario.apollo11SourceBacked.id)
        #expect(abs(checkpoint.simulationTimeSeconds - p65Baseline.timeSeconds) < 1e-9)
        // Terminal-descent entry altitude for the bundled slice (~143 ft).
        #expect(abs(p65Baseline.vehicleState.altitudeMeters - 43.6) < 25,
                "P65 entry altitude \(p65Baseline.vehicleState.altitudeMeters) m")

        // Refuse tampered fixtures without touching any state.
        let untouched = try LMSimulationRuntime(binFile: romURL, scenario: .apollo11SourceBacked)
        let before = await untouched.snapshot()
        var wrongScenario = checkpoint
        wrongScenario.scenarioID = "some-other-scenario"
        #expect(await refusalError(of: untouched, restoring: wrongScenario)
            == LMSimulationCheckpointError.scenarioMismatch(
                expected: LMPoweredDescentScenario.apollo11SourceBacked.id,
                found: "some-other-scenario"
            ))
        var wrongSchema = checkpoint
        wrongSchema.schemaVersion = LMSimulationCheckpoint.schemaVersion + 1
        #expect(await refusalError(of: untouched, restoring: wrongSchema)
            == LMSimulationCheckpointError.schemaVersionMismatch(
                expected: LMSimulationCheckpoint.schemaVersion,
                found: LMSimulationCheckpoint.schemaVersion + 1
            ))
        let after = await untouched.snapshot()
        #expect(after == before, "refused fixtures must not mutate any state")

        // Continue the baseline to contact while flying the restored fixture.
        let baselineFinal = try await automaticToContact(baseline, from: p65Baseline)

        let resumed = try LMSimulationRuntime(binFile: romURL, scenario: .apollo11SourceBacked)
        let decoded = try LMSimulationCheckpoint.decodeFixture(try checkpoint.encodedFixture())
        let restoredStart = try await resumed.restore(from: decoded)

        #expect(restoredStart.vehicleState == p65Baseline.vehicleState)
        #expect(restoredStart.agc.dsky.programNumber == 65)
        #expect(abs(restoredStart.timeSeconds - p65Baseline.timeSeconds) < 1e-9,
                "restore must resume the simulation clock")

        let resumedFinal = try await automaticToContact(resumed, from: restoredStart)

        #expect(resumedFinal.vehicleState.flightOutcome == .softLanding)
        #expect(resumedFinal.vehicleState == baselineFinal.vehicleState,
                "checkpoint-resumed automatic flight must match the baseline outcome")
    }

    @Test func `p65 checkpoint resumes the p66 crew trajectory bit exactly`() async throws {
        let romURL = luminaryROM
        let baseline = try LMSimulationRuntime(binFile: romURL, scenario: .apollo11SourceBacked)
        let p65Baseline = try await reachP65(baseline)
        let checkpoint = await baseline.captureCheckpoint()

        let baselineRun = try await p66ToContact(baseline, from: p65Baseline)
        #expect(baselineRun.final.vehicleState.flightOutcome == .softLanding)
        #expect(baselineRun.final.vehicleState.surfaceContact != nil)

        let resumed = try LMSimulationRuntime(binFile: romURL, scenario: .apollo11SourceBacked)
        let decoded = try LMSimulationCheckpoint.decodeFixture(try checkpoint.encodedFixture())
        let restoredStart = try await resumed.restore(from: decoded)
        let resumedRun = try await p66ToContact(resumed, from: restoredStart)

        #expect(resumedRun.frames.count == baselineRun.frames.count)
        #expect(resumedRun.frames == baselineRun.frames,
                "checkpoint-resumed P66 flight must match the crew baseline frame for frame")
        #expect(resumedRun.final.vehicleState.flightOutcome == .softLanding)
    }

    @Test func `fixture decoding rejects malformed data`() throws {
        #expect(throws: DecodingError.self) {
            _ = try LMSimulationCheckpoint.decodeFixture(Data([0x62, 0x70, 0x6c, 0x00, 0x01]))
        }
    }

    // MARK: - Flight phases

    private func reachP65(_ runtime: LMSimulationRuntime) async throws -> LMSimulationSnapshot {
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
        #expect(snapshot.agc.dsky.programNumber == 65, "closed loop must reach P65")
        return snapshot
    }

    private func automaticToContact(
        _ runtime: LMSimulationRuntime,
        from start: LMSimulationSnapshot
    ) async throws -> LMSimulationSnapshot {
        var snapshot = start
        let dt = LMSimulationPace.acceleratedDeltaSeconds
        let deadline = snapshot.timeSeconds + 240.0
        while snapshot.timeSeconds < deadline,
              !snapshot.vehicleState.flightOutcome.isTerminal {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .autoLand(from: snapshot.vehicleState)
            )
        }
        #expect(snapshot.vehicleState.surfaceContact != nil, "automatic flight must reach contact")
        return snapshot
    }

    /// Mirrors ``LMP66FlightRecorder.record`` from the P65 frame onward so both
    /// runs see identical ACA/ROD commands at identical frames.
    private func p66ToContact(
        _ runtime: LMSimulationRuntime,
        from start: LMSimulationSnapshot
    ) async throws -> P66Run {
        let dt = LMSimulationPace.acceleratedDeltaSeconds
        let pilot = LMP66Pilot()
        var snapshot = start
        var frames = [snapshot.vehicleState]

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
        frames.append(snapshot.vehicleState)

        for _ in 0..<80 where snapshot.agc.dsky.programNumber != 66 {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .astronautLand(
                    from: snapshot.vehicleState,
                    panelState: .p66AttitudeHold,
                    attitudeController: handController
                )
            )
            frames.append(snapshot.vehicleState)
        }
        #expect(snapshot.agc.dsky.programNumber == 66, "ATT HOLD must transition P65 into P66")

        for _ in 0..<4 {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .astronautLand(
                    from: snapshot.vehicleState,
                    panelState: .p66AttitudeHold,
                    attitudeController: handController
                )
            )
            frames.append(snapshot.vehicleState)
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
        frames.append(snapshot.vehicleState)
        for _ in 0..<20 {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .astronautLand(
                    from: snapshot.vehicleState,
                    panelState: .p66AttitudeHold,
                    attitudeController: handController
                )
            )
            frames.append(snapshot.vehicleState)
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
            frames.append(snapshot.vehicleState)
            manualStep += 1
        }

        #expect(snapshot.vehicleState.surfaceContact != nil, "P66 flight must reach contact")
        return P66Run(frames: frames, final: snapshot)
    }

    private func refusalError(
        of runtime: LMSimulationRuntime,
        restoring checkpoint: LMSimulationCheckpoint
    ) async -> LMSimulationCheckpointError? {
        do {
            try await runtime.restore(from: checkpoint)
            return nil
        } catch let error as LMSimulationCheckpointError {
            return error
        } catch {
            Issue.record("Unexpected error: \(error)")
            return nil
        }
    }
}
