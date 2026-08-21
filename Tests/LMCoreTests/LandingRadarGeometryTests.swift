import Foundation
import Testing
@testable import LMCore

struct LandingRadarGeometryTests {
    @Test func `SETPOS transforms source-backed antenna beams into NASA body`() {
        let h1 = LMLandingRadar.nasaBodyVector(
            fromAntenna: LMLandingRadar.hBeamAntenna.normalized(),
            position2: false
        )
        let h2 = LMLandingRadar.nasaBodyVector(
            fromAntenna: LMLandingRadar.hBeamAntenna.normalized(),
            position2: true
        )

        #expect(abs(h1.x - -0.715) < 0.002)
        #expect(abs(h1.y - -0.073) < 0.002)
        #expect(abs(h1.z - -0.696) < 0.002)
        #expect(abs(h2.x - -0.937) < 0.002)
        #expect(abs(h2.y - -0.036) < 0.002)
        #expect(abs(h2.z - -0.346) < 0.002)
    }

    @Test func `LR velocity words are Doppler projections along SETPOS beams`() {
        let state = LMVehicleStateSnapshot(
            positionMeters: LMVector3D(z: 1_000),
            velocityMetersPerSecond: LMVector3D(z: 10),
            attitude: .identity
        )
        let measurement = try! #require(
            LMLandingRadar.measurement(from: state, position2: false)
        )
        let beams = try! #require(measurement.landingRadarBeamVelocityMetersPerSecond)
        let nasaVelocity = LMIMUGimbalMap.nasaBody(fromSim: state.velocityMetersPerSecond)
        let xBeam = LMLandingRadar.nasaBodyVector(
            fromAntenna: LMVector3D(x: 1),
            position2: false
        )
        let yBeam = LMLandingRadar.nasaBodyVector(
            fromAntenna: LMVector3D(y: 1),
            position2: false
        )

        #expect(abs(beams.x - nasaVelocity.dot(xBeam)) < 1e-12)
        #expect(abs(beams.y - nasaVelocity.dot(yBeam)) < 1e-12)
        #expect(abs(beams.z - nasaVelocity.dot(xBeam.cross(yBeam))) < 1e-12)
    }

    /// Site ENU is a tangent plane pinned at RLS. At PDI the LM is ~21° of
    /// lunar arc uprange, so projecting the range beam onto the site's up axis
    /// overstates slant range even after applying the source-backed POS1 angles.
    @Test func `LR slant range uses the vehicle local vertical, not the site tangent plane`() {
        let state = LMPoweredDescentScenario.apollo11SourceBacked.initialState
        let (north, east, up) = LMAGCNavState.moonFixedSiteBasis()

        let localUp = LMAGCNavState.moonCenteredPositionMeters(from: state).normalized()
        let arcDegrees = acos(max(-1, min(1, localUp.dot(up)))) * 180 / .pi
        #expect(
            arcDegrees > 15,
            "PDI should sit well off the site tangent plane, got \(arcDegrees)°"
        )

        let hBeamNasa = LMLandingRadar.nasaBodyVector(
            fromAntenna: LMLandingRadar.hBeamAntenna.normalized(),
            position2: false
        )
        let beamWorld = state.attitude.rotated(LMIMUGimbalMap.sim(fromNasa: hBeamNasa))
        let beamMoon = north * beamWorld.x + east * beamWorld.y + up * beamWorld.z
        let towardGroundLocal = -beamMoon.dot(localUp)
        let towardGroundSite = -beamWorld.z

        #expect(
            towardGroundLocal > 1.3 * towardGroundSite,
            "site-plane projection understates the beam's look-down: local \(towardGroundLocal) vs site \(towardGroundSite)"
        )

        let measured = LMLandingRadar.measurement(from: state)
        let slant = try! #require(measured?.altitudeMeters)
        let localSlant = state.altitudeMeters / towardGroundLocal
        #expect(
            abs(slant - localSlant) < 1,
            "measurement should use the local vertical: \(slant) vs \(localSlant)"
        )
    }

    /// The source-backed PDI slant exceeds the low-scale counter but fits the
    /// high-scale counter selected through CH33.
    @Test func `source-backed PDI sample fits the high scale counter`() {
        let highScale = 4.316 * 0.3048
        let highCeiling = 0o77777 * highScale
        let lowCeiling = 0o77777 * 1.079 * 0.3048
        #expect(highCeiling > 43_000 && highCeiling < 44_000, "15-bit high-scale ceiling ≈ 43.1 km")

        let measurement = try! #require(
            LMLandingRadar.measurement(
                from: LMPoweredDescentScenario.apollo11SourceBacked.initialState,
                position2: false
            )
        )
        let slant = try! #require(measurement.altitudeMeters)
        #expect(slant > lowCeiling && slant < highCeiling)

        let raw = LMRadarConversion.rawInput(from: measurement)
        #expect(raw.landingRadarAltitude == Int((slant / highScale).rounded()))
        #expect(raw.landingRadarAltitudeHighScale)
    }
}
