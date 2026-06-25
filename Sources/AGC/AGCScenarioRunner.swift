import Foundation

public struct AGCScenarioResult: Equatable, Sendable {
    public let initialSnapshot: AGCSnapshot
    public let finalSnapshot: AGCSnapshot
    public let channelTrace: [AGCChannelTraceEntry]

    public init(initialSnapshot: AGCSnapshot, finalSnapshot: AGCSnapshot, channelTrace: [AGCChannelTraceEntry]) {
        self.initialSnapshot = initialSnapshot
        self.finalSnapshot = finalSnapshot
        self.channelTrace = channelTrace
    }
}

/// Shared scenario harness for API tests and MissionControl quick actions.
public struct AGCScenarioRunner: Sendable {
    public let runtime: AGCRuntime

    public init(runtime: AGCRuntime) {
        self.runtime = runtime
    }

    public func boot(cycles: UInt64 = 0) async throws -> AGCSnapshot {
        _ = try await runtime.reset()
        guard cycles > 0 else {
            return await runtime.snapshot()
        }
        return await runtime.step(cycles: cycles)
    }

    public func run(_ script: DSKYScript, cyclesPerKey: UInt64 = 50_000) async -> AGCScenarioResult {
        let initialSnapshot = await runtime.snapshot()
        let finalSnapshot = await runtime.sendDSKYScript(script, cyclesPerKey: cyclesPerKey)
        return AGCScenarioResult(
            initialSnapshot: initialSnapshot,
            finalSnapshot: finalSnapshot,
            channelTrace: finalSnapshot.channelTrace
        )
    }

    public func rset(cyclesPerKey: UInt64 = 50_000) async -> AGCScenarioResult {
        await run(.reset, cyclesPerKey: cyclesPerKey)
    }

    public func v35e(cyclesPerKey: UInt64 = 50_000) async -> AGCScenarioResult {
        await run(.v35e, cyclesPerKey: cyclesPerKey)
    }

    public func v16n36e(cyclesPerKey: UInt64 = 50_000) async -> AGCScenarioResult {
        await run(.v16n36e, cyclesPerKey: cyclesPerKey)
    }
}
