import Foundation

/// The contact surface the landing gear touches.
///
/// Heights are meters above the AGC landing-site sphere at a site-ENU
/// horizontal position, so a flat implementation returning zero reproduces the
/// previous spherical-datum contact exactly. The renderer supplies the real
/// implementation from the same evaluator that builds the visible mesh, which
/// is why a craterlet under one footpad tilts the vehicle it is under.
public protocol LMLandingSurfaceModel: Sendable {
    func surfaceHeightMeters(northMeters: Double, eastMeters: Double) -> Double
}

extension LMLandingSurfaceModel {
    /// Upward unit normal in site-ENU axes (x north, y east, z up).
    ///
    /// Central differences over `sampleSpacingMeters` deliberately measure the
    /// slope the footpad actually spans rather than an analytic point slope; a
    /// pad is 0.94 m across and cannot balance on a millimeter-wide ridge.
    public func surfaceNormal(
        northMeters: Double,
        eastMeters: Double,
        sampleSpacingMeters: Double = LMLandingGearGeometry.footpadDiameterMeters / 2
    ) -> LMVector3D {
        let span = max(sampleSpacingMeters, 1e-3)
        let north = (
            surfaceHeightMeters(northMeters: northMeters + span, eastMeters: eastMeters)
                - surfaceHeightMeters(northMeters: northMeters - span, eastMeters: eastMeters)
        ) / (2 * span)
        let east = (
            surfaceHeightMeters(northMeters: northMeters, eastMeters: eastMeters + span)
                - surfaceHeightMeters(northMeters: northMeters, eastMeters: eastMeters - span)
        ) / (2 * span)
        return LMVector3D(x: -north, y: -east, z: 1).normalized()
    }
}

/// The spherical datum the simulation used before terrain-relative contact.
public struct LMSphericalLandingSurface: LMLandingSurfaceModel {
    public init() {}

    public func surfaceHeightMeters(northMeters: Double, eastMeters: Double) -> Double { 0 }
}

/// Landing-gear legs in the simulation body frame.
///
/// `LMRCSGeometry` fixes that frame as +Z = NASA +X (the DPS thrust axis),
/// +X = NASA +Y, +Y = NASA +Z. The four LM legs lie on the NASA ±Y/±Z axes, so
/// in simulation axes they lie on ±X and ±Y. The forward leg carries the ladder
/// and is the one leg without a lunar-contact probe.
public enum LMLandingGearLeg: String, CaseIterable, Equatable, Sendable, Codable {
    /// NASA +Z. Ladder leg, no contact probe.
    case forward
    /// NASA +Y.
    case right
    /// NASA -Z.
    case aft
    /// NASA -Y.
    case left

    /// Outward horizontal unit direction in simulation body axes.
    public var outwardBody: LMVector3D {
        switch self {
        case .forward: LMVector3D(y: 1)
        case .right: LMVector3D(x: 1)
        case .aft: LMVector3D(y: -1)
        case .left: LMVector3D(x: -1)
        }
    }

    /// Three of the four legs carry a 68-inch lunar-contact probe. The forward
    /// leg's probe was deleted so it could not foul the crew's egress path.
    public var hasContactProbe: Bool { self != .forward }
}

/// Deployed landing-gear dimensions and the crushable-strut energy budget.
///
/// Published LM dimensions fix the gear spread, footpad size, probe length, and
/// primary-strut stroke. The touchdown center-of-mass height and the strut
/// crush load are *derived* from those dimensions and from the landing-gear
/// design envelope in `LMLandingContactCriteria`; they are not quoted values.
/// `modelingStatus` says so explicitly so a future sourced gear report can
/// replace the derivation without anyone mistaking it for measured data.
public enum LMLandingGearGeometry {
    public static let modelID = "lm-crushable-strut-landing-gear-v1"

    public static let source = LMSourceReference(
        id: "apollo-lm-news-reference-landing-gear",
        title: "Apollo Lunar Module News Reference, landing gear",
        url: "https://www.hq.nasa.gov/alsj/LM10HandbookVol1.pdf",
        detail: """
        Deployed landing gear spans 31 ft footpad to footpad, footpads are 37 in \
        across, the lunar-contact probes are 68 in long on the three legs other \
        than the forward ladder leg, and each primary strut absorbs energy in a \
        crushable aluminum honeycomb cartridge with about 32 in of stroke.
        """
    )

    public static var modelingStatus: LMModelingStatus {
        LMModelingStatus(
            isSourceBacked: false,
            detail: """
            Gear spread, footpad diameter, probe length, and primary-strut stroke \
            are published LM dimensions. Center-of-mass height above the footpad \
            plane, strut cant, and honeycomb crush load are derived from those \
            dimensions plus the Apollo 12 landing-gear velocity envelope already \
            modeled by LMLandingContactCriteria, and are not quoted values.
            """,
            source: LMSourceLocator(
                reference: source,
                detail: "Dimensional basis for the derived crushable-strut model."
            )
        )
    }

    private static let metersPerFoot = 0.3048
    private static let metersPerInch = 0.0254

    /// 31 ft footpad-to-footpad spread.
    public static let footpadSpreadMeters = 31.0 * metersPerFoot
    public static let footpadRadiusMeters = footpadSpreadMeters / 2
    /// 37 in footpad.
    public static let footpadDiameterMeters = 37.0 * metersPerInch
    /// 68 in lunar-contact probe hanging below each of three footpads.
    public static let contactProbeLengthMeters = 68.0 * metersPerInch
    /// About 32 in of crushable primary-strut stroke.
    public static let primaryStrutStrokeMeters = 32.0 * metersPerInch

    /// Derived: touchdown center of mass above the uncompressed footpad plane.
    /// The LM stands 22 ft 11 in tall on its gear and the loaded descent stage
    /// dominates the touchdown mass, which puts the landing CG near half the
    /// vehicle height.
    public static let centerOfMassAboveFootpadPlaneMeters = 3.6

    /// The simulation's position vector is the vehicle reference point that
    /// reads guidance altitude, and lunar guidance references altitude zero to
    /// the vehicle standing on the surface. So the reference point is the
    /// uncompressed footpad plane, and the center of mass is above it. Gear
    /// reactions are resolved about the center of mass, which is what makes
    /// tip-over depend on the real ratio of gear spread to CG height.
    public static let centerOfMassBody = LMVector3D(
        z: centerOfMassAboveFootpadPlaneMeters
    )

    /// Derived: the primary strut runs from the descent-stage outrigger down
    /// and outward to the footpad, so stroking it lifts the pad up and inward.
    /// The attachment radius follows the descent stage's 13.75 ft octagon.
    public static let strutAttachmentRadiusMeters = 2.05
    public static let strutAttachmentAboveFootpadPlaneMeters = 2.90

    /// Derived crush load. Sized so four struts absorb the maximum vertical
    /// touchdown rate the gear is rated for (10 ft/s at zero horizontal rate,
    /// per `LMLandingContactCriteria`) inside 85 % of the available stroke at
    /// the Apollo 11 touchdown mass. Static lunar weight is then only about a
    /// fifth of the crush threshold, so a soft landing leaves the struts
    /// un-stroked while a hard one visibly crushes them.
    public static let designTouchdownMassKilograms = 7_300.0
    public static let usableStrokeFraction = 0.85

    public static var primaryStrutCrushLoadNewtons: Double {
        let stroke = primaryStrutStrokeMeters * usableStrokeFraction
        let impactSpeed = LMLandingContactCriteria.maximumVerticalSpeedMetersPerSecond(
            horizontalSpeedMetersPerSecond: 0
        )
        let kinetic = 0.5 * designTouchdownMassKilograms * impactSpeed * impactSpeed
        let potential = designTouchdownMassKilograms
            * LMVehicleConfiguration.sourceBackedDefault
                .lunarGravityMetersPerSecondSquared.value
            * stroke
        return (kinetic + potential) / (stroke * Double(LMLandingGearLeg.allCases.count))
    }

    /// Unit vector from the footpad toward the strut attachment, in body axes.
    /// Compression slides the pad along this direction.
    public static func strutAxisBody(_ leg: LMLandingGearLeg) -> LMVector3D {
        let inward = -leg.outwardBody * (footpadRadiusMeters - strutAttachmentRadiusMeters)
        return LMVector3D(
            x: inward.x,
            y: inward.y,
            z: strutAttachmentAboveFootpadPlaneMeters
        ).normalized()
    }

    /// Footpad center in body axes for a given strut stroke, relative to the
    /// vehicle reference point.
    public static func footpadBody(
        _ leg: LMLandingGearLeg,
        strokeMeters: Double
    ) -> LMVector3D {
        leg.outwardBody * footpadRadiusMeters + strutAxisBody(leg) * max(0, strokeMeters)
    }

    /// Tip of the lunar-contact probe in body axes.
    public static func contactProbeTipBody(
        _ leg: LMLandingGearLeg,
        strokeMeters: Double
    ) -> LMVector3D {
        footpadBody(leg, strokeMeters: strokeMeters)
            + LMVector3D(z: -contactProbeLengthMeters)
    }

    /// Tilt at which the center of mass passes outside the line joining two
    /// adjacent footpads. Beyond this the vehicle cannot recover.
    public static var criticalTiltRadians: Double {
        let edgeDistance = footpadRadiusMeters / 2.0.squareRoot()
        return atan2(edgeDistance, centerOfMassAboveFootpadPlaneMeters)
    }
}

/// Why a modeled landing was lost.
public enum LMLandingGearFailure: String, Equatable, Sendable, Codable {
    /// A primary strut ran out of crushable honeycomb.
    case strutBottomed
    /// The vehicle rotated past the footpad support polygon.
    case tipOver
    /// Touchdown rates or attitude were outside the gear's rated envelope.
    case contactEnvelopeExceeded
}

public struct LMLandingGearLegSnapshot: Equatable, Sendable, Codable {
    public let leg: LMLandingGearLeg
    /// Permanently crushed honeycomb, meters.
    public let strokeMeters: Double
    /// Permanent regolith imprint under the pad, meters.
    public let regolithPenetrationMeters: Double
    public let isInContact: Bool
    public let peakLoadNewtons: Double

    public init(
        leg: LMLandingGearLeg,
        strokeMeters: Double = 0,
        regolithPenetrationMeters: Double = 0,
        isInContact: Bool = false,
        peakLoadNewtons: Double = 0
    ) {
        self.leg = leg
        self.strokeMeters = strokeMeters
        self.regolithPenetrationMeters = regolithPenetrationMeters
        self.isInContact = isInContact
        self.peakLoadNewtons = peakLoadNewtons
    }
}

/// Live landing-gear state carried through touchdown and settling.
public struct LMLandingGearState: Equatable, Sendable, Codable {
    public let legs: [LMLandingGearLegSnapshot]
    /// A lunar-contact probe is touching. This is the discrete that lights the
    /// cockpit CONTACT lamp, and it precedes footpad contact by 1.7 m.
    public let isProbeContact: Bool
    /// Continuous time the vehicle has been quiescent on the surface.
    public let quiescentSeconds: Double
    public let failure: LMLandingGearFailure?
    /// Highest single-pad load seen, for post-landing reporting.
    public let peakLoadNewtons: Double
    /// Number of distinct footpad touch events, so a bounce is observable.
    public let touchdownEvents: Int

    public init(
        legs: [LMLandingGearLegSnapshot] = LMLandingGearLeg.allCases.map {
            LMLandingGearLegSnapshot(leg: $0)
        },
        isProbeContact: Bool = false,
        quiescentSeconds: Double = 0,
        failure: LMLandingGearFailure? = nil,
        peakLoadNewtons: Double = 0,
        touchdownEvents: Int = 0
    ) {
        self.legs = legs
        self.isProbeContact = isProbeContact
        self.quiescentSeconds = quiescentSeconds
        self.failure = failure
        self.peakLoadNewtons = peakLoadNewtons
        self.touchdownEvents = touchdownEvents
    }

    public var isAnyFootpadInContact: Bool { legs.contains { $0.isInContact } }
    public var maximumStrokeMeters: Double { legs.map(\.strokeMeters).max() ?? 0 }
    public var isFullyStroked: Bool {
        maximumStrokeMeters >= LMLandingGearGeometry.primaryStrutStrokeMeters - 1e-6
    }

    public func snapshot(_ leg: LMLandingGearLeg) -> LMLandingGearLegSnapshot? {
        legs.first { $0.leg == leg }
    }
}

/// Rigid-body landing-gear contact with crushable struts and plastic regolith.
///
/// The vehicle keeps integrating through touchdown instead of freezing at the
/// instant of contact, so a hard arrival crushes honeycomb, a slanted arrival
/// rocks onto the downhill legs, a fast arrival can rebound off the elastic
/// part of the pad, and enough of either tips the vehicle over. The solver runs
/// on its own fixed substep because the flight loop's delta reaches 1/15 s,
/// which no useful contact stiffness survives.
public enum LMLandingGearDynamics {
    /// Fixed contact substep. Contact stiffness below is sized against this.
    public static let substepSeconds = 0.002

    /// Stiffness of a footpad resting on compacted regolith. Lunar soil is far
    /// from an elastic pad: it carries load up to a bearing limit, yields
    /// plastically into a print, then stiffens once compacted. That plateau,
    /// not this stiffness, sets how deep a print a given arrival leaves.
    public static let padStiffnessNewtonsPerMeter = 1.6e6
    /// About a tenth of critical damping at the touchdown mass, so the impulse
    /// on first touch is realistic without dominating the peak pad load.
    public static let padDampingNewtonSecondsPerMeter = 1.1e4
    /// Bearing load at which a 37 in footpad starts sinking into regolith,
    /// about 20 kPa over the pad area. Static lunar weight is only a fifth of
    /// this, so a parked vehicle barely moves, while a nominal touchdown leaves
    /// the few-centimeter print Apollo and Surveyor footpads actually left. The
    /// crushable strut, not the soil, remains the energy absorber for anything
    /// harder.
    public static let regolithBearingLoadNewtons = 1.4e4
    /// Deepest print before the soil under the pad is fully compacted. Past
    /// this the crushable strut, not the regolith, absorbs what is left.
    public static let maximumRegolithPenetrationMeters = 0.12
    /// Soil cannot be displaced faster than the pad is driving into it.
    public static let sinkRateMarginOverClosingRate = 2.0
    /// Coulomb friction against lunar soil. The reported regolith friction
    /// angle of roughly 35-40 degrees puts this near 0.8.
    public static let regolithFrictionCoefficient = 0.8
    /// Honeycomb cannot crush faster than the pad is closing on the ground.
    public static let strokeRateMarginOverClosingRate = 2.0
    public static let minimumStrokeRateMetersPerSecond = 0.1

    public static let quiescentSpeedMetersPerSecond = 0.05
    public static let quiescentRateRadiansPerSecond = 0.02
    public static let requiredQuiescentSeconds = 0.75

    public struct Result: Equatable, Sendable {
        public var positionMeters: LMVector3D
        public var velocityMetersPerSecond: LMVector3D
        public var attitude: LMQuaternion
        public var angularVelocityRadiansPerSecond: LMVector3D
        public var gear: LMLandingGearState
        /// First footpad touchdown observed during this call, if any.
        public var firstContact: LMSurfaceContactSnapshot?
        public var isSettled: Bool
    }

    /// Integrate one flight-loop delta with gear contact active.
    ///
    /// `accelerationMetersPerSecondSquared` and `angularAccelerationRadiansPerSecondSquared`
    /// are the non-contact terms the caller already computed (gravity, rotating
    /// frame, and any thrust still commanded); they are held constant across
    /// the substeps, which is exact enough over a 1/15 s frame.
    public static func integrate(
        positionMeters: LMVector3D,
        velocityMetersPerSecond: LMVector3D,
        attitude: LMQuaternion,
        angularVelocityRadiansPerSecond: LMVector3D,
        massKilograms: Double,
        inertiaKilogramMetersSquared: LMVector3D,
        accelerationMetersPerSecondSquared: LMVector3D,
        angularAccelerationRadiansPerSecondSquared: LMVector3D,
        gear: LMLandingGearState,
        surface: LMLandingSurfaceModel,
        deltaTime: Double
    ) -> Result {
        var position = positionMeters
        var velocity = velocityMetersPerSecond
        var orientation = attitude
        var angularVelocity = angularVelocityRadiansPerSecond
        var legs = Dictionary(
            uniqueKeysWithValues: gear.legs.map { ($0.leg, $0) }
        )
        var failure = gear.failure
        var quiescent = gear.quiescentSeconds
        var peakLoad = gear.peakLoadNewtons
        var touchdownEvents = gear.touchdownEvents
        var firstContact: LMSurfaceContactSnapshot?
        var probeContact = gear.isProbeContact
        var settled = false

        let mass = max(massKilograms, 1)
        let substeps = max(1, Int((deltaTime / substepSeconds).rounded(.up)))
        let step = deltaTime / Double(substeps)

        for _ in 0..<substeps {
            var contactForce = LMVector3D.zero
            var contactTorqueBody = LMVector3D.zero
            var anyPadContact = false
            var anyProbeContact = false

            for leg in LMLandingGearLeg.allCases {
                var snapshot = legs[leg] ?? LMLandingGearLegSnapshot(leg: leg)

                if leg.hasContactProbe, !probeContact {
                    let tip = orientation.rotated(
                        LMLandingGearGeometry.contactProbeTipBody(
                            leg,
                            strokeMeters: snapshot.strokeMeters
                        )
                    )
                    let tipWorld = position + tip
                    let ground = surface.surfaceHeightMeters(
                        northMeters: tipWorld.x,
                        eastMeters: tipWorld.y
                    )
                    if tipWorld.z <= ground { anyProbeContact = true }
                }

                let arm = orientation.rotated(
                    LMLandingGearGeometry.footpadBody(
                        leg,
                        strokeMeters: snapshot.strokeMeters
                    )
                )
                let padWorld = position + arm
                let ground = surface.surfaceHeightMeters(
                    northMeters: padWorld.x,
                    eastMeters: padWorld.y
                )
                let penetration = ground - padWorld.z

                func liftOff() {
                    guard snapshot.isInContact else { return }
                    legs[leg] = LMLandingGearLegSnapshot(
                        leg: leg,
                        strokeMeters: snapshot.strokeMeters,
                        regolithPenetrationMeters: snapshot.regolithPenetrationMeters,
                        isInContact: false,
                        peakLoadNewtons: snapshot.peakLoadNewtons
                    )
                }

                guard penetration > 0 else {
                    liftOff()
                    continue
                }

                let normal = surface.surfaceNormal(
                    northMeters: padWorld.x,
                    eastMeters: padWorld.y
                )
                let padVelocity = velocity
                    + orientation.rotated(
                        angularVelocity.cross(
                            LMLandingGearGeometry.footpadBody(
                                leg,
                                strokeMeters: snapshot.strokeMeters
                            )
                        )
                    )
                let closingRate = -padVelocity.dot(normal)

                // The regolith keeps whatever print the pad has already pushed
                // into it, so only the elastic remainder can push back. Load
                // above the bearing limit deepens the print at constant force
                // until the soil under the pad is compacted.
                var imprint = min(
                    snapshot.regolithPenetrationMeters,
                    maximumRegolithPenetrationMeters
                )
                func padLoad() -> Double {
                    padStiffnessNewtonsPerMeter * max(0, penetration - imprint)
                        + padDampingNewtonSecondsPerMeter * max(0, closingRate)
                }
                var load = padLoad()
                if load > regolithBearingLoadNewtons,
                   imprint < maximumRegolithPenetrationMeters {
                    let sinkRateLimit = max(closingRate, 0) * sinkRateMarginOverClosingRate
                    let sink = min(
                        (load - regolithBearingLoadNewtons) / padStiffnessNewtonsPerMeter,
                        sinkRateLimit * step
                    )
                    imprint = min(imprint + sink, maximumRegolithPenetrationMeters)
                    load = padLoad()
                }
                // The pad rests in the hole it made. Once it climbs back out of
                // that imprint the leg is airborne again, which is how a bounce
                // becomes a second touchdown rather than a silent oscillation.
                guard load > 0 else {
                    liftOff()
                    continue
                }

                if !snapshot.isInContact {
                    touchdownEvents += 1
                    if firstContact == nil, gear.touchdownEvents == 0 {
                        firstContact = contactSnapshot(
                            position: position,
                            velocity: velocity,
                            attitude: orientation,
                            normal: normal
                        )
                    }
                }

                // Crushable primary strut: the honeycomb holds a near-constant
                // load and strokes as far as it must to keep it there.
                var stroke = snapshot.strokeMeters
                let axis = orientation.rotated(LMLandingGearGeometry.strutAxisBody(leg))
                let alignment = max(normal.dot(axis), 0.2)
                let crushLimit = LMLandingGearGeometry.primaryStrutCrushLoadNewtons / alignment
                if load > crushLimit {
                    let excess = (load - crushLimit) * alignment
                    let relaxation = 0.5 * excess
                        / (padStiffnessNewtonsPerMeter * alignment * alignment)
                    let strokeRateLimit = max(closingRate, 0) * strokeRateMarginOverClosingRate
                        + minimumStrokeRateMetersPerSecond
                    stroke += min(relaxation, strokeRateLimit * step)
                    load = crushLimit
                    if stroke >= LMLandingGearGeometry.primaryStrutStrokeMeters {
                        stroke = LMLandingGearGeometry.primaryStrutStrokeMeters
                        failure = failure ?? .strutBottomed
                    }
                }

                var force = normal * load
                let tangentialVelocity = padVelocity - normal * padVelocity.dot(normal)
                let tangentialSpeed = tangentialVelocity.magnitude
                if tangentialSpeed > 1e-6 {
                    // Cap friction at the impulse that would just stop the slide
                    // this substep so a stationary pad cannot be driven backward.
                    let arrest = tangentialSpeed * mass
                        / (step * Double(LMLandingGearLeg.allCases.count))
                    let friction = min(regolithFrictionCoefficient * load, arrest)
                    force = force - tangentialVelocity * (friction / tangentialSpeed)
                }

                contactForce = contactForce + force
                contactTorqueBody = contactTorqueBody
                    + (
                        LMLandingGearGeometry.footpadBody(leg, strokeMeters: stroke)
                            - LMLandingGearGeometry.centerOfMassBody
                    ).cross(orientation.inverseRotated(force))
                anyPadContact = true
                peakLoad = max(peakLoad, load)

                legs[leg] = LMLandingGearLegSnapshot(
                    leg: leg,
                    strokeMeters: stroke,
                    regolithPenetrationMeters: imprint,
                    isInContact: true,
                    peakLoadNewtons: max(snapshot.peakLoadNewtons, load)
                )
            }

            if anyProbeContact { probeContact = true }

            // Linear momentum acts on the center of mass, so the reference
            // point follows it through the attitude rather than the other way
            // around. Without this the vehicle would pivot about its own feet
            // and could never tip.
            let centerOfMassArm = orientation.rotated(
                LMLandingGearGeometry.centerOfMassBody
            )
            var centerOfMass = position + centerOfMassArm
            var centerOfMassVelocity = velocity + orientation.rotated(
                angularVelocity.cross(LMLandingGearGeometry.centerOfMassBody)
            )
            centerOfMassVelocity = centerOfMassVelocity
                + (accelerationMetersPerSecondSquared + contactForce / mass) * step
            centerOfMass = centerOfMass + centerOfMassVelocity * step

            let angularAcceleration = LMVector3D(
                x: inertiaKilogramMetersSquared.x == 0
                    ? 0
                    : contactTorqueBody.x / inertiaKilogramMetersSquared.x,
                y: inertiaKilogramMetersSquared.y == 0
                    ? 0
                    : contactTorqueBody.y / inertiaKilogramMetersSquared.y,
                z: inertiaKilogramMetersSquared.z == 0
                    ? 0
                    : contactTorqueBody.z / inertiaKilogramMetersSquared.z
            )
            angularVelocity = angularVelocity
                + (angularAccelerationRadiansPerSecondSquared + angularAcceleration) * step
            orientation = orientation.integrated(
                angularVelocityRadiansPerSecond: angularVelocity,
                deltaTime: step
            )
            position = centerOfMass - orientation.rotated(
                LMLandingGearGeometry.centerOfMassBody
            )
            velocity = centerOfMassVelocity - orientation.rotated(
                angularVelocity.cross(LMLandingGearGeometry.centerOfMassBody)
            )

            let localUp = localUpDirection(position: position, surface: surface)
            let tilt = tiltRadians(attitude: orientation, localUp: localUp)
            if tilt > LMLandingGearGeometry.criticalTiltRadians {
                failure = failure ?? .tipOver
            }

            if anyPadContact,
               velocity.magnitude < quiescentSpeedMetersPerSecond,
               angularVelocity.magnitude < quiescentRateRadiansPerSecond {
                quiescent += step
            } else {
                quiescent = 0
            }
            if quiescent >= requiredQuiescentSeconds || failure != nil {
                settled = true
                break
            }
        }

        return Result(
            positionMeters: position,
            velocityMetersPerSecond: velocity,
            attitude: orientation.normalized(),
            angularVelocityRadiansPerSecond: angularVelocity,
            gear: LMLandingGearState(
                legs: LMLandingGearLeg.allCases.map {
                    legs[$0] ?? LMLandingGearLegSnapshot(leg: $0)
                },
                isProbeContact: probeContact,
                quiescentSeconds: quiescent,
                failure: failure,
                peakLoadNewtons: peakLoad,
                touchdownEvents: touchdownEvents
            ),
            firstContact: firstContact,
            isSettled: settled
        )
    }

    /// True once any part of the gear can reach the surface, including the
    /// 1.7 m contact probes. Above this the flight integrator does no contact
    /// work at all.
    public static func isWithinContactRange(
        positionMeters: LMVector3D,
        attitude: LMQuaternion,
        gear: LMLandingGearState,
        surface: LMLandingSurfaceModel
    ) -> Bool {
        // Probe length plus the swing a tilted vehicle gives its outermost pad.
        let reach = LMLandingGearGeometry.contactProbeLengthMeters
            + LMLandingGearGeometry.footpadRadiusMeters
        let ground = surface.surfaceHeightMeters(
            northMeters: positionMeters.x,
            eastMeters: positionMeters.y
        )
        return positionMeters.z - ground <= reach
    }

    public static func localUpDirection(
        position: LMVector3D,
        surface: LMLandingSurfaceModel
    ) -> LMVector3D {
        surface.surfaceNormal(northMeters: position.x, eastMeters: position.y)
    }

    /// Angle between the vehicle's thrust axis and the local surface normal.
    public static func tiltRadians(attitude: LMQuaternion, localUp: LMVector3D) -> Double {
        let bodyUp = attitude.rotated(LMVector3D(z: 1)).normalized()
        return acos(min(max(bodyUp.dot(localUp), -1), 1))
    }

    private static func contactSnapshot(
        position: LMVector3D,
        velocity: LMVector3D,
        attitude: LMQuaternion,
        normal: LMVector3D
    ) -> LMSurfaceContactSnapshot {
        let vertical = velocity.dot(normal)
        let horizontal = (velocity - normal * vertical).magnitude
        return LMSurfaceContactSnapshot(
            groundRangeMeters: hypot(position.x, position.y),
            horizontalSpeedMetersPerSecond: horizontal,
            verticalSpeedMetersPerSecond: max(0, -vertical),
            tiltRadians: tiltRadians(attitude: attitude, localUp: normal),
            surfaceNormal: normal
        )
    }
}
