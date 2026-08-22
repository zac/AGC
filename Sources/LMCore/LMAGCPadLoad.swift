import AGC
import Foundation

/// Apollo 11 Luminary 099 landing-guidance pad loads from NASA SNA-8-D-027(II)
/// Table LM5/4.5.1-1 (prelaunch erasable load).
///
/// Aimpoints are in descent-guidance coordinates. TLAND is 100:50:49.20 GET.
/// The AGC clock is left at Luminary GET. TLAND is set to
/// `GET + GUIDDURN + ZOOMTIME` plus the MIDTOAV TIG lead (`SEC45 + D29.9SEC
/// + TIMEDELT`) so IGNALG’s TIG clears P41SPOT after IGNALG. BURNBABY
/// `LONGCALL`s TIG-35; TIG ≤ GET+35 s alarms 01204. MIDTOAV1 needs
/// `TIG − D29.9SEC > GET + TIMEDELT` or it alarms 01703.
/// Do not write TIME2/TIME1 after idle boot (that alarms 01107).
public enum Luminary99LandingPadLoad {
    /// NASA mission-tape TLAND, centiseconds GET, B28.
    public static let tlandCentiseconds = 36_304_920.0
    /// Luminary `GUIDDURN 2DEC +66440` (664.40 s) in THE_LUNAR_LANDING.agc.
    public static let guidDurnCentiseconds = 66_440.0
    /// NASA ZOOMTIME, 26 s of DPS throttle-up, B14 centiseconds.
    public static let zoomTimeCentiseconds = 2_600.0
    /// Apollo 11 LM timeline: key V57 five minutes after ignition to permit
    /// incorporation of validated landing-radar state-vector updates.
    public static let landingRadarUpdateDelayAfterIgnitionSeconds = 300.0
    /// BURNBABY `TIG-5` / CLOCPLAY V99, centiseconds.
    public static let tigMinusFiveCentiseconds = 500.0
    /// P41SPOT `D29.9SEC 2DEC 2990`. `TDEC1 = TIG − 29.9 s` for MIDTOAV1.
    public static let d29p9SecCentiseconds = 2_990.0
    /// `INTEGRATION_INITIALIZATION` `TIMEDELT 2DEC 2000`. MIDTOAV1 01703 if
    /// `TDEC1 ≤ GET + 20 s` (“ignition time slipped”).
    public static let timeDeltCentiseconds = 2_000.0
    /// P40/BURNBABY `SEC45 DEC 4500`. GET used by V37/IGNALG/R60 before P41SPOT
    /// (P40 crew note: 01703 if TIG is less than 45 s away).
    public static let sec45Centiseconds = 4_500.0
    /// TIG after GET: `D29.9SEC + TIMEDELT` so MIDTOAV1 sees `TDEC1 > GET+20 s`
    /// after IGNALG, plus `SEC45` for GET used before P41SPOT.
    public static var preIgnitionCentiseconds: Double {
        sec45Centiseconds + d29p9SecCentiseconds + timeDeltCentiseconds
    }
    /// First IGNALG `TDEC1` look-ahead: ZOOMTIME + MIDTOAV TIG lead.
    public static var ignalgLookaheadCentiseconds: Double {
        zoomTimeCentiseconds + preIgnitionCentiseconds
    }
    /// NASA RIGNX, meters B24. Guidance-frame X of (R−LAND) at ignition (site-vertical channel).
    public static let rignXMeters = -39_782.453328
    /// NASA RIGNZ, meters B24. Guidance-frame Z of (R−LAND) at ignition (downrange channel).
    public static let rignZMeters = -436_655.657
    /// NASA VIGN, meters/centisecond B10.
    public static let vignMetersPerCentisecond = 16.90256208
    /// NASA TN D-6846 PDI altitude rate, meters/centisecond.
    public static let pdiAltitudeRateMetersPerCentisecond = -4.0 * 0.3048 / 100.0

    public static var pdiGroundRangeMeters: Double {
        hypot(rignXMeters, rignZMeters)
    }

    public static var pdiClockCentiseconds: Double {
        tlandCentiseconds - guidDurnCentiseconds - zoomTimeCentiseconds
    }

    /// TLAND so IGNALG’s TIG clears MIDTOAV1 after IGNALG/R60 (BURNBABY TIG-35 LONGCALL).
    /// Writing TIME2/TIME1 after idle boot trips alarm 01107 (phase-table / fresh start).
    public static func tlandCentiseconds(fromClock clockCentiseconds: Double) -> Double {
        clockCentiseconds + guidDurnCentiseconds + ignalgLookaheadCentiseconds
    }

    public static func clockWords() -> [AGCErasableWord] {
        dp(Luminary099Erasable.time2, pdiClockCentiseconds, scale: 28)
    }

    public static func tlandWords(fromClock clockCentiseconds: Double) -> [AGCErasableWord] {
        dp(Luminary099Erasable.tland, tlandCentiseconds(fromClock: clockCentiseconds), scale: 28)
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
        words.append(contentsOf: dp(Luminary099Erasable.vign, vignMetersPerCentisecond, scale: 10))
        words.append(contentsOf: dp(Luminary099Erasable.rignx, rignXMeters, scale: 24))
        words.append(contentsOf: dp(Luminary099Erasable.rignz, rignZMeters, scale: 24))
        words.append(contentsOf: dp(Luminary099Erasable.kignx, -0.617631, scale: 4))
        words.append(contentsOf: dp(Luminary099Erasable.kigny, -2.4770341207e-6, scale: -16))
        words.append(contentsOf: dp(Luminary099Erasable.kignv, -41_000, scale: 18))
        words.append(sp(Luminary099Erasable.lowcrit, 2_124.4, scale: 14))
        words.append(sp(Luminary099Erasable.highcrit, 2_348.0, scale: 14))
        words.append(contentsOf: vector(Luminary099Erasable.v2fg, [-0.009144, 0, 0], scale: 10))
        words.append(contentsOf: dp(Luminary099Erasable.tauvert, 1_000, scale: 14))
        // NASA LM5/4.5.1-1 octal. SETPOS uses the position-specific antenna
        // Euler angles to transform the fixed LR beam vectors into NB.
        words.append(contentsOf: [
            AGCErasableWord(ecadr: Luminary099Erasable.delqfix, value: 0o00000),
            AGCErasableWord(ecadr: Luminary099Erasable.delqfix + 1, value: 0o01717),
            AGCErasableWord(ecadr: Luminary099Erasable.lralpha, value: 0o01042),
            AGCErasableWord(ecadr: Luminary099Erasable.lrbeta1, value: 0o04211),
            AGCErasableWord(ecadr: Luminary099Erasable.lralpha2, value: 0o01042),
            AGCErasableWord(ecadr: Luminary099Erasable.lrbeta2, value: 0o00000),
            AGCErasableWord(ecadr: Luminary099Erasable.lrvmax, value: 0o01414),
            AGCErasableWord(ecadr: Luminary099Erasable.lrvf, value: 0o00116),
            AGCErasableWord(ecadr: Luminary099Erasable.lrwvz, value: 0o11463),
            AGCErasableWord(ecadr: Luminary099Erasable.lrwvy, value: 0o11463),
            AGCErasableWord(ecadr: Luminary099Erasable.lrwvx, value: 0o11463),
            AGCErasableWord(ecadr: Luminary099Erasable.lrwvfz, value: 0o06315),
            AGCErasableWord(ecadr: Luminary099Erasable.lrwvfy, value: 0o06315),
            AGCErasableWord(ecadr: Luminary099Erasable.lrwvfx, value: 0o06315),
            AGCErasableWord(ecadr: Luminary099Erasable.lrwvff, value: 0o03146),
            // Apollo 11 Luminary 99 P66 flight pad-load block.
            AGCErasableWord(ecadr: Luminary099Erasable.rodScale, value: 0o14370),
            AGCErasableWord(ecadr: Luminary099Erasable.tauRod, value: 0o11300),
            AGCErasableWord(ecadr: Luminary099Erasable.tauRod + 1, value: 0o00000),
            AGCErasableWord(ecadr: Luminary099Erasable.lagOverTau, value: 0o15164),
            AGCErasableWord(ecadr: Luminary099Erasable.lagOverTau + 1, value: 0o01420),
            AGCErasableWord(ecadr: Luminary099Erasable.minForce, value: 0o00001),
            AGCErasableWord(ecadr: Luminary099Erasable.minForce + 1, value: 0o27631),
            AGCErasableWord(ecadr: Luminary099Erasable.maxForce, value: 0o00013),
            AGCErasableWord(ecadr: Luminary099Erasable.maxForce + 1, value: 0o06551),
            AGCErasableWord(ecadr: Luminary099Erasable.lrhmax, value: 0o35610),
            AGCErasableWord(ecadr: Luminary099Erasable.lrwh, value: 0o13146)
        ])
        words.append(sp(Luminary099Erasable.zoomtime, zoomTimeCentiseconds, scale: 14))
        words.append(sp(Luminary099Erasable.tendbrak, 6_200, scale: 17))
        words.append(sp(Luminary099Erasable.tendappr, 1_200, scale: 17))
        words.append(sp(Luminary099Erasable.delttfap, -11_000, scale: 17))
        words.append(sp(Luminary099Erasable.leadtime, -220, scale: 17))
        words.append(AGCErasableWord(ecadr: Luminary099Erasable.rpcrtime, value: 0o01407))
        words.append(AGCErasableWord(ecadr: Luminary099Erasable.rpcrtqsw, value: 0o77777))
        words.append(contentsOf: Luminary99CoordinatePadLoad.erasableWords())
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

/// Launch-tape lunar orientation and landing-site vector from the same NASA
/// table as the landing-guidance overlay. IGNALG’s `RP-TO-R` needs TEPHEM,
/// AZO/−AYO/AXO, 504LM, and RLS. NASA octal is stored as truth.
public enum Luminary99CoordinatePadLoad {
    public static let landingSiteMeters = LMVector3D(
        x: 1_588_471.994,
        y: 697_547.4954,
        z: 21_616.9998
    )
    /// NASA TEPHEM `00000 20017 20500`, centiseconds from 1 July 1968 to GET 0, B42.
    public static let tephemCentiseconds = 134_472_000.0
    /// NASA 504LM, moon-fixed libration radians B0.
    public static let librationRadians = LMVector3D(
        x: AGCDoublePrecision(high: 0o77775, low: 0o46355).decoded(scale: 0),
        y: AGCDoublePrecision(high: 0o77766, low: 0o72372).decoded(scale: 0),
        z: AGCDoublePrecision(high: 0o77777, low: 0o52552).decoded(scale: 0)
    )

    public static func erasableWords() -> [AGCErasableWord] {
        [
            AGCErasableWord(ecadr: Luminary099Erasable.tephem, value: 0o00000),
            AGCErasableWord(ecadr: Luminary099Erasable.tephem + 1, value: 0o20017),
            AGCErasableWord(ecadr: Luminary099Erasable.tephem + 2, value: 0o20500),
            AGCErasableWord(ecadr: Luminary099Erasable.azo, value: 0o30624),
            AGCErasableWord(ecadr: Luminary099Erasable.azo + 1, value: 0o01636),
            AGCErasableWord(ecadr: Luminary099Erasable.negAyo, value: 0o77777),
            AGCErasableWord(ecadr: Luminary099Erasable.negAyo + 1, value: 0o53172),
            AGCErasableWord(ecadr: Luminary099Erasable.axo, value: 0o00000),
            AGCErasableWord(ecadr: Luminary099Erasable.axo + 1, value: 0o26056),
            AGCErasableWord(ecadr: Luminary099Erasable.lm504, value: 0o77775),
            AGCErasableWord(ecadr: Luminary099Erasable.lm504 + 1, value: 0o46355),
            AGCErasableWord(ecadr: Luminary099Erasable.lm504 + 2, value: 0o77766),
            AGCErasableWord(ecadr: Luminary099Erasable.lm504 + 3, value: 0o72372),
            AGCErasableWord(ecadr: Luminary099Erasable.lm504 + 4, value: 0o77777),
            AGCErasableWord(ecadr: Luminary099Erasable.lm504 + 5, value: 0o52552),
            AGCErasableWord(ecadr: Luminary099Erasable.rls, value: 0o00301),
            AGCErasableWord(ecadr: Luminary099Erasable.rls + 1, value: 0o34760),
            AGCErasableWord(ecadr: Luminary099Erasable.rls + 2, value: 0o00125),
            AGCErasableWord(ecadr: Luminary099Erasable.rls + 3, value: 0o04627),
            AGCErasableWord(ecadr: Luminary099Erasable.rls + 4, value: 0o00002),
            AGCErasableWord(ecadr: Luminary099Erasable.rls + 5, value: 0o24342)
        ]
    }
}

/// Held powered-descent panel discretes. Channels 30–33 are inverted:
/// 0 means the named signal is present.
public enum LMPoweredDescentPanel {
    /// Before the PDI state is loaded, tell Luminary the already-powered IMU
    /// is in OPERATE without also moving the landing-panel switches. Fresh
    /// start otherwise sees OPERATE arrive after P63 and schedules a delayed
    /// ICDU zero in the middle of braking.
    public static let channel30IMUOperating = 0o37777 & ~0o400
    /// CH30: engine armed, auto throttle, IMU operate, LGC in control; temp OK already at boot.
    public static let channel30 = 0o37777 & ~0o1424
    /// CH31: MODE CONTROL AUTO (bit 14 = 0); ATT HOLD off; no RHC/THC.
    public static let channel31 = 0o57777
    /// Inverted CH31 bit 13: 0 = MODE CONTROL ATT HOLD, which selects P66.
    public static let channel31AttitudeHold = 0o10000
    /// Inverted CH31 bit 15: 0 = rotational hand controller out of detent.
    public static let channel31RHCOutOfDetent = 0o40000
    /// CH33: landing-radar antenna in position 1 (bit 6 = 0) and low scale
    /// (bit 9 = 0). Data-good bits 5/8 stay 1 until `applyLandingRadarChannel33`
    /// sees a measurement. P63 waits on POS1. R12 SCALECHK treats bit 9 as ALTSCBIT.
    public static let channel33 = 0o77337
    /// Inverted CH33 bit 5: 0 = LR altitude data good.
    public static let channel33LRAltitudeDataGood = 0o20
    /// Inverted CH33 bit 8: 0 = LR velocity data good.
    public static let channel33LRVelocityDataGood = 0o200
    /// Inverted CH33 bit 6: 0 = LR antenna in position 1.
    public static let channel33LRPosition1 = 0o40
    /// Inverted CH33 bit 7: 0 = LR antenna in position 2.
    public static let channel33LRPosition2 = 0o100
    /// CH33 bit 9: 1 = LR altitude high scale (`ALTSCBIT`).
    public static let channel33LRAltitudeHighScale = 0o400
    /// CH12 bit 13: command LR antenna to position 2.
    public static let channel12LRPosition2Command = 0o10000

    public static var channelInputs: [AGCChannelInput] {
        [
            AGCChannelInput(channel: 0o30, value: channel30),
            AGCChannelInput(channel: 0o31, value: channel31),
            AGCChannelInput(channel: 0o33, value: channel33)
        ]
    }
}

/// Crew responses that P63 still needs after IGNALG: agree the event timer
/// (V06N61), skip R51 fine-align, skip the R60 burn-attitude slew, then
/// enable the engine at V99.
///
/// From `THE_LUNAR_LANDING.agc` / `BURNBABY`: ASTNCLOK flashes V06N61;
/// PROCEED goes to `ASTNRET` → `R51P63`. R51P63 PROCEED fine-aligns, ENTER
/// returns to P63SPOT2. R60 `GOPERF2R` flashes V50N18; ENTER is
/// `ENDMANU1` (“finished with R60”) so KALCMANU is not waited on. `BURNBABY`
/// pastes V99 at TIG-5. T4RUPT samples inverted CH32 bit 14 every 120 ms, so
/// PRO is held longer than one sample. ENTER is a one-shot CH15 keycode.
public struct LMP63CrewHandshake: Equatable, Sendable {
    public static let proHoldSeconds = 0.15

    public enum Action: Equatable, Sendable {
        case enter
        case pro(pressed: Bool)
    }

    private enum Prompt: String, Equatable, Hashable, Sendable {
        case eventTimerAgree
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
        case .fineAlignSkip, .autoManeuver:
            completed.insert(prompt)
            return .enter
        case .eventTimerAgree, .engineEnable:
            activePRO = prompt
            holdRemaining = Self.proHoldSeconds
            return .pro(pressed: true)
        }
    }

    private static func prompt(verb: String, noun: String) -> Prompt? {
        switch (verb, noun) {
        case ("06", "61"):
            return .eventTimerAgree
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
