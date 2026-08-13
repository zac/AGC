import Foundation

extension AGCEngine {
    func backtraceAdd(tag: Int, target: Int) {
        let source = readRegister(.regZ) & 0o177777
        let entry = AGCBacktraceEntry(
            cycle: state.cycleCounter,
            source: source,
            target: target & 0o177777,
            tag: tag & 0o777
        )
        state.backtrace.append(entry)
        if state.backtrace.count > BACKTRACE_LIMIT {
            state.backtrace.removeFirst(state.backtrace.count - BACKTRACE_LIMIT)
        }
    }

    func readCounter(at offset: Int) -> Int? {
        guard offset >= 0 && offset < state.erasableMemory[0].count else {
            return nil
        }
        return state.erasableMemory[0][offset] & 0o77777
    }

    func writeCounter(at offset: Int, _ value: Int) {
        guard offset >= 0 && offset < state.erasableMemory[0].count else {
            return
        }
        state.erasableMemory[0][offset] = value & 0o77777
    }

    @discardableResult
    func counterPINC(register: Register) -> Bool {
        return counterPINC(at: register.rawValue)
    }

    @discardableResult
    func counterMINC(register: Register) -> Bool {
        return counterMINC(at: register.rawValue)
    }

    @discardableResult
    func counterDINC(register: Register, counterNumber: Int = 0) -> Bool {
        return counterDINC(at: register.rawValue, counterNumber: counterNumber)
    }

    func counterPINC(at offset: Int) -> Bool {
        guard var value = readCounter(at: offset) else { return false }
        if value == 0o37777 {
            writeCounter(at: offset, AGC_P0)
            return true
        }
        value = (value + 1) & 0o77777
        if value == AGC_P0 {
            value = (value + 1) & 0o77777
        }
        writeCounter(at: offset, value)
        return false
    }

    func counterMINC(at offset: Int) -> Bool {
        guard var value = readCounter(at: offset) else { return false }
        if value == 0o40000 {
            writeCounter(at: offset, AGC_M0)
            return true
        }
        value = (value &- 1) & 0o77777
        if value == AGC_M0 {
            value = (value &- 1) & 0o77777
        }
        writeCounter(at: offset, value)
        return false
    }

    func counterPCDU(at offset: Int) -> Bool {
        guard var value = readCounter(at: offset) else { return false }
        let overflow = value == 0o77777
        value = (value + 1) & 0o77777
        writeCounter(at: offset, value)
        return overflow
    }

    func counterMCDU(at offset: Int) -> Bool {
        guard var value = readCounter(at: offset) else { return false }
        let overflow = value == 0
        value = (value &- 1) & 0o77777
        writeCounter(at: offset, value)
        return overflow
    }

    func counterSHINC(at offset: Int) -> Bool {
        guard var value = readCounter(at: offset) else { return false }
        let overflow = (value & 0o20000) != 0
        value = (value << 1) & 0o37777
        writeCounter(at: offset, value)
        return overflow
    }

    func counterSHANC(at offset: Int) -> Bool {
        guard var value = readCounter(at: offset) else { return false }
        let overflow = (value & 0o20000) != 0
        value = ((value << 1) + 1) & 0o37777
        writeCounter(at: offset, value)
        return overflow
    }

    func counterDINC(at offset: Int, counterNumber: Int) -> Bool {
        guard var value = readCounter(at: offset) else { return false }
        var overflow = false

        if value == AGC_P0 || value == AGC_M0 {
            overflow = true
            emitCounterPulse(counterNumber: counterNumber, code: 0o17)
        } else if (value & 0o40000) != 0 {
            value = addSP16(signExtend(value), signExtend(AGC_P1)) & 0o77777
            emitCounterPulse(counterNumber: counterNumber, code: 0o16)
        } else {
            value = addSP16(signExtend(value), signExtend(AGC_M1)) & 0o77777
            emitCounterPulse(counterNumber: counterNumber, code: 0o15)
        }

        writeCounter(at: offset, value)
        return overflow
    }

    func emitCounterPulse(counterNumber: Int, code: Int) {
        guard counterNumber != 0 else { return }
        let channel = 0o200 | (counterNumber & 0o177)
        channelOutput(channel: channel, value: code & 0o17)
    }

    /// Check if a value has overflowed
}
