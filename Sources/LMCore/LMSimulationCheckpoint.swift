import AGC
import Foundation

public enum LMSimulationCheckpointError: Error, Equatable, Sendable {
    case schemaVersionMismatch(expected: Int, found: Int)
    case coreImageMismatch(expected: String, found: String)
    case scenarioMismatch(expected: String, found: String)
}

/// Versioned full-state snapshot of an ``LMSimulationRuntime``: the mutable AGC
/// (memory, CPU sequencing, channels, DSKY, pending inputs), peripherals,
/// sensor-feedback remainders, vehicle integrator state, crew panel mirrors,
/// and DPS throttle drive — everything required to continue flight bit-exactly.
///
/// Fixed memory is never stored. Restoring reloads it from the Luminary core
/// image named by ``coreImageSHA256``, so a fixture is bound to one core rope
/// set and is refused outright when the image differs.
public struct LMSimulationCheckpoint: Equatable, Sendable, Codable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    /// Lowercase SHA-256 of the Luminary core image backing this state.
    public var coreImageSHA256: String
    public var scenarioID: String
    public var simulationTimeSeconds: Double

    public var agc: AGCRuntimeCheckpoint
    public var vehicleState: LMVehicleStateSnapshot

    public var radarInput: LMRadarInput?
    public var panelState: LMPoweredDescentPanelState
    public var rhcInput: LMRotationalHandControllerInput
    public var descentRateChannel16: Int
    public var cycleRemainder: Double

    public var sensorFeedback: LMSensorFeedbackCheckpoint
    public var lastSpecificForceBody: LMVector3D

    public var throttle: LMThrottleCheckpoint
    public var crewHandshake: LMP63CrewHandshakeCheckpoint
    public var lastDSKYVerb: String
    public var lastDSKYNoun: String
    public var landingRadarInPosition2: Bool
    public var poweredDescentIgnitionTimeSeconds: Double?
    public var landingRadarPermissionKeyIndex: Int
    public var lastTraceEntryID: UInt64

    public init(
        schemaVersion: Int = LMSimulationCheckpoint.schemaVersion,
        coreImageSHA256: String,
        scenarioID: String,
        simulationTimeSeconds: Double,
        agc: AGCRuntimeCheckpoint,
        vehicleState: LMVehicleStateSnapshot,
        radarInput: LMRadarInput?,
        panelState: LMPoweredDescentPanelState,
        rhcInput: LMRotationalHandControllerInput,
        descentRateChannel16: Int,
        cycleRemainder: Double,
        sensorFeedback: LMSensorFeedbackCheckpoint,
        lastSpecificForceBody: LMVector3D,
        throttle: LMThrottleCheckpoint,
        crewHandshake: LMP63CrewHandshakeCheckpoint,
        lastDSKYVerb: String,
        lastDSKYNoun: String,
        landingRadarInPosition2: Bool,
        poweredDescentIgnitionTimeSeconds: Double?,
        landingRadarPermissionKeyIndex: Int,
        lastTraceEntryID: UInt64
    ) {
        self.schemaVersion = schemaVersion
        self.coreImageSHA256 = coreImageSHA256
        self.scenarioID = scenarioID
        self.simulationTimeSeconds = simulationTimeSeconds
        self.agc = agc
        self.vehicleState = vehicleState
        self.radarInput = radarInput
        self.panelState = panelState
        self.rhcInput = rhcInput
        self.descentRateChannel16 = descentRateChannel16
        self.cycleRemainder = cycleRemainder
        self.sensorFeedback = sensorFeedback
        self.lastSpecificForceBody = lastSpecificForceBody
        self.throttle = throttle
        self.crewHandshake = crewHandshake
        self.lastDSKYVerb = lastDSKYVerb
        self.lastDSKYNoun = lastDSKYNoun
        self.landingRadarInPosition2 = landingRadarInPosition2
        self.poweredDescentIgnitionTimeSeconds = poweredDescentIgnitionTimeSeconds
        self.landingRadarPermissionKeyIndex = landingRadarPermissionKeyIndex
        self.lastTraceEntryID = lastTraceEntryID
    }

    /// Refuse incompatible fixtures before any state is applied.
    public func validate(
        coreImageSHA256 expectedCoreImage: String? = nil,
        scenarioID expectedScenario: String? = nil
    ) throws {
        guard schemaVersion == Self.schemaVersion else {
            throw LMSimulationCheckpointError.schemaVersionMismatch(
                expected: Self.schemaVersion,
                found: schemaVersion
            )
        }
        if let expectedCoreImage, coreImageSHA256 != expectedCoreImage {
            throw LMSimulationCheckpointError.coreImageMismatch(
                expected: expectedCoreImage,
                found: coreImageSHA256
            )
        }
        if let expectedScenario, scenarioID != expectedScenario {
            throw LMSimulationCheckpointError.scenarioMismatch(
                expected: expectedScenario,
                found: scenarioID
            )
        }
    }

    /// Binary property-list fixture bytes suitable for bundling as an app asset.
    public func encodedFixture() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    public static func decodeFixture(_ data: Data) throws -> LMSimulationCheckpoint {
        try PropertyListDecoder().decode(LMSimulationCheckpoint.self, from: data)
    }
}
