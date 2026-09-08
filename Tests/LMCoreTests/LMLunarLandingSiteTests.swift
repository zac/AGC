import Foundation
import AGC
import Testing
@testable import LMCore

@Suite("Lunar landing sites")
struct LMLunarLandingSiteTests {
    @Test func finitePoleSafeFramesAndSphericalRadar() throws {
        for latitude in [-90.0, -42, 0, 89.99999, 90] {
            let site = try LMLunarLandingSite(latitudeDegrees: latitude, longitudeDegrees: 179.99, radiusMeters: 1_735_471.96)
            let b = site.basis
            #expect(abs(b.north.dot(b.east)) < 1e-12)
            #expect(abs(b.up.magnitude - 1) < 1e-12)
            let state = LMVehicleStateSnapshot(positionMeters: .init(x: 50_000, y: -30_000, z: 1000),
                                               velocityMetersPerSecond: .init(x: 12, y: -3, z: -4), landingSite: site)
            let expected = sqrt(50_000.0 * 50_000 + 30_000.0 * 30_000 + pow(site.radiusMeters + 1000, 2)) - site.radiusMeters
            #expect(abs(state.altitudeMeters - expected) < 1e-8)
            let moon = LMAGCNavState.moonCenteredPositionMeters(from: state)
            #expect(abs(moon.magnitude - site.radiusMeters - expected) < 1e-8)
            #expect(state.verticalSpeedMetersPerSecond.isFinite)
        }
    }
    @Test func retargetedPDIAndPadWordsUseSameSite() throws {
        let clock = AGCDoublePrecision.encode(value: Luminary99LandingPadLoad.pdiClockCentiseconds, scale: 28)
        let time = clock.decoded(scale: 28)
        // B27 double precision has 0.5 m steps; each rounded component
        // is within 0.25 m, so the 3D encoding bound is sqrt(3) * 0.25.
        let encodingBound = sqrt(3.0) * 0.25 + 1e-7
        for latitude in [-90.0, -42, 8.35, 90] {
            let site = try LMLunarLandingSite(latitudeDegrees: latitude, longitudeDegrees: 120, radiusMeters: 1_738_000)
            let scenario = LMPoweredDescentScenario.lunarSite(site)
            #expect(scenario.initialState.landingSite == site)
            #expect(scenario.id != LMPoweredDescentScenario.apollo11SourceBacked.id)
            let liveState = LMAGCNavState.vehicleState(timeCentiseconds: time, attitude: scenario.initialState.attitude, massKilograms: 10_000, site: site)
            let words = LMAGCNavState.erasableWords(vehicle: liveState, time2: clock.high, time1: clock.low)
            func decode(_ address: Int) throws -> Double {
                let high = try #require(words.first { $0.ecadr == address })
                let low = try #require(words.first { $0.ecadr == address + 1 })
                return AGCDoublePrecision(high: high.value, low: low.value).decoded(scale: Luminary099NavScale.positionScale)
            }
            let rls = LMVector3D(x: try decode(Luminary099Erasable.rls), y: try decode(Luminary099Erasable.rls + 2), z: try decode(Luminary099Erasable.rls + 4))
            #expect((rls - site.positionMeters).magnitude <= encodingBound)
            let encoded = LMVector3D(x: try decode(Luminary099Erasable.rn), y: try decode(Luminary099Erasable.rn + 2), z: try decode(Luminary099Erasable.rn + 4))
            let expected = LMAGCNavState.basicReferencePositionMeters(from: liveState, timeCentiseconds: time)
            #expect((encoded - expected).magnitude <= encodingBound)
            print("AGC_SITE lat=\(latitude) RLSerror=\((rls - site.positionMeters).magnitude)m RNerror=\((encoded - expected).magnitude)m")
        }
    }
    @Test func propagationRetainsSiteAndOldVehicleJSONStaysCompatible() throws {
        let site = try LMLunarLandingSite(latitudeDegrees: -42, longitudeDegrees: 120, radiusMeters: 1_739_000)
        var state = LMVehicleStateSnapshot(positionMeters: .init(z: 100), massKilograms: 10_000, landingSite: site)
        for _ in 0..<60 {
            state = LMDynamics.propagate(state: state, commands: .init(), configuration: .sourceBackedDefault, deltaTime: 1.0 / 60)
            #expect(state.landingSite == site)
        }
        #expect(state.altitudeMeters < 100)
        let legacy = LMVehicleStateSnapshot(positionMeters: .init(z: 10))
        let data = try JSONEncoder().encode(legacy)
        #expect(!String(decoding: data, as: UTF8.self).contains("landingSite"))
        #expect(try JSONDecoder().decode(LMVehicleStateSnapshot.self, from: data) == legacy)
        #expect(LMAGCNavState.landingSiteMeters() == Luminary99CoordinatePadLoad.landingSiteMeters)
    }
    @Test func checkpointCannotSilentlyChangeTheLandingSite() async throws {
        let rom = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("AGCTests/Luminary099.bin")
        let site = try LMLunarLandingSite(latitudeDegrees: -42, longitudeDegrees: 120, radiusMeters: 1_737_400)
        let custom = try LMSimulationRuntime(binFile: rom, initialState: .init(landingSite: site))
        let legacy = try LMSimulationRuntime(binFile: rom)
        let checkpoint = await legacy.captureCheckpoint()
        let before = await custom.snapshot()
        do {
            _ = try await custom.restore(from: checkpoint)
            Issue.record("Cross-site checkpoint was accepted")
        } catch LMLunarLandingSite.SiteError.incompatibleCheckpoint { }
        let after = await custom.snapshot()
        #expect(before.vehicleState == after.vehicleState)
        #expect(before.agc == after.agc)
    }

    @Test func retargetedP63ReachesTerminalContact() async throws {
        let rom = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("AGCTests/Luminary099.bin")
        let site = try LMLunarLandingSite(latitudeDegrees: 8.35, longitudeDegrees: 30.83, radiusMeters: 1_735_000)
        let runtime = try LMSimulationRuntime(binFile: rom, scenario: .lunarSite(site))
        var snapshot = await runtime.bootAndEnterP63()
        var programs = Set<Int>()
        let deadline = snapshot.timeSeconds + Luminary99LandingPadLoad.guidDurnCentiseconds / 100 + 240
        while snapshot.timeSeconds < deadline, !snapshot.vehicleState.flightOutcome.isTerminal {
            if let program = snapshot.agc.dsky.programNumber { programs.insert(program) }
            snapshot = await runtime.step(deltaTime: LMSimulationPace.acceleratedDeltaSeconds,
                                           input: .autoLand(from: snapshot.vehicleState))
        }
        print("AGC_CUSTOM_DESCENT programs=\(programs.sorted()) t=\(snapshot.timeSeconds)s altitude=\(snapshot.vehicleState.altitudeMeters)m outcome=\(snapshot.vehicleState.flightOutcome)")
        #expect(snapshot.vehicleState.landingSite == site)
        #expect(programs.contains(64) && programs.contains(65))
        #expect(snapshot.vehicleState.flightOutcome == .softLanding)
    }

}
