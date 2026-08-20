import Foundation
import Testing
@testable import LMCore

struct LandingRadarGeometryTests {
    /// Site ENU is a tangent plane pinned at RLS. At PDI the LM is ~21° of
    /// lunar arc uprange, so projecting the range beam onto the site's up axis
    /// instead of the vehicle's own local vertical overstates slant range by
    /// 2.2x. That inflated range saturates the 15-bit altitude word and feeds
    /// SERVICER a pinned value it accepts unchecked before HIGATE.
    @Test func `LR slant range uses the vehicle local vertical, not the site tangent plane`() {
        let state = LMPoweredDescentScenario.apollo11SourceBacked.initialState
        let (north, east, up) = LMAGCNavState.moonFixedSiteBasis()

        let localUp = LMAGCNavState.moonCenteredPositionMeters(from: state).normalized()
        let arcDegrees = acos(max(-1, min(1, localUp.dot(up)))) * 180 / .pi
        #expect(
            arcDegrees > 15,
            "PDI should sit well off the site tangent plane, got \(arcDegrees)°"
        )

        let beamWorld = state.attitude.rotated(
            LMIMUGimbalMap.sim(fromNasa: LMLandingRadar.hBeamAntenna.normalized())
        )
        let beamMoon = north * beamWorld.x + east * beamWorld.y + up * beamWorld.z
        let towardGroundLocal = -beamMoon.dot(localUp)
        let towardGroundSite = -beamWorld.z

        #expect(
            towardGroundLocal > 1.8 * towardGroundSite,
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

    /// Correcting the projection shortens PDI slant from 56.7 km to 25.3 km.
    /// Both still exceed the 15-bit counter, so the word pins either way and
    /// the AGC sees an identical sample while out of range — the fix changes
    /// what the AGC is told only once the beam is genuinely within range.
    @Test func `curvature fix only changes the sample once inside counter range`() {
        let ceiling = 0o77777 * (1.079 * 0.3048)
        #expect(ceiling > 10_000 && ceiling < 11_000, "15-bit ceiling ≈ 10.8 km")

        let pinnedBefore = LMRadarConversion.rawInput(
            from: LMRadarMeasurementInput(altitudeMeters: 56_704)
        )
        let pinnedAfter = LMRadarConversion.rawInput(
            from: LMRadarMeasurementInput(altitudeMeters: 25_340)
        )
        #expect(pinnedBefore.landingRadarAltitude == pinnedAfter.landingRadarAltitude)

        let inRange = LMRadarConversion.rawInput(
            from: LMRadarMeasurementInput(altitudeMeters: 5_000)
        )
        #expect(inRange.landingRadarAltitude == Int((5_000 / (1.079 * 0.3048)).rounded()))
    }
}
