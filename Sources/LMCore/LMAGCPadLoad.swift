import AGC
import Foundation

/// Apollo 11 Luminary 099 landing-guidance pad loads from NASA SNA-8-D-027(II)
/// Table LM5/4.5.1-1 (prelaunch erasable load).
///
/// Aimpoints are in descent-guidance coordinates. TLAND is 100:50:49.20 GET.
/// The AGC clock is set to `TLAND − GUIDDURN − ZOOMTIME` so IGNALG starts at
/// a sourced PDI-relative time rather than GET 0.
public enum Luminary99LandingPadLoad {
    /// NASA mission-tape TLAND, centiseconds GET, B28.
    public static let tlandCentiseconds = 36_304_920.0
    /// Luminary `GUIDDURN 2DEC +66440` (664.40 s) in THE_LUNAR_LANDING.agc.
    public static let guidDurnCentiseconds = 66_440.0
    /// NASA ZOOMTIME, 26 s of DPS throttle-up, B14 centiseconds.
    public static let zoomTimeCentiseconds = 2_600.0

    public static var pdiClockCentiseconds: Double {
        tlandCentiseconds - guidDurnCentiseconds - zoomTimeCentiseconds
    }

    public static func clockWords() -> [AGCErasableWord] {
        dp(Luminary099Erasable.time2, pdiClockCentiseconds, scale: 28)
    }

    public static func erasableWords() -> [AGCErasableWord] {
        var words: [AGCErasableWord] = []
        words.append(contentsOf: dp(Luminary099Erasable.tland, tlandCentiseconds, scale: 28))
        words.append(contentsOf: vector(Luminary099Erasable.rbrfg, [52.375308, 0, -3_254.836061], scale: 24))
        words.append(contentsOf: vector(Luminary099Erasable.vbrfg, [-0.322710048, 0, -0.00316992], scale: 10))
        words.append(contentsOf: vector(Luminary099Erasable.abrfg, [0.000019022568, 0, -0.000277502112], scale: -4))
        words.append(contentsOf: dp(Luminary099Erasable.vbrfgStar, -0.05705856, scale: 13))
        words.append(contentsOf: dp(Luminary099Erasable.abrfgStar, -0.001665012672, scale: -4))
        words.append(contentsOf: dp(Luminary099Erasable.jbrfgStar, -5.738399496e-9, scale: -21))
        words.append(AGCErasableWord(ecadr: Luminary099Erasable.gainBrak, value: 0o37777))
        words.append(AGCErasableWord(ecadr: Luminary099Erasable.gainBrak + 1, value: 0o37777))
        words.append(sp(Luminary099Erasable.tcgfBrak, 3_000, scale: 17))
        words.append(sp(Luminary099Erasable.tcgiBrak, 90_000, scale: 17))
        words.append(contentsOf: vector(Luminary099Erasable.rapfg, [33.858708, 0, -8.1668112], scale: 24))
        words.append(contentsOf: vector(Luminary099Erasable.vapfg, [-0.015218664, 0, 0.000755904], scale: 10))
        words.append(contentsOf: vector(Luminary099Erasable.aapfg, [-7.997952e-6, 0, -1.560576e-5], scale: -4))
        words.append(contentsOf: dp(Luminary099Erasable.vapfgStar, 0.013606272, scale: 13))
        words.append(contentsOf: dp(Luminary099Erasable.aapfgStar, -9.363456e-5, scale: -4))
        words.append(contentsOf: dp(Luminary099Erasable.japfgStar, 5.50993056e-10, scale: -21))
        words.append(contentsOf: dp(Luminary099Erasable.gainAppr, 0, scale: 0))
        words.append(sp(Luminary099Erasable.tcgfAppr, 3_000, scale: 17))
        words.append(sp(Luminary099Erasable.tcgiAppr, 20_000, scale: 17))
        words.append(contentsOf: dp(Luminary099Erasable.vign, 16.90256208, scale: 10))
        words.append(contentsOf: dp(Luminary099Erasable.rignx, -39_782.453328, scale: 24))
        words.append(contentsOf: dp(Luminary099Erasable.rignz, -436_655.657, scale: 24))
        words.append(contentsOf: dp(Luminary099Erasable.kignx, -0.617631, scale: 4))
        words.append(contentsOf: dp(Luminary099Erasable.kigny, -2.4770341207e-6, scale: -16))
        words.append(contentsOf: dp(Luminary099Erasable.kignv, -41_000, scale: 18))
        words.append(sp(Luminary099Erasable.lowcrit, 2_124.4, scale: 14))
        words.append(sp(Luminary099Erasable.highcrit, 2_348.0, scale: 14))
        words.append(contentsOf: vector(Luminary099Erasable.v2fg, [-0.009144, 0, 0], scale: 10))
        words.append(contentsOf: dp(Luminary099Erasable.tauvert, 1_000, scale: 14))
        words.append(sp(Luminary099Erasable.zoomtime, zoomTimeCentiseconds, scale: 14))
        words.append(sp(Luminary099Erasable.tendbrak, 6_200, scale: 17))
        words.append(sp(Luminary099Erasable.tendappr, 1_200, scale: 17))
        words.append(sp(Luminary099Erasable.delttfap, -11_000, scale: 17))
        words.append(sp(Luminary099Erasable.leadtime, -220, scale: 17))
        return words
    }

    private static func dp(_ ecadr: Int, _ value: Double, scale: Int) -> [AGCErasableWord] {
        let encoded = AGCDoublePrecision.encode(value: value, scale: scale)
        return [
            AGCErasableWord(ecadr: ecadr, value: encoded.high),
            AGCErasableWord(ecadr: ecadr + 1, value: encoded.low)
        ]
    }

    private static func sp(_ ecadr: Int, _ value: Double, scale: Int) -> AGCErasableWord {
        AGCErasableWord(
            ecadr: ecadr,
            value: AGCSinglePrecision.encode(value: value, scale: scale).word
        )
    }

    private static func vector(_ ecadr: Int, _ components: [Double], scale: Int) -> [AGCErasableWord] {
        var words: [AGCErasableWord] = []
        for (index, component) in components.enumerated() {
            words.append(contentsOf: dp(ecadr + index * 2, component, scale: scale))
        }
        return words
    }
}

/// Held powered-descent panel discretes. Channels 30–33 are inverted:
/// 0 means the named signal is present.
public enum LMPoweredDescentPanel {
    /// CH30: engine armed, auto throttle, IMU operate, LGC in control; temp OK already at boot.
    public static let channel30 = 0o37777 & ~0o1424
    /// CH31: MODE CONTROL AUTO (bit 14 = 0); ATT HOLD off; no RHC/THC.
    public static let channel31 = 0o57777
    /// CH33: landing-radar antenna in position 1 (bit 6 = 0). P63 waits on this.
    public static let channel33 = 0o77737

    public static var channelInputs: [AGCChannelInput] {
        [
            AGCChannelInput(channel: 0o30, value: channel30),
            AGCChannelInput(channel: 0o31, value: channel31),
            AGCChannelInput(channel: 0o33, value: channel33)
        ]
    }
}

/// Crew responses that P63 still needs after IGNALG: skip R51 fine-align,
/// enable the R60 burn-attitude maneuver, then enable the engine at V99.
///
/// From `THE_LUNAR_LANDING.agc`: R51P63 PROCEED fine-aligns, ENTER returns
/// to P63SPOT2. R60 flashes V50N18. `BURNBABY` pastes V99 at TIG-5.
/// T4RUPT samples inverted CH32 bit 14 every 120 ms, so PRO is held longer
/// than one sample. ENTER is a one-shot CH15 keycode.
public struct LMP63CrewHandshake: Equatable, Sendable {
    public static let proHoldSeconds = 0.15

    public enum Action: Equatable, Sendable {
        case enter
        case pro(pressed: Bool)
    }

    private enum Prompt: String, Equatable, Hashable, Sendable {
        case fineAlignSkip
        case autoManeuver
        case engineEnable
    }

    private var activePRO: Prompt?
    private var holdRemaining = 0.0
    private var completed: Set<Prompt> = []

    public init() {}

    public mutating func advance(verb: String, noun: String, deltaTime: Double) -> Action? {
        if let prompt = activePRO {
            holdRemaining -= deltaTime
            guard holdRemaining <= 0 else { return nil }
            activePRO = nil
            completed.insert(prompt)
            return .pro(pressed: false)
        }

        guard verb != "  " else { return nil }

        guard let prompt = Self.prompt(verb: verb, noun: noun) else {
            completed.removeAll()
            return nil
        }
        guard !completed.contains(prompt) else { return nil }

        switch prompt {
        case .fineAlignSkip:
            completed.insert(prompt)
            return .enter
        case .autoManeuver, .engineEnable:
            activePRO = prompt
            holdRemaining = Self.proHoldSeconds
            return .pro(pressed: true)
        }
    }

    private static func prompt(verb: String, noun: String) -> Prompt? {
        switch (verb, noun) {
        case ("50", "25"):
            return .fineAlignSkip
        case ("50", "18"):
            return .autoManeuver
        case ("99", _):
            return .engineEnable
        default:
            return nil
        }
    }
}
