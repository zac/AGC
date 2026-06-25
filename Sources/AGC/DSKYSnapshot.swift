import Foundation

/// DSKY key codes matching yaDSKY/Luminary channel-15 keyboard input values.
public enum DSKYKeyCode: Int, CaseIterable, Sendable {
    case digit1 = 0o1
    case digit2 = 0o2
    case digit3 = 0o3
    case digit4 = 0o4
    case digit5 = 0o5
    case digit6 = 0o6
    case digit7 = 0o7
    case digit8 = 0o10
    case digit9 = 0o11
    case digit0 = 0o20
    case verb = 0o21
    case reset = 0o22
    case keyRelease = 0o31
    case plus = 0o32
    case minus = 0o33
    case enter = 0o34
    case clear = 0o36
    case noun = 0o37

    /// PRO is delivered through the channel-13 u-bit mask path, not channel 15.
    case pro = -1

    public var label: String {
        switch self {
        case .digit0: return "0"
        case .digit1: return "1"
        case .digit2: return "2"
        case .digit3: return "3"
        case .digit4: return "4"
        case .digit5: return "5"
        case .digit6: return "6"
        case .digit7: return "7"
        case .digit8: return "8"
        case .digit9: return "9"
        case .verb: return "VERB"
        case .noun: return "NOUN"
        case .pro: return "PRO"
        case .keyRelease: return "KEY REL"
        case .plus: return "+"
        case .minus: return "-"
        case .enter: return "ENTR"
        case .clear: return "CLR"
        case .reset: return "RSET"
        }
    }
}

/// A package-level DSKY script that can be used by tests, MissionControl, and future simulators.
public struct DSKYScript: Equatable, Sendable, Identifiable {
    public let id: String
    public let keys: [DSKYKeyCode]

    public init(id: String, keys: [DSKYKeyCode]) {
        self.id = id
        self.keys = keys
    }

    public static let reset = DSKYScript(id: "RSET", keys: [.reset])

    public static let v35e = DSKYScript(
        id: "V35E lamp",
        keys: [.verb, .digit3, .digit5, .enter]
    )

    public static let v16n36e = DSKYScript(
        id: "V16N36E",
        keys: [.verb, .digit1, .digit6, .noun, .digit3, .digit6, .enter]
    )
}

/// Immutable DSKY display and annunciator state decoded from AGC output channels.
public struct DSKYSnapshot: Equatable, Sendable {
    public static let indicatorIDs: [Int] = [11, 12, 13, 14, 15, 16, 17, 21, 22, 23, 24, 25, 26, 27]

    public let channel10Rows: [Int]
    public let channel11: Int
    public let channel13: Int
    public let channel163: Int
    public let r1: String
    public let r2: String
    public let r3: String
    public let verb: String
    public let noun: String
    public let mode: String
    public let verbNounFlash: Bool
    public let lampTest: Bool
    public let compActy: Bool
    public let proKeyPressed: Bool
    public let indicators: [Int: Bool]

    public init(
        channel10Rows: [Int] = Array(repeating: 0, count: 16),
        channel11: Int = 0,
        channel13: Int = 0,
        channel163: Int = 0,
        r1: String = "      ",
        r2: String = "      ",
        r3: String = "      ",
        verb: String = "  ",
        noun: String = "  ",
        mode: String = "  ",
        verbNounFlash: Bool = false,
        lampTest: Bool = false,
        compActy: Bool = false,
        proKeyPressed: Bool = false,
        indicators: [Int: Bool] = [:]
    ) {
        self.channel10Rows = channel10Rows
        self.channel11 = channel11 & 0o77777
        self.channel13 = channel13 & 0o77777
        self.channel163 = channel163 & 0o77777
        self.r1 = r1
        self.r2 = r2
        self.r3 = r3
        self.verb = verb
        self.noun = noun
        self.mode = mode
        self.verbNounFlash = verbNounFlash
        self.lampTest = lampTest
        self.compActy = compActy
        self.proKeyPressed = proKeyPressed
        self.indicators = indicators
    }

    public func indicatorIsOn(_ id: Int) -> Bool {
        indicators[id] ?? false
    }
}
