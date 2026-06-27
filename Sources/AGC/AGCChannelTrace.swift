import Foundation

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

/// Forwards all ``AGCIOProtocol`` messages to multiple delegates while recording ordered channel traffic.
public final class CompositeAGCIO: AGCIOProtocol {
    private let children: [any AGCIOProtocol]
    private let traceRecorder: AGCChannelTraceRecorder

    public init(
        children: [any AGCIOProtocol],
        tracedChannels: Set<Int> = [0o5, 0o6, 0o10, 0o11, 0o12, 0o13, 0o14, 0o15, 0o16, 0o163],
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
