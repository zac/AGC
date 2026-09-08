import Testing
@testable import LMCore

@Suite("Terrain contact below the guidance datum")
struct LMTerrainDatumContactTests {
    struct Ground: LMLandingSurfaceModel {
        func surfaceHeightMeters(northMeters: Double, eastMeters: Double) -> Double { -20 }
    }

    @Test func installedTerrainDoesNotLandOnTheReferenceSphere() {
        var state = LMVehicleStateSnapshot(positionMeters: .init(z: 0.1),
            velocityMetersPerSecond: .init(z: -1), massKilograms: 7_000)
        for _ in 0..<60 {
            state = LMDynamics.propagate(state: state, commands: .init(),
                configuration: .sourceBackedDefault, deltaTime: 1.0 / 60, surface: Ground())
        }
        #expect(state.positionMeters.z < -1)
        #expect(state.flightOutcome == .inFlight)
        #expect(state.surfaceContact == nil)
    }
}
