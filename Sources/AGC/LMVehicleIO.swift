import Foundation

/// Last-known LM **OUT0** / **OUT1** channel words (octal channels 5 and 6).
///
/// Luminary drives RCS jet selection and engine discretes via these outputs; decode bit patterns
/// using mission documentation or Virtual AGC hardware notes for your Luminary revision.
public struct LMJetEngineOutputs: Equatable, Sendable {
    public var channel5: Int
    public var channel6: Int

    public init(channel5: Int = 0, channel6: Int = 0) {
        self.channel5 = channel5 & 0o77777
        self.channel6 = channel6 & 0o77777
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
    private var lastOutputs = LMJetEngineOutputs()

    public weak var agcEngine: AGCEngine?

    /// Called when radar integration should load ``Register/regRNRAD`` (and any related state).
    public var onRequestRadarData: (() -> Void)?

    public init(agcEngine: AGCEngine? = nil, onRequestRadarData: (() -> Void)? = nil) {
        self.agcEngine = agcEngine
        self.onRequestRadarData = onRequestRadarData
    }

    public var jetEngineOutputs: LMJetEngineOutputs {
        keyLock.lock()
        defer { keyLock.unlock() }
        return lastOutputs
    }

    public func channelOutput(channel: Int, value: Int) {
        let ch = channel & 0o777
        let v = value & 0o77777
        guard ch == 0o5 || ch == 0o6 else { return }
        keyLock.lock()
        if ch == 0o5 {
            lastOutputs.channel5 = v
        } else {
            lastOutputs.channel6 = v
        }
        keyLock.unlock()
    }

    public func channelInput() async -> [Int: Int]? { nil }

    public func requestRadarData() {
        onRequestRadarData?()
    }

    public func shiftToDeda(data: Int) {}

    public func channelRoutine() async {}
}

/// Forwards all ``AGCIOProtocol`` messages to multiple delegates (e.g. ``DSKY`` + ``LMVehicleIO``).
public final class CompositeAGCIO: AGCIOProtocol {
    private let children: [any AGCIOProtocol]

    public init(children: [any AGCIOProtocol]) {
        self.children = children
    }

    public func channelOutput(channel: Int, value: Int) {
        for child in children {
            child.channelOutput(channel: channel, value: value)
        }
    }

    public func channelInput() async -> [Int: Int]? {
        var merged: [Int: Int] = [:]
        for child in children {
            guard let part = await child.channelInput() else { continue }
            for (k, v) in part {
                merged[k] = v
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
}
