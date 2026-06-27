import AGC
import Foundation

public typealias LMRotationalHandControllerInput = AGCRotationalHandControllerInput

public enum LMVehicleOutputChannel: Int, Sendable, Codable {
    case out0 = 0o5
    case out1 = 0o6
    case channel11 = 0o11
    case channel12 = 0o12
    case channel13 = 0o13
    case channel14 = 0o14
}

public enum LMVehicleInputChannel: Int, Sendable, Codable {
    case channel16 = 0o16
}

public enum LMRCSAxis: String, Sendable, Codable {
    case positiveU = "+U"
    case negativeU = "-U"
    case positiveV = "+V"
    case negativeV = "-V"
    case positivePitch = "+P"
    case negativePitch = "-P"
}

public enum LMRCSJet: Int, CaseIterable, Sendable, Codable {
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

public struct LMRCSJetCommand: Equatable, Sendable, Codable {
    public let jet: LMRCSJet
    public let axis: LMRCSAxis
    public let channel: Int
    public let bit: Int
    public let source: LMSourceLocator

    public init(jet: LMRCSJet, axis: LMRCSAxis, channel: Int, bit: Int, source: LMSourceLocator) {
        self.jet = jet
        self.axis = axis
        self.channel = channel
        self.bit = bit
        self.source = source
    }
}

public struct LMSourceBackedDiscreteGroup: Equatable, Sendable, Codable {
    public let name: String
    public let channel: Int
    public let mask: Int
    public let source: LMSourceLocator

    public init(name: String, channel: Int, mask: Int, source: LMSourceLocator) {
        self.name = name
        self.channel = channel
        self.mask = mask
        self.source = source
    }
}

public struct LMVehicleDiscreteCommand: Equatable, Sendable, Codable {
    public let name: String
    public let channel: Int
    public let bit: Int
    public let mask: Int
    public let source: LMSourceLocator

    public init(name: String, channel: Int, bit: Int, mask: Int, source: LMSourceLocator) {
        self.name = name
        self.channel = channel & 0o777
        self.bit = bit
        self.mask = mask & 0o77777
        self.source = source
    }
}

public struct LMUnmappedDiscrete: Equatable, Sendable, Codable {
    public let channel: Int
    public let bit: Int
    public let mask: Int

    public init(channel: Int, bit: Int, mask: Int) {
        self.channel = channel
        self.bit = bit
        self.mask = mask
    }
}

public struct LMDPSCommandState: Equatable, Sendable, Codable {
    public let engineOn: Bool
    public let engineOff: Bool
    public let thrustDriveActive: Bool
    public let engineCommands: [LMVehicleDiscreteCommand]
    public let gimbalTrimCommands: [LMVehicleDiscreteCommand]
    public let thrustDriveCommands: [LMVehicleDiscreteCommand]
    public let throttleMappingStatus: LMModelingStatus

    public init(
        engineOn: Bool,
        engineOff: Bool,
        thrustDriveActive: Bool,
        engineCommands: [LMVehicleDiscreteCommand],
        gimbalTrimCommands: [LMVehicleDiscreteCommand],
        thrustDriveCommands: [LMVehicleDiscreteCommand],
        throttleMappingStatus: LMModelingStatus
    ) {
        self.engineOn = engineOn
        self.engineOff = engineOff
        self.thrustDriveActive = thrustDriveActive
        self.engineCommands = engineCommands
        self.gimbalTrimCommands = gimbalTrimCommands
        self.thrustDriveCommands = thrustDriveCommands
        self.throttleMappingStatus = throttleMappingStatus
    }
}

/// Last-known LM vehicle channel words plus source-backed command decoding.
public struct LMVehicleSnapshot: Equatable, Sendable, Codable {
    public let out0: Int
    public let out1: Int
    public let outputChannel11: Int
    public let outputChannel12: Int
    public let outputChannel13: Int
    public let outputChannel14: Int
    public let inputChannel16: Int
    public let rcsJets: [LMRCSJetCommand]
    public let discreteGroups: [LMSourceBackedDiscreteGroup]
    public let mainEngineCommands: [LMVehicleDiscreteCommand]
    public let gimbalTrimCommands: [LMVehicleDiscreteCommand]
    public let controlCommands: [LMVehicleDiscreteCommand]
    public let descentRateCommands: [LMVehicleDiscreteCommand]
    public let unmappedBits: [LMUnmappedDiscrete]
    public let mainEngineOn: Bool
    public let mainEngineOff: Bool
    public let thrustDriveActive: Bool
    public let dps: LMDPSCommandState

    public init(agcSnapshot: AGCSnapshot) {
        self.init(
            out0: agcSnapshot.outputChannels[0o5] ?? 0,
            out1: agcSnapshot.outputChannels[0o6] ?? 0,
            outputChannel11: agcSnapshot.outputChannels[0o11] ?? 0,
            outputChannel12: agcSnapshot.outputChannels[0o12] ?? 0,
            outputChannel13: agcSnapshot.outputChannels[0o13] ?? 0,
            outputChannel14: agcSnapshot.outputChannels[0o14] ?? 0,
            inputChannel16: agcSnapshot.inputChannels[0o16] ?? 0
        )
    }

    public init(
        out0: Int = 0,
        out1: Int = 0,
        outputChannel11: Int = 0,
        outputChannel12: Int = 0,
        outputChannel13: Int = 0,
        outputChannel14: Int = 0,
        inputChannel16: Int = 0
    ) {
        self.out0 = out0 & 0o77777
        self.out1 = out1 & 0o77777
        self.outputChannel11 = outputChannel11 & 0o77777
        self.outputChannel12 = outputChannel12 & 0o77777
        self.outputChannel13 = outputChannel13 & 0o77777
        self.outputChannel14 = outputChannel14 & 0o77777
        self.inputChannel16 = inputChannel16 & 0o77777
        self.rcsJets = LMVehicleSnapshot.decodeRCSJets(out0: self.out0)
        self.discreteGroups = LMVehicleSnapshot.decodeDiscreteGroups(out1: self.out1)
        self.mainEngineCommands = LMVehicleSnapshot.decodeMainEngineCommands(channel11: self.outputChannel11)
        self.gimbalTrimCommands = LMVehicleSnapshot.decodeGimbalTrimCommands(channel12: self.outputChannel12)
        self.controlCommands = LMVehicleSnapshot.decodeControlCommands(
            channel13: self.outputChannel13,
            channel14: self.outputChannel14
        )
        self.descentRateCommands = LMVehicleSnapshot.decodeDescentRateCommands(channel16: self.inputChannel16)
        self.unmappedBits = LMVehicleSnapshot.decodeUnmappedBits(
            out0: self.out0,
            out1: self.out1,
            channel11: self.outputChannel11,
            channel12: self.outputChannel12,
            channel13: self.outputChannel13,
            channel14: self.outputChannel14,
            channel16: self.inputChannel16
        )
        self.mainEngineOn = (self.outputChannel11 & 0o10000) != 0
        self.mainEngineOff = (self.outputChannel11 & 0o20000) != 0
        self.thrustDriveActive = (self.outputChannel14 & 0o10) != 0
        self.dps = LMDPSCommandState(
            engineOn: self.mainEngineOn,
            engineOff: self.mainEngineOff,
            thrustDriveActive: self.thrustDriveActive,
            engineCommands: self.mainEngineCommands,
            gimbalTrimCommands: self.gimbalTrimCommands,
            thrustDriveCommands: self.controlCommands.filter { $0.name == "thrust drive activity" },
            throttleMappingStatus: .unmodeled("DPS throttle command mapping from AGC output words to thrust magnitude is unmodeled.")
        )
    }

    public var sourceReferences: [LMSourceReference] {
        var references = (rcsJets.map(\.source.reference)
            + discreteGroups.map(\.source.reference)
            + mainEngineCommands.map(\.source.reference)
            + gimbalTrimCommands.map(\.source.reference)
            + controlCommands.map(\.source.reference)
            + descentRateCommands.map(\.source.reference))
        if let source = dps.throttleMappingStatus.source?.reference {
            references.append(source)
        }
        var seen = Set<String>()
        return references.filter { seen.insert($0.id).inserted }
    }

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
                source: .channel5RCSJets
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
                source: .channel6RCSGroups
            ))
        }
        if (out1 & 0o252) != 0 {
            groups.append(LMSourceBackedDiscreteGroup(
                name: "negative pitch RCS command bits",
                channel: LMVehicleOutputChannel.out1.rawValue,
                mask: out1 & 0o252,
                source: .channel6RCSGroups
            ))
        }
        return groups
    }

    // Channel 11 bit 13 is ENGINE ON, bit 14 is ENGINE OFF in:
    // https://github.com/chrislgarry/Apollo-11/blob/master/Luminary099/INPUT_OUTPUT_CHANNEL_BIT_DESCRIPTIONS.agc
    private static func decodeMainEngineCommands(channel11: Int) -> [LMVehicleDiscreteCommand] {
        discreteCommands(channel: 0o11, value: channel11, mappings: [
            (13, "main engine on command"),
            (14, "main engine off command")
        ])
    }

    // Channel 12 bits 9-12 are descent-engine pitch/roll gimbal trim commands:
    // -PITCH, +PITCH, -ROLL, +ROLL.
    // Source: Apollo-11 Luminary099 INPUT_OUTPUT_CHANNEL_BIT_DESCRIPTIONS.agc.
    private static func decodeGimbalTrimCommands(channel12: Int) -> [LMVehicleDiscreteCommand] {
        discreteCommands(channel: 0o12, value: channel12, mappings: [
            (9, "descent engine -pitch gimbal trim"),
            (10, "descent engine +pitch gimbal trim"),
            (11, "descent engine -roll gimbal trim"),
            (12, "descent engine +roll gimbal trim")
        ])
    }

    // Channel 13 carries RHC/radar control bits. Channel 14 carries thrust-drive activity.
    // Source: Apollo-11 Luminary099 INPUT_OUTPUT_CHANNEL_BIT_DESCRIPTIONS.agc.
    private static func decodeControlCommands(channel13: Int, channel14: Int) -> [LMVehicleDiscreteCommand] {
        discreteCommands(channel: 0o13, value: channel13, mappings: [
            (5, "radar activity"),
            (9, "RHC counter enable"),
            (10, "start RHC read")
        ]) + discreteCommands(channel: 0o14, value: channel14, mappings: [
            (4, "thrust drive activity")
        ])
    }

    // Channel 16 bits 14 and 15 are the crew DESCEND+ / DESCEND- inputs.
    // Source: Apollo-11 Luminary099 INPUT_OUTPUT_CHANNEL_BIT_DESCRIPTIONS.agc.
    private static func decodeDescentRateCommands(channel16: Int) -> [LMVehicleDiscreteCommand] {
        discreteCommands(channel: 0o16, value: channel16, mappings: [
            (14, "DESCEND+ crew input"),
            (15, "DESCEND- crew input")
        ])
    }

    private static func discreteCommands(
        channel: Int,
        value: Int,
        mappings: [(bit: Int, name: String)]
    ) -> [LMVehicleDiscreteCommand] {
        mappings.compactMap { mapping in
            let mask = 1 << (mapping.bit - 1)
            guard (value & mask) != 0 else { return nil }
            return LMVehicleDiscreteCommand(
                name: mapping.name,
                channel: channel,
                bit: mapping.bit,
                mask: mask,
                source: .luminaryIOChannels
            )
        }
    }

    private static func decodeUnmappedBits(
        out0: Int,
        out1: Int,
        channel11: Int,
        channel12: Int,
        channel13: Int,
        channel14: Int,
        channel16: Int
    ) -> [LMUnmappedDiscrete] {
        var bits: [LMUnmappedDiscrete] = []
        let mappedOut0Mask = channel5Mappings.reduce(0) { partial, mapping in
            partial | (1 << (mapping.bit - 1))
        }
        bits.append(contentsOf: unmappedBits(channel: 0o5, value: out0, mappedMask: mappedOut0Mask))

        // Channel 6 group masks come from Apollo-11 Luminary099/P-AXIS_RCS_AUTOPILOT.agc:
        // https://github.com/chrislgarry/Apollo-11/blob/master/Luminary099/P-AXIS_RCS_AUTOPILOT.agc
        // Exact bit-to-jet names are intentionally left raw until verified from an authoritative source.
        bits.append(contentsOf: unmappedBits(channel: 0o6, value: out1, mappedMask: 0))
        bits.append(contentsOf: unmappedBits(channel: 0o11, value: channel11, mappedMask: bitsMask([13, 14])))
        bits.append(contentsOf: unmappedBits(channel: 0o12, value: channel12, mappedMask: bitsMask([9, 10, 11, 12])))
        bits.append(contentsOf: unmappedBits(channel: 0o13, value: channel13, mappedMask: bitsMask([5, 9, 10])))
        bits.append(contentsOf: unmappedBits(channel: 0o14, value: channel14, mappedMask: bitsMask([4])))
        bits.append(contentsOf: unmappedBits(channel: 0o16, value: channel16, mappedMask: bitsMask([14, 15])))
        return bits
    }

    private static func bitsMask(_ bits: [Int]) -> Int {
        bits.reduce(0) { partial, bit in partial | (1 << (bit - 1)) }
    }

    private static func unmappedBits(channel: Int, value: Int, mappedMask: Int) -> [LMUnmappedDiscrete] {
        (1...15).compactMap { bit in
            let mask = 1 << (bit - 1)
            guard (value & mask) != 0, (mappedMask & mask) == 0 else { return nil }
            return LMUnmappedDiscrete(channel: channel, bit: bit, mask: mask)
        }
    }
}
