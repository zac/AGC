import AGC
import Foundation

public struct LMRadarRawInput: Equatable, Sendable, Codable {
    public let rendezvousRadarWord: Int?
    public let altitudeMeterWord: Int?

    public init(rendezvousRadarWord: Int? = nil, altitudeMeterWord: Int? = nil) {
        self.rendezvousRadarWord = rendezvousRadarWord.map { $0 & 0o77777 }
        self.altitudeMeterWord = altitudeMeterWord.map { $0 & 0o77777 }
    }
}

public struct LMRadarMeasurementInput: Equatable, Sendable, Codable {
    public let rangeMeters: Double?
    public let altitudeMeters: Double?
    public let rangeRateMetersPerSecond: Double?
    /// NASA body (NB) velocity for LRVELX/Y/Z. Zero pad-load antenna
    /// angles make the velocity beams the NASA body axes.
    public let nasaBodyVelocityMetersPerSecond: LMVector3D?

    public init(
        rangeMeters: Double? = nil,
        altitudeMeters: Double? = nil,
        rangeRateMetersPerSecond: Double? = nil,
        nasaBodyVelocityMetersPerSecond: LMVector3D? = nil
    ) {
        self.rangeMeters = rangeMeters
        self.altitudeMeters = altitudeMeters
        self.rangeRateMetersPerSecond = rangeRateMetersPerSecond
        self.nasaBodyVelocityMetersPerSecond = nasaBodyVelocityMetersPerSecond
    }
}

public enum LMRadarInput: Equatable, Sendable, Codable {
    case raw(LMRadarRawInput)
    case measurement(LMRadarMeasurementInput)

    public var rawAGCInput: AGCRadarInput? {
        switch self {
        case .raw(let input):
            return AGCRadarInput(
                rendezvousRadar: input.rendezvousRadarWord,
                altitudeMeter: input.altitudeMeterWord
            )
        case .measurement(let measurement):
            return LMRadarConversion.rawInput(from: measurement)
        }
    }

    public var conversionStatus: LMModelingStatus {
        switch self {
        case .raw:
            return .sourceBacked(
                detail: "Raw AGC radar register words are injected without unit conversion.",
                source: .yaAGCRadarRequest
            )
        case .measurement:
            return .sourceBacked(
                detail: "SI altitude/range converted at 1.079 feet per bit (landing radar low scale).",
                source: .luminaryLandingRadarScale
            )
        }
    }
}

public struct LMDescentRateControlInput: Equatable, Sendable, Codable {
    public let descendPlus: Bool
    public let descendMinus: Bool

    public init(descendPlus: Bool = false, descendMinus: Bool = false) {
        self.descendPlus = descendPlus
        self.descendMinus = descendMinus
    }

    public var channel16Value: Int {
        var value = 0
        if descendPlus {
            value |= 0o20000
        }
        if descendMinus {
            value |= 0o40000
        }
        return value
    }
}

public struct LMFrameInput: Equatable, Sendable {
    public let radarInput: LMRadarInput?
    public let rotationalHandControllerInput: LMRotationalHandControllerInput?
    public let descentRateInput: LMDescentRateControlInput?
    public let rawChannelInputs: [AGCChannelInput]

    public init(
        radarInput: LMRadarInput? = nil,
        rotationalHandControllerInput: LMRotationalHandControllerInput? = nil,
        descentRateInput: LMDescentRateControlInput? = nil,
        rawChannelInputs: [AGCChannelInput] = []
    ) {
        self.radarInput = radarInput
        self.rotationalHandControllerInput = rotationalHandControllerInput
        self.descentRateInput = descentRateInput
        self.rawChannelInputs = rawChannelInputs
    }

    public static let none = LMFrameInput()

    /// Held AUTO / engine-arm / LR POS1 plus landing-radar altitude.
    /// This is the auto-land button frame: no invented rates, no extra keys.
    public static func autoLand(
        altitudeMeters: Double,
        nasaBodyVelocityMetersPerSecond: LMVector3D? = nil,
        rotationalHandController: LMRotationalHandControllerInput? = nil,
        descendPlus: Bool = false,
        descendMinus: Bool = false
    ) -> LMFrameInput {
        LMFrameInput(
            radarInput: .measurement(LMRadarMeasurementInput(
                altitudeMeters: max(0, altitudeMeters),
                nasaBodyVelocityMetersPerSecond: nasaBodyVelocityMetersPerSecond
            )),
            rotationalHandControllerInput: rotationalHandController,
            descentRateInput: LMDescentRateControlInput(
                descendPlus: descendPlus,
                descendMinus: descendMinus
            ),
            rawChannelInputs: LMPoweredDescentPanel.channelInputs
        )
    }

    /// Auto-land with R12 radar when the range beam sees the ground.
    /// HMEAS is slant range along `HBEAMANT`, not nadir altitude.
    public static func autoLand(
        from state: LMVehicleStateSnapshot,
        rotationalHandController: LMRotationalHandControllerInput? = nil,
        descendPlus: Bool = false,
        descendMinus: Bool = false
    ) -> LMFrameInput {
        LMFrameInput(
            radarInput: LMLandingRadar.measurement(from: state).map { .measurement($0) },
            rotationalHandControllerInput: rotationalHandController,
            descentRateInput: LMDescentRateControlInput(
                descendPlus: descendPlus,
                descendMinus: descendMinus
            ),
            rawChannelInputs: LMPoweredDescentPanel.channelInputs
        )
    }
}
