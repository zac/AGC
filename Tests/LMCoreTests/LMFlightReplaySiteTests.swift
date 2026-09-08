import Foundation
import Testing
@testable import LMCore

@Suite("Flight replay landing-site continuity")
struct LMFlightReplaySiteTests {
    @Test func interpolationPreservesRecordedLandingGear() throws {
        let states = [
            LMVehicleStateSnapshot(positionMeters: .init(z: 1)),
            LMVehicleStateSnapshot(positionMeters: .zero,
                landingGear: LMLandingGearState(isProbeContact: true)),
            LMVehicleStateSnapshot(positionMeters: .zero,
                landingGear: LMLandingGearState(isProbeContact: true, touchdownEvents: 4))
        ]
        let recording = LMFlightRecording(controlMode: .automatic,
            frames: states.enumerated().map { frame($0.element, time: 100 + Double($0.offset) * 2) })
        let replay = LMFlightReplay(recording: try .decode(recording.encoded()))
        for (time, index) in [(1.0, 0), (2.0, 1), (3.0, 1), (4.0, 2)] {
            let state = try #require(replay.frame(at: time)).vehicleState
            #expect(state.landingGear == states[index].landingGear)
        }
    }

    @Test func interpolationPreservesSiteAndMoonCenteredPosition() throws {
        let sites: [LMLunarLandingSite?] = [nil,
            try .init(latitudeDegrees: -42, longitudeDegrees: 120, radiusMeters: 1_739_000),
            try .init(latitudeDegrees: 90, longitudeDegrees: -180, radiusMeters: 1_735_000)]
        for site in sites {
            let start = LMVehicleStateSnapshot(positionMeters: .init(x: 20, y: 50, z: 100), landingSite: site)
            let end = LMVehicleStateSnapshot(positionMeters: .init(x: 40, y: 10, z: 20), landingSite: site)
            let recording = LMFlightRecording(controlMode: .automatic,
                frames: [frame(start, time: 100), frame(end, time: 102)])
            let replay = LMFlightReplay(recording: try .decode(recording.encoded()))
            for elapsed in [0.0, 0.5, 1, 1.5, 2] {
                let state = try #require(replay.frame(at: elapsed)).vehicleState
                #expect(state.landingSite == site)
                let a = LMAGCNavState.moonCenteredPositionMeters(from: start)
                let b = LMAGCNavState.moonCenteredPositionMeters(from: end)
                let expected = a + (b - a) * (elapsed / 2)
                #expect((LMAGCNavState.moonCenteredPositionMeters(from: state) - expected).magnitude < 1e-8)
            }
        }
    }

    @Test func differentSiteFramesSwitchAtomically() throws {
        let site = try LMLunarLandingSite(latitudeDegrees: -42, longitudeDegrees: 120, radiusMeters: 1_739_000)
        let custom = LMVehicleStateSnapshot(positionMeters: .init(z: 10), landingSite: site)
        let legacy = LMVehicleStateSnapshot(positionMeters: .init(x: 100, z: 30))
        // This also exercises an exact interior frame time, which goes through
        // interpolation rather than the first/last-frame fast paths.
        for states in [[custom, legacy, custom], [legacy, custom, legacy]] {
            let replay = LMFlightReplay(recording: .init(controlMode: .automatic,
                frames: states.enumerated().map { frame($0.element, time: 100 + Double($0.offset) * 2) }))
            #expect(replay.frame(at: 1)?.vehicleState == states[0])
            #expect(replay.frame(at: 2)?.vehicleState == states[1])
            #expect(replay.frame(at: 3)?.vehicleState == states[1])
            #expect(replay.frame(at: 4)?.vehicleState == states[2])
        }
    }

    @Test func streamedJSONMatchesExistingEncodingAcrossBufferBoundaries() throws {
        let site = try LMLunarLandingSite(latitudeDegrees: -42, longitudeDegrees: 120, radiusMeters: 1_739_000)
        let contact = LMSurfaceContactSnapshot(groundRangeMeters: 20,
            horizontalSpeedMetersPerSecond: 0.2, verticalSpeedMetersPerSecond: 0.5,
            tiltRadians: 0.1, surfaceNormal: .init(x: 0, y: 0.1, z: sqrt(0.99)))
        let state = LMVehicleStateSnapshot(positionMeters: .init(z: -20),
            flightOutcome: .hardLanding, surfaceContact: contact, landingSite: site)
        for count in [0, 1, 2_000] {
            let recording = LMFlightRecording(scenarioID: "quoted \"site\"/🌙\\n",
                controlMode: .astronautP66,
                frames: (0..<count).map { frame(state, time: Double($0)) })
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: url) }
            #expect(FileManager.default.createFile(atPath: url.path, contents: nil))
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try recording.writeJSON(to: handle)
            let data = try Data(contentsOf: url)
            #expect(data == (try recording.encoded()))
            #expect(try LMFlightRecording.decode(data) == recording)
        }
    }

    @Test func streamedJSONReportsWriteFailure() throws {
        let recording = LMFlightRecording(controlMode: .automatic, frames: [])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data().write(to: url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        #expect(throws: (any Error).self) { try recording.writeJSON(to: handle) }
    }

    private func frame(_ state: LMVehicleStateSnapshot, time: Double) -> LMFlightFrame {
        .init(timeSeconds: time, cycle: 0, programNumber: 65, vehicleState: state, vehicleCommands: .init())
    }
}
