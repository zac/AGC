import Foundation

extension AGCEngine {
    /// Convert AGC-format word to internal format
    func convertToAGCWord(_ word: Int) -> Int {
        // AGC words are 15 bits, right-aligned
        return (word >> 1) & 0o37777
    }
    
    func loadBinFile() throws {
        guard let data = state.binFile else {
            throw AGCError.invalidBinFile // File not found
        }
        
        // Must be an integral number of words
        guard data.count % 2 == 0 else {
            throw AGCError.invalidBinFile 
        }
        
        let wordCount = data.count / 2
        
        // Check if file is too large
        guard wordCount <= 36 * 0o2000 else {
            throw AGCError.invalidBinFile
        }
        
        // Reset parity checking state
        state.checkParity = false
        state.parities = Array(repeating: 0, count: state.parities.count)
        
        var bank = 2
        var offset = 0
        
        // Process each word in the binary
        for i in stride(from: 0, to: data.count, by: 2) {
            guard bank <= 35 else {
                throw AGCError.invalidBinFile
            }
            
            // Read raw 16-bit word (big endian)
            let rawWord = (Int(data[i]) << 8) | Int(data[i + 1])
            let parity = rawWord & 1
            
            // Store word and parity
            state.fixedMemory[bank][offset] = rawWord >> 1
            let parityIndex = (bank * 0o2000 + offset) / 32
            state.parities[parityIndex] |= parity << (offset % 32)
            
            // Enable parity checking if any parity bits are set
            if parity != 0 {
                state.checkParity = true
            }
            
            offset += 1
            if offset >= 0o2000 {
                offset = 0
                // Advance to next bank following original ordering: 2,3,0,1,4,5,6,...,35
                bank = switch bank {
                case 2: 3
                case 3: 0
                case 0: 1
                case 1: 4
                default: bank + 1
                }
            }
        }
    }
    
    /// Read a word from memory at the given address
    func readMemory(_ address: Int) -> Int {
        if address < 0o2000 {
            // Erasable memory
            let bank = address / ERASABLE_BANK_SIZE
            let offset = address % ERASABLE_BANK_SIZE
            return state.erasableMemory[bank][offset]
        } else {
            // Fixed memory
            let bank = (address - 0o2000) / FIXED_BANK_SIZE
            let offset = (address - 0o2000) % FIXED_BANK_SIZE
            return state.fixedMemory[bank][offset]
        }
    }
    
    /// Fetch an instruction word using AGC bank-selection rules (test hook)
    func fetchInstructionWord(at address: Int) -> Int {
        return findMemoryWord(address & 0o7777)
    }
    
    /// Write a word to memory at the given address
    func writeMemory(_ address: Int, _ value: Int) {
        if address < 0o2000 {
            // Only erasable memory is writable
            let bank = address / ERASABLE_BANK_SIZE
            let offset = address % ERASABLE_BANK_SIZE
            state.erasableMemory[bank][offset] = value & 0o37777 // Mask to 15 bits
        }
    }
    
    /// Read a word from a specific register
    func readRegister(_ register: Register) -> Int {
        return readMemory(register.rawValue)
    }

    /// Check if address is the accumulator register
    func isA(_ address: Int) -> Bool {
        return address == Register.regA.rawValue
    }
    
    /// Check if address is the L register
    func isL(_ address: Int) -> Bool {
        return address == Register.regL.rawValue
    }
    
    /// Check if address is the Q register 
    func isQ(_ address: Int) -> Bool {
        return address == Register.regQ.rawValue
    }
    
    /// Check if address is the EB register
    func isEB(_ address: Int) -> Bool {
        return address == Register.regEB.rawValue
    }
    
    /// Check if address is the Z register
    func isZ(_ address: Int) -> Bool {
        return address == Register.regZ.rawValue
    }
    
    /// Check if address matches the given register
    func isReg(_ address: Int, _ register: Register) -> Bool {
        return address == register.rawValue
    }
    
    /// Write a word to a specific register, applying editing rules via assign()
    func writeRegister(_ register: Register, _ value: Int) {
        assign(bank: 0, offset: register.rawValue, value: value)
    }

    /// Write a value to an I/O channel with special handling for certain channels
    func cpuWriteIO(address: Int, value: Int) {
        guard address >= 0 && address <= 0o777 else {
            return
        }

        var modifiedValue = value
        
        if address == 0o13 {
            // Handle HANDRUPT trap settings
            if (value & 0o4000) != 0 {
                state.trap31A = true
            }
            if (value & 0o10000) != 0 {
                state.trap31B = true  
            }
            if (value & 0o20000) != 0 {
                state.trap32 = true
            }
            
            modifiedValue &= 0o43777
        }
        
        if address == 0o33 {
            // Reset bits 11-15 to 1 for channel 33
            state.inputChannels[address] |= 0o76000
            
            // Don't allow warning reset if light still on
            if state.warningFilter > WARNING_FILTER_THRESHOLD {
                state.inputChannels[address] &= 0o57777
            }
            
            // Use existing channel value
            modifiedValue = state.inputChannels[address]
        }
        else if address == 0o77 {
            // Reset CH77 alarm codes
            modifiedValue = 0
            
            // Set night watchman bit if tripped
            if state.nightWatchmanTripped {
                modifiedValue |= CH77_NIGHT_WATCHMAN
            }
        }
        else if address == 0o11 && (value & 0o1000) != 0 {
            // Reset DSKY restart light
            state.restartLight = false
        }
        
        let storedValue = writeIO(address: address, value: modifiedValue)
        channelOutput(channel: address, value: storedValue)

        // Handle downlink timing
        if address == 0o34 {
            state.downlink |= 1
        }
        else if address == 0o35 {
            state.downlink |= 2
        }
        
        if state.downlink == 3 {
            state.downruptTimeValid = true
            state.downruptTime = state.cycleCounter + (AGC_PER_SECOND / 50)
            state.downlink = 0
        }
    }
        
    /// Execute an extended instruction based on the opcode
}
