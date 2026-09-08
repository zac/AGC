import AGC
import Foundation

public struct LMSourceReference: Equatable, Sendable, Identifiable, Codable {
    public let id: String
    public let title: String
    public let url: String?
    public let detail: String

    public init(id: String, title: String, url: String? = nil, detail: String) {
        self.id = id
        self.title = title
        self.url = url
        self.detail = detail
    }
}

public struct LMSourceLocator: Equatable, Sendable, Codable {
    public let reference: LMSourceReference
    public let section: String?
    public let detail: String

    public init(reference: LMSourceReference, section: String? = nil, detail: String) {
        self.reference = reference
        self.section = section
        self.detail = detail
    }
}

public struct LMModelingStatus: Equatable, Sendable, Codable {
    public let isSourceBacked: Bool
    public let detail: String
    public let source: LMSourceLocator?

    public init(isSourceBacked: Bool, detail: String, source: LMSourceLocator? = nil) {
        self.isSourceBacked = isSourceBacked
        self.detail = detail
        self.source = source
    }

    public static func sourceBacked(detail: String, source: LMSourceLocator) -> LMModelingStatus {
        LMModelingStatus(isSourceBacked: true, detail: detail, source: source)
    }
}

public extension LMSourceReference {
    static let luminaryIOChannels = LMSourceReference(
        id: "luminary099-input-output-channel-bit-descriptions",
        title: "Luminary099 input/output channel bit descriptions",
        url: "https://github.com/chrislgarry/Apollo-11/blob/master/Luminary099/INPUT_OUTPUT_CHANNEL_BIT_DESCRIPTIONS.agc",
        detail: "Primary source for named AGC input/output channel bits."
    )

    static let luminaryQRCSAutopilot = LMSourceReference(
        id: "luminary099-q-r-axis-rcs-autopilot",
        title: "Luminary099 Q/R-axis RCS autopilot",
        url: "https://github.com/chrislgarry/Apollo-11/blob/master/Luminary099/Q_R-AXIS_RCS_AUTOPILOT.agc",
        detail: "Source for channel 005 ALLJETS bit-to-jet table."
    )

    static let luminaryPRCSAutopilot = LMSourceReference(
        id: "luminary099-p-axis-rcs-autopilot",
        title: "Luminary099 P-axis RCS autopilot",
        url: "https://github.com/chrislgarry/Apollo-11/blob/master/Luminary099/P-AXIS_RCS_AUTOPILOT.agc",
        detail: "Source for channel 006 JETSALL bit groups and P-axis jet numbers."
    )

    static let yaAGCRadarRequest = LMSourceReference(
        id: "yaagc-radar-request",
        title: "yaAGC radar request path",
        detail: "references/yaAGC/agc_engine.c documents radar gate completion loading RNRAD with radar data."
    )

    static let luminaryPIPAScale = LMSourceReference(
        id: "nasa-r567-luminary-pipa-scale",
        title: "NASA R-567 / Luminary SERVICER PIPA scale",
        detail: "SERVICER ABDELV is cm/s at 2(-14); one PINC is 1 cm/s so DVMON’s DPSTHRSH 36 cm/s is ~600 lbf. R-567’s 5.85 cm/s is the analog IMU quantum, not the PINC size."
    )

    static let agcCDUEncoding = LMSourceReference(
        id: "agc-cdu-15bit-encoding",
        title: "AGC CDU 15-bit encoding",
        detail: "CDUX/Y/Z are 15-bit counters wrapping at 32768 counts per revolution (360 degrees)."
    )

    static let luminaryLandingRadarScale = LMSourceReference(
        id: "luminary099-landing-radar-low-scale",
        title: "Luminary099 landing radar low-scale altitude",
        url: "https://github.com/chrislgarry/Apollo-11/blob/master/Luminary099/LANDING_RADAR_RUPT.agc",
        detail: "Landing radar low-scale altitude is 1.079 feet per bit. Velocity beams are LVELBIAS 12288 with VX/Y/Z −0.644 / 1.212 / 0.8668 ft/s per bit (CONTROLLED_CONSTANTS)."
    )

    static let luminaryThrottleConstants = LMSourceReference(
        id: "luminary099-throttle-control-routines",
        title: "Luminary099 throttle control routines and controlled constants",
        url: "https://github.com/chrislgarry/Apollo-11/blob/master/Luminary099/THROTTLE_CONTROL_ROUTINES.agc",
        detail: "THRUST/CHAN14 pulse interface, 10%–94% throttle region, FMAXPOS 3467 = 4.34546769e4 N, FRATE 32 units/cs."
    )

    static let luminaryRCSGeometry = LMSourceReference(
        id: "luminary099-rcs-alljets-torkjet",
        title: "Luminary099 ALLJETS/TYPEPOLY/JETSALL RCS geometry and TORKJET1 arm",
        url: "https://github.com/chrislgarry/Apollo-11/blob/master/Luminary099/Q_R-AXIS_RCS_AUTOPILOT.agc",
        detail: "Channel 005 ALLJETS U/V jets, TYPEPOLY ±X, channel 006 JETSALL ±P/±Y/±Z, FRCS4 400 lbf/4 jets, TORKJET1 550 ft-lbf → 5.5 ft arm, clusters at 45°."
    )

    static let luminary1ACCS = LMSourceReference(
        id: "luminary099-aostask-1accs",
        title: "Luminary099 1/ACCS INERCON jet-acceleration curve fits",
        url: "https://github.com/chrislgarry/Apollo-11/blob/master/Luminary099/AOSTASK_AND_AOSJOB.agc",
        detail: "1JACC = A/(MASS+C)+B; I = TORKJET1/1JACC. L,PVT-CG uses the same fit at 8 ft. A scaled at π/4 rad/s²·2^16 kg (L at 8 ft·2^16 kg), B at π/4 (L at 8 ft), C at 2^16 kg. NASA P/Q/R map to sim Z/X/Y."
    )

    static let nasaTN6846PoweredDescent = LMSourceReference(
        id: "nasa-tn-d-6846-powered-descent",
        title: "NASA TN D-6846 Apollo Experience Report: Mission Planning for Lunar Module Descent and Ascent",
        url: "https://ntrs.nasa.gov/api/citations/19720018205/downloads/19720018205.pdf",
        detail: "Table I Apollo 11 premission powered-descent event summary: PDI inertial velocity 5560 fps, altitude rate -4 fps, altitude 48,814 ft."
    )

    static let nasaTN4131PDIAttitude = LMSourceReference(
        id: "nasa-tn-d-4131-pdi-attitude",
        title: "NASA TN D-4131 Lunar Module Pilot Control Considerations",
        url: "https://ibiblio.org/apollo/Documents/TN-D-4131%20Lunar%20Module%20Pilot%20Control%20Considerations.pdf",
        detail: "PDI pitch is approximately 95° back from local vertical; DPS trim gimbals drive at 0.2 deg/s."
    )

    static let nasaR567GimbalTrim = LMSourceReference(
        id: "nasa-r567-descent-engine-trim-gimbal",
        title: "NASA R-567 Luminary GSOP Section 3 Digital Autopilot",
        url: "https://www.ibiblio.org/apollo/Documents/j2-80-R-567-SEC3-REV8_text.pdf",
        detail: "Descent-engine trim gimbals: 0.2 deg/s drive, stops at -6 deg, then timed drive to the N48 trim angles."
    )

    static let luminaryErasableAssignments = LMSourceReference(
        id: "luminary099-erasable-assignments",
        title: "Luminary099 erasable assignments",
        url: "https://ibiblio.org/apollo/listings/Luminary099/ERASABLE_ASSIGNMENTS.agc.html",
        detail: "yaYUL listing: RN 01220, VN 01226, PIPTIME 01234, MASS 01244, REFSMMAT E3,1733, RLS E4,1422 (ECADR 02022)."
    )

    static let luminaryControlledConstants = LMSourceReference(
        id: "luminary099-controlled-constants-504rm",
        title: "Luminary099 controlled constants 504RM",
        url: "https://ibiblio.org/apollo/listings/Luminary099/CONTROLLED_CONSTANTS.agc.html",
        detail: "504RM 2DEC 1738090 B-29; MUM 2DEC* 4.9027780 E8 B-30* lunar GM m³/cs²; DPSVEX VE +2.95588868E+3 m/s (MASSMON)."
    )

    static let luminaryFlagwordAssignments = LMSourceReference(
        id: "luminary099-flagword-assignments",
        title: "Luminary099 flagword assignments",
        url: "https://github.com/virtualagc/virtualagc/blob/master/Luminary099/FLAGWORD_ASSIGNMENTS.agc",
        detail: "MOONFLAG (003), LUNAFLAG (048), LMOONFLG (124), and REFSMFLG (047) select lunar-SOI scaling and a valid REFSMMAT."
    )

    static let nasaR567NavScales = LMSourceReference(
        id: "nasa-r567-luminary-nav-scales",
        title: "NASA R-567 Luminary GSOP Section 5 guidance equations",
        url: "https://ibiblio.org/apollo/Documents/j2-80-R-567-SEC5-REV11_text.pdf",
        detail: "Lunar-SOI RN meters B27, VN meters/centisecond B5, RLS moon-fixed meters B27, REFSMMAT half-unit direction cosines, MASS kilograms B16."
    )

    static let nasaSNA8D027Luminary99PadLoads = LMSourceReference(
        id: "nasa-sna-8-d-027-luminary99-pad-loads",
        title: "NASA SNA-8-D-027(II) LM Data Book Luminary 99 prelaunch erasable load",
        url: "https://www.ibiblio.org/apollo/Documents/Luminary99PadLoads.pdf",
        detail: "Table LM5/4.5.1-1: TLAND 100:50:49.20 GET, braking/approach aimpoints, VIGN/RIGNX/RIGNZ, NASA RLS, TEPHEM/AZO/504LM, V2FG −3 ft/s, ZOOMTIME 26 s."
    )

    static let luminaryP63GUIDDURN = LMSourceReference(
        id: "luminary099-the-lunar-landing-guiddurn",
        title: "Luminary099 THE_LUNAR_LANDING GUIDDURN",
        url: "https://github.com/chrislgarry/Apollo-11/blob/master/Luminary099/THE_LUNAR_LANDING.agc",
        detail: "GUIDDURN 2DEC +66440 is 664.40 s from IGNALG to landing. P63SPOT3 waits for CH33 LR POS1. R51P63 ENTER skips fine-align and returns to P63SPOT2."
    )

    static let luminaryBurnBaby = LMSourceReference(
        id: "luminary099-burn-baby",
        title: "Luminary099 BURN, BABY, BURN -- MASTER IGNITION ROUTINE",
        url: "https://github.com/chrislgarry/Apollo-11/blob/master/Luminary099/BURN,_BABY,_BURN_--_MASTER_IGNITION_ROUTINE.agc",
        detail: "V99 at TIG-5 via CLOCPLAY; PROCEED sets ASTNFLAG; IGNYET? lights the engine at TIG."
    )

    static let luminaryPlanetaryInertialOrientation = LMSourceReference(
        id: "luminary099-planetary-inertial-orientation",
        title: "Luminary099 PLANETARY_INERTIAL_ORIENTATION",
        url: "https://github.com/chrislgarry/Apollo-11/blob/master/Luminary099/PLANETARY_INERTIAL_ORIENTATION.agc",
        detail: "RP-TO-R: R = Mᵀ(T)*(RP + L×RP). MOONMX builds M from BSUBO/BDOT, FSUBO/FDOT, NODIO/NODDOT, COSI/SINI, and TEPHEM."
    )
}

public extension LMSourceLocator {
    static let luminaryIOChannels = LMSourceLocator(
        reference: .luminaryIOChannels,
        detail: "Named bit mapping from INPUT_OUTPUT_CHANNEL_BIT_DESCRIPTIONS.agc."
    )

    static let channel5RCSJets = LMSourceLocator(
        reference: .luminaryQRCSAutopilot,
        section: "ALLJETS",
        detail: "Channel 005 bit-to-jet mapping from the ALLJETS table."
    )

    static let channel6RCSGroups = LMSourceLocator(
        reference: .luminaryPRCSAutopilot,
        section: "JETSALL",
        detail: "Channel 006 JETSALL ±P/±Y/±Z bit groups and P-axis jet numbers 3,4,7,8,11,12,15,16."
    )

    static let yaAGCRadarRequest = LMSourceLocator(
        reference: .yaAGCRadarRequest,
        detail: "Raw radar register word injection follows the yaAGC radar request hook."
    )

    static let luminaryPIPAScale = LMSourceLocator(
        reference: .luminaryPIPAScale,
        detail: "PIPA PINCs are 1 cm/s so SERVICER ABDELV matches DVMON’s cm/s threshold."
    )

    static let agcCDUEncoding = LMSourceLocator(
        reference: .agcCDUEncoding,
        detail: "CDU catch-up pulses use 32768 counts per revolution."
    )

    static let luminaryLandingRadarScale = LMSourceLocator(
        reference: .luminaryLandingRadarScale,
        detail: "SI altitude is converted at 1.079 feet per bit (low scale)."
    )

    static let luminaryThrottleConstants = LMSourceLocator(
        reference: .luminaryThrottleConstants,
        detail: "DPS thrust from THRUST pulse units via FMAXPOS and the 10%–94% throttle region."
    )

    static let luminaryRCSGeometry = LMSourceLocator(
        reference: .luminaryRCSGeometry,
        detail: "Channel 005/006 jet force/position from ALLJETS, TYPEPOLY, JETSALL, FRCS4, and TORKJET1."
    )

    static let luminary1ACCS = LMSourceLocator(
        reference: .luminary1ACCS,
        detail: "Diagonal inertia from 1/ACCS INERCON curve fits and TORKJET1; DPS gimbal torque from L,PVT-CG."
    )

    static let nasaTN6846PoweredDescent = LMSourceLocator(
        reference: .nasaTN6846PoweredDescent,
        section: "Table I",
        detail: "Apollo 11 premission PDI: 5560 fps inertial, -4 fps altitude rate, 48,814 ft."
    )

    static let nasaTN4131PDIAttitude = LMSourceLocator(
        reference: .nasaTN4131PDIAttitude,
        detail: "PDI attitude 95° from local vertical; trim-gimbal rate 0.2 deg/s."
    )

    static let nasaR567GimbalTrim = LMSourceLocator(
        reference: .nasaR567GimbalTrim,
        detail: "Channel 12 pitch/roll trim bits slew DPS gimbals at 0.2 deg/s within ±6 deg stops."
    )

    static let luminaryErasableAssignments = LMSourceLocator(
        reference: .luminaryErasableAssignments,
        detail: "ECADRs for RN, VN, PIPTIME, MASS, REFSMMAT, RLS, and LEM integration vectors."
    )

    static let luminaryControlledConstants = LMSourceLocator(
        reference: .luminaryControlledConstants,
        detail: "Landing-site radius uses Luminary 504RM = 1,738,090 m. IGNALG PDI coast uses MUM."
    )

    static let luminaryFlagwordAssignments = LMSourceLocator(
        reference: .luminaryFlagwordAssignments,
        detail: "MOONFLAG/LUNAFLAG/LMOONFLG set so Average-G uses lunar B27/B5 scales."
    )

    static let nasaR567NavScales = LMSourceLocator(
        reference: .nasaR567NavScales,
        detail: "Sourced PDI kinematics are coasted backward to live GET and encoded into RN/VN/RLS/MASS at GSOP lunar-SOI scales; PDI is ZOOMTIME before RIGN."
    )

    static let nasaSNA8D027Luminary99PadLoads = LMSourceLocator(
        reference: .nasaSNA8D027Luminary99PadLoads,
        section: "Table LM5/4.5.1-1",
        detail: "Landing-guidance overlay TLAND through TAUVERT, launch-tape TEPHEM/AZO/504LM, and NASA RLS at ECADR 02022."
    )

    static let luminaryP63GUIDDURN = LMSourceLocator(
        reference: .luminaryP63GUIDDURN,
        detail: "AGC clock stays at Luminary GET. TLAND is GET + GUIDDURN + ZOOMTIME + SEC45 + D29.9SEC + TIMEDELT so MIDTOAV1 and BURNBABY’s TIG-35 LONGCALL both have a positive dt after IGNALG."
    )

    static let luminaryBurnBaby = LMSourceLocator(
        reference: .luminaryBurnBaby,
        detail: "Auto-PRO holds inverted CH32 bit 14 for 150 ms on V06N61 and V99; ENTER skips V50N25 fine-align and V50N18 R60 (ENDMANU1)."
    )

    static let luminaryPlanetaryInertialOrientation = LMSourceLocator(
        reference: .luminaryPlanetaryInertialOrientation,
        detail: "PDI is ZOOMTIME of MUM two-body before LAND+(RIGNX,0,RIGNZ) in P52LS SM; the live RN/VN state is a further pre-ignition coast backward; VN includes GUIDINIT WM×R; RCV=RRECT."
    )

    static let luminaryIOChannelsModeControl = LMSourceLocator(
        reference: .luminaryIOChannels,
        detail: "CH31 bit 14 AUTO and CH30 bit 5 auto-throttle are inverted discretes; 0 means present."
    )
}

public struct LMSourceValue<Value: Equatable & Sendable>: Equatable, Sendable {
    public let value: Value
    public let source: LMSourceReference

    public init(_ value: Value, source: LMSourceReference) {
        self.value = value
        self.source = source
    }
}

extension LMSourceValue: Codable where Value: Codable {}

public struct LMVector3D: Equatable, Sendable, Codable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double = 0, y: Double = 0, z: Double = 0) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = LMVector3D()

    public var magnitude: Double {
        sqrt(x * x + y * y + z * z)
    }

    public func normalized() -> LMVector3D {
        let length = magnitude
        guard length > 0 else { return .zero }
        return self / length
    }

    public func dot(_ other: LMVector3D) -> Double {
        x * other.x + y * other.y + z * other.z
    }

    public func cross(_ other: LMVector3D) -> LMVector3D {
        LMVector3D(
            x: y * other.z - z * other.y,
            y: z * other.x - x * other.z,
            z: x * other.y - y * other.x
        )
    }

    public static func + (lhs: LMVector3D, rhs: LMVector3D) -> LMVector3D {
        LMVector3D(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    public static func - (lhs: LMVector3D, rhs: LMVector3D) -> LMVector3D {
        LMVector3D(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    public static prefix func - (value: LMVector3D) -> LMVector3D {
        LMVector3D(x: -value.x, y: -value.y, z: -value.z)
    }

    public static func * (lhs: LMVector3D, rhs: Double) -> LMVector3D {
        LMVector3D(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
    }

    public static func * (lhs: Double, rhs: LMVector3D) -> LMVector3D {
        rhs * lhs
    }

    public static func / (lhs: LMVector3D, rhs: Double) -> LMVector3D {
        LMVector3D(x: lhs.x / rhs, y: lhs.y / rhs, z: lhs.z / rhs)
    }
}

public struct LMQuaternion: Equatable, Sendable, Codable {
    public let w: Double
    public let x: Double
    public let y: Double
    public let z: Double

    public init(w: Double = 1, x: Double = 0, y: Double = 0, z: Double = 0) {
        self.w = w
        self.x = x
        self.y = y
        self.z = z
    }

    public static let identity = LMQuaternion()

    public func normalized() -> LMQuaternion {
        let length = sqrt(w * w + x * x + y * y + z * z)
        guard length > 0 else { return .identity }
        return LMQuaternion(w: w / length, x: x / length, y: y / length, z: z / length)
    }

    public func multiplied(by rhs: LMQuaternion) -> LMQuaternion {
        LMQuaternion(
            w: w * rhs.w - x * rhs.x - y * rhs.y - z * rhs.z,
            x: w * rhs.x + x * rhs.w + y * rhs.z - z * rhs.y,
            y: w * rhs.y - x * rhs.z + y * rhs.w + z * rhs.x,
            z: w * rhs.z + x * rhs.y - y * rhs.x + z * rhs.w
        )
    }

    public func rotated(_ vector: LMVector3D) -> LMVector3D {
        let qVector = LMVector3D(x: x, y: y, z: z)
        let t = 2 * qVector.cross(vector)
        return vector + w * t + qVector.cross(t)
    }

    public var conjugated: LMQuaternion {
        LMQuaternion(w: w, x: -x, y: -y, z: -z)
    }

    public func inverseRotated(_ vector: LMVector3D) -> LMVector3D {
        conjugated.rotated(vector)
    }

    /// 3-2-1 yaw-pitch-roll (Z, Y, X) in radians, used as a stand-in for IMU gimbal angles.
    public var yawPitchRollRadians: LMVector3D {
        let q = normalized()
        let sinr = 2 * (q.w * q.x + q.y * q.z)
        let cosr = 1 - 2 * (q.x * q.x + q.y * q.y)
        let roll = atan2(sinr, cosr)

        let sinp = 2 * (q.w * q.y - q.z * q.x)
        let pitch: Double
        if abs(sinp) >= 1 {
            pitch = copysign(.pi / 2, sinp)
        } else {
            pitch = asin(sinp)
        }

        let siny = 2 * (q.w * q.z + q.x * q.y)
        let cosy = 1 - 2 * (q.y * q.y + q.z * q.z)
        let yaw = atan2(siny, cosy)
        return LMVector3D(x: roll, y: pitch, z: yaw)
    }

    public func integrated(angularVelocityRadiansPerSecond: LMVector3D, deltaTime: Double) -> LMQuaternion {
        let angle = angularVelocityRadiansPerSecond.magnitude * deltaTime
        guard angle > 0 else { return self }
        let axis = angularVelocityRadiansPerSecond.normalized()
        let half = angle / 2
        let delta = LMQuaternion(
            w: cos(half),
            x: axis.x * sin(half),
            y: axis.y * sin(half),
            z: axis.z * sin(half)
        )
        return multiplied(by: delta).normalized()
    }

    public static func fromAxisAngle(axis: LMVector3D, radians: Double) -> LMQuaternion {
        let half = radians / 2
        let direction = axis.normalized()
        guard direction.magnitude > 0 else { return .identity }
        return LMQuaternion(
            w: cos(half),
            x: direction.x * sin(half),
            y: direction.y * sin(half),
            z: direction.z * sin(half)
        ).normalized()
    }
}

public struct LMMainEngineConfiguration: Equatable, Sendable, Codable {
    public let maximumRatedThrustNewtons: LMSourceValue<Double>
    public let engineOnThrustNewtons: LMSourceValue<Double>?

    public init(
        maximumRatedThrustNewtons: LMSourceValue<Double>,
        engineOnThrustNewtons: LMSourceValue<Double>? = nil
    ) {
        self.maximumRatedThrustNewtons = maximumRatedThrustNewtons
        self.engineOnThrustNewtons = engineOnThrustNewtons
    }
}

public struct LMRCSJetConfiguration: Equatable, Sendable, Codable {
    public let jet: LMRCSJet
    public let positionMeters: LMSourceValue<LMVector3D>
    public let thrustDirectionBody: LMSourceValue<LMVector3D>
    public let thrustNewtons: LMSourceValue<Double>

    public init(
        jet: LMRCSJet,
        positionMeters: LMSourceValue<LMVector3D>,
        thrustDirectionBody: LMSourceValue<LMVector3D>,
        thrustNewtons: LMSourceValue<Double>
    ) {
        self.jet = jet
        self.positionMeters = positionMeters
        self.thrustDirectionBody = thrustDirectionBody
        self.thrustNewtons = thrustNewtons
    }
}

public struct LMVehicleConfiguration: Equatable, Sendable, Codable {
    public let lunarGravityMetersPerSecondSquared: LMSourceValue<Double>
    public let agcCyclesPerSecond: LMSourceValue<Double>
    public let mainEngine: LMMainEngineConfiguration?
    public let rcsJets: [LMRCSJet: LMRCSJetConfiguration]
    public let inertiaStage: LMInertiaStage
    public let diagonalInertiaKilogramMetersSquared: LMSourceValue<LMVector3D>?

    public init(
        lunarGravityMetersPerSecondSquared: LMSourceValue<Double>,
        agcCyclesPerSecond: LMSourceValue<Double>,
        mainEngine: LMMainEngineConfiguration? = nil,
        rcsJets: [LMRCSJet: LMRCSJetConfiguration] = [:],
        inertiaStage: LMInertiaStage = .descent,
        diagonalInertiaKilogramMetersSquared: LMSourceValue<LMVector3D>? = nil
    ) {
        self.lunarGravityMetersPerSecondSquared = lunarGravityMetersPerSecondSquared
        self.agcCyclesPerSecond = agcCyclesPerSecond
        self.mainEngine = mainEngine
        self.rcsJets = rcsJets
        self.inertiaStage = inertiaStage
        self.diagonalInertiaKilogramMetersSquared = diagonalInertiaKilogramMetersSquared
    }

    public var sourceReferences: [LMSourceReference] {
        var references: [LMSourceReference] = [
            lunarGravityMetersPerSecondSquared.source,
            agcCyclesPerSecond.source
        ]
        if let mainEngine {
            references.append(mainEngine.maximumRatedThrustNewtons.source)
            if let engineOnThrust = mainEngine.engineOnThrustNewtons {
                references.append(engineOnThrust.source)
            }
        }
        if let inertia = diagonalInertiaKilogramMetersSquared {
            references.append(inertia.source)
        } else {
            references.append(LMInertiaMap.source)
        }
        for jet in rcsJets.values.sorted(by: { $0.jet.rawValue < $1.jet.rawValue }) {
            references.append(jet.positionMeters.source)
            references.append(jet.thrustDirectionBody.source)
            references.append(jet.thrustNewtons.source)
        }
        var seen = Set<String>()
        return references.filter { seen.insert($0.id).inserted }
    }

    public static let sourceBackedDefault = LMVehicleConfiguration(
        lunarGravityMetersPerSecondSquared: LMSourceValue(
            9.80665 / 6.0,
            source: LMSourceReference(
                id: "nasa-moon-facts-gravity",
                title: "NASA Moon facts",
                url: "https://science.nasa.gov/moon/facts/",
                detail: "NASA describes lunar gravity as about one-sixth Earth's; this uses standard gravity divided by six."
            )
        ),
        agcCyclesPerSecond: LMSourceValue(
            Double((1_024_000 + 6) / 12),
            source: LMSourceReference(
                id: "yaagc-agc-per-second",
                title: "yaAGC AGC_PER_SECOND timing",
                detail: "Mirrors the existing AGCEngine AGC_PER_SECOND value: (1024000 + 6) / 12."
            )
        ),
        mainEngine: LMMainEngineConfiguration(
            maximumRatedThrustNewtons: LMSourceValue(
                10_500.0 * 4.4482216152605,
                source: LMSourceReference(
                    id: "nasa-tn-d-7143-dps-max-thrust",
                    title: "NASA TN D-7143 Apollo Experience Report: Descent Propulsion System",
                    url: "https://ntrs.nasa.gov/api/citations/19730011150/downloads/19730011150.pdf",
                    detail: "DPS requirements list a throttleable engine with a maximum thrust of 10,500 pounds."
                )
            ),
            engineOnThrustNewtons: nil
        ),
        rcsJets: LMRCSGeometry.sourceBackedJets
    )
}

public enum LMFlightOutcome: String, Equatable, Sendable, Codable {
    case inFlight
    case softLanding
    case hardLanding
    case crashed

    public var isTerminal: Bool { self != .inFlight }
    public var isIntactLanding: Bool { self == .softLanding || self == .hardLanding }
}

public struct LMSurfaceContactSnapshot: Equatable, Sendable, Codable {
    public let groundRangeMeters: Double
    public let horizontalSpeedMetersPerSecond: Double
    public let verticalSpeedMetersPerSecond: Double
    /// Vehicle thrust-axis angle relative to the first loaded pad's normal.
    /// This is not the terrain slope.
    public let tiltRadians: Double
    /// First-contact pad-scale normal in site ENU (north, east, up).
    /// Older recordings and sphere-only contacts may not contain this value.
    public let surfaceNormal: LMVector3D?

    public init(
        groundRangeMeters: Double,
        horizontalSpeedMetersPerSecond: Double,
        verticalSpeedMetersPerSecond: Double,
        tiltRadians: Double,
        surfaceNormal: LMVector3D? = nil
    ) {
        self.groundRangeMeters = groundRangeMeters
        self.horizontalSpeedMetersPerSecond = horizontalSpeedMetersPerSecond
        self.verticalSpeedMetersPerSecond = verticalSpeedMetersPerSecond
        self.tiltRadians = tiltRadians
        self.surfaceNormal = surfaceNormal
    }

    public var flightOutcome: LMFlightOutcome {
        LMLandingContactCriteria.classify(self)
    }
}

/// Apollo 12 descent dispersion report figure 3 plots the LM landing-gear
/// constraint as 4 ft/s maximum horizontal velocity, with maximum vertical
/// velocity decreasing linearly from 10 ft/s at zero horizontal velocity to
/// 7 ft/s at 4 ft/s horizontal velocity. Section 5.12 gives the nominal
/// automatic touchdown as 0.008 ft/s horizontal and 3 ft/s vertical; section
/// 5.9 gives a 6-degree pitch constraint.
public enum LMLandingContactCriteria {
    public static let softHorizontalSpeedMetersPerSecond = 1.0 * 0.3048
    public static let softVerticalSpeedMetersPerSecond = 4.0 * 0.3048
    public static let softTiltRadians = 2.0 * .pi / 180.0
    public static let maximumHorizontalSpeedMetersPerSecond = 4.0 * 0.3048
    public static let maximumTiltRadians = 6.0 * .pi / 180.0

    public static func maximumVerticalSpeedMetersPerSecond(
        horizontalSpeedMetersPerSecond: Double
    ) -> Double {
        let horizontalFeetPerSecond = horizontalSpeedMetersPerSecond / 0.3048
        return max(0, 10.0 - 0.75 * horizontalFeetPerSecond) * 0.3048
    }

    public static func classify(_ contact: LMSurfaceContactSnapshot) -> LMFlightOutcome {
        guard contact.horizontalSpeedMetersPerSecond <= maximumHorizontalSpeedMetersPerSecond,
              contact.verticalSpeedMetersPerSecond <= maximumVerticalSpeedMetersPerSecond(
                  horizontalSpeedMetersPerSecond: contact.horizontalSpeedMetersPerSecond
              ),
              contact.tiltRadians <= maximumTiltRadians
        else { return .crashed }

        if contact.horizontalSpeedMetersPerSecond <= softHorizontalSpeedMetersPerSecond,
           contact.verticalSpeedMetersPerSecond <= softVerticalSpeedMetersPerSecond,
           contact.tiltRadians <= softTiltRadians {
            return .softLanding
        }
        return .hardLanding
    }
}

public struct LMVehicleStateSnapshot: Equatable, Sendable, Codable {
    public fileprivate(set) var landingSite: LMLunarLandingSite?
    public let positionMeters: LMVector3D
    public let velocityMetersPerSecond: LMVector3D
    public let attitude: LMQuaternion
    public let angularVelocityRadiansPerSecond: LMVector3D
    public let massKilograms: Double?
    public let propellantMassKilograms: Double?
    public let isLanded: Bool
    public let flightOutcome: LMFlightOutcome
    public let surfaceContact: LMSurfaceContactSnapshot?
    /// Crushable-strut landing-gear state. Optional so checkpoints and flight
    /// recordings captured before the gear model still decode unchanged.
    public let landingGear: LMLandingGearState?
    public let dpsPitchGimbalRadians: Double
    public let dpsRollGimbalRadians: Double

    public init(
        positionMeters: LMVector3D = .zero,
        velocityMetersPerSecond: LMVector3D = .zero,
        attitude: LMQuaternion = .identity,
        angularVelocityRadiansPerSecond: LMVector3D = .zero,
        massKilograms: Double? = nil,
        propellantMassKilograms: Double? = nil,
        isLanded: Bool = false,
        flightOutcome: LMFlightOutcome? = nil,
        surfaceContact: LMSurfaceContactSnapshot? = nil,
        landingGear: LMLandingGearState? = nil,
        dpsPitchGimbalRadians: Double = 0,
        dpsRollGimbalRadians: Double = 0,
        landingSite: LMLunarLandingSite? = nil
    ) {
        self.landingSite = landingSite
        self.positionMeters = positionMeters
        self.velocityMetersPerSecond = velocityMetersPerSecond
        self.attitude = attitude.normalized()
        self.angularVelocityRadiansPerSecond = angularVelocityRadiansPerSecond
        self.massKilograms = massKilograms
        self.propellantMassKilograms = propellantMassKilograms
        let resolvedOutcome = flightOutcome ?? (isLanded ? .softLanding : .inFlight)
        self.flightOutcome = resolvedOutcome
        self.surfaceContact = surfaceContact
        self.landingGear = landingGear
        self.isLanded = resolvedOutcome.isIntactLanding
        self.dpsPitchGimbalRadians = dpsPitchGimbalRadians
        self.dpsRollGimbalRadians = dpsRollGimbalRadians
    }

    /// Height above the sphere through NASA RLS. Site-ENU `z` is the tangent
    /// plane, which is below the LM at PDI range.
    public var altitudeMeters: Double {
        let moon = LMAGCNavState.moonCenteredPositionMeters(from: self)
        return moon.magnitude - LMAGCNavState.landingSiteMeters(site: landingSite).magnitude
    }

    /// East of the landing site. Negative is uprange (PDI); positive is past.
    public var downrangeMeters: Double {
        positionMeters.y
    }

    /// Horizontal distance from the landing-site origin in the modeled local-vertical.
    public var groundRangeMeters: Double {
        hypot(positionMeters.x, positionMeters.y)
    }

    /// Radial rate `V · UNIT(R)` in moon-fixed axes.
    public var verticalSpeedMetersPerSecond: Double {
        let moon = LMAGCNavState.moonCenteredPositionMeters(from: self)
        guard moon.magnitude > 0 else { return 0 }
        let (north, east, up) = LMAGCNavState.moonFixedSiteBasis(site: landingSite)
        let velocity = north * velocityMetersPerSecond.x
            + east * velocityMetersPerSecond.y
            + up * velocityMetersPerSecond.z
        return velocity.dot(moon) / moon.magnitude
    }
}

public struct LMSensorSnapshot: Equatable, Sendable {
    public let radarInput: LMRadarInput?
    public let poweredDescentPanelState: LMPoweredDescentPanelState
    public let rotationalHandControllerInput: LMRotationalHandControllerInput
    public let descentRateChannel16: Int

    public init(
        radarInput: LMRadarInput? = nil,
        poweredDescentPanelState: LMPoweredDescentPanelState = .automatic,
        rotationalHandControllerInput: LMRotationalHandControllerInput = LMRotationalHandControllerInput(),
        descentRateChannel16: Int = 0
    ) {
        self.radarInput = radarInput
        self.poweredDescentPanelState = poweredDescentPanelState
        self.rotationalHandControllerInput = rotationalHandControllerInput
        self.descentRateChannel16 = descentRateChannel16 & 0o77777
    }
}

public struct LMSourceStatus: Equatable, Sendable, Codable {
    public let sources: [LMSourceReference]
    public let unmodeledItems: [String]

    public init(sources: [LMSourceReference], unmodeledItems: [String]) {
        self.sources = sources
        self.unmodeledItems = unmodeledItems
    }
}

public struct LMSimulationSnapshot: Equatable, Sendable {
    public let timeSeconds: Double
    public let agc: AGCSnapshot
    public let vehicleState: LMVehicleStateSnapshot
    public let vehicleCommands: LMVehicleSnapshot
    public let sensorState: LMSensorSnapshot
    public let channelTrace: [AGCChannelTraceEntry]
    public let sourceStatus: LMSourceStatus
    public let traceSample: LMSimulationTraceSample

    public init(
        timeSeconds: Double,
        agc: AGCSnapshot,
        vehicleState: LMVehicleStateSnapshot,
        vehicleCommands: LMVehicleSnapshot,
        sensorState: LMSensorSnapshot,
        channelTrace: [AGCChannelTraceEntry],
        sourceStatus: LMSourceStatus,
        traceSample: LMSimulationTraceSample
    ) {
        self.timeSeconds = timeSeconds
        self.agc = agc
        self.vehicleState = vehicleState
        self.vehicleCommands = vehicleCommands
        self.sensorState = sensorState
        self.channelTrace = channelTrace
        self.sourceStatus = sourceStatus
        self.traceSample = traceSample
    }
}

public struct LMPoweredDescentCheckpoint: Equatable, Sendable, Identifiable {
    public let id: String
    public let program: Int
    public let expectedScript: DSKYScript
    public let source: LMSourceReference

    public init(id: String, program: Int, expectedScript: DSKYScript, source: LMSourceReference) {
        self.id = id
        self.program = program
        self.expectedScript = expectedScript
        self.source = source
    }
}

public struct LMPoweredDescentScenario: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let initialState: LMVehicleStateSnapshot
    public let configuration: LMVehicleConfiguration
    public let checkpoints: [LMPoweredDescentCheckpoint]
    public let sourceStatus: LMSourceStatus

    public init(
        id: String,
        title: String,
        initialState: LMVehicleStateSnapshot,
        configuration: LMVehicleConfiguration,
        checkpoints: [LMPoweredDescentCheckpoint],
        sourceStatus: LMSourceStatus
    ) {
        self.id = id
        self.title = title
        self.initialState = initialState
        self.configuration = configuration
        self.checkpoints = checkpoints
        self.sourceStatus = sourceStatus
    }

    public static let apollo11SourceBacked: LMPoweredDescentScenario = {
        let dpsSource = LMSourceReference(
            id: "nasa-tn-d-7143-dps-requirements",
            title: "NASA TN D-7143 Apollo Experience Report: Descent Propulsion System",
            url: "https://ntrs.nasa.gov/api/citations/19730011150/downloads/19730011150.pdf",
            detail: "DPS design requirements cover a 33,000-pound LM separation weight and powered descent from 50,000 feet."
        )
        let guidanceSource = LMSourceReference(
            id: "luminary099-lunar-landing-guidance",
            title: "Luminary099 lunar landing guidance equations",
            url: "https://github.com/chrislgarry/Apollo-11/blob/master/Luminary099/LUNAR_LANDING_GUIDANCE_EQUATIONS.agc",
            detail: "Source anchor for powered-descent program checkpoints P63-P66."
        )
        let configuration = LMVehicleConfiguration.sourceBackedDefault
        let pdiPitch = LMQuaternion.fromAxisAngle(
            axis: LMVector3D(x: 1),
            radians: 95.0 * .pi / 180.0
        )
        let initialState = LMAGCNavState.vehicleState(
            timeCentiseconds: Luminary99LandingPadLoad.pdiClockCentiseconds,
            attitude: pdiPitch,
            massKilograms: 33_000.0 * 0.45359237
        )
        let checkpoints = [
            LMPoweredDescentCheckpoint(id: "p63", program: 63, expectedScript: .v37e63e, source: guidanceSource),
            LMPoweredDescentCheckpoint(id: "p64", program: 64, expectedScript: .v37e64e, source: guidanceSource),
            LMPoweredDescentCheckpoint(id: "p65", program: 65, expectedScript: .v37e65e, source: guidanceSource),
            LMPoweredDescentCheckpoint(id: "p66", program: 66, expectedScript: .v37e66e, source: guidanceSource)
        ]
        return LMPoweredDescentScenario(
            id: "apollo11-source-backed-foundation",
            title: "Apollo 11 powered descent foundation",
            initialState: initialState,
            configuration: configuration,
            checkpoints: checkpoints,
            sourceStatus: LMSourceStatus(
                sources: [
                    dpsSource,
                    guidanceSource,
                    .nasaTN6846PoweredDescent,
                    .nasaTN4131PDIAttitude,
                    .nasaR567GimbalTrim,
                    .luminaryErasableAssignments,
                    .luminaryControlledConstants,
                    .luminaryFlagwordAssignments,
                    .nasaR567NavScales,
                    .nasaSNA8D027Luminary99PadLoads,
                    .luminaryP63GUIDDURN,
                    .luminaryBurnBaby,
                    .luminaryPlanetaryInertialOrientation
                ] + configuration.sourceReferences,
                unmodeledItems: [
                    "Apollo 11 powered-descent body angular rates"
                ]
            )
        )
    }()
}

public actor LMSimulationRuntime {
    private let agcRuntime: AGCRuntime
    private let initialState: LMVehicleStateSnapshot
    private var vehicleState: LMVehicleStateSnapshot
    private var configuration: LMVehicleConfiguration
    private var radarInput: LMRadarInput?
    private var poweredDescentPanelState = LMPoweredDescentPanelState.automatic
    private var rhcInput = LMRotationalHandControllerInput()
    private var descentRateChannel16 = 0
    private var cycleRemainder = 0.0
    private var elapsedTimeSeconds = 0.0
    private var lastTraceEntryID: UInt64 = 0
    private var traceSamples: [LMSimulationTraceSample] = []
    private var scenarioSourceStatus: LMSourceStatus?
    private var sensorFeedback = LMSensorFeedbackState()
    private var lastSpecificForceBody = LMVector3D.zero
    private var throttleState = LMDPSThrottleState()
    private var p63CrewHandshake = LMP63CrewHandshake()
    private var lastDSKYVerb = "  "
    private var lastDSKYNoun = "  "
    /// CH12 bit 13 commands LR POS2; CH33 bits 6/7 are the antenna discretes.
    private var landingRadarInPosition2 = false
    private var poweredDescentIgnitionTimeSeconds: Double?
    private var landingRadarPermissionKeyIndex = 0
    private var scenarioID: String?
    /// Terrain the landing gear touches. Left unset, contact falls back to the
    /// AGC landing-site sphere and the vehicle lands as if the mare were flat.
    private var landingSurface: LMLandingSurfaceModel?

    public init(
        binFile: URL,
        configuration: LMVehicleConfiguration = .sourceBackedDefault,
        initialState: LMVehicleStateSnapshot = LMVehicleStateSnapshot(),
        sourceStatus: LMSourceStatus? = nil
    ) throws {
        self.agcRuntime = try AGCRuntime(binFile: binFile)
        self.configuration = configuration
        self.initialState = initialState
        self.vehicleState = initialState
        self.scenarioSourceStatus = sourceStatus
    }

    public init(
        coreImage: Data,
        configuration: LMVehicleConfiguration = .sourceBackedDefault,
        initialState: LMVehicleStateSnapshot = LMVehicleStateSnapshot(),
        sourceStatus: LMSourceStatus? = nil
    ) throws {
        self.agcRuntime = try AGCRuntime(coreImage: coreImage)
        self.configuration = configuration
        self.initialState = initialState
        self.vehicleState = initialState
        self.scenarioSourceStatus = sourceStatus
    }

    public init(binFile: URL, scenario: LMPoweredDescentScenario) throws {
        self.agcRuntime = try AGCRuntime(binFile: binFile)
        self.configuration = scenario.configuration
        self.initialState = scenario.initialState
        self.vehicleState = scenario.initialState
        self.scenarioSourceStatus = scenario.sourceStatus
        self.scenarioID = scenario.id
    }

    public init(coreImage: Data, scenario: LMPoweredDescentScenario) throws {
        self.agcRuntime = try AGCRuntime(coreImage: coreImage)
        self.configuration = scenario.configuration
        self.initialState = scenario.initialState
        self.vehicleState = scenario.initialState
        self.scenarioSourceStatus = scenario.sourceStatus
        self.scenarioID = scenario.id
    }

    /// Install the contact surface the landing gear touches. The renderer
    /// supplies the same evaluator that builds the visible mesh so a footpad
    /// cannot rest above or below the terrain the crew is looking at.
    public func setLandingSurface(_ surface: LMLandingSurfaceModel?) {
        landingSurface = surface
    }

    public func reset() async throws -> LMSimulationSnapshot {
        let agc = try await agcRuntime.reset()
        vehicleState = initialState
        cycleRemainder = 0
        elapsedTimeSeconds = 0
        lastTraceEntryID = 0
        traceSamples.removeAll()
        sensorFeedback.reset()
        lastSpecificForceBody = .zero
        throttleState.reset()
        p63CrewHandshake = LMP63CrewHandshake()
        lastDSKYVerb = "  "
        lastDSKYNoun = "  "
        landingRadarInPosition2 = false
        poweredDescentIgnitionTimeSeconds = nil
        landingRadarPermissionKeyIndex = 0
        return makeSnapshot(agc: agc, channelDeltas: [])
    }

    public func snapshot() async -> LMSimulationSnapshot {
        let agc = await agcRuntime.snapshot()
        return makeSnapshot(agc: agc, channelDeltas: [])
    }

    public func step(deltaTime: Double) async -> LMSimulationSnapshot {
        await step(deltaTime: deltaTime, input: .none)
    }

    public func step(deltaTime: Double, input: LMFrameInput) async -> LMSimulationSnapshot {
        await applyFrameInput(input)
        let safeDelta = max(0, deltaTime)
        let totalCycles = safeDelta * configuration.agcCyclesPerSecond.value + cycleRemainder
        let cycles = UInt64(totalCycles.rounded(.down))
        cycleRemainder = totalCycles - Double(cycles)
        return await stepExact(cycles: cycles, deltaTime: safeDelta)
    }

    public func step(cycles: UInt64) async -> LMSimulationSnapshot {
        await step(cycles: cycles, input: .none)
    }

    public func step(cycles: UInt64, input: LMFrameInput) async -> LMSimulationSnapshot {
        await applyFrameInput(input)
        let deltaTime = Double(cycles) / configuration.agcCyclesPerSecond.value
        return await stepExact(cycles: cycles, deltaTime: deltaTime)
    }

    public func sendDSKYKey(_ key: DSKYKeyCode) async {
        await agcRuntime.sendDSKYKey(key)
    }

    public func sendPRO(pressed: Bool) async {
        await agcRuntime.sendPRO(pressed: pressed)
    }

    public func debuggerSnapshot() async -> AGCDebuggerSnapshot {
        await agcRuntime.debuggerSnapshot()
    }

    public func setBreakpoint(_ address: Int) async {
        await agcRuntime.setBreakpoint(address)
    }

    public func clearBreakpoints() async {
        await agcRuntime.clearBreakpoints()
    }

    public func watchErasable(_ address: Int) async {
        await agcRuntime.watchErasable(address)
    }

    public func stepInstruction() async -> LMSimulationSnapshot {
        _ = await agcRuntime.stepInstruction()
        let agc = await agcRuntime.snapshot()
        return makeSnapshot(agc: agc, channelDeltas: [])
    }

    @discardableResult
    public func sendDSKYScript(_ script: DSKYScript, cyclesPerKey: UInt64 = 50_000) async -> LMSimulationSnapshot {
        var snapshot = await self.snapshot()
        for key in script.keys {
            if Task.isCancelled { break }
            await agcRuntime.sendDSKYKey(key)
            snapshot = await step(cycles: cyclesPerKey)
        }
        return snapshot
    }

    /// Idle-boot Luminary for `bootCycles` MCTs, load PDI nav + P63 pad-loads,
    /// assert MODE CONTROL AUTO, then key V37E63E.
    @discardableResult
    public func bootAndEnterP63(
        bootCycles: UInt64 = 1_000_000,
        cyclesPerKey: UInt64 = 50_000
    ) async -> LMSimulationSnapshot {
        // Apollo 11's IMU had completed turn-on long before PDI. Present the
        // inverted OPERATE discrete during fresh start and let Luminary finish
        // its operate-only ICDU initialization before seeding the PDI attitude.
        await agcRuntime.enqueueInput(
            AGCChannelInput(channel: 0o30, value: LMPoweredDescentPanel.channel30IMUOperating)
        )
        if bootCycles > 0 {
            // Idle Luminary only: do not integrate the vehicle or inject PIPA/CDU
            // during fresh start. Physics during that window can GOJAM (01107).
            _ = await agcRuntime.step(cycles: bootCycles)
            elapsedTimeSeconds += Double(bootCycles) / configuration.agcCyclesPerSecond.value
        }
        await finishIMUInitializationBeforePDI()
        await loadP63PadLoads()
        await loadPDINavState()
        // V37 keys must run through `step` so the plant coasts with TIME2.
        // AGC-only stepping here left GET ~4 s ahead of the frozen PDI state;
        // the first AVERAGEG PGUIDE then integrated that gap and MUNRVG R
        // stayed ~6 km downrange of the vehicle through P64.
        for key in DSKYScript.v37e63e.keys {
            if Task.isCancelled { break }
            await agcRuntime.sendDSKYKey(key)
            _ = await step(cycles: cyclesPerKey)
        }
        // Held AUTO / engine-arm / LR POS1 after V37. Applying CH31 AUTO
        // before V37E63E keeps PROG blank.
        await applyPoweredDescentPanel()
        await enableLandingDAP()
        let prepared = await snapshot()
        lastDSKYVerb = prepared.agc.dsky.verb
        lastDSKYNoun = prepared.agc.dsky.noun
        return prepared
    }

    /// Fresh start initializes IMODES30 as though IMU OPERATE were absent.
    /// Wait for T4's operate-only sequence (zero discrete, 10-second counter
    /// reacquisition, DAP re-enable) so no waitlist job can zero the seeded
    /// 95-degree PDI ICDUs later in the burn.
    private func finishIMUInitializationBeforePDI() async {
        var remainingCycles: UInt64 = 2_000_000
        let chunkCycles: UInt64 = 50_000
        while remainingCycles > 0 {
            let agc = await agcRuntime.snapshot()
            let imodes30 = await agcRuntime.readErasable(ecadr: Luminary099Erasable.imodes30)
            let imodes33 = await agcRuntime.readErasable(ecadr: Luminary099Erasable.imodes33)
            let zeroDiscrete = (agc.outputChannels[0o12] ?? 0) & 0o20
            let operateSampled = (imodes30 & 0o400) == 0
            let dapEnabled = (imodes33 & 0o40) == 0
            if operateSampled && dapEnabled && zeroDiscrete == 0 {
                break
            }
            let cycles = min(chunkCycles, remainingCycles)
            _ = await agcRuntime.step(cycles: cycles)
            elapsedTimeSeconds += Double(cycles) / configuration.agcCyclesPerSecond.value
            remainingCycles -= cycles
        }
    }

    /// NASA Luminary 99 landing-guidance overlay. TLAND is placed
    /// `GUIDDURN + ZOOMTIME` plus the MIDTOAV TIG lead after the live GET
    /// (01703 if TIG − 29.9 s ≤ GET + 20 s; 01204 if TIG-35 ≤ GET).
    public func loadP63PadLoads() async {
        await agcRuntime.writeErasable(Luminary99LandingPadLoad.erasableWords())
        let time2 = await agcRuntime.readErasable(ecadr: Luminary099Erasable.time2)
        let time1 = await agcRuntime.readErasable(ecadr: Luminary099Erasable.time1)
        let clock = AGCDoublePrecision(high: time2, low: time1).decoded(scale: 28)
        await agcRuntime.writeErasable(Luminary99LandingPadLoad.tlandWords(fromClock: clock))
    }

    /// Held MODE CONTROL AUTO, auto throttle, engine armed, IMU operate, LR POS1.
    /// Apply after V37E63E: CH31 AUTO before the program change leaves PROG blank.
    public func applyPoweredDescentPanel() async {
        await agcRuntime.enqueueInputs(LMPoweredDescentPanel.channelInputs)
    }

    /// Encode the sourced-PDI runtime lead state into RN/VN at live GET.
    /// REFSMMAT stays at GET. Call after pad-loads so TLAND and the state-vector
    /// epoch share the same live clock.
    public func loadPDINavState() async {
        let time2 = await agcRuntime.readErasable(ecadr: Luminary099Erasable.time2)
        let time1 = await agcRuntime.readErasable(ecadr: Luminary099Erasable.time1)
        let time = AGCDoublePrecision(high: time2, low: time1).decoded(scale: 28)
        vehicleState = LMAGCNavState.vehicleState(
            timeCentiseconds: time,
            attitude: vehicleState.attitude,
            massKilograms: vehicleState.massKilograms ?? 0, site: vehicleState.landingSite
        )
        await agcRuntime.writeErasable(
            LMAGCNavState.erasableWords(vehicle: vehicleState, time2: time2, time1: time1)
        )
        for flag in LMAGCNavState.lunarSphereFlags() {
            await agcRuntime.setErasableBit(ecadr: flag.ecadr, bit: flag.bit)
        }
        await enableLandingDAP()
    }

    /// Skip-R51 never runs IMUFINE. Clear IMODES33 bit 6 (DAP AUTO/HOLD
    /// enabled) so DAPIDLER can leave SHUTDOWN. IMODES30 holds inverted
    /// channel-30 samples: IMU OPERATE is bit 9 clear, established during
    /// fresh-start initialization above. Writing it set retriggers T4's
    /// operate-only sequence and schedules a delayed ICDU zero.
    /// V65 SNUFFBIT keeps Q,R RCS off so GTS is not stacked with jets
    /// (AFTERTJ XTRANS). P64 FINDCDUW’s LAND−R switch still needs GTS-only:
    /// clearing SNUFFBIT there lets Q,R jets tumble through the window change.
    /// P66 ATT HOLD instead requires it clear so ACA rate commands can use RCS.
    private func enableLandingDAP(allowRotationalRCS: Bool = false) async {
        let imodes33 = await agcRuntime.readErasable(ecadr: Luminary099Erasable.imodes33)
        await agcRuntime.writeErasable(
            ecadr: Luminary099Erasable.imodes33,
            value: imodes33 & ~0o40
        )
        let snuffer = (
            Luminary099Flag.ecadr(decimalIndex: Luminary099Flag.snuffer),
            Luminary099Flag.bit(decimalIndex: Luminary099Flag.snuffer)
        )
        if allowRotationalRCS {
            await agcRuntime.clearErasableBit(ecadr: snuffer.0, bit: snuffer.1)
        } else {
            await agcRuntime.setErasableBit(ecadr: snuffer.0, bit: snuffer.1)
        }
    }

    public func readErasable(ecadr: Int) async -> Int {
        await agcRuntime.readErasable(ecadr: ecadr)
    }

    public func readDoublePrecision(ecadr: Int) async -> AGCDoublePrecision {
        await agcRuntime.readDoublePrecision(ecadr: ecadr)
    }

    public func enqueueInput(_ input: AGCChannelInput) async {
        await agcRuntime.enqueueInput(input)
    }

    public func enqueueInputs(_ inputs: [AGCChannelInput]) async {
        await agcRuntime.enqueueInputs(inputs)
    }

    public func setRadarInput(_ input: LMRadarInput?) async {
        let resolved: LMRadarInput?
        switch input {
        case .landingRadar(let state):
            resolved = LMLandingRadar.measurement(
                from: state,
                position2: landingRadarInPosition2
            ).map(LMRadarInput.measurement)
        case .raw, .measurement:
            resolved = input
        case nil:
            resolved = nil
        }
        radarInput = resolved
        await agcRuntime.setRadarInput(resolved?.rawAGCInput)
    }

    public func setRotationalHandControllerInput(_ input: LMRotationalHandControllerInput) async {
        rhcInput = input
        await agcRuntime.setRotationalHandControllerInput(input)
    }

    public func setDescentRateControlInput(descendPlus: Bool, descendMinus: Bool) async {
        let input = LMDescentRateControlInput(descendPlus: descendPlus, descendMinus: descendMinus)
        descentRateChannel16 = input.channel16Value
        await agcRuntime.enqueueInput(AGCChannelInput(
            channel: 0o16,
            value: input.channel16Value,
            interrupt: input.channel16Value != 0
        ))
    }

    public func simulationTrace() -> [LMSimulationTraceSample] {
        traceSamples
    }

    private func applyFrameInput(_ input: LMFrameInput) async {
        // A missing frame sample means the beam is out of range or off the
        // surface. Clear the previous measurement so CH33 data-good cannot
        // remain asserted with stale LR registers.
        await setRadarInput(input.radarInput)
        if let rhcInput = input.rotationalHandControllerInput {
            await setRotationalHandControllerInput(rhcInput)
        }
        if let panelState = input.poweredDescentPanelState {
            poweredDescentPanelState = panelState
            await agcRuntime.enqueueInputs(
                panelState.channelInputs(rhcOutOfDetent: rhcInput.outOfDetent)
                    .filter { $0.channel != 0o33 }
            )
            await enableLandingDAP(
                allowRotationalRCS: panelState.attitudeMode == .attitudeHold
            )
        }
        if !input.rawChannelInputs.isEmpty {
            // CH33 is the LR discretes word. The held panel value has data-good
            // off; INITREAD latches that into OLDATAGD and DGCHECK then rejects
            // the sample. Never enqueue the panel CH33 — applyLandingRadarChannel33
            // writes the live POS/scale/data-good word once per frame.
            let withoutRadarDiscretes = input.rawChannelInputs.filter { $0.channel != 0o33 }
            if !withoutRadarDiscretes.isEmpty {
                await agcRuntime.enqueueInputs(withoutRadarDiscretes)
            }
            if input.rawChannelInputs.contains(where: { $0.channel == 0o31 }) {
                await enableLandingDAP()
            }
        }
        await applyLandingRadarChannel33()
        if let descentRateInput = input.descentRateInput {
            descentRateChannel16 = descentRateInput.channel16Value
            // Typed panel frames model an actual momentary ROD switch: the
            // release changes CH16 back to zero without raising KEYRUPT2.
            // Legacy AUTO frames retain their established input timing until
            // that closed-loop trajectory is recalibrated independently.
            let isTypedMomentaryRelease = input.poweredDescentPanelState != nil
                && descentRateInput.channel16Value == 0
            await agcRuntime.enqueueInput(AGCChannelInput(
                channel: 0o16,
                value: descentRateInput.channel16Value,
                interrupt: !isTypedMomentaryRelease
            ))
        }
        await advanceLandingRadarPermission(for: input)
    }

    /// Apollo 11 keyed V57 at TIG + 5:00. Key the real extended verb one key
    /// per simulation frame once the auto-land trajectory reaches that point.
    private func advanceLandingRadarPermission(for input: LMFrameInput) async {
        guard case .landingRadar? = input.radarInput,
              let ignitionTime = poweredDescentIgnitionTimeSeconds,
              elapsedTimeSeconds - ignitionTime
                >= Luminary99LandingPadLoad.landingRadarUpdateDelayAfterIgnitionSeconds
        else { return }

        let flagWord = await agcRuntime.readErasable(ecadr: Luminary099Erasable.flagwrd11)
        let mask = 1 << (
            Luminary099Flag.bit(decimalIndex: Luminary099Flag.landingRadarUpdates) - 1
        )
        if (flagWord & mask) != 0 {
            landingRadarPermissionKeyIndex = DSKYScript.v57e.keys.count
            return
        }

        if landingRadarPermissionKeyIndex >= DSKYScript.v57e.keys.count {
            landingRadarPermissionKeyIndex = 0
        }
        await agcRuntime.sendDSKYKey(DSKYScript.v57e.keys[landingRadarPermissionKeyIndex])
        landingRadarPermissionKeyIndex += 1
    }

    /// CH33 bits 5/8 are inverted LR data-good; bits 6/7 are antenna POS1/POS2.
    /// Auto-land holds the panel, including a POS1 discrete; HIGATJOB’s CH12
    /// bit 13 must still be allowed to move the antenna or R12 rejects POS2.
    /// This is the only CH33 writer on the auto-land frame path so INITREAD
    /// cannot sample the panel's not-good word into OLDATAGD.
    private func applyLandingRadarChannel33() async {
        var value = LMPoweredDescentPanel.channel33
        if radarInput?.rawAGCInput?.altitudeMeter != nil {
            value &= ~LMPoweredDescentPanel.channel33LRAltitudeDataGood
        }
        if radarInput?.rawAGCInput?.landingRadarVelocityX != nil {
            value &= ~LMPoweredDescentPanel.channel33LRVelocityDataGood
        }
        if radarInput?.rawAGCInput?.landingRadarAltitudeHighScale == true {
            value |= LMPoweredDescentPanel.channel33LRAltitudeHighScale
        }
        if landingRadarInPosition2 {
            value |= LMPoweredDescentPanel.channel33LRPosition1
            value &= ~LMPoweredDescentPanel.channel33LRPosition2
        }
        await agcRuntime.enqueueInput(AGCChannelInput(channel: 0o33, value: value))
    }

    private func stepExact(cycles: UInt64, deltaTime: Double) async -> LMSimulationSnapshot {
        if let action = p63CrewHandshake.advance(verb: lastDSKYVerb, noun: lastDSKYNoun, deltaTime: deltaTime) {
            switch action {
            case .enter:
                await agcRuntime.sendDSKYKey(.enter)
            case .pro(let pressed):
                await agcRuntime.sendPRO(pressed: pressed)
            }
        }
        elapsedTimeSeconds += deltaTime
        let slices = LMRCSSampling.slices(
            totalCycles: cycles,
            deltaTime: deltaTime,
            cyclesPerSecond: configuration.agcCyclesPerSecond.value
        )
        var agc = await agcRuntime.snapshot()
        var rcsOut0 = 0
        var rcsOut1 = 0
        for slice in slices {
            // ENU-as-SM: inertial PIPA + ENU CDUs still leaves braking after
            // ZOOM (P64 at 173 nmi, CDUY error +88°) even with the V37 plant
            // coasting. SM CDUs tumble GTS. Keep both maps on ENU.
            let sensorPulses = sensorFeedback.increments(
                specificForceBody: lastSpecificForceBody,
                attitude: vehicleState.attitude,
                deltaTime: slice.deltaTime
            )
            if !sensorPulses.isEmpty {
                await agcRuntime.enqueueInputs(sensorPulses)
            }
            agc = await agcRuntime.step(cycles: slice.cycles)
            var commands = LMVehicleSnapshot(agcSnapshot: agc)
            rcsOut0 |= commands.out0
            rcsOut1 |= commands.out1
            if !landingRadarInPosition2,
               (commands.outputChannel12 & LMPoweredDescentPanel.channel12LRPosition2Command) != 0 {
                landingRadarInPosition2 = true
                await applyLandingRadarChannel33()
            }
            throttleState.advance(
                thrustRegister: agc.registers.thrust,
                driveActive: commands.thrustDriveActive,
                deltaTime: slice.deltaTime
            )
            let engineOn = commands.mainEngineOn && !commands.mainEngineOff
            if engineOn, poweredDescentIgnitionTimeSeconds == nil {
                poweredDescentIgnitionTimeSeconds = elapsedTimeSeconds
            }
            commands = commands.withCommandedThrust(throttleState.commandedThrustNewtons(engineOn: engineOn))
            lastSpecificForceBody = LMDynamics.specificForceBody(
                state: vehicleState,
                commands: commands,
                configuration: configuration
            )
            vehicleState = LMDynamics.propagate(
                state: vehicleState,
                commands: commands,
                configuration: configuration,
                deltaTime: slice.deltaTime,
                surface: landingSurface
            )
        }
        lastDSKYVerb = agc.dsky.verb
        lastDSKYNoun = agc.dsky.noun
        let engineOn = {
            let raw = LMVehicleSnapshot(agcSnapshot: agc)
            return raw.mainEngineOn && !raw.mainEngineOff
        }()
        let commands = LMVehicleSnapshot(agcSnapshot: agc)
            .withCommandedThrust(throttleState.commandedThrustNewtons(engineOn: engineOn))
            .withRCSBits(out0: rcsOut0, out1: rcsOut1)
        let channelDeltas = traceDeltas(from: agc.channelTrace)
        let snapshot = makeSnapshot(agc: agc, commands: commands, channelDeltas: channelDeltas)
        traceSamples.append(snapshot.traceSample)
        if traceSamples.count > 2_048 {
            traceSamples.removeFirst(traceSamples.count - 2_048)
        }
        return snapshot
    }

    private func makeSnapshot(
        agc: AGCSnapshot,
        commands: LMVehicleSnapshot? = nil,
        channelDeltas: [AGCChannelTraceEntry]
    ) -> LMSimulationSnapshot {
        let engineOn = {
            let raw = LMVehicleSnapshot(agcSnapshot: agc)
            return raw.mainEngineOn && !raw.mainEngineOff
        }()
        let resolved = commands ?? LMVehicleSnapshot(agcSnapshot: agc)
            .withCommandedThrust(throttleState.commandedThrustNewtons(engineOn: engineOn))
        let sourceStatus = makeSourceStatus(commands: resolved)
        let sensorState = LMSensorSnapshot(
            radarInput: radarInput,
            poweredDescentPanelState: poweredDescentPanelState,
            rotationalHandControllerInput: rhcInput,
            descentRateChannel16: descentRateChannel16
        )
        let traceSample = LMSimulationTraceSample(
            timeSeconds: elapsedTimeSeconds,
            agc: agc,
            vehicleState: vehicleState,
            vehicleCommands: resolved,
            sourceStatus: sourceStatus,
            channelDeltas: channelDeltas
        )
        return LMSimulationSnapshot(
            timeSeconds: elapsedTimeSeconds,
            agc: agc,
            vehicleState: vehicleState,
            vehicleCommands: resolved,
            sensorState: sensorState,
            channelTrace: agc.channelTrace,
            sourceStatus: sourceStatus,
            traceSample: traceSample
        )
    }

    private func makeSourceStatus(commands: LMVehicleSnapshot) -> LMSourceStatus {
        var unmodeled = scenarioSourceStatus?.unmodeledItems ?? []
        if let radarInput, !radarInput.conversionStatus.isSourceBacked {
            unmodeled.append(radarInput.conversionStatus.detail)
        }
        for jet in commands.rcsJets where configuration.rcsJets[jet.jet] == nil {
            unmodeled.append("RCS jet \(jet.jet.rawValue) command is decoded, but sourced geometry/thrust is missing.")
        }
        if vehicleState.massKilograms == nil {
            unmodeled.append("Vehicle mass is unknown, so non-gravity forces cannot change translation.")
        }
        let sources = (scenarioSourceStatus?.sources ?? [])
            + configuration.sourceReferences
            + commands.sourceReferences
            + [radarInput?.conversionStatus.source?.reference].compactMap { $0 }
            + [.luminaryPIPAScale, .agcCDUEncoding, .luminaryThrottleConstants, .luminaryRCSGeometry, .luminary1ACCS, .nasaR567GimbalTrim]
        var seen = Set<String>()
        return LMSourceStatus(
            sources: sources.filter { seen.insert($0.id).inserted },
            unmodeledItems: Array(Set(unmodeled)).sorted()
        )
    }

    private func traceDeltas(from trace: [AGCChannelTraceEntry]) -> [AGCChannelTraceEntry] {
        let deltas = trace.filter { $0.id > lastTraceEntryID }
        if let newest = trace.last?.id {
            lastTraceEntryID = newest
        }
        return deltas
    }

    // MARK: - Checkpoints

    /// Capture the complete resumable flight state. Diagnostic-only buffers
    /// (the rolling trace-sample window and channel-trace ring) are excluded;
    /// ``lastTraceEntryID`` is captured so restored runs do not re-report old
    /// channel deltas.
    public func captureCheckpoint(scenarioID: String? = nil) async -> LMSimulationCheckpoint {
        let agcCheckpoint = await agcRuntime.captureCheckpoint()
        return LMSimulationCheckpoint(
            schemaVersion: LMSimulationCheckpoint.schemaVersion,
            coreImageSHA256: agcCheckpoint.coreImageSHA256,
            scenarioID: scenarioID ?? self.scenarioID ?? "unspecified",
            simulationTimeSeconds: elapsedTimeSeconds,
            agc: agcCheckpoint,
            vehicleState: vehicleState,
            radarInput: radarInput,
            panelState: poweredDescentPanelState,
            rhcInput: rhcInput,
            descentRateChannel16: descentRateChannel16,
            cycleRemainder: cycleRemainder,
            sensorFeedback: sensorFeedback.captureCheckpoint(),
            lastSpecificForceBody: lastSpecificForceBody,
            throttle: throttleState.captureCheckpoint(),
            crewHandshake: p63CrewHandshake.captureCheckpoint(),
            lastDSKYVerb: lastDSKYVerb,
            lastDSKYNoun: lastDSKYNoun,
            landingRadarInPosition2: landingRadarInPosition2,
            poweredDescentIgnitionTimeSeconds: poweredDescentIgnitionTimeSeconds,
            landingRadarPermissionKeyIndex: landingRadarPermissionKeyIndex,
            lastTraceEntryID: lastTraceEntryID
        )
    }

    /// Restore a checkpoint captured by this runtime type from the same Luminary
    /// core image and, when known, the same scenario. Every check runs before
    /// any mutation so an incompatible fixture is refused without partial state.
    @discardableResult
    public func restore(from checkpoint: LMSimulationCheckpoint) async throws -> LMSimulationSnapshot {
        try checkpoint.validate(
            coreImageSHA256: await agcRuntime.checkpointCoreImageSHA256(),
            scenarioID: scenarioID
        )

        guard checkpoint.vehicleState.landingSite == initialState.landingSite else {
            throw LMLunarLandingSite.SiteError.incompatibleCheckpoint
        }
        try await agcRuntime.applyCheckpoint(checkpoint.agc)

        vehicleState = checkpoint.vehicleState
        radarInput = checkpoint.radarInput
        await agcRuntime.setRadarInput(radarInput?.rawAGCInput)
        poweredDescentPanelState = checkpoint.panelState
        rhcInput = checkpoint.rhcInput
        descentRateChannel16 = checkpoint.descentRateChannel16
        cycleRemainder = checkpoint.cycleRemainder
        elapsedTimeSeconds = checkpoint.simulationTimeSeconds
        sensorFeedback.restore(from: checkpoint.sensorFeedback)
        lastSpecificForceBody = checkpoint.lastSpecificForceBody
        throttleState.restore(from: checkpoint.throttle)
        p63CrewHandshake.restore(from: checkpoint.crewHandshake)
        lastDSKYVerb = checkpoint.lastDSKYVerb
        lastDSKYNoun = checkpoint.lastDSKYNoun
        landingRadarInPosition2 = checkpoint.landingRadarInPosition2
        poweredDescentIgnitionTimeSeconds = checkpoint.poweredDescentIgnitionTimeSeconds
        landingRadarPermissionKeyIndex = checkpoint.landingRadarPermissionKeyIndex
        lastTraceEntryID = checkpoint.lastTraceEntryID

        return await snapshot()
    }
}

enum LMDynamics {
    static func propagate(
        state: LMVehicleStateSnapshot,
        commands: LMVehicleSnapshot,
        configuration: LMVehicleConfiguration,
        deltaTime: Double,
        surface: LMLandingSurfaceModel? = nil
    ) -> LMVehicleStateSnapshot {
        var result = propagateInSite(state: state, commands: commands, configuration: configuration,
                                     deltaTime: deltaTime, surface: surface)
        result.landingSite = state.landingSite
        return result
    }

    private static func propagateInSite(
        state: LMVehicleStateSnapshot,
        commands: LMVehicleSnapshot,
        configuration: LMVehicleConfiguration,
        deltaTime: Double,
        surface: LMLandingSurfaceModel? = nil
    ) -> LMVehicleStateSnapshot {
        guard deltaTime > 0, !state.flightOutcome.isTerminal else { return state }

        let (pitch, roll) = advancedGimbal(state: state, commands: commands, deltaTime: deltaTime)
        var forceWorld = LMVector3D.zero
        var torqueBody = LMVector3D.zero
        var expendedForceNewtons = 0.0

        // Apollo shut the descent engine down at touchdown: Aldrin called the
        // contact light, Armstrong stopped the engine. Model that, because the
        // AGC references altitude to a sphere and cannot tell that terrain
        // relief has already put the footpads on the ground. Without it the
        // guidance keeps flying a vehicle that has landed.
        let descentEngineStopped = state.surfaceContact != nil
        if commands.mainEngineOn,
           !commands.mainEngineOff,
           !descentEngineStopped,
           let thrust = commands.dps.commandedThrustNewtons ?? configuration.mainEngine?.engineOnThrustNewtons?.value {
            let bodyForce = LMDPSGimbalMap.thrustDirectionBody(pitchRadians: pitch, rollRadians: roll) * thrust
            forceWorld = forceWorld + state.attitude.rotated(bodyForce)
            expendedForceNewtons += thrust
            if let mass = state.massKilograms, mass > 0 {
                torqueBody = torqueBody + LMInertiaMap.descentEnginePivotBodyMeters(massKilograms: mass).cross(bodyForce)
            }
        }

        for command in commands.rcsJets {
            guard let jet = configuration.rcsJets[command.jet] else { continue }
            let bodyForce = jet.thrustDirectionBody.value.normalized() * jet.thrustNewtons.value
            forceWorld = forceWorld + state.attitude.rotated(bodyForce)
            expendedForceNewtons += jet.thrustNewtons.value
            torqueBody = torqueBody + jet.positionMeters.value.cross(bodyForce)
        }

        let (north, east, up) = LMAGCNavState.moonFixedSiteBasis(site: state.landingSite)
        let site = LMAGCNavState.landingSiteMeters(site: state.landingSite)
        var moonPosition = LMAGCNavState.moonCenteredPositionMeters(from: state)
        var moonVelocity = north * state.velocityMetersPerSecond.x
            + east * state.velocityMetersPerSecond.y
            + up * state.velocityMetersPerSecond.z

        let radiusSquared = moonPosition.dot(moonPosition)
        var acceleration = radiusSquared > 0
            ? moonPosition * (
                -Luminary099NavScale.lunarMuMetersCubedPerSecondSquared
                    / (radiusSquared * sqrt(radiusSquared))
            )
            : LMVector3D.zero
        if let mass = state.massKilograms, mass > 0 {
            let thrustMoon = north * (forceWorld.x / mass)
                + east * (forceWorld.y / mass)
                + up * (forceWorld.z / mass)
            acceleration = acceleration + thrustMoon
        }
        // Moon-fixed axes rotate at OMEGMOON. Average-G+ENU PIPA is a
        // non-rotating SM; these terms keep the plant on the same Kepler
        // arc as R-TO-RP. They are not the P64 5 km RGU lead.
        let omega = LMVector3D(z: LuminaryMoonOrientation.moonRateRadiansPerSecond)
        acceleration = acceleration
            - omega.cross(moonVelocity) * 2.0
            - omega.cross(omega.cross(moonPosition))

        let inertia = configuration.diagonalInertiaKilogramMetersSquared?.value
            ?? state.massKilograms.flatMap { mass in
                mass > 0
                    ? LMInertiaMap.diagonalInertiaKilogramMetersSquared(
                        massKilograms: mass,
                        stage: configuration.inertiaStage
                    )
                    : nil
            }
        let angularAcceleration = inertia.map { inertia in
            LMVector3D(
                x: inertia.x == 0 ? 0 : torqueBody.x / inertia.x,
                y: inertia.y == 0 ? 0 : torqueBody.y / inertia.y,
                z: inertia.z == 0 ? 0 : torqueBody.z / inertia.z
            )
        } ?? .zero

        let burned = LMDPSThrottleMap.burnedMassKilograms(
            forceNewtons: expendedForceNewtons,
            deltaTime: deltaTime
        )
        let massKilograms = state.massKilograms.map { mass in
            max(mass - burned, 1.0)
        }
        let propellantMassKilograms = state.propellantMassKilograms.map { propellant in
            max(propellant - burned, 0)
        }

        // Within gear reach the crushable-strut solver owns the step. It works
        // in the site tangent plane, which over the final few meters differs
        // from the moon-fixed arc by far less than the honeycomb stroke it is
        // resolving, and it substeps at a rate the contact stiffness survives.
        if let surface,
           let inertia,
           let mass = state.massKilograms,
           LMLandingGearDynamics.isWithinContactRange(
               positionMeters: state.positionMeters,
               attitude: state.attitude,
               gear: state.landingGear ?? LMLandingGearState(),
               surface: surface
           ) {
            return propagateOnGear(
                state: state,
                surface: surface,
                inertia: inertia,
                massKilograms: mass,
                accelerationMoonFixed: acceleration,
                angularAccelerationBody: angularAcceleration,
                basis: (north, east, up),
                updatedMassKilograms: massKilograms,
                propellantMassKilograms: propellantMassKilograms,
                dpsPitchGimbalRadians: pitch,
                dpsRollGimbalRadians: roll,
                deltaTime: deltaTime
            )
        }

        moonVelocity = moonVelocity + acceleration * deltaTime
        moonPosition = moonPosition + moonVelocity * deltaTime
        var angularVelocity = state.angularVelocityRadiansPerSecond
        if inertia != nil {
            angularVelocity = angularVelocity + angularAcceleration * deltaTime
        }

        let attitude = state.attitude.integrated(
            angularVelocityRadiansPerSecond: angularVelocity,
            deltaTime: deltaTime
        )

        var flightOutcome = state.flightOutcome
        var surfaceContact = state.surfaceContact
        let siteRadius = site.magnitude
        // An installed terrain surface owns touchdown, including depressions
        // below the guidance datum. The sphere is only the no-terrain fallback.
        if surface == nil, moonPosition.magnitude <= siteRadius, siteRadius > 0 {
            moonPosition = moonPosition.normalized() * siteRadius
            let radial = moonPosition.normalized()
            let radialSpeed = moonVelocity.dot(radial)
            let tangentialVelocity = moonVelocity - radial * radialSpeed
            let bodyUpSite = attitude.rotated(LMVector3D(z: 1)).normalized()
            let bodyUpMoon = (
                north * bodyUpSite.x
                    + east * bodyUpSite.y
                    + up * bodyUpSite.z
            ).normalized()
            let tiltCosine = min(max(bodyUpMoon.dot(radial), -1), 1)
            let delta = moonPosition - site
            let contact = LMSurfaceContactSnapshot(
                groundRangeMeters: hypot(delta.dot(north), delta.dot(east)),
                horizontalSpeedMetersPerSecond: tangentialVelocity.magnitude,
                verticalSpeedMetersPerSecond: max(0, -radialSpeed),
                tiltRadians: acos(tiltCosine)
            )
            surfaceContact = contact
            flightOutcome = contact.flightOutcome
            if radialSpeed < 0 {
                moonVelocity = moonVelocity - radial * radialSpeed
            }
        }

        let delta = moonPosition - site
        let position = LMVector3D(
            x: delta.dot(north),
            y: delta.dot(east),
            z: delta.dot(up)
        )
        let velocity = LMVector3D(
            x: moonVelocity.dot(north),
            y: moonVelocity.dot(east),
            z: moonVelocity.dot(up)
        )

        return LMVehicleStateSnapshot(
            positionMeters: position,
            velocityMetersPerSecond: velocity,
            attitude: attitude,
            angularVelocityRadiansPerSecond: angularVelocity,
            massKilograms: massKilograms,
            propellantMassKilograms: propellantMassKilograms,
            flightOutcome: flightOutcome,
            surfaceContact: surfaceContact,
            landingGear: state.landingGear,
            dpsPitchGimbalRadians: pitch,
            dpsRollGimbalRadians: roll
        )
    }

    /// Terrain-relative touchdown, settling, rebound, and tip-over.
    ///
    /// The vehicle is not frozen at first contact. It keeps integrating on its
    /// gear until every footpad is quiescent, so the difference between a soft
    /// arrival, a crushed-strut arrival, and a slope that rolls the vehicle off
    /// its downhill legs is produced by the dynamics rather than by a label.
    private static func propagateOnGear(
        state: LMVehicleStateSnapshot,
        surface: LMLandingSurfaceModel,
        inertia: LMVector3D,
        massKilograms mass: Double,
        accelerationMoonFixed: LMVector3D,
        angularAccelerationBody: LMVector3D,
        basis: (north: LMVector3D, east: LMVector3D, up: LMVector3D),
        updatedMassKilograms: Double?,
        propellantMassKilograms: Double?,
        dpsPitchGimbalRadians: Double,
        dpsRollGimbalRadians: Double,
        deltaTime: Double
    ) -> LMVehicleStateSnapshot {
        let accelerationSite = LMVector3D(
            x: accelerationMoonFixed.dot(basis.north),
            y: accelerationMoonFixed.dot(basis.east),
            z: accelerationMoonFixed.dot(basis.up)
        )
        let result = LMLandingGearDynamics.integrate(
            positionMeters: state.positionMeters,
            velocityMetersPerSecond: state.velocityMetersPerSecond,
            attitude: state.attitude,
            angularVelocityRadiansPerSecond: state.angularVelocityRadiansPerSecond,
            massKilograms: mass,
            inertiaKilogramMetersSquared: inertia,
            accelerationMetersPerSecondSquared: accelerationSite,
            angularAccelerationRadiansPerSecondSquared: angularAccelerationBody,
            gear: state.landingGear ?? LMLandingGearState(),
            surface: surface,
            deltaTime: deltaTime
        )

        let surfaceContact = state.surfaceContact ?? result.firstContact
        var gear = result.gear
        var flightOutcome = LMFlightOutcome.inFlight
        if let contact = surfaceContact, contact.flightOutcome == .crashed {
            // Arriving outside the rated gear envelope is not survivable, so
            // there is nothing left to settle.
            gear = LMLandingGearState(
                legs: gear.legs,
                isProbeContact: gear.isProbeContact,
                quiescentSeconds: gear.quiescentSeconds,
                failure: gear.failure ?? .contactEnvelopeExceeded,
                peakLoadNewtons: gear.peakLoadNewtons,
                touchdownEvents: gear.touchdownEvents
            )
            flightOutcome = .crashed
        } else if gear.failure != nil {
            flightOutcome = .crashed
        } else if result.isSettled {
            flightOutcome = surfaceContact?.flightOutcome ?? .softLanding
        }

        return LMVehicleStateSnapshot(
            positionMeters: result.positionMeters,
            velocityMetersPerSecond: result.velocityMetersPerSecond,
            attitude: result.attitude,
            angularVelocityRadiansPerSecond: result.angularVelocityRadiansPerSecond,
            massKilograms: updatedMassKilograms,
            propellantMassKilograms: propellantMassKilograms,
            flightOutcome: flightOutcome,
            surfaceContact: surfaceContact,
            landingGear: gear,
            dpsPitchGimbalRadians: dpsPitchGimbalRadians,
            dpsRollGimbalRadians: dpsRollGimbalRadians
        )
    }

    /// Non-gravitational acceleration in the body frame (what the PIPAs measure).
    static func specificForceBody(
        state: LMVehicleStateSnapshot,
        commands: LMVehicleSnapshot,
        configuration: LMVehicleConfiguration
    ) -> LMVector3D {
        var forceBody = LMVector3D.zero
        if commands.mainEngineOn,
           !commands.mainEngineOff,
           let thrust = commands.dps.commandedThrustNewtons ?? configuration.mainEngine?.engineOnThrustNewtons?.value {
            forceBody = forceBody + LMDPSGimbalMap.thrustDirectionBody(
                pitchRadians: state.dpsPitchGimbalRadians,
                rollRadians: state.dpsRollGimbalRadians
            ) * thrust
        }
        for command in commands.rcsJets {
            guard let jet = configuration.rcsJets[command.jet] else { continue }
            forceBody = forceBody + jet.thrustDirectionBody.value.normalized() * jet.thrustNewtons.value
        }
        guard let mass = state.massKilograms, mass > 0 else { return .zero }
        return forceBody / mass
    }

    static func advancedGimbal(
        state: LMVehicleStateSnapshot,
        commands: LMVehicleSnapshot,
        deltaTime: Double
    ) -> (pitch: Double, roll: Double) {
        let channel12 = commands.outputChannel12
        let pitch = LMDPSGimbalMap.integrated(
            current: state.dpsPitchGimbalRadians,
            command: LMDPSGimbalMap.command(
                plusBit: (channel12 & 0o1000) != 0,
                minusBit: (channel12 & 0o400) != 0
            ),
            deltaTime: deltaTime
        )
        let roll = LMDPSGimbalMap.integrated(
            current: state.dpsRollGimbalRadians,
            command: LMDPSGimbalMap.command(
                plusBit: (channel12 & 0o4000) != 0,
                minusBit: (channel12 & 0o2000) != 0
            ),
            deltaTime: deltaTime
        )
        return (pitch, roll)
    }
}
