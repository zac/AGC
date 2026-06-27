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

    public init(
        rangeMeters: Double? = nil,
        altitudeMeters: Double? = nil,
        rangeRateMetersPerSecond: Double? = nil
    ) {
        self.rangeMeters = rangeMeters
        self.altitudeMeters = altitudeMeters
        self.rangeRateMetersPerSecond = rangeRateMetersPerSecond
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
        case .measurement:
            return nil
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
            return .unmodeled("SI radar measurement conversion into AGC raw words is unmodeled.")
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
}
