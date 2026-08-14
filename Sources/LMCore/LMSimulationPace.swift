import Foundation

/// Wall-clock vs GET pacing for the closed-loop landing.
///
/// P63 braking is ~11 min of AGC GET. The AGC itself is only ~0.26× realtime
/// on this host, so a 1× frame loop with 60 fps sleep would sit through the
/// whole burn. During PROG 63 the loop steps a quarter-second of GET per
/// iteration and does not sleep; from P64 onward it runs 1× so the approach
/// and auto-land are watchable.
public enum LMSimulationPace: Equatable, Sendable {
    /// Fast-forward braking: fixed GET chunk, no wall-clock sleep.
    case accelerated
    /// Watchable landing: 1× wall clock, capped frame delta.
    case realtime

    public static let acceleratedDeltaSeconds = 0.25
    public static let realtimeFrameCapSeconds = 1.0 / 15.0
    public static let realtimeTargetFrameSeconds = 1.0 / 60.0
    public static let realtimeMinimumDeltaSeconds = 1.0 / 240.0

    public static func pace(programNumber: Int?) -> LMSimulationPace {
        switch programNumber {
        case 64, 65, 66:
            return .realtime
        default:
            return .accelerated
        }
    }

    public func simulationDelta(wallDelta: Double) -> Double {
        switch self {
        case .accelerated:
            return Self.acceleratedDeltaSeconds
        case .realtime:
            return min(max(wallDelta, Self.realtimeMinimumDeltaSeconds), Self.realtimeFrameCapSeconds)
        }
    }

    public var shouldSleepToFrameRate: Bool {
        self == .realtime
    }
}
