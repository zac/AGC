import Foundation
import Testing

@testable import LMCore

/// A tilted plane through the origin, in site-ENU meters.
private struct SlopeSurface: LMLandingSurfaceModel {
    let riseNorth: Double
    let riseEast: Double

    init(degreesDownToSouth: Double = 0, degreesDownToWest: Double = 0) {
        riseNorth = tan(degreesDownToSouth * .pi / 180)
        riseEast = tan(degreesDownToWest * .pi / 180)
    }

    func surfaceHeightMeters(northMeters: Double, eastMeters: Double) -> Double {
        riseNorth * northMeters + riseEast * eastMeters
    }
}

/// One isolated bump, so a single footpad can be put on a craterlet rim.
private struct BumpSurface: LMLandingSurfaceModel {
    let northMeters: Double
    let eastMeters: Double
    let heightMeters: Double
    let radiusMeters: Double

    func surfaceHeightMeters(northMeters: Double, eastMeters: Double) -> Double {
        let distance = hypot(northMeters - self.northMeters, eastMeters - self.eastMeters)
        guard distance < radiusMeters else { return 0 }
        let normalized = distance / radiusMeters
        return heightMeters * (1 - normalized * normalized)
    }
}

private let touchdownMass = LMLandingGearGeometry.designTouchdownMassKilograms
private let lunarGravity = LMVehicleConfiguration.sourceBackedDefault
    .lunarGravityMetersPerSecondSquared.value
private let inertia = LMInertiaMap.diagonalInertiaKilogramMetersSquared(
    massKilograms: touchdownMass
)

/// Fly a vehicle down onto a surface and return the settled result.
@discardableResult
private func land(
    on surface: LMLandingSurfaceModel,
    descentRateMetersPerSecond: Double,
    horizontalRateMetersPerSecond: Double = 0,
    attitude: LMQuaternion = .identity,
    startHeightAboveGroundMeters: Double = 0.02,
    maximumSeconds: Double = 12
) -> (
    position: LMVector3D,
    velocity: LMVector3D,
    attitude: LMQuaternion,
    gear: LMLandingGearState,
    contact: LMSurfaceContactSnapshot?,
    settled: Bool,
    seconds: Double
) {
    var position = LMVector3D(z: startHeightAboveGroundMeters)
    var velocity = LMVector3D(
        x: horizontalRateMetersPerSecond,
        z: -descentRateMetersPerSecond
    )
    var orientation = attitude
    var angularVelocity = LMVector3D.zero
    var gear = LMLandingGearState()
    var contact: LMSurfaceContactSnapshot?
    var elapsed = 0.0
    let frame = 1.0 / 60.0

    while elapsed < maximumSeconds {
        let result = LMLandingGearDynamics.integrate(
            positionMeters: position,
            velocityMetersPerSecond: velocity,
            attitude: orientation,
            angularVelocityRadiansPerSecond: angularVelocity,
            massKilograms: touchdownMass,
            inertiaKilogramMetersSquared: inertia,
            accelerationMetersPerSecondSquared: LMVector3D(z: -lunarGravity),
            angularAccelerationRadiansPerSecondSquared: .zero,
            gear: gear,
            surface: surface,
            deltaTime: frame
        )
        position = result.positionMeters
        velocity = result.velocityMetersPerSecond
        orientation = result.attitude
        angularVelocity = result.angularVelocityRadiansPerSecond
        gear = result.gear
        contact = contact ?? result.firstContact
        elapsed += frame
        if result.isSettled {
            return (position, velocity, orientation, gear, contact, true, elapsed)
        }
    }
    return (position, velocity, orientation, gear, contact, false, elapsed)
}

@Suite("LM landing gear")
struct LMLandingGearTests {
    @Test func rotationInterruptsContinuousSettlingTime() {
        let result = LMLandingGearDynamics.integrate(
            positionMeters: .init(z: -0.001),
            velocityMetersPerSecond: .zero,
            attitude: .identity,
            angularVelocityRadiansPerSecond: .init(z: 0.1),
            massKilograms: touchdownMass,
            inertiaKilogramMetersSquared: inertia,
            accelerationMetersPerSecondSquared: .init(z: -lunarGravity),
            angularAccelerationRadiansPerSecondSquared: .zero,
            gear: LMLandingGearState(quiescentSeconds: 0.5),
            surface: LMSphericalLandingSurface(),
            deltaTime: 0.001
        )
        #expect(result.gear.isAnyFootpadInContact)
        #expect(result.velocityMetersPerSecond.magnitude < LMLandingGearDynamics.quiescentSpeedMetersPerSecond)
        #expect(result.angularVelocityRadiansPerSecond.magnitude > LMLandingGearDynamics.quiescentRateRadiansPerSecond)
        #expect(result.gear.quiescentSeconds == 0)
        #expect(!result.isSettled)
    }

    @Test func firstContactRetainsSurfaceNormalSeparatelyFromVehicleTilt() throws {
        let surface = SlopeSurface(degreesDownToSouth: 12)
        let halfAngle = -2.5 * Double.pi / 180
        let attitude = LMQuaternion(w: cos(halfAngle), y: sin(halfAngle))
        let result = land(on: surface, descentRateMetersPerSecond: 0.5, attitude: attitude,
                          startHeightAboveGroundMeters: 0.02, maximumSeconds: 1)
        let contact = try #require(result.contact)
        let normal = try #require(contact.surfaceNormal)
        #expect(abs(acos(normal.z) * 180 / .pi - 12) < 1e-8)
        #expect(abs(contact.tiltRadians * 180 / .pi - 7) < 0.1)
        #expect(contact.flightOutcome == .crashed)
        let encoded = try JSONEncoder().encode(contact)
        #expect(try JSONDecoder().decode(LMSurfaceContactSnapshot.self, from: encoded) == contact)
    }

    @Test func legacyContactDecodesWithoutInventingASurfaceNormal() throws {
        let data = Data(#"{"groundRangeMeters":1,"horizontalSpeedMetersPerSecond":0.1,"verticalSpeedMetersPerSecond":0.5,"tiltRadians":0}"#.utf8)
        let contact = try JSONDecoder().decode(LMSurfaceContactSnapshot.self, from: data)
        #expect(contact.surfaceNormal == nil)
        #expect(contact.flightOutcome == .softLanding)
    }

    @Test func `gear geometry matches published LM dimensions`() {
        #expect(abs(LMLandingGearGeometry.footpadSpreadMeters - 9.4488) < 1e-3)
        #expect(abs(LMLandingGearGeometry.footpadRadiusMeters - 4.7244) < 1e-3)
        #expect(abs(LMLandingGearGeometry.footpadDiameterMeters - 0.9398) < 1e-3)
        #expect(abs(LMLandingGearGeometry.contactProbeLengthMeters - 1.7272) < 1e-3)
        #expect(abs(LMLandingGearGeometry.primaryStrutStrokeMeters - 0.8128) < 1e-3)
    }

    @Test func `four legs sit on the simulation lateral axes`() {
        let pads = LMLandingGearLeg.allCases.map {
            LMLandingGearGeometry.footpadBody($0, strokeMeters: 0)
        }
        for pad in pads {
            #expect(
                abs(hypot(pad.x, pad.y) - LMLandingGearGeometry.footpadRadiusMeters) < 1e-9
            )
            // The reference point is the uncompressed footpad plane itself.
            #expect(abs(pad.z) < 1e-9)
        }
        let probed = LMLandingGearLeg.allCases.filter(\.hasContactProbe).count
        #expect(probed == 3)
    }

    @Test func `stroking a strut lifts the pad up and inward`() {
        let rest = LMLandingGearGeometry.footpadBody(.forward, strokeMeters: 0)
        let stroked = LMLandingGearGeometry.footpadBody(.forward, strokeMeters: 0.4)
        #expect(stroked.z > rest.z)
        #expect(hypot(stroked.x, stroked.y) < hypot(rest.x, rest.y))
    }

    @Test func `static lunar weight does not crush the honeycomb`() {
        let weightPerStrut = touchdownMass * lunarGravity
            / Double(LMLandingGearLeg.allCases.count)
        #expect(LMLandingGearGeometry.primaryStrutCrushLoadNewtons > weightPerStrut * 4)
    }

    @Test func `a soft touchdown settles with un-stroked struts`() {
        let result = land(
            on: SlopeSurface(),
            descentRateMetersPerSecond: 0.5
        )
        #expect(result.settled)
        #expect(result.gear.failure == nil)
        #expect(result.gear.maximumStrokeMeters < 0.005)
        #expect(result.contact?.flightOutcome == .softLanding)
        // Every pad carries the vehicle, and it is resting on the ground.
        #expect(result.gear.legs.filter(\.isInContact).count == 4)
        #expect(abs(result.velocity.z) < LMLandingGearDynamics.quiescentSpeedMetersPerSecond)
    }

    @Test func `a hard touchdown crushes the struts and a soft one does not`() {
        let soft = land(on: SlopeSurface(), descentRateMetersPerSecond: 0.5)
        let hard = land(
            on: SlopeSurface(),
            descentRateMetersPerSecond: 2.6
        )
        #expect(hard.settled)
        #expect(hard.gear.failure == nil)
        #expect(hard.gear.maximumStrokeMeters > soft.gear.maximumStrokeMeters + 0.05)
        #expect(hard.gear.peakLoadNewtons > soft.gear.peakLoadNewtons)
        // Permanently crushed honeycomb leaves the vehicle sitting lower.
        #expect(hard.position.z < soft.position.z)
    }

    @Test func `a fast arrival rebounds before it settles`() {
        let result = land(
            on: SlopeSurface(),
            descentRateMetersPerSecond: 2.2,
            maximumSeconds: 20
        )
        #expect(result.settled)
        // Pads that lift and re-touch record extra touchdown events, so the
        // rebound is observable rather than smoothed away.
        #expect(result.gear.touchdownEvents > LMLandingGearLeg.allCases.count)
    }

    @Test func `an Apollo-like arrival leaves a shallow footpad print`() {
        let result = land(on: SlopeSurface(), descentRateMetersPerSecond: 0.5)
        let print = result.gear.legs.map(\.regolithPenetrationMeters).max() ?? 0
        #expect(print > 0.01)
        #expect(print < LMLandingGearDynamics.maximumRegolithPenetrationMeters)
        #expect(result.gear.maximumStrokeMeters == 0)
    }

    @Test func `landing on a slope leaves the vehicle tilted downhill`() {
        let result = land(
            on: SlopeSurface(degreesDownToSouth: 8),
            descentRateMetersPerSecond: 0.5,
            maximumSeconds: 20
        )
        #expect(result.settled)
        #expect(result.gear.failure == nil)
        let tilt = LMLandingGearDynamics.tiltRadians(
            attitude: result.attitude,
            localUp: LMVector3D(z: 1)
        )
        #expect(tilt > 2.0 * .pi / 180)
        #expect(tilt < 12.0 * .pi / 180)
    }

    @Test func `a footpad on a craterlet rim tilts the vehicle`() {
        let rim = BumpSurface(
            northMeters: LMLandingGearGeometry.footpadRadiusMeters,
            eastMeters: 0,
            heightMeters: 0.45,
            radiusMeters: 1.2
        )
        let flat = land(on: SlopeSurface(), descentRateMetersPerSecond: 0.5)
        let onRim = land(on: rim, descentRateMetersPerSecond: 0.5, maximumSeconds: 20)
        let flatTilt = LMLandingGearDynamics.tiltRadians(
            attitude: flat.attitude,
            localUp: LMVector3D(z: 1)
        )
        let rimTilt = LMLandingGearDynamics.tiltRadians(
            attitude: onRim.attitude,
            localUp: LMVector3D(z: 1)
        )
        #expect(rimTilt > flatTilt + 1.0 * .pi / 180)
    }

    @Test func `too steep a slope tips the vehicle over`() {
        let critical = LMLandingGearGeometry.criticalTiltRadians * 180 / .pi
        #expect(critical > 35 && critical < 50)

        let result = land(
            on: SlopeSurface(degreesDownToSouth: critical + 12),
            descentRateMetersPerSecond: 0.5,
            maximumSeconds: 30
        )
        #expect(result.gear.failure == .tipOver)
    }

    @Test func `horizontal velocity is arrested by regolith friction`() {
        let result = land(
            on: SlopeSurface(),
            descentRateMetersPerSecond: 0.5,
            horizontalRateMetersPerSecond: 1.0,
            maximumSeconds: 20
        )
        #expect(result.settled)
        #expect(
            hypot(result.velocity.x, result.velocity.y)
                < LMLandingGearDynamics.quiescentSpeedMetersPerSecond
        )
    }

    @Test func `contact probes touch before the footpads do`() {
        let surface = SlopeSurface()
        var position = LMVector3D(
            z: LMLandingGearGeometry.contactProbeLengthMeters + 1.0
        )
        var velocity = LMVector3D(z: -0.5)
        var gear = LMLandingGearState()
        var probeFirstSeenHeight: Double?

        for _ in 0..<600 {
            let result = LMLandingGearDynamics.integrate(
                positionMeters: position,
                velocityMetersPerSecond: velocity,
                attitude: .identity,
                angularVelocityRadiansPerSecond: .zero,
                massKilograms: touchdownMass,
                inertiaKilogramMetersSquared: inertia,
                accelerationMetersPerSecondSquared: LMVector3D(z: -lunarGravity),
                angularAccelerationRadiansPerSecondSquared: .zero,
                gear: gear,
                surface: surface,
                deltaTime: 1.0 / 60.0
            )
            position = result.positionMeters
            velocity = result.velocityMetersPerSecond
            gear = result.gear
            if gear.isProbeContact, probeFirstSeenHeight == nil {
                probeFirstSeenHeight = position.z
            }
            if gear.isAnyFootpadInContact { break }
        }

        let probeHeight = probeFirstSeenHeight ?? 0
        #expect(probeHeight > 1.5)
        #expect(probeHeight < LMLandingGearGeometry.contactProbeLengthMeters + 0.1)
    }

    @Test func `contact range gate ignores altitude far above the gear`() {
        let surface = SlopeSurface()
        #expect(!LMLandingGearDynamics.isWithinContactRange(
            positionMeters: LMVector3D(z: 60),
            attitude: .identity,
            gear: LMLandingGearState(),
            surface: surface
        ))
        #expect(LMLandingGearDynamics.isWithinContactRange(
            positionMeters: LMVector3D(z: 4),
            attitude: .identity,
            gear: LMLandingGearState(),
            surface: surface
        ))
    }
}
