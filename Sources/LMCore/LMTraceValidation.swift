import AGC
import Foundation

public struct LMAGCRegisterSummary: Equatable, Sendable, Codable {
    public let a: Int
    public let l: Int
    public let q: Int
    public let z: Int
    public let eb: Int
    public let fb: Int
    public let bb: Int
    public let rendezvousRadar: Int
    public let altitudeMeter: Int

    public init(registers: AGCRegisterSnapshot) {
        self.a = registers.a
        self.l = registers.l
        self.q = registers.q
        self.z = registers.z
        self.eb = registers.eb
        self.fb = registers.fb
        self.bb = registers.bb
        self.rendezvousRadar = registers.rendezvousRadar
        self.altitudeMeter = registers.altitudeMeter
    }
}

public struct LMDSKYSummary: Equatable, Sendable, Codable {
    public let verb: String
    public let noun: String
    public let mode: String
    public let lampTest: Bool
    public let compActy: Bool
    public let proKeyPressed: Bool

    public init(dsky: DSKYSnapshot) {
        self.verb = dsky.verb
        self.noun = dsky.noun
        self.mode = dsky.mode
        self.lampTest = dsky.lampTest
        self.compActy = dsky.compActy
        self.proKeyPressed = dsky.proKeyPressed
    }
}

public struct LMAGCSnapshotSummary: Equatable, Sendable, Codable {
    public let cycle: UInt64
    public let registers: LMAGCRegisterSummary
    public let inputChannels: [Int: Int]
    public let outputChannels: [Int: Int]
    public let dsky: LMDSKYSummary

    public init(snapshot: AGCSnapshot) {
        self.cycle = snapshot.cycle
        self.registers = LMAGCRegisterSummary(registers: snapshot.registers)
        self.inputChannels = snapshot.inputChannels
        self.outputChannels = snapshot.outputChannels
        self.dsky = LMDSKYSummary(dsky: snapshot.dsky)
    }
}

public struct LMTraceChannelDelta: Equatable, Sendable, Codable, Identifiable {
    public let id: UInt64
    public let direction: String
    public let channel: Int
    public let value: Int

    public init(entry: AGCChannelTraceEntry) {
        self.id = entry.id
        self.direction = entry.direction.rawValue
        self.channel = entry.channel
        self.value = entry.value
    }
}

public struct LMSimulationTraceSample: Equatable, Sendable, Codable {
    public let timeSeconds: Double
    public let cycle: UInt64
    public let agc: LMAGCSnapshotSummary
    public let vehicleState: LMVehicleStateSnapshot
    public let vehicleCommands: LMVehicleSnapshot
    public let sourceStatus: LMSourceStatus
    public let channelDeltas: [LMTraceChannelDelta]

    public init(
        timeSeconds: Double,
        agc: AGCSnapshot,
        vehicleState: LMVehicleStateSnapshot,
        vehicleCommands: LMVehicleSnapshot,
        sourceStatus: LMSourceStatus,
        channelDeltas: [AGCChannelTraceEntry]
    ) {
        self.timeSeconds = timeSeconds
        self.cycle = agc.cycle
        self.agc = LMAGCSnapshotSummary(snapshot: agc)
        self.vehicleState = vehicleState
        self.vehicleCommands = vehicleCommands
        self.sourceStatus = sourceStatus
        self.channelDeltas = channelDeltas.map(LMTraceChannelDelta.init)
    }
}

public enum LMPoweredDescentCheckpointStatus: String, Sendable, Codable {
    case notObserved
    case partial
    case observed
}

public struct LMPoweredDescentCheckpointResult: Equatable, Sendable, Codable, Identifiable {
    public let id: String
    public let program: Int
    public let expectedScriptID: String
    public let status: LMPoweredDescentCheckpointStatus
    public let observedCycle: UInt64?
    public let evidence: [String]

    public init(
        id: String,
        program: Int,
        expectedScriptID: String,
        status: LMPoweredDescentCheckpointStatus,
        observedCycle: UInt64?,
        evidence: [String]
    ) {
        self.id = id
        self.program = program
        self.expectedScriptID = expectedScriptID
        self.status = status
        self.observedCycle = observedCycle
        self.evidence = evidence
    }
}

public struct LMPoweredDescentValidationResult: Equatable, Sendable, Codable {
    public let checkpointResults: [LMPoweredDescentCheckpointResult]
    public let channelActivityCounts: [Int: Int]
    public let finalState: LMVehicleStateSnapshot?
    public let unmodeledItems: [String]

    public init(
        scenario: LMPoweredDescentScenario,
        samples: [LMSimulationTraceSample],
        finalSnapshot: LMSimulationSnapshot?
    ) {
        let deltas = samples.flatMap(\.channelDeltas)
        let channel15Values = deltas
            .filter { $0.direction == AGCChannelTraceDirection.input.rawValue && $0.channel == 0o15 }
            .map(\.value)
        let channel15Cycles = samples.flatMap { sample in
            sample.channelDeltas
                .filter { $0.direction == AGCChannelTraceDirection.input.rawValue && $0.channel == 0o15 }
                .map { _ in sample.cycle }
        }

        self.checkpointResults = scenario.checkpoints.map { checkpoint in
            let expected = checkpoint.expectedScript.keys.map(\.rawValue)
            if let matchStart = Self.indexOfSequence(expected, in: channel15Values) {
                let cycleIndex = min(matchStart + expected.count - 1, max(0, channel15Cycles.count - 1))
                return LMPoweredDescentCheckpointResult(
                    id: checkpoint.id,
                    program: checkpoint.program,
                    expectedScriptID: checkpoint.expectedScript.id,
                    status: .observed,
                    observedCycle: channel15Cycles.isEmpty ? nil : channel15Cycles[cycleIndex],
                    evidence: ["Observed expected channel 015 key sequence."]
                )
            }

            let partialCount = Self.longestSuffixPrefixMatch(expected: expected, observed: channel15Values)
            return LMPoweredDescentCheckpointResult(
                id: checkpoint.id,
                program: checkpoint.program,
                expectedScriptID: checkpoint.expectedScript.id,
                status: partialCount > 0 ? .partial : .notObserved,
                observedCycle: nil,
                evidence: partialCount > 0
                    ? ["Observed \(partialCount) trailing key values for \(checkpoint.expectedScript.id)."]
                    : ["No complete channel 015 key sequence observed for \(checkpoint.expectedScript.id)."]
            )
        }

        self.channelActivityCounts = Dictionary(
            grouping: deltas,
            by: \.channel
        ).mapValues(\.count)
        self.finalState = finalSnapshot?.vehicleState
        self.unmodeledItems = finalSnapshot?.sourceStatus.unmodeledItems ?? []
    }

    private static func indexOfSequence(_ expected: [Int], in observed: [Int]) -> Int? {
        guard !expected.isEmpty, observed.count >= expected.count else { return nil }
        for start in 0...(observed.count - expected.count) {
            if Array(observed[start..<(start + expected.count)]) == expected {
                return start
            }
        }
        return nil
    }

    private static func longestSuffixPrefixMatch(expected: [Int], observed: [Int]) -> Int {
        guard !expected.isEmpty, !observed.isEmpty else { return 0 }
        let maxLength = min(expected.count, observed.count)
        for length in stride(from: maxLength, through: 1, by: -1) {
            if Array(observed.suffix(length)) == Array(expected.prefix(length)) {
                return length
            }
        }
        return 0
    }
}
