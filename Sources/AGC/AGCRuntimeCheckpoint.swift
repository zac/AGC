import Foundation

public enum AGCCheckpointError: Error, Equatable, Sendable {
    case schemaVersionMismatch(expected: Int, found: Int)
    case coreImageMismatch(expected: String, found: String)
    case corruptState(String)
}

public struct DSKYCheckpointDisplayRegister: Equatable, Sendable, Codable {
    public var signBits: Int
    public var digits: [Int]

    public init(signBits: Int, digits: [Int]) {
        self.signBits = signBits
        self.digits = digits
    }
}

public struct DSKYCheckpointIndicatorState: Equatable, Sendable, Codable {
    public var isOn: Bool

    public init(isOn: Bool) {
        self.isOn = isOn
    }
}

/// Mutable DSKY state: display registers, indicators, held channel values,
/// and any keypresses still queued for delivery to channel 015/032.
public struct DSKYCheckpoint: Equatable, Sendable, Codable {
    public var r1: DSKYCheckpointDisplayRegister
    public var r2: DSKYCheckpointDisplayRegister
    public var r3: DSKYCheckpointDisplayRegister
    public var verbDigits: [Int]
    public var nounDigits: [Int]
    public var modeDigits: [Int]
    public var indicators: [Int: DSKYCheckpointIndicatorState]
    public var channel163: Int
    public var channel11: Int
    public var channel13: Int
    public var channel32: Int
    public var channel10Rows: [Int]
    public var channel10IndicatorValue: Int
    public var verbNounFlash: Bool
    public var pendingKeypresses: [AGCChannelInput]

    public init(
        r1: DSKYCheckpointDisplayRegister,
        r2: DSKYCheckpointDisplayRegister,
        r3: DSKYCheckpointDisplayRegister,
        verbDigits: [Int],
        nounDigits: [Int],
        modeDigits: [Int],
        indicators: [Int: DSKYCheckpointIndicatorState],
        channel163: Int,
        channel11: Int,
        channel13: Int,
        channel32: Int,
        channel10Rows: [Int],
        channel10IndicatorValue: Int,
        verbNounFlash: Bool,
        pendingKeypresses: [AGCChannelInput]
    ) {
        self.r1 = r1
        self.r2 = r2
        self.r3 = r3
        self.verbDigits = verbDigits
        self.nounDigits = nounDigits
        self.modeDigits = modeDigits
        self.indicators = indicators
        self.channel163 = channel163
        self.channel11 = channel11
        self.channel13 = channel13
        self.channel32 = channel32
        self.channel10Rows = channel10Rows
        self.channel10IndicatorValue = channel10IndicatorValue
        self.verbNounFlash = verbNounFlash
        self.pendingKeypresses = pendingKeypresses
    }
}

/// Versioned capture of every mutable `AGCRuntime` component: erasable memory,
/// I/O channels, CPU sequencing registers, interrupt and scaler state, DSKY,
/// pending external channel inputs, and the held radar input.
///
/// Fixed memory is deliberately absent. Restoring reloads it from the Luminary
/// core image named by ``coreImageSHA256`` so a checkpoint can never drift from
/// its core ropes.
public struct AGCRuntimeCheckpoint: Equatable, Sendable, Codable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    /// Lowercase SHA-256 of the Luminary core image the state was captured from.
    public var coreImageSHA256: String
    public var cycleCounter: UInt64

    // 8 erasable banks × 1024 words, including the mirrored A/L/Q/Z/EB/FB/BB
    // register cells in bank 0.
    public var erasableMemory: [[Int]]

    public var inputChannels: [Int]
    public var outputChannels: [Int]
    public var outputChannel7: Int
    public var outputChannel10: [Int]

    // CPU sequencing.
    public var extraCode: Bool
    public var allowInterrupt: Bool
    public var pendFlag: Bool
    public var pendDelay: Int
    public var extraDelay: Int
    public var indexValue: Int
    public var inIsr: Bool
    public var substituteInstruction: Bool
    public var interruptRequests: [Int]

    // Downlink scheduling.
    public var downruptTimeValid: Bool
    public var downruptTime: UInt64
    public var downlink: Int

    // Night watchman, traps, and warnings.
    public var nightWatchman: Int
    public var nightWatchmanTripped: Bool
    public var ruptLock: Bool
    public var noRupt: Bool
    public var tcTrap: Bool
    public var noTC: Bool
    public var parityFail: Bool
    public var checkParity: Bool
    public var warningFilter: Int
    public var generatedWarning: Bool

    // Display, standby, and misc engine latches.
    public var restartLight: Bool
    public var standby: Bool
    public var sbyPressed: Bool
    public var sbyStillPressed: Bool
    public var nextZ: Int
    public var scalerCounter: Int
    public var channelRoutineCount: Int
    public var dskyTimer: Int
    public var dskyFlash: Int
    public var dskyChannel163: Int
    public var tookBZF: Bool
    public var tookBZMF: Bool
    public var trap31A: Bool
    public var trap31B: Bool
    public var trap32: Bool
    public var radarGateCounter: Int

    public var dsky: DSKYCheckpoint
    public var pendingChannelInputs: [AGCChannelInput]
    public var radarInput: AGCRadarInput?

    public init(
        schemaVersion: Int = AGCRuntimeCheckpoint.schemaVersion,
        coreImageSHA256: String,
        cycleCounter: UInt64,
        erasableMemory: [[Int]],
        inputChannels: [Int],
        outputChannels: [Int],
        outputChannel7: Int,
        outputChannel10: [Int],
        extraCode: Bool,
        allowInterrupt: Bool,
        pendFlag: Bool,
        pendDelay: Int,
        extraDelay: Int,
        indexValue: Int,
        inIsr: Bool,
        substituteInstruction: Bool,
        interruptRequests: [Int],
        downruptTimeValid: Bool,
        downruptTime: UInt64,
        downlink: Int,
        nightWatchman: Int,
        nightWatchmanTripped: Bool,
        ruptLock: Bool,
        noRupt: Bool,
        tcTrap: Bool,
        noTC: Bool,
        parityFail: Bool,
        checkParity: Bool,
        warningFilter: Int,
        generatedWarning: Bool,
        restartLight: Bool,
        standby: Bool,
        sbyPressed: Bool,
        sbyStillPressed: Bool,
        nextZ: Int,
        scalerCounter: Int,
        channelRoutineCount: Int,
        dskyTimer: Int,
        dskyFlash: Int,
        dskyChannel163: Int,
        tookBZF: Bool,
        tookBZMF: Bool,
        trap31A: Bool,
        trap31B: Bool,
        trap32: Bool,
        radarGateCounter: Int,
        dsky: DSKYCheckpoint,
        pendingChannelInputs: [AGCChannelInput],
        radarInput: AGCRadarInput?
    ) {
        self.schemaVersion = schemaVersion
        self.coreImageSHA256 = coreImageSHA256
        self.cycleCounter = cycleCounter
        self.erasableMemory = erasableMemory
        self.inputChannels = inputChannels
        self.outputChannels = outputChannels
        self.outputChannel7 = outputChannel7
        self.outputChannel10 = outputChannel10
        self.extraCode = extraCode
        self.allowInterrupt = allowInterrupt
        self.pendFlag = pendFlag
        self.pendDelay = pendDelay
        self.extraDelay = extraDelay
        self.indexValue = indexValue
        self.inIsr = inIsr
        self.substituteInstruction = substituteInstruction
        self.interruptRequests = interruptRequests
        self.downruptTimeValid = downruptTimeValid
        self.downruptTime = downruptTime
        self.downlink = downlink
        self.nightWatchman = nightWatchman
        self.nightWatchmanTripped = nightWatchmanTripped
        self.ruptLock = ruptLock
        self.noRupt = noRupt
        self.tcTrap = tcTrap
        self.noTC = noTC
        self.parityFail = parityFail
        self.checkParity = checkParity
        self.warningFilter = warningFilter
        self.generatedWarning = generatedWarning
        self.restartLight = restartLight
        self.standby = standby
        self.sbyPressed = sbyPressed
        self.sbyStillPressed = sbyStillPressed
        self.nextZ = nextZ
        self.scalerCounter = scalerCounter
        self.channelRoutineCount = channelRoutineCount
        self.dskyTimer = dskyTimer
        self.dskyFlash = dskyFlash
        self.dskyChannel163 = dskyChannel163
        self.tookBZF = tookBZF
        self.tookBZMF = tookBZMF
        self.trap31A = trap31A
        self.trap31B = trap31B
        self.trap32 = trap32
        self.radarGateCounter = radarGateCounter
        self.dsky = dsky
        self.pendingChannelInputs = pendingChannelInputs
        self.radarInput = radarInput
    }

    public static func coreImageSHA256(of data: Data) -> String {
        AGCSHA256.hexDigest(data)
    }

    /// Full validation before restore. Callers must run this before applying any
    /// field so an incompatible fixture is refused without partial state.
    public func validate(coreImage: Data) throws {
        guard schemaVersion == Self.schemaVersion else {
            throw AGCCheckpointError.schemaVersionMismatch(
                expected: Self.schemaVersion,
                found: schemaVersion
            )
        }
        let digest = Self.coreImageSHA256(of: coreImage)
        guard coreImageSHA256 == digest else {
            throw AGCCheckpointError.coreImageMismatch(expected: digest, found: coreImageSHA256)
        }
        guard erasableMemory.count == 8, erasableMemory.allSatisfy({ $0.count == 0x400 }) else {
            throw AGCCheckpointError.corruptState(
                "erasable memory must be 8 banks of 1024 words"
            )
        }
        guard inputChannels.count == 512, outputChannels.count == 512 else {
            throw AGCCheckpointError.corruptState("I/O channels must hold 512 entries")
        }
        guard outputChannel10.count == 16 else {
            throw AGCCheckpointError.corruptState("channel 10 must hold 16 rows")
        }
        guard interruptRequests.count == 11 else {
            throw AGCCheckpointError.corruptState("interrupt requests must hold 11 entries")
        }
    }

    /// Binary property-list fixture bytes suitable for bundling as an app asset.
    public func encodedFixture() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    public static func decodeFixture(_ data: Data) throws -> AGCRuntimeCheckpoint {
        try PropertyListDecoder().decode(AGCRuntimeCheckpoint.self, from: data)
    }
}
