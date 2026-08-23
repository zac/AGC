import Foundation
import Testing

@testable import AGC
@testable import LMCore

/// Manual diagnostic: replays the checkpoint-resumed P65→ATT HOLD→P66 flow
/// with small realtime-sized steps instead of the recorder's 0.25 s chunks.
/// Runs only when P66_REALTIME_PROBE=1 so normal suite stays fast.
@Suite("P66 realtime transition probe")
struct P66RealtimeProbeTests {
    @Test func p65CheckpointTransitionsToP66AtRealtimeFrameSizes() async throws {
        guard ProcessInfo.processInfo.environment["P66_REALTIME_PROBE"] == "1" else {
            return
        }
        let romURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AGCTests/Luminary099.bin")
        let baseline = try LMSimulationRuntime(binFile: romURL, scenario: .apollo11SourceBacked)
        var snapshot = await baseline.bootAndEnterP63()
        let accel = LMSimulationPace.acceleratedDeltaSeconds
        let deadline = Luminary99LandingPadLoad.guidDurnCentiseconds / 100.0 + 240.0
        while snapshot.timeSeconds < deadline,
              snapshot.agc.dsky.programNumber != 65,
              !snapshot.vehicleState.flightOutcome.isTerminal {
            snapshot = await baseline.step(deltaTime: accel, input: .autoLand(from: snapshot.vehicleState))
        }
        #expect(snapshot.agc.dsky.programNumber == 65)

        let checkpoint = await baseline.captureCheckpoint()
        let resumed = try LMSimulationRuntime(binFile: romURL, scenario: .apollo11SourceBacked)
        var snap = try await resumed.restore(from: checkpoint)

        let dtChoices: [Double] = [1.0 / 60.0, 0.01, 0.05]
        for dt in dtChoices {
            // Restore again for each frame size.
            snap = try await resumed.restore(from: checkpoint)
            var frame = 0
            var sawP66 = false
            while !snap.vehicleState.flightOutcome.isTerminal, frame < 3000 {
                // Crew flow: ATT HOLD plus one momentary DESCEND+ click.
                // GUILDENSTERN only selects P66 when RODCOUNT is nonzero.
                let click = frame == 5
                snap = await resumed.step(
                    deltaTime: dt,
                    input: .astronautLand(
                        from: snap.vehicleState,
                        panelState: .p66AttitudeHold,
                        attitudeController: LMRotationalHandControllerInput(),
                        descendPlus: click
                    )
                )
                if snap.agc.dsky.programNumber == 66 {
                    sawP66 = true
                    break
                }
                frame += 1
            }
            print(
                "dt=\(dt): sawP66=\(sawP66) frames=\(frame) simT=\(snap.timeSeconds) "
                    + "alt=\(snap.vehicleState.altitudeMeters) prog=\(snap.agc.dsky.programNumber ?? -1)"
            )
            #expect(sawP66, "ATT HOLD must select P66 at dt=\(dt)")
        }
    }
}
