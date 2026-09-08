import Testing
@testable import LMCore

@Suite("Site-aware IMU diagnostics")
struct LMSiteIMUDiagnosticTests {
    @Test func frozenMemberForceMatchesInertialVelocityDifference() throws {
        let epoch = Luminary99LandingPadLoad.pdiClockCentiseconds
        let attitude = LMQuaternion.fromAxisAngle(axis: .init(x: 1, y: 2, z: 3), radians: 0.7)
        let body = LMVector3D(x: 0.3, y: -0.4, z: 2)
        for latitude in [-90.0, -42, 8.35, 90] {
            let site = try LMLunarLandingSite(latitudeDegrees: latitude, longitudeDegrees: 120, radiusMeters: 1_739_000)
            let ref = LMAGCNavState.refsmmat(timeCentiseconds: epoch, site: site)
            for time in [epoch, epoch + 120_000] {
                let velocity = LMVector3D(x: 12, y: -8, z: -3)
                let before = LMVehicleStateSnapshot(positionMeters: .init(x: 30_000, y: -20_000, z: 1_000),
                    velocityMetersPerSecond: velocity, landingSite: site)
                let after = LMVehicleStateSnapshot(positionMeters: before.positionMeters,
                    velocityMetersPerSecond: velocity + attitude.rotated(body), landingSite: site)
                let a = LMAGCNavState.stableMemberKinematics(from: before, refsmmat: ref, timeCentiseconds: time)
                let b = LMAGCNavState.stableMemberKinematics(from: after, refsmmat: ref, timeCentiseconds: time)
                let force = LMAGCNavState.specificForceSM(body: body, attitude: attitude,
                    refsmmat: ref, timeCentiseconds: time, site: site)
                let error = (force - (b.velocityMetersPerSecond - a.velocityMetersPerSecond)).magnitude
                print("AGC_SITE_IMU latitude=\(latitude) time=\(time) forceError=\(error)")
                #expect(error < 1e-10)
            }
        }
    }

    @Test func customCDUsAgreeWithSiteAxesAtReferenceEpoch() throws {
        let time = Luminary99LandingPadLoad.pdiClockCentiseconds
        let attitude = LMQuaternion.fromAxisAngle(axis: .init(x: 1), radians: 95 * .pi / 180)
        let expected = LMIMUGimbalMap.cduCounts(from: attitude)
        for latitude in [-90.0, -42, 8.35, 90] {
            let site = try LMLunarLandingSite(latitudeDegrees: latitude, longitudeDegrees: 120, radiusMeters: 1_739_000)
            let ref = LMAGCNavState.refsmmat(timeCentiseconds: time, site: site)
            let actual = LMIMUGimbalMap.cduCounts(from: attitude, refsmmat: ref, timeCentiseconds: time, site: site)
            for (a, b) in [(expected.x, actual.x), (expected.y, actual.y), (expected.z, actual.z)] {
                #expect(abs(LMIMUGimbalMap.shortestCountDelta(from: a, to: b)) <= 2)
            }
            var feedback = LMSensorFeedbackState()
            _ = feedback.increments(specificForceSM: .zero, attitude: attitude, deltaTime: 1,
                refsmmat: ref, timeCentiseconds: time, site: site)
            let checkpoint = feedback.captureCheckpoint()
            #expect(checkpoint.lastCDUX == actual.x)
            #expect(checkpoint.lastCDUY == actual.y)
            #expect(checkpoint.lastCDUZ == actual.z)
        }
    }
}
