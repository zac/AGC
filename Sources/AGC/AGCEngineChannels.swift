import Foundation

extension AGCEngine {
    func requestRadarData() {
        ioDelegate?.requestRadarData()
    }

    /// Radar sample gate finished: reset gate state, notify delegate, then RADARUPT (yaAGC parity).
    func completeRadarSampleGate() {
        state.radarGateCounter = 0
        state.inputChannels[0o13] &= ~0o10
        requestRadarData()
        state.interruptRequests[9] = 1
    }

    /// Invokes the same completion path as a hardware radar gate end (for tests / tooling).
    internal func integrationTestCompleteRadarSampleGate() {
        completeRadarSampleGate()
    }

    /// Read a value from an I/O channel or register
    func readIO(address: Int) -> Int {
        // Validate address range
        guard address >= 0 && address <= 0o777 else {
            return 0
        }
        
        // Handle special registers that appear in both memory and I/O space
        if address == Register.regL.rawValue || address == Register.regQ.rawValue {
            return state.erasableMemory[0][address]
        }
        
        return state.inputChannels[address]
    }

    /// Write a value to an I/O channel or register with special handling
    @discardableResult
    func writeIO(address: Int, value: Int) -> Int {
        // Validate address range
        guard address >= 0 && address <= 0o777 else {
            return 0
        }
        
        // Mask value to 15 bits
        let maskedValue = value & 0o77777
        
        // Handle special registers that appear in both memory and I/O space
        if address == Register.regL.rawValue || address == Register.regQ.rawValue {
            state.erasableMemory[0][address] = maskedValue
        }
        
        // Handle special cases for certain channels
        var modifiedValue = maskedValue
        
        if address == 0o10 {
            // Channel 10 is converted externally into up to 16 ports via latching relays
            let rowIndex = (maskedValue >> 11) & 0o17
            state.outputChannel10[rowIndex] = maskedValue
        }
        else if address == 0o15 || address == 0o16 {
            // RSET being pressed on either DSKY clears RESTART light directly
            if maskedValue == 0o22 {
                state.restartLight = false
            }
        }
        else if address == 0o33 {
            // Channel 33 bits 11-15 are internally controlled latched inputs.
            modifiedValue = (state.inputChannels[address] & 0o76000) | (maskedValue & 0o1777)
        }
        
        // Store final value
        state.inputChannels[address] = modifiedValue
        return modifiedValue & 0o77777
    }

    /// Public helper for sending keypresses into the AGC
    func writeIOChannel(address: Int, value: Int) {
        cpuWriteIO(address: address, value: value)
    }
}
