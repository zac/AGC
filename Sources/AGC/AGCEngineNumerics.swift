import Foundation

extension AGCEngine {
    func valueOverflowed(_ value: Int) -> Int {
        if (value & 0o140000) == 0o040000 {
            return 1  // Positive overflow
        }
        if (value & 0o140000) == 0o100000 {
            return -1 // Negative overflow
        }
        return 0     // No overflow
    }
    
    /// Sign extend an SP value into AGC's 17-bit accumulator format
    func signExtend(_ value: Int) -> Int {
        return (value & 0o77777) | ((value << 1) & 0o100000)
    }

    /// Convert a double-precision value to two single-precision values
    func decentToSp(_ decent: Int) -> (msb: Int, lsb: Int) {
        let sign = decent & 0o4000000000
        var lsb = decent & 0o37777
        if sign != 0 {
            lsb |= 0o40000
        }
        let msb = overflowCorrected((decent >> 14) & 0o177777)
        return (msb, lsb)
    }
    
    /// Add two 16-bit values with 1's complement arithmetic
    func addSP16(_ a: Int, _ b: Int) -> Int {
        var sum = (a & 0o177777) + (b & 0o177777)
        if (sum & 0o200000) != 0 {
            sum = (sum + 1) & 0o177777
        } else {
            sum &= 0o177777
        }
        return sum
    }

    func readRawWord(_ address: Int) -> Int {
        if address < REG16, let reg = Register(rawValue: address) {
            return readRegister(reg) & 0o177777
        }
        return findMemoryWord(address) & 0o77777
    }
    
    /// Correct overflow in a 16-bit value by moving bit 16 down to bit 15
    /// (yaAGC `OverflowCorrected`).
    func overflowCorrected(_ value: Int) -> Int {
        return (value & 0o37777) | ((value >> 1) & 0o40000)
    }
    
    /// Find the memory word for a given 12-bit address, taking bank selection into account
    func findMemoryWord(_ address12: Int) -> Int {
        // Make sure the address is 12 bits
        let address = address12 & 0o7777
        
        // Check for NEWJOB access (address 67) for Night Watchman
        if address == 0o67 {
            state.nightWatchman = 0
        }
        
        // Handle different memory regions
        if address < 0o400 {
            // Unswitched erasable
            return state.erasableMemory[0][address & 0o377]
        } else if address < 0o1000 {
            // Unswitched erasable (continued)
            return state.erasableMemory[1][address & 0o377]
        } else if address < 0o1400 {
            // Unswitched erasable (continued)
            return state.erasableMemory[2][address & 0o377]
        } else if address < 0o2000 {
            // Switched erasable
            let adjustmentEB = 7 & (readRegister(.regEB) >> 8)
            return state.erasableMemory[adjustmentEB][address & 0o377]
        }
        
        // Handle fixed memory regions
        var adjustmentFB: Int
        if address < 0o4000 {
            // Fixed-switchable
            adjustmentFB = 0o37 & (readRegister(.regFB) >> 10)
            // Account for superbank bit
            if (0o30 == (adjustmentFB & 0o30)) && ((state.outputChannel7 & 0o100) != 0) {
                adjustmentFB += 0o10
            }
        } else if address < 0o6000 {
            // Fixed-fixed
            adjustmentFB = 2
        } else {
            // Fixed-fixed (continued)
            adjustmentFB = 3
        }
        
        let value = state.fixedMemory[adjustmentFB][address & 0o1777]
        
        // Check parity if enabled
        if state.checkParity {
            let linearAddr = adjustmentFB * 0o2000 + (address & 0o1777)
            let expectedParity = (state.parities[linearAddr / 32] >> (linearAddr % 32)) & 1
            var word = (value << 1) | expectedParity
            
            // Calculate parity
            word ^= (word >> 8)
            word ^= (word >> 4)
            word ^= (word >> 2)
            word ^= (word >> 1)
            word &= 1
            
            if word != 1 {
                // Accessing unused fixed memory triggers parity alarm
                state.parityFail = true
                state.inputChannels[0o77] |= CH77_PARITY_FAIL
            }
        }
        
        return value
    }
    
    /// Compute the "diminished absolute value" for a 15-bit value in AGC 1's-complement format
    func dabs(_ input: Int) -> Int {
        var value = input
        
        // If input is negative, convert to positive by taking 1's complement
        if (0o40000 & value) != 0 {
            value = 0o37777 & ~value
        }
        
        // "Diminish" if greater than 1, otherwise return +0
        if value > 1 {
            value -= 1
        } else {
            value = AGC_P0
        }
        
        return value
    }
    
    /// Compute the "diminished absolute value" for a 16-bit register value
    func odabs(_ input: Int) -> Int {
        var value = input
        
        // If input is negative, convert to positive by taking 1's complement
        if (0o100000 & value) != 0 {
            value = 0o177777 & ~value
        }
        
        // "Diminish" if greater than 1, otherwise return +0 
        if value > 1 {
            value -= 1
        } else {
            value = AGC_P0
        }
        
        return value
    }

    /// Convert an AGC-formatted word to CPU-native format
    func agc2cpu(_ input: Int) -> Int {
        if (0o40000 & input) != 0 {
            return -(0o37777 & ~input)
        } else {
            return 0o37777 & input
        }
    }
    
    /// Convert a native CPU-formatted word to AGC format
    /// If the input value is out of range, it is truncated by discarding high-order bits
    func cpu2agc(_ input: Int) -> Int {
        if input < 0 {
            return 0o77777 & ~(-input)
        } else {
            return 0o77777 & input
        }
    }
    
    /// Double-length version of agc2cpu
    func agc2cpu2(_ input: Int) -> Int {
        if (0o2000000000 & input) != 0 {
            return -(0o1777777777 & ~input)
        } else {
            return 0o1777777777 & input
        }
    }
    
    /// Double-length version of cpu2agc
    func cpu2agc2(_ input: Int) -> Int {
        if input < 0 {
            return 0o3777777777 & ~(0o1777777777 & (-input))
        } else {
            return 0o1777777777 & input
        }
    }

    /// Assign a value to erasable memory at a 12-bit CPU address.
    ///
    /// Matches `findMemoryWord` banking: 00000–00377 bank 0, 00400–00777 bank 1,
    /// 01000–01377 bank 2, 01400–01777 the EB-selected bank. Fixed-memory
    /// addresses (02000–03777) are not writable.
    func assignFromPointer(_ address: Int, _ value: Int) {
        let address12 = address & 0o7777
        guard address12 < 0o2000 else { return }

        let offset = address12 & 0o377
        let bank: Int
        if address12 < 0o400 {
            bank = 0
        } else if address12 < 0o1000 {
            bank = 1
        } else if address12 < 0o1400 {
            bank = 2
        } else {
            bank = 7 & (readRegister(.regEB) >> 8)
        }
        assign(bank: bank, offset: offset, value: value)
    }

    /// Assign a value to erasable memory with editing for special registers
    func assign(bank: Int, offset: Int, value: Int) {
        // Validate bank range
        guard bank >= 0 && bank < 8 else {
            return // Non-erasable memory
        }
        
        // Validate offset range
        guard offset >= 0 && offset < 0o400 else {
            return
        }
        
        var newValue = value
        
        // Handle special registers in bank 0
        if bank == 0 {
            switch offset {
            case Register.regZ.rawValue:
                state.nextZ = newValue
                
            case Register.regCYR.rawValue:
                newValue &= 0o77777
                if (newValue & 1) != 0 {
                    newValue = (newValue >> 1) | 0o40000
                } else {
                    newValue >>= 1
                }
                
            case Register.regSR.rawValue:
                newValue &= 0o77777
                if (newValue & 0o40000) != 0 {
                    newValue = (newValue >> 1) | 0o40000
                } else {
                    newValue >>= 1
                }
                
            case Register.regCYL.rawValue:
                newValue &= 0o77777
                if (newValue & 0o40000) != 0 {
                    newValue = (newValue << 1) + 1
                } else {
                    newValue <<= 1
                }
                
            case Register.regEDOP.rawValue:
                newValue = ((newValue & 0o77777) >> 7) & 0o177
                
            case Register.regZERO.rawValue:
                newValue = AGC_P0
                
            default:
                break
            }
        }
        
        // Apply appropriate masking rules
        let mask: Int
        if bank == 0 && offset < REG16 && !(offset >= 0o20 && offset <= 0o23) {
            mask = 0o177777
        } else {
            mask = 0o77777
        }
        
        state.erasableMemory[bank][offset] = newValue & mask
    }


    /// Request new radar data from peripherals
}
