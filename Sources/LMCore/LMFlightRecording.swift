import Foundation

public enum LMFlightControlMode: String, Equatable, Sendable, Codable {
    case automatic
    case astronautP66
}

public struct LMFlightFrame: Equatable, Sendable, Codable {
    public let timeSeconds: Double
    public let cycle: UInt64
    public let programNumber: Int?
    public let vehicleState: LMVehicleStateSnapshot
    public let vehicleCommands: LMVehicleSnapshot
    public let panelState: LMPoweredDescentPanelState
    public let rhcPitch: Int
    public let rhcYaw: Int
    public let rhcRoll: Int
    public let descentRateChannel16: Int

    public init(
        timeSeconds: Double,
        cycle: UInt64,
        programNumber: Int?,
        vehicleState: LMVehicleStateSnapshot,
        vehicleCommands: LMVehicleSnapshot,
        panelState: LMPoweredDescentPanelState = .automatic,
        rhcPitch: Int = 0,
        rhcYaw: Int = 0,
        rhcRoll: Int = 0,
        descentRateChannel16: Int = 0
    ) {
        self.timeSeconds = timeSeconds
        self.cycle = cycle
        self.programNumber = programNumber
        self.vehicleState = vehicleState
        self.vehicleCommands = vehicleCommands
        self.panelState = panelState
        self.rhcPitch = rhcPitch & 0o77777
        self.rhcYaw = rhcYaw & 0o77777
        self.rhcRoll = rhcRoll & 0o77777
        self.descentRateChannel16 = descentRateChannel16 & 0o77777
    }

    public init(snapshot: LMSimulationSnapshot) {
        self.init(
            timeSeconds: snapshot.timeSeconds,
            cycle: snapshot.agc.cycle,
            programNumber: snapshot.agc.dsky.programNumber,
            vehicleState: snapshot.vehicleState,
            vehicleCommands: snapshot.vehicleCommands,
            panelState: snapshot.sensorState.poweredDescentPanelState,
            rhcPitch: snapshot.sensorState.rotationalHandControllerInput.pitch,
            rhcYaw: snapshot.sensorState.rotationalHandControllerInput.yaw,
            rhcRoll: snapshot.sensorState.rotationalHandControllerInput.roll,
            descentRateChannel16: snapshot.sensorState.descentRateChannel16
        )
    }
}

public struct LMFlightRecording: Equatable, Sendable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let scenarioID: String
    public let controlMode: LMFlightControlMode
    public let frames: [LMFlightFrame]

    public init(
        scenarioID: String = "apollo-11-powered-descent",
        controlMode: LMFlightControlMode,
        frames: [LMFlightFrame]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.scenarioID = scenarioID
        self.controlMode = controlMode
        self.frames = frames.sorted { $0.timeSeconds < $1.timeSeconds }
    }

    public var durationSeconds: Double {
        guard let first = frames.first, let last = frames.last else { return 0 }
        return max(0, last.timeSeconds - first.timeSeconds)
    }

    public var flightOutcome: LMFlightOutcome? {
        frames.last?.vehicleState.flightOutcome
    }

    public func encoded(prettyPrinted: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> LMFlightRecording {
        let recording = try JSONDecoder().decode(Self.self, from: data)
        guard recording.schemaVersion == currentSchemaVersion else {
            throw LMFlightRecordingError.unsupportedSchemaVersion(recording.schemaVersion)
        }
        return recording
    }
}

public enum LMFlightRecordingError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
}

public struct LMFlightReplayFrame: Equatable, Sendable {
    public let timeSeconds: Double
    public let programNumber: Int?
    public let vehicleState: LMVehicleStateSnapshot
    public let vehicleCommands: LMVehicleSnapshot
    public let panelState: LMPoweredDescentPanelState
    public let rhcPitch: Int
    public let rhcYaw: Int
    public let rhcRoll: Int
    public let descentRateChannel16: Int
}

public struct LMFlightReplay: Equatable, Sendable {
    public let recording: LMFlightRecording

    public init(recording: LMFlightRecording) {
        self.recording = recording
    }

    public func frame(at elapsedSeconds: Double) -> LMFlightReplayFrame? {
        guard let first = recording.frames.first, let last = recording.frames.last else {
            return nil
        }
        let time = min(max(first.timeSeconds + elapsedSeconds, first.timeSeconds), last.timeSeconds)
        if time <= first.timeSeconds { return Self.replayFrame(first) }
        if time >= last.timeSeconds { return Self.replayFrame(last) }

        var lowerIndex = 0
        var upperIndex = recording.frames.count - 1
        while lowerIndex + 1 < upperIndex {
            let middle = (lowerIndex + upperIndex) / 2
            if recording.frames[middle].timeSeconds <= time {
                lowerIndex = middle
            } else {
                upperIndex = middle
            }
        }

        let lower = recording.frames[lowerIndex]
        let upper = recording.frames[upperIndex]
        let span = upper.timeSeconds - lower.timeSeconds
        let fraction = span > 0 ? (time - lower.timeSeconds) / span : 0
        return LMFlightReplayFrame(
            timeSeconds: time,
            programNumber: lower.programNumber,
            vehicleState: Self.interpolate(lower.vehicleState, upper.vehicleState, fraction: fraction),
            vehicleCommands: lower.vehicleCommands,
            panelState: lower.panelState,
            rhcPitch: lower.rhcPitch,
            rhcYaw: lower.rhcYaw,
            rhcRoll: lower.rhcRoll,
            descentRateChannel16: lower.descentRateChannel16
        )
    }

    private static func replayFrame(_ frame: LMFlightFrame) -> LMFlightReplayFrame {
        LMFlightReplayFrame(
            timeSeconds: frame.timeSeconds,
            programNumber: frame.programNumber,
            vehicleState: frame.vehicleState,
            vehicleCommands: frame.vehicleCommands,
            panelState: frame.panelState,
            rhcPitch: frame.rhcPitch,
            rhcYaw: frame.rhcYaw,
            rhcRoll: frame.rhcRoll,
            descentRateChannel16: frame.descentRateChannel16
        )
    }

    private static func interpolate(
        _ lower: LMVehicleStateSnapshot,
        _ upper: LMVehicleStateSnapshot,
        fraction: Double
    ) -> LMVehicleStateSnapshot {
        let t = min(max(fraction, 0), 1)
        let discrete = t >= 1 ? upper : lower
        return LMVehicleStateSnapshot(
            positionMeters: lower.positionMeters + (upper.positionMeters - lower.positionMeters) * t,
            velocityMetersPerSecond: lower.velocityMetersPerSecond
                + (upper.velocityMetersPerSecond - lower.velocityMetersPerSecond) * t,
            attitude: interpolate(lower.attitude, upper.attitude, fraction: t),
            angularVelocityRadiansPerSecond: lower.angularVelocityRadiansPerSecond
                + (upper.angularVelocityRadiansPerSecond - lower.angularVelocityRadiansPerSecond) * t,
            massKilograms: interpolate(lower.massKilograms, upper.massKilograms, fraction: t),
            propellantMassKilograms: interpolate(
                lower.propellantMassKilograms,
                upper.propellantMassKilograms,
                fraction: t
            ),
            flightOutcome: discrete.flightOutcome,
            surfaceContact: discrete.surfaceContact,
            dpsPitchGimbalRadians: lower.dpsPitchGimbalRadians
                + (upper.dpsPitchGimbalRadians - lower.dpsPitchGimbalRadians) * t,
            dpsRollGimbalRadians: lower.dpsRollGimbalRadians
                + (upper.dpsRollGimbalRadians - lower.dpsRollGimbalRadians) * t
        )
    }

    private static func interpolate(
        _ lower: Double?,
        _ upper: Double?,
        fraction: Double
    ) -> Double? {
        guard let lower, let upper else { return fraction >= 1 ? upper : lower }
        return lower + (upper - lower) * fraction
    }

    private static func interpolate(
        _ lower: LMQuaternion,
        _ upper: LMQuaternion,
        fraction: Double
    ) -> LMQuaternion {
        let dot = lower.w * upper.w + lower.x * upper.x
            + lower.y * upper.y + lower.z * upper.z
        let sign = dot < 0 ? -1.0 : 1.0
        return LMQuaternion(
            w: lower.w + (upper.w * sign - lower.w) * fraction,
            x: lower.x + (upper.x * sign - lower.x) * fraction,
            y: lower.y + (upper.y * sign - lower.y) * fraction,
            z: lower.z + (upper.z * sign - lower.z) * fraction
        ).normalized()
    }
}
