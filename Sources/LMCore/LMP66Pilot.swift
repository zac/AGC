import AGC
import Foundation

/// Deterministic crew surrogate for exercising Luminary P66 through the same
/// ACA inputs available to an astronaut. It commands body rates only; Luminary's
/// DAP remains responsible for selecting and firing the RCS jets.
public struct LMP66Pilot: Equatable, Sendable {
    public let horizontalVelocityGainRadiansPerMeterPerSecond: Double
    public let maximumTiltRadians: Double
    public let attitudeDeadbandRadians: Double
    public let rateDampingSeconds: Double
    public let correctionIntervalFrames: Int
    public let maximumHandControllerCounts: Int
    public let descentRateIntervalFrames: Int
    public let verticalSpeedDeadbandMetersPerSecond: Double

    public init(
        horizontalVelocityGainRadiansPerMeterPerSecond: Double = 0.04,
        maximumTiltRadians: Double = 8 * .pi / 180,
        attitudeDeadbandRadians: Double = 0.2 * .pi / 180,
        rateDampingSeconds: Double = 0.75,
        correctionIntervalFrames: Int = 1,
        maximumHandControllerCounts: Int = 8,
        descentRateIntervalFrames: Int = 8,
        verticalSpeedDeadbandMetersPerSecond: Double = 0.12
    ) {
        self.horizontalVelocityGainRadiansPerMeterPerSecond =
            max(0, horizontalVelocityGainRadiansPerMeterPerSecond)
        self.maximumTiltRadians = max(0, maximumTiltRadians)
        self.attitudeDeadbandRadians = max(0, attitudeDeadbandRadians)
        self.rateDampingSeconds = max(0, rateDampingSeconds)
        self.correctionIntervalFrames = max(1, correctionIntervalFrames)
        self.maximumHandControllerCounts = max(1, min(maximumHandControllerCounts, 57))
        self.descentRateIntervalFrames = max(1, descentRateIntervalFrames)
        self.verticalSpeedDeadbandMetersPerSecond = max(
            0,
            verticalSpeedDeadbandMetersPerSecond
        )
    }

    /// ACA command that tilts the thrust axis against horizontal velocity and
    /// returns upright as the vehicle settles. NASA P/Q/R map to sim Z/X/Y.
    /// The AGC special counters are historically exposed as pitch/yaw/roll,
    /// but addresses 042/043/044 are the Q/P/R RHC counters respectively.
    public func attitudeController(
        for state: LMVehicleStateSnapshot,
        frameIndex: Int = 0
    ) -> LMRotationalHandControllerInput {
        guard frameIndex.isMultiple(of: correctionIntervalFrames) else {
            return .signedCounts()
        }
        let horizontalVelocity = LMVector3D(
            x: state.velocityMetersPerSecond.x,
            y: state.velocityMetersPerSecond.y
        )
        let requestedTilt = min(
            maximumTiltRadians,
            horizontalVelocity.magnitude * horizontalVelocityGainRadiansPerMeterPerSecond
        )
        let desiredHorizontalDirection = horizontalVelocity.magnitude > 0
            ? -horizontalVelocity.normalized()
            : .zero
        let desiredUp = (
            LMVector3D(z: cos(requestedTilt))
                + desiredHorizontalDirection * sin(requestedTilt)
        ).normalized()
        let currentUp = state.attitude.rotated(LMVector3D(z: 1)).normalized()
        let cross = currentUp.cross(desiredUp)
        let sinError = min(max(cross.magnitude, 0), 1)
        let attitudeErrorWorld = cross.normalized() * asin(sinError)
        let attitudeErrorBody = state.attitude.inverseRotated(attitudeErrorWorld)
        let dampedError = attitudeErrorBody
            - state.angularVelocityRadiansPerSecond * rateDampingSeconds

        let x = abs(dampedError.x)
        let y = abs(dampedError.y)
        let z = abs(dampedError.z)
        let q = x >= y && x >= z ? signedCount(for: dampedError.x) : 0
        let r = y > x && y >= z ? signedCount(for: dampedError.y) : 0
        let p = z > x && z > y ? signedCount(for: dampedError.z) : 0
        return .signedCounts(pitch: q, yaw: p, roll: r)
    }

    /// Momentary ROD switch command for a conservative terminal-descent
    /// profile. Luminary defines DESCENT+ as slowing the descent and DESCENT-
    /// as speeding it up; each accepted click changes VDGVERT by 1 ft/s.
    public func descentRateController(
        for state: LMVehicleStateSnapshot,
        frameIndex: Int = 0
    ) -> LMDescentRateControlInput {
        guard frameIndex.isMultiple(of: descentRateIntervalFrames) else {
            return LMDescentRateControlInput()
        }
        let target: Double
        switch state.altitudeMeters {
        case 30...:
            target = -0.9
        case 10..<30:
            target = -0.6
        default:
            target = -0.3
        }
        let error = state.verticalSpeedMetersPerSecond - target
        if error > verticalSpeedDeadbandMetersPerSecond {
            return LMDescentRateControlInput(descendMinus: true)
        }
        if error < -verticalSpeedDeadbandMetersPerSecond {
            return LMDescentRateControlInput(descendPlus: true)
        }
        return LMDescentRateControlInput()
    }

    private func signedCount(for error: Double) -> Int {
        guard abs(error) > attitudeDeadbandRadians else { return 0 }
        let magnitude = min(
            maximumHandControllerCounts,
            max(
                1,
                Int(ceil((abs(error) - attitudeDeadbandRadians) / attitudeDeadbandRadians))
            )
        )
        return error > 0 ? magnitude : -magnitude
    }
}

public extension AGCRotationalHandControllerInput {
    /// Encode signed ACA deflection counts as AGC 15-bit ones'-complement words.
    static func signedCounts(
        pitch: Int = 0,
        yaw: Int = 0,
        roll: Int = 0
    ) -> AGCRotationalHandControllerInput {
        AGCRotationalHandControllerInput(
            pitch: AGCSinglePrecision.encode(value: Double(pitch), scale: 14).word,
            yaw: AGCSinglePrecision.encode(value: Double(yaw), scale: 14).word,
            roll: AGCSinglePrecision.encode(value: Double(roll), scale: 14).word
        )
    }
}
