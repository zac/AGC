import Foundation

extension AGCEngine {
    /// Get input from peripherals for a channel
    func channelInput() async -> Bool {
        guard let input = await ioDelegate?.channelInput() else {
            return false
        }

        var servicedCounter = false

        for event in input {
            let normalizedChannel = event.channel & 0o377
            let maskedInput = event.value & 0o77777

            if (event.channel & 0o400) != 0 {
                if normalizedChannel < channelMasks.count {
                    channelMasks[normalizedChannel] = maskedInput
                }
                continue
            }

            if (normalizedChannel & 0o200) != 0 {
                if handleUnprogrammedIncrement(counterChannel: normalizedChannel, incrementType: maskedInput) {
                    servicedCounter = true
                }
            } else {
                let channelMask = normalizedChannel < channelMasks.count ? channelMasks[normalizedChannel] : 0o77777
                let mergedValue = (maskedInput & channelMask) | (readIO(address: normalizedChannel) & ~channelMask)
                let storedValue = writeIO(address: normalizedChannel, value: mergedValue)
                
                // If this is a keystroke from the DSKY (channel 15), generate KEYRUPT interrupt
                if normalizedChannel == 0o15 {
                    state.interruptRequests[5] = 1  // KEYRUPT interrupt
                } else if normalizedChannel == 0o173 {
                    state.erasableMemory[0][Register.regINLINK.rawValue] = storedValue & 0o77777
                    state.interruptRequests[7] = 1  // UPRUPT interrupt
                } else if normalizedChannel == 0o166 {
                    lastRhcPitch = storedValue
                    channelOutput(channel: normalizedChannel, value: storedValue)
                } else if normalizedChannel == 0o167 {
                    lastRhcYaw = storedValue
                    channelOutput(channel: normalizedChannel, value: storedValue)
                } else if normalizedChannel == 0o170 {
                    lastRhcRoll = storedValue
                    channelOutput(channel: normalizedChannel, value: storedValue)
                }
            }
        }

        return servicedCounter
    }

    /// Rate-limits PCDU/MCDU into CDUX–CDUZ like yaAGC `PushCduFifo`.
    func pushCduFifo(counter: Int, incType: Int) {
        let first = CDUFifoConstants.firstCounter
        guard counter >= first && counter < first + CDUFifoConstants.fifoCount else { return }
        let (interval, base): (UInt64, UInt32)
        switch incType {
        case 1:
            interval = 213
            base = 0x0000_0000
        case 3:
            interval = 213
            base = 0x4000_0000
        case 0o21:
            interval = 13
            base = 0x8000_0000
        case 0o23:
            interval = 13
            base = 0xC000_0000
        default:
            return
        }
        let fifoIndex = counter - first
        var fifo = cduFifoStates[fifoIndex]
        defer { cduFifoStates[fifoIndex] = fifo }

        if fifo.size == 0 {
            fifo.ptr = 0
            fifo.size = 1
            fifo.counts[0] = Int32(bitPattern: base &+ 1)
            fifo.nextUpdate = state.cycleCounter &+ interval
            fifo.intervalType = 1
            return
        }

        var next = fifo.ptr + fifo.size - 1
        if next >= CDUFifoConstants.maxEntries {
            next -= CDUFifoConstants.maxEntries
        }
        let lastMasked = UInt32(bitPattern: fifo.counts[next]) & 0xC000_0000
        if lastMasked != base {
            if fifo.size >= CDUFifoConstants.maxEntries {
                return
            }
            fifo.size += 1
            next += 1
            if next >= CDUFifoConstants.maxEntries {
                next -= CDUFifoConstants.maxEntries
            }
            fifo.counts[next] = Int32(bitPattern: base &+ 1)
            return
        }
        fifo.counts[next] &+= 1
    }

    /// Applies at most one queued CDU pulse per call (yaAGC `ServiceCduFifo`). Returns true if a machine cycle was consumed.
    func serviceCduFifo() -> Bool {
        let idx = cduChecker
        var fifo = cduFifoStates[idx]
        var consumed = false
        defer {
            cduFifoStates[idx] = fifo
            cduChecker += 1
            if cduChecker >= CDUFifoConstants.fifoCount {
                cduChecker = 0
            }
        }

        if fifo.size > 0 && state.cycleCounter >= fifo.nextUpdate {
            let counterOffset = idx + CDUFifoConstants.firstCounter
            var count = fifo.counts[fifo.ptr]
            let highRate = (count & Int32(bitPattern: 0x8000_0000)) != 0
            let downCount = (count & Int32(bitPattern: 0x4000_0000)) != 0
            if downCount {
                _ = counterMCDU(at: counterOffset)
            } else {
                _ = counterPCDU(at: counterOffset)
            }
            count -= 1
            let payloadMask = Int32(bitPattern: ~UInt32(0xC000_0000))
            if (count & payloadMask) != 0 {
                fifo.counts[fifo.ptr] = count
            } else {
                fifo.size -= 1
                fifo.ptr += 1
                if fifo.ptr >= CDUFifoConstants.maxEntries {
                    fifo.ptr = 0
                }
            }
            if fifo.nextUpdate == 0 {
                fifo.nextUpdate = state.cycleCounter
            }
            if fifo.intervalType < 2 {
                fifo.nextUpdate += highRate ? 13 : 213
                fifo.intervalType += 1
            } else {
                fifo.nextUpdate += highRate ? 14 : 214
                fifo.intervalType = 0
            }
            consumed = true
        }
        return consumed
    }

    func handleUnprogrammedIncrement(counterChannel: Int, incrementType: Int) -> Bool {
        guard (counterChannel & 0o200) != 0 else {
            return false
        }

        let counter = counterChannel & 0o177
        guard counter >= 0 && counter < state.erasableMemory[0].count else {
            return false
        }

        let type = incrementType & 0o77
        let firstCDU = CDUFifoConstants.firstCounter
        let lastCDUExclusive = firstCDU + CDUFifoConstants.fifoCount
        switch type {
        case 0:
            _ = counterPINC(at: counter)
            return true
        case 1, 0o21:
            if counter >= firstCDU && counter < lastCDUExclusive {
                pushCduFifo(counter: counter, incType: type)
            } else {
                _ = counterPCDU(at: counter)
            }
            return true
        case 2:
            _ = counterMINC(at: counter)
            return true
        case 3, 0o23:
            if counter >= firstCDU && counter < lastCDUExclusive {
                pushCduFifo(counter: counter, incType: type)
            } else {
                _ = counterMCDU(at: counter)
            }
            return true
        case 4:
            _ = counterDINC(at: counter, counterNumber: counter)
            return true
        case 5:
            _ = counterSHINC(at: counter)
            return true
        case 6:
            _ = counterSHANC(at: counter)
            return true
        default:
            return false
        }
    }
}
