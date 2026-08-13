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
        title: "NASA R-567 Luminary GSOP PIPA scale",
        detail: "LM PIPA scale factor is 5.85 cm/s per pulse."
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
        detail: "Landing radar low-scale altitude is 1.079 feet per bit."
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
        detail: "1JACC = A/(MASS+C)+B; I = TORKJET1/1JACC. A scaled at π/4 rad/s²·2^16 kg, B at π/4 rad/s², C at 2^16 kg. NASA P/Q/R map to sim Z/X/Y."
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
        detail: "PIPA pulse generation uses 5.85 cm/s per pulse."
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
        detail: "Diagonal inertia from 1/ACCS INERCON curve fits and TORKJET1."
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

public struct LMVehicleStateSnapshot: Equatable, Sendable, Codable {
    public let positionMeters: LMVector3D
    public let velocityMetersPerSecond: LMVector3D
    public let attitude: LMQuaternion
    public let angularVelocityRadiansPerSecond: LMVector3D
    public let massKilograms: Double?
    public let propellantMassKilograms: Double?
    public let isLanded: Bool

    public init(
        positionMeters: LMVector3D = .zero,
        velocityMetersPerSecond: LMVector3D = .zero,
        attitude: LMQuaternion = .identity,
        angularVelocityRadiansPerSecond: LMVector3D = .zero,
        massKilograms: Double? = nil,
        propellantMassKilograms: Double? = nil,
        isLanded: Bool = false
    ) {
        self.positionMeters = positionMeters
        self.velocityMetersPerSecond = velocityMetersPerSecond
        self.attitude = attitude.normalized()
        self.angularVelocityRadiansPerSecond = angularVelocityRadiansPerSecond
        self.massKilograms = massKilograms
        self.propellantMassKilograms = propellantMassKilograms
        self.isLanded = isLanded
    }

    public var altitudeMeters: Double {
        positionMeters.z
    }

    public var verticalSpeedMetersPerSecond: Double {
        velocityMetersPerSecond.z
    }
}

public struct LMSensorSnapshot: Equatable, Sendable {
    public let radarInput: LMRadarInput?
    public let rotationalHandControllerInput: LMRotationalHandControllerInput
    public let descentRateChannel16: Int

    public init(
        radarInput: LMRadarInput? = nil,
        rotationalHandControllerInput: LMRotationalHandControllerInput = LMRotationalHandControllerInput(),
        descentRateChannel16: Int = 0
    ) {
        self.radarInput = radarInput
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
        let initialState = LMVehicleStateSnapshot(
            positionMeters: LMVector3D(z: 50_000.0 * 0.3048),
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
                sources: [dpsSource, guidanceSource] + configuration.sourceReferences,
                unmodeledItems: [
                    "Apollo 11 powered-descent initial velocity",
                    "Apollo 11 powered-descent initial attitude and angular velocity"
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
    }

    public init(coreImage: Data, scenario: LMPoweredDescentScenario) throws {
        self.agcRuntime = try AGCRuntime(coreImage: coreImage)
        self.configuration = scenario.configuration
        self.initialState = scenario.initialState
        self.vehicleState = scenario.initialState
        self.scenarioSourceStatus = scenario.sourceStatus
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

    public func enqueueInput(_ input: AGCChannelInput) async {
        await agcRuntime.enqueueInput(input)
    }

    public func enqueueInputs(_ inputs: [AGCChannelInput]) async {
        await agcRuntime.enqueueInputs(inputs)
    }

    public func setRadarInput(_ input: LMRadarInput?) async {
        radarInput = input
        await agcRuntime.setRadarInput(input?.rawAGCInput)
    }

    public func setRotationalHandControllerInput(_ input: LMRotationalHandControllerInput) async {
        rhcInput = input
        await agcRuntime.setRotationalHandControllerInput(input)
    }

    public func setDescentRateControlInput(descendPlus: Bool, descendMinus: Bool) async {
        let input = LMDescentRateControlInput(descendPlus: descendPlus, descendMinus: descendMinus)
        descentRateChannel16 = input.channel16Value
        await agcRuntime.enqueueInput(AGCChannelInput(channel: 0o16, value: input.channel16Value))
    }

    public func simulationTrace() -> [LMSimulationTraceSample] {
        traceSamples
    }

    private func applyFrameInput(_ input: LMFrameInput) async {
        if let radarInput = input.radarInput {
            await setRadarInput(radarInput)
        }
        if let rhcInput = input.rotationalHandControllerInput {
            await setRotationalHandControllerInput(rhcInput)
        }
        if !input.rawChannelInputs.isEmpty {
            await agcRuntime.enqueueInputs(input.rawChannelInputs)
        }
        if let descentRateInput = input.descentRateInput {
            descentRateChannel16 = descentRateInput.channel16Value
            await agcRuntime.enqueueInput(AGCChannelInput(channel: 0o16, value: descentRateInput.channel16Value))
        }
    }

    private func stepExact(cycles: UInt64, deltaTime: Double) async -> LMSimulationSnapshot {
        let sensorPulses = sensorFeedback.increments(
            specificForceBody: lastSpecificForceBody,
            attitude: vehicleState.attitude,
            deltaTime: deltaTime
        )
        if !sensorPulses.isEmpty {
            await agcRuntime.enqueueInputs(sensorPulses)
        }
        elapsedTimeSeconds += deltaTime
        let agc = await agcRuntime.step(cycles: cycles)
        let channelDeltas = traceDeltas(from: agc.channelTrace)
        var commands = LMVehicleSnapshot(agcSnapshot: agc)
        throttleState.advance(
            thrustRegister: agc.registers.thrust,
            driveActive: commands.thrustDriveActive,
            deltaTime: deltaTime
        )
        let engineOn = commands.mainEngineOn && !commands.mainEngineOff
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
            deltaTime: deltaTime
        )
        let snapshot = makeSnapshot(agc: agc, channelDeltas: channelDeltas)
        traceSamples.append(snapshot.traceSample)
        if traceSamples.count > 2_048 {
            traceSamples.removeFirst(traceSamples.count - 2_048)
        }
        return snapshot
    }

    private func makeSnapshot(agc: AGCSnapshot, channelDeltas: [AGCChannelTraceEntry]) -> LMSimulationSnapshot {
        let engineOn = {
            let raw = LMVehicleSnapshot(agcSnapshot: agc)
            return raw.mainEngineOn && !raw.mainEngineOff
        }()
        let commands = LMVehicleSnapshot(agcSnapshot: agc)
            .withCommandedThrust(throttleState.commandedThrustNewtons(engineOn: engineOn))
        let sourceStatus = makeSourceStatus(commands: commands)
        let sensorState = LMSensorSnapshot(
            radarInput: radarInput,
            rotationalHandControllerInput: rhcInput,
            descentRateChannel16: descentRateChannel16
        )
        let traceSample = LMSimulationTraceSample(
            timeSeconds: elapsedTimeSeconds,
            agc: agc,
            vehicleState: vehicleState,
            vehicleCommands: commands,
            sourceStatus: sourceStatus,
            channelDeltas: channelDeltas
        )
        return LMSimulationSnapshot(
            timeSeconds: elapsedTimeSeconds,
            agc: agc,
            vehicleState: vehicleState,
            vehicleCommands: commands,
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
            + [.luminaryPIPAScale, .agcCDUEncoding, .luminaryThrottleConstants, .luminaryRCSGeometry, .luminary1ACCS]
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
}

enum LMDynamics {
    static func propagate(
        state: LMVehicleStateSnapshot,
        commands: LMVehicleSnapshot,
        configuration: LMVehicleConfiguration,
        deltaTime: Double
    ) -> LMVehicleStateSnapshot {
        guard deltaTime > 0, !state.isLanded else { return state }

        var forceWorld = LMVector3D.zero
        var torqueBody = LMVector3D.zero

        if commands.mainEngineOn,
           !commands.mainEngineOff,
           let thrust = commands.dps.commandedThrustNewtons ?? configuration.mainEngine?.engineOnThrustNewtons?.value {
            forceWorld = forceWorld + state.attitude.rotated(LMVector3D(z: thrust))
        }

        for command in commands.rcsJets {
            guard let jet = configuration.rcsJets[command.jet] else { continue }
            let bodyForce = jet.thrustDirectionBody.value.normalized() * jet.thrustNewtons.value
            forceWorld = forceWorld + state.attitude.rotated(bodyForce)
            torqueBody = torqueBody + jet.positionMeters.value.cross(bodyForce)
        }

        var acceleration = LMVector3D(z: -configuration.lunarGravityMetersPerSecondSquared.value)
        if let mass = state.massKilograms, mass > 0 {
            acceleration = acceleration + forceWorld / mass
        }

        var velocity = state.velocityMetersPerSecond + acceleration * deltaTime
        var position = state.positionMeters + velocity * deltaTime
        var angularVelocity = state.angularVelocityRadiansPerSecond

        let inertia = configuration.diagonalInertiaKilogramMetersSquared?.value
            ?? state.massKilograms.flatMap { mass in
                mass > 0
                    ? LMInertiaMap.diagonalInertiaKilogramMetersSquared(
                        massKilograms: mass,
                        stage: configuration.inertiaStage
                    )
                    : nil
            }
        if let inertia {
            let angularAcceleration = LMVector3D(
                x: inertia.x == 0 ? 0 : torqueBody.x / inertia.x,
                y: inertia.y == 0 ? 0 : torqueBody.y / inertia.y,
                z: inertia.z == 0 ? 0 : torqueBody.z / inertia.z
            )
            angularVelocity = angularVelocity + angularAcceleration * deltaTime
        }

        let attitude = state.attitude.integrated(
            angularVelocityRadiansPerSecond: angularVelocity,
            deltaTime: deltaTime
        )

        var landed = state.isLanded
        if position.z <= 0 {
            position = LMVector3D(x: position.x, y: position.y, z: 0)
            if velocity.z < 0 {
                velocity = LMVector3D(x: velocity.x, y: velocity.y, z: 0)
            }
            landed = true
        }

        return LMVehicleStateSnapshot(
            positionMeters: position,
            velocityMetersPerSecond: velocity,
            attitude: attitude,
            angularVelocityRadiansPerSecond: angularVelocity,
            massKilograms: state.massKilograms,
            propellantMassKilograms: state.propellantMassKilograms,
            isLanded: landed
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
            forceBody = forceBody + LMVector3D(z: thrust)
        }
        for command in commands.rcsJets {
            guard let jet = configuration.rcsJets[command.jet] else { continue }
            forceBody = forceBody + jet.thrustDirectionBody.value.normalized() * jet.thrustNewtons.value
        }
        guard let mass = state.massKilograms, mass > 0 else { return .zero }
        return forceBody / mass
    }
}
