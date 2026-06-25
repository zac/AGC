import Foundation

public enum LMVehicleOutputChannel: Int, Sendable {
    case out0 = 0o5
    case out1 = 0o6
}

public enum LMRCSAxis: String, Sendable {
    case positiveU = "+U"
    case negativeU = "-U"
    case positiveV = "+V"
    case negativeV = "-V"
    case positivePitch = "+P"
    case negativePitch = "-P"
}

public enum LMRCSJet: Int, CaseIterable, Sendable {
    case jet1 = 1
    case jet2 = 2
    case jet3 = 3
    case jet4 = 4
    case jet5 = 5
    case jet6 = 6
    case jet7 = 7
    case jet8 = 8
    case jet9 = 9
    case jet10 = 10
    case jet11 = 11
    case jet12 = 12
    case jet13 = 13
    case jet14 = 14
    case jet15 = 15
    case jet16 = 16
}

public struct LMRCSJetCommand: Equatable, Sendable {
    public let jet: LMRCSJet
    public let axis: LMRCSAxis
    public let channel: Int
    public let bit: Int
    public let source: String

    public init(jet: LMRCSJet, axis: LMRCSAxis, channel: Int, bit: Int, source: String) {
        self.jet = jet
        self.axis = axis
        self.channel = channel
        self.bit = bit
        self.source = source
    }
}

public struct LMSourceBackedDiscreteGroup: Equatable, Sendable {
    public let name: String
    public let channel: Int
    public let mask: Int
    public let source: String

    public init(name: String, channel: Int, mask: Int, source: String) {
        self.name = name
        self.channel = channel
        self.mask = mask
        self.source = source
    }
}

public struct LMUnmappedDiscrete: Equatable, Sendable {
    public let channel: Int
    public let bit: Int
    public let mask: Int

    public init(channel: Int, bit: Int, mask: Int) {
        self.channel = channel
        self.bit = bit
        self.mask = mask
    }
}

/// Last-known LM OUT0 / OUT1 channel words (octal channels 5 and 6) plus source-backed decoding.
public struct LMVehicleSnapshot: Equatable, Sendable {
    public let out0: Int
    public let out1: Int
    public let rcsJets: [LMRCSJetCommand]
    public let discreteGroups: [LMSourceBackedDiscreteGroup]
    public let unmappedBits: [LMUnmappedDiscrete]

    public init(out0: Int = 0, out1: Int = 0) {
        self.out0 = out0 & 0o77777
        self.out1 = out1 & 0o77777
        self.rcsJets = LMVehicleSnapshot.decodeRCSJets(out0: self.out0)
        self.discreteGroups = LMVehicleSnapshot.decodeDiscreteGroups(out1: self.out1)
        self.unmappedBits = LMVehicleSnapshot.decodeUnmappedBits(out0: self.out0, out1: self.out1)
    }

    private static let ch5Source = "Apollo-11/Luminary099/Q_R-AXIS_RCS_AUTOPILOT.agc ALLJETS table: -U 6 13, -V 2 9, +U 5 14, +V 1 10"
    private static let ch6Source = "Apollo-11/Luminary099/P-AXIS_RCS_AUTOPILOT.agc JETSALL table: +P mask 00125, -P mask 00252"

    private struct RCSBitMapping {
        let bit: Int
        let jet: LMRCSJet
        let axis: LMRCSAxis
    }

    // Channel 5 is PYJETS ("PITCH RCS JET CONTROL") in Apollo-11
    // Luminary099/INPUT_OUTPUT_CHANNEL_BIT_DESCRIPTIONS.agc:
    // https://github.com/chrislgarry/Apollo-11/blob/master/Luminary099/INPUT_OUTPUT_CHANNEL_BIT_DESCRIPTIONS.agc
    // Exact bit-to-jet names come from Luminary099/Q_R-AXIS_RCS_AUTOPILOT.agc's ALLJETS table:
    // https://github.com/chrislgarry/Apollo-11/blob/master/Luminary099/Q_R-AXIS_RCS_AUTOPILOT.agc
    // OCT 110 = -U jets 6/13, OCT 022 = -V jets 2/9, OCT 204 = +U jets 5/14,
    // OCT 041 = +V jets 1/10. Bits are 1-indexed from the least-significant bit.
    private static let channel5Mappings: [RCSBitMapping] = [
        RCSBitMapping(bit: 1, jet: .jet1, axis: .positiveV),
        RCSBitMapping(bit: 2, jet: .jet2, axis: .negativeV),
        RCSBitMapping(bit: 3, jet: .jet5, axis: .positiveU),
        RCSBitMapping(bit: 4, jet: .jet6, axis: .negativeU),
        RCSBitMapping(bit: 5, jet: .jet9, axis: .negativeV),
        RCSBitMapping(bit: 6, jet: .jet10, axis: .positiveV),
        RCSBitMapping(bit: 7, jet: .jet13, axis: .negativeU),
        RCSBitMapping(bit: 8, jet: .jet14, axis: .positiveU)
    ]

    private static func decodeRCSJets(out0: Int) -> [LMRCSJetCommand] {
        channel5Mappings.compactMap { mapping in
            let mask = 1 << (mapping.bit - 1)
            guard (out0 & mask) != 0 else { return nil }
            return LMRCSJetCommand(
                jet: mapping.jet,
                axis: mapping.axis,
                channel: LMVehicleOutputChannel.out0.rawValue,
                bit: mapping.bit,
                source: ch5Source
            )
        }
    }

    private static func decodeDiscreteGroups(out1: Int) -> [LMSourceBackedDiscreteGroup] {
        var groups: [LMSourceBackedDiscreteGroup] = []
        if (out1 & 0o125) != 0 {
            groups.append(LMSourceBackedDiscreteGroup(
                name: "positive pitch RCS command bits",
                channel: LMVehicleOutputChannel.out1.rawValue,
                mask: out1 & 0o125,
                source: ch6Source
            ))
        }
        if (out1 & 0o252) != 0 {
            groups.append(LMSourceBackedDiscreteGroup(
                name: "negative pitch RCS command bits",
                channel: LMVehicleOutputChannel.out1.rawValue,
                mask: out1 & 0o252,
                source: ch6Source
            ))
        }
        return groups
    }

    private static func decodeUnmappedBits(out0: Int, out1: Int) -> [LMUnmappedDiscrete] {
        var bits: [LMUnmappedDiscrete] = []
        let mappedOut0Mask = channel5Mappings.reduce(0) { partial, mapping in
            partial | (1 << (mapping.bit - 1))
        }
        bits.append(contentsOf: unmappedBits(channel: 0o5, value: out0, mappedMask: mappedOut0Mask))

        // Channel 6 group masks come from Apollo-11 Luminary099/P-AXIS_RCS_AUTOPILOT.agc:
        // https://github.com/chrislgarry/Apollo-11/blob/master/Luminary099/P-AXIS_RCS_AUTOPILOT.agc
        // Exact bit-to-jet names are intentionally left raw until verified from an authoritative source.
        bits.append(contentsOf: unmappedBits(channel: 0o6, value: out1, mappedMask: 0))
        return bits
    }

    private static func unmappedBits(channel: Int, value: Int, mappedMask: Int) -> [LMUnmappedDiscrete] {
        (1...15).compactMap { bit in
            let mask = 1 << (bit - 1)
            guard (value & mask) != 0, (mappedMask & mask) == 0 else { return nil }
            return LMUnmappedDiscrete(channel: channel, bit: bit, mask: mask)
        }
    }
}

/// Captures LM vehicle outputs from the AGC and exposes hooks for IMU/PIPA/RHC/radar integration.
///
/// On each ``AGCIOProtocol/requestRadarData()`` call (before the RADARUPT interrupt), integrators should
/// write radar samples into erasable ``Register/regRNRAD`` (octal 046), e.g.
/// `engine.state.erasableMemory[0][Register.regRNRAD.rawValue] = sample`, then let the flight
/// software ISR consume it—matching yaAGC’s ``RequestRadarData`` contract.
public final class LMVehicleIO: AGCIOProtocol {
    private let keyLock = NSLock()
    private var lastOut0 = 0
    private var lastOut1 = 0

    public weak var agcEngine: AGCEngine?

    /// Called when radar integration should load ``Register/regRNRAD`` (and any related state).
    public var onRequestRadarData: (() -> Void)?

    public init(agcEngine: AGCEngine? = nil, onRequestRadarData: (() -> Void)? = nil) {
        self.agcEngine = agcEngine
        self.onRequestRadarData = onRequestRadarData
    }

    public var snapshot: LMVehicleSnapshot {
        keyLock.lock()
        defer { keyLock.unlock() }
        return LMVehicleSnapshot(out0: lastOut0, out1: lastOut1)
    }

    public func channelOutput(channel: Int, value: Int) {
        let ch = channel & 0o777
        let v = value & 0o77777
        guard ch == 0o5 || ch == 0o6 else { return }
        keyLock.lock()
        if ch == 0o5 {
            lastOut0 = v
        } else {
            lastOut1 = v
        }
        keyLock.unlock()
    }

    public func channelInput() async -> [AGCChannelInput]? { nil }

    public func requestRadarData() {
        onRequestRadarData?()
    }

    public func shiftToDeda(data: Int) {}

    public func channelRoutine() async {}
}

public enum AGCChannelTraceDirection: String, Sendable {
    case input
    case output
}

public struct AGCChannelTraceEntry: Equatable, Sendable, Identifiable {
    public let id: UInt64
    public let direction: AGCChannelTraceDirection
    public let channel: Int
    public let value: Int

    public init(id: UInt64, direction: AGCChannelTraceDirection, channel: Int, value: Int) {
        self.id = id
        self.direction = direction
        self.channel = channel & 0o777
        self.value = value & 0o77777
    }
}

private final class AGCChannelTraceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let monitoredChannels: Set<Int>
    private let limit: Int
    private var nextID: UInt64 = 0
    private var entries: [AGCChannelTraceEntry] = []

    init(monitoredChannels: Set<Int>, limit: Int) {
        self.monitoredChannels = monitoredChannels
        self.limit = limit
    }

    func append(direction: AGCChannelTraceDirection, channel: Int, value: Int) {
        let normalizedChannel = channel & 0o777
        let baseChannel = normalizedChannel & 0o377
        guard monitoredChannels.contains(normalizedChannel) || monitoredChannels.contains(baseChannel) else { return }

        lock.lock()
        defer { lock.unlock() }
        nextID += 1
        entries.append(AGCChannelTraceEntry(id: nextID, direction: direction, channel: normalizedChannel, value: value))
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
    }

    func snapshot() -> [AGCChannelTraceEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    func reset() {
        lock.lock()
        entries.removeAll()
        nextID = 0
        lock.unlock()
    }
}

/// Forwards all ``AGCIOProtocol`` messages to multiple delegates (e.g. ``DSKY`` + ``LMVehicleIO``).
public final class CompositeAGCIO: AGCIOProtocol {
    private let children: [any AGCIOProtocol]
    private let traceRecorder: AGCChannelTraceRecorder

    public init(
        children: [any AGCIOProtocol],
        tracedChannels: Set<Int> = [0o10, 0o11, 0o13, 0o15, 0o163, 0o5, 0o6],
        traceLimit: Int = 512
    ) {
        self.children = children
        self.traceRecorder = AGCChannelTraceRecorder(monitoredChannels: tracedChannels, limit: traceLimit)
    }

    public func channelOutput(channel: Int, value: Int) {
        traceRecorder.append(direction: .output, channel: channel, value: value)
        for child in children {
            child.channelOutput(channel: channel, value: value)
        }
    }

    public func channelInput() async -> [AGCChannelInput]? {
        var merged: [AGCChannelInput] = []
        for child in children {
            guard let part = await child.channelInput() else { continue }
            for event in part {
                traceRecorder.append(direction: .input, channel: event.channel, value: event.value)
                merged.append(event)
            }
        }
        return merged.isEmpty ? nil : merged
    }

    public func requestRadarData() {
        for child in children {
            child.requestRadarData()
        }
    }

    public func shiftToDeda(data: Int) {
        for child in children {
            child.shiftToDeda(data: data)
        }
    }

    public func channelRoutine() async {
        for child in children {
            await child.channelRoutine()
        }
    }

    public func channelTrace() -> [AGCChannelTraceEntry] {
        traceRecorder.snapshot()
    }

    public func resetTrace() {
        traceRecorder.reset()
    }
}
