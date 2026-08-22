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
    /// Direct NASA-body velocity for callers supplying synthetic LRVELX/Y/Z.
    /// Source-backed vehicle measurements instead use
    /// `landingRadarBeamVelocityMetersPerSecond` after applying SETPOS geometry.
    public let nasaBodyVelocityMetersPerSecond: LMVector3D?
    /// Three scalar Doppler measurements along Luminary's VX/VY/VZ beams.
    public let landingRadarBeamVelocityMetersPerSecond: LMVector3D?

    public init(
        rangeMeters: Double? = nil,
        altitudeMeters: Double? = nil,
        rangeRateMetersPerSecond: Double? = nil,
        nasaBodyVelocityMetersPerSecond: LMVector3D? = nil,
        landingRadarBeamVelocityMetersPerSecond: LMVector3D? = nil
    ) {
        self.rangeMeters = rangeMeters
        self.altitudeMeters = altitudeMeters
        self.rangeRateMetersPerSecond = rangeRateMetersPerSecond
        self.nasaBodyVelocityMetersPerSecond = nasaBodyVelocityMetersPerSecond
        self.landingRadarBeamVelocityMetersPerSecond = landingRadarBeamVelocityMetersPerSecond
    }
}

public enum LMRadarInput: Equatable, Sendable, Codable {
    case raw(LMRadarRawInput)
    case measurement(LMRadarMeasurementInput)
    /// Vehicle state awaiting projection through the runtime's live LR position.
    case landingRadar(LMVehicleStateSnapshot)

    public var rawAGCInput: AGCRadarInput? {
        switch self {
        case .raw(let input):
            return AGCRadarInput(
                rendezvousRadar: input.rendezvousRadarWord,
                altitudeMeter: input.altitudeMeterWord
            )
        case .measurement(let measurement):
            return LMRadarConversion.rawInput(from: measurement)
        case .landingRadar(let state):
            return LMLandingRadar.measurement(from: state, position2: false)
                .map(LMRadarConversion.rawInput(from:))
        }
    }

    public var conversionStatus: LMModelingStatus {
        switch self {
        case .raw:
            return .sourceBacked(
                detail: "Raw AGC radar register words are injected without unit conversion.",
                source: .yaAGCRadarRequest
            )
        case .measurement, .landingRadar:
            return .sourceBacked(
                detail: "SI landing-radar range uses the Luminary low/high altitude scales; vehicle Doppler uses the live SETPOS beam geometry.",
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
            value |= 0o40
        }
        if descendMinus {
            value |= 0o100
        }
        return value
    }
}

public enum LMPoweredDescentAttitudeMode: String, Equatable, Sendable, Codable {
    case automatic
    case attitudeHold
}

/// Crew-selectable powered-descent panel state held for an entire simulation
/// frame. Luminary's GUILDENSTERN monitor switches P65/P67 into P66 whenever
/// the MODE CONTROL switch presents the ATT HOLD discrete on channel 31.
public struct LMPoweredDescentPanelState: Equatable, Sendable, Codable {
    public let attitudeMode: LMPoweredDescentAttitudeMode

    public init(attitudeMode: LMPoweredDescentAttitudeMode = .automatic) {
        self.attitudeMode = attitudeMode
    }

    public static let automatic = LMPoweredDescentPanelState()
    public static let p66AttitudeHold = LMPoweredDescentPanelState(attitudeMode: .attitudeHold)

    public var channel31Value: Int {
        channel31Value(rhcOutOfDetent: false)
    }

    public func channel31Value(rhcOutOfDetent: Bool) -> Int {
        var value: Int
        switch attitudeMode {
        case .automatic:
            value = LMPoweredDescentPanel.channel31
        case .attitudeHold:
            value = LMPoweredDescentPanel.channel31
                & ~LMPoweredDescentPanel.channel31AttitudeHold
        }
        if rhcOutOfDetent {
            value &= ~LMPoweredDescentPanel.channel31RHCOutOfDetent
        }
        return value
    }

    public var channelInputs: [AGCChannelInput] {
        channelInputs(rhcOutOfDetent: false)
    }

    public func channelInputs(rhcOutOfDetent: Bool) -> [AGCChannelInput] {
        [
            AGCChannelInput(channel: 0o30, value: LMPoweredDescentPanel.channel30),
            AGCChannelInput(
                channel: 0o31,
                value: channel31Value(rhcOutOfDetent: rhcOutOfDetent)
            ),
            AGCChannelInput(channel: 0o33, value: LMPoweredDescentPanel.channel33)
        ]
    }
}

public struct LMFrameInput: Equatable, Sendable {
    public let radarInput: LMRadarInput?
    public let poweredDescentPanelState: LMPoweredDescentPanelState?
    public let rotationalHandControllerInput: LMRotationalHandControllerInput?
    public let descentRateInput: LMDescentRateControlInput?
    public let rawChannelInputs: [AGCChannelInput]

    public init(
        radarInput: LMRadarInput? = nil,
        poweredDescentPanelState: LMPoweredDescentPanelState? = nil,
        rotationalHandControllerInput: LMRotationalHandControllerInput? = nil,
        descentRateInput: LMDescentRateControlInput? = nil,
        rawChannelInputs: [AGCChannelInput] = []
    ) {
        self.radarInput = radarInput
        self.poweredDescentPanelState = poweredDescentPanelState
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
    /// HMEAS is slant range along `HBEAMANT`, not nadir altitude. The runtime
    /// follows the Apollo 11 crew timeline for V57 radar-update permission.
    public static func autoLand(
        from state: LMVehicleStateSnapshot,
        rotationalHandController: LMRotationalHandControllerInput? = nil,
        descendPlus: Bool = false,
        descendMinus: Bool = false
    ) -> LMFrameInput {
        LMFrameInput(
            radarInput: LMLandingRadar.measurement(from: state, position2: false).map { _ in
                .landingRadar(state)
            },
            rotationalHandControllerInput: rotationalHandController,
            descentRateInput: LMDescentRateControlInput(
                descendPlus: descendPlus,
                descendMinus: descendMinus
            ),
            rawChannelInputs: LMPoweredDescentPanel.channelInputs
        )
    }

    /// P66 crew frame: ATT HOLD selects rate-of-descent guidance, the ACA is
    /// held continuously for every AGC RHC sample, and each ROD switch closure
    /// increments or decrements Luminary's desired descent rate.
    public static func astronautLand(
        from state: LMVehicleStateSnapshot,
        panelState: LMPoweredDescentPanelState = .automatic,
        attitudeController: LMRotationalHandControllerInput = LMRotationalHandControllerInput(),
        descendPlus: Bool = false,
        descendMinus: Bool = false
    ) -> LMFrameInput {
        LMFrameInput(
            radarInput: LMLandingRadar.measurement(from: state, position2: false).map { _ in
                .landingRadar(state)
            },
            poweredDescentPanelState: panelState,
            rotationalHandControllerInput: attitudeController,
            descentRateInput: LMDescentRateControlInput(
                descendPlus: descendPlus,
                descendMinus: descendMinus
            )
        )
    }
}
