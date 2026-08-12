import Foundation

extension AGCEngine {
    func executeExtendedInstruction(_ instruction: Int, opcode: Int, overflow: Bool) {
        // Track if we took certain branch instructions
        var justTookBZF = false
        var justTookBZMF = false
        var executedTC = false
        var tcTransient = false
        var keepExtraCode = false

        let currentBB = readRegister(.regBB)
        let currentEB = readRegister(.regEB)
        let currentFB = readRegister(.regFB)
        let opCode = opcode & 0o177
        let address12 = instruction & MASK12
        let address10 = instruction & MASK10
        let address9 = instruction & 0o777

        // Check for TCF0 transient after BZF
        if state.tookBZF && !(instruction == 0o000 && address12 == 6) {
            tcTransient = true
        }
        
        switch opCode {
        case 0...7: // TC instruction (1 MCT)
            let valueK = address12
            
            switch valueK {
            case 3: // RELINT instruction
                state.allowInterrupt = true
                if state.tookBZF || state.tookBZMF {
                    tcTransient = true
                }
                
            case 4: // INHINT instruction 
                state.allowInterrupt = false
                if state.tookBZF || state.tookBZMF {
                    tcTransient = true
                }
                
            case 6: // EXTEND instruction
                state.extraCode = true
                keepExtraCode = true
                
            default:
                if valueK != Register.regQ.rawValue { // If not RETURN
                    writeRegister(.regQ, state.nextZ & 0o177777)
                }
                backtraceAdd(tag: 0, target: address12)
                state.nextZ = address12
                executedTC = true
            }
            
        case 0o10...0o11: // CCS instruction (2 MCT)
            handleCCS(address10: address10)
            
        // Continue implementing other opcodes...
        case 0o12...0o17: // TCF instruction (1 MCT)
            performTCF(address12: address12)
            executedTC = true
            
        case 0o20...0o21: // DAS instruction (3 MCT)
            var msw: Int
            var lsw: Int
            
            if isL(address10) { // DDOUBL
                doubleRegisters()
            } else {
                let whereWord = findMemoryWord(address10)
                
                if address10 < REG16 {
                    lsw = addSP16(readRegister(.regL) & 0o177777, readRegister(Register(rawValue: address10)!) & 0o177777)
                } else {
                    lsw = addSP16(readRegister(.regL) & 0o177777, signExtend(whereWord))
                }
                
                let bottomAddress = (address10 &- 1) & 0o7777
                let bottomWord = findMemoryWord(bottomAddress)

                if address10 < REG16 + 1 {
                    msw = addSP16(state.accumulator, readRegister(Register(rawValue: address10 - 1)!) & 0o177777)
                } else {
                    msw = addSP16(state.accumulator, signExtend(bottomWord))
                }
                
                if (0o140000 & lsw) == 0o40000 {
                    msw = addSP16(msw, AGC_P1)
                } else if (0o140000 & lsw) == 0o100000 {
                    msw = addSP16(msw, signExtend(AGC_M1))
                }
                lsw = overflowCorrected(lsw)
                
                if (0o140000 & msw) == 0o100000 {
                    writeRegister(.regA, signExtend(AGC_M1))
                } else if (0o140000 & msw) == 0o40000 {
                    writeRegister(.regA, AGC_P1)
                } else {
                    writeRegister(.regA, AGC_P0)
                }
                writeRegister(.regL, AGC_P0)
                
                if address10 < REG16 {
                    writeRegister(Register(rawValue: address10)!, signExtend(lsw))
                } else {
                    assignFromPointer(address10, lsw)
                }
                
                if address10 < REG16 + 1 {
                    writeRegister(Register(rawValue: address10 - 1)!, msw)
                } else {
                    assignFromPointer(bottomAddress, overflowCorrected(msw))
                }
            }
            
        case 0o22...0o23: // LXCH instruction (2 MCT)
            performLXCH(address10: address10)
            
        case 0o24...0o25: // INCR instruction (2 MCT)
            performINCR(address10: address10)
            
        case 0o26...0o27: // ADS instruction (2 MCT)
            performADS(address10: address10)
            
        case 0o30...0o37: // CA instruction
            performCA(address12: address12)
            
        case 0o40...0o47: // CS instruction
            tcTransient = true // CS causes transients on the TC0 line
            performCS(address12: address12)
            
        case 0o50...0o51: // INDEX instruction
            performIndex(address10: address10)
            
        case 0o150...0o157: // INDEX (continued)
            if performExtracodeIndex(address12: address12) {
                keepExtraCode = true
            }
            
        case 0o52...0o53: // DXCH instruction
            tcTransient = true // DXCH causes transients on the TCF0 line
            handleDXCH(address10: address10)
            
        case 0o54...0o55: // TS instruction
            tcTransient = true // TS causes transients on the TCF0 line
            performTS(address10: address10, overflow: overflow)
            
        case 0o56...0o57: // XCH instruction
            tcTransient = true // XCH causes transients on the TCF0 line
            performXCH(address10: address10)
            
        case 0o60...0o67: // AD instruction
            performAD(address12: address12)
            
        case 0o70...0o77: // MASK instruction
            performMask(address12: address12)
            break
            
        case 0o100: // READ instruction
            performRead(address9: address9)
            break
            
        case 0o101: // WRITE instruction
            performWrite(address9: address9)
            break
            
        case 0o102: // RAND instruction
            performRand(address9: address9)
            break
            
        case 0o103: // WAND instruction
            performWand(address9: address9)
            break
            
        case 0o104: // ROR instruction
            if isL(address9) || isQ(address9) {
                writeRegister(.regA, state.accumulator | readRegister(Register(rawValue: address9)!))
            } else {
                var operand16 = overflowCorrected(state.accumulator)
                operand16 |= readIO(address: address9)
                writeRegister(.regA, signExtend(operand16))
            }
            
        case 0o105: // WOR instruction
            if isL(address9) || isQ(address9) {
                let result = state.accumulator | readRegister(Register(rawValue: address9)!)
                writeRegister(.regA, result)
                writeRegister(Register(rawValue: address9)!, result)
            } else {
                var operand16 = overflowCorrected(state.accumulator)
                operand16 |= readIO(address: address9)
                cpuWriteIO(address: address9, value: operand16)
                writeRegister(.regA, signExtend(operand16))
            }
            
        case 0o106: // RXOR instruction
            if isL(address9) || isQ(address9) {
                writeRegister(.regA, state.accumulator ^ readRegister(Register(rawValue: address9)!))
            } else {
                var operand16 = overflowCorrected(state.accumulator)
                operand16 ^= readIO(address: address9)
                writeRegister(.regA, signExtend(operand16))
            }
            
        case 0o107: // EDRUPT instruction
            // Should not be possible to get here since EDRUPT is treated as interrupt
            break
            
        case 0o110...0o111: // DV instruction
            performDV(address10: address10)
        case 0o112...0o117: // BZF instruction
            if performBZF(address12: address12) {
                justTookBZF = true
            }
            break
            
        case 0o120...0o121: // MSU instruction
            performMSU(address10: address10)
        case 0o122...0o123: // QXCH instruction
            performQXCH(address10: address10)
        case 0o124...0o125: // AUG instruction
            performAUG(address10: address10)
            
        case 0o126...0o127: // DIM instruction
            performDIM(address10: address10)
            
        case 0o130...0o137: // DCA instruction
            performDCA(address12: address12)
            
        case 0o140...0o147: // DCS instruction
            performDCS(address12: address12)
            
        case 0o160...0o161: // SU instruction
            performSU(address10: address10)
            
        case 0o162...0o167: // BZMF instruction
            if performBZMF(address12: address12) {
                justTookBZMF = true
            }
            break
        case 0o170...0o177: // MP instruction
            performMP(address12: address12)
            
        default:
            break // Unrecognized instruction
        }
        
        finalizeInstructionCycle(
            previousEB: currentEB,
            previousFB: currentFB,
            previousBB: currentBB,
            keepExtraCode: keepExtraCode,
            executedTC: executedTC,
            tcTransient: tcTransient,
            tookBZF: justTookBZF,
            tookBZMF: justTookBZMF
        )
    }

    func finalizeInstructionCycle(
        previousEB: Int,
        previousFB: Int,
        previousBB: Int,
        keepExtraCode: Bool,
        executedTC: Bool,
        tcTransient: Bool,
        tookBZF: Bool,
        tookBZMF: Bool
    ) {
        guard !state.pendFlag else { return }

        writeRegister(.regZERO, AGC_P0)
        state.inputChannels[7] = state.outputChannel7 & 0o160
        writeRegister(.regZ, state.nextZ)

        // In all cases except for RESUME, Z will be truncated to 12 bits between instructions.
        if !state.substituteInstruction {
            writeRegister(.regZ, readRegister(.regZ) & 0o7777)
        }

        if !keepExtraCode {
            state.extraCode = false
        }

        // Values written to EB and FB are automatically mirrored to BB, and vice versa.
        if previousBB != readRegister(.regBB) {
            writeRegister(.regFB, readRegister(.regBB) & 0o76000)
            writeRegister(.regEB, (readRegister(.regBB) & 0o7) << 8)
        } else if previousEB != readRegister(.regEB) || previousFB != readRegister(.regFB) {
            writeRegister(.regBB, (readRegister(.regFB) & 0o76000) | ((readRegister(.regEB) & 0o3400) >> 8))
        }

        writeRegister(.regEB, readRegister(.regEB) & 0o3400)
        writeRegister(.regFB, readRegister(.regFB) & 0o76000)
        writeRegister(.regBB, readRegister(.regBB) & 0o76007)

        // Correct overflow in the L register.
        writeRegister(.regL, signExtend(overflowCorrected(readRegister(.regL))))

        // Check ISR status and clear Rupt Lock flags accordingly.
        if state.inIsr {
            state.noRupt = false
        } else {
            state.ruptLock = false
        }

        // Update TC Trap flags according to the instruction we just executed.
        if executedTC || tcTransient {
            state.noTC = false
        }
        if !executedTC {
            state.tcTrap = false
        }

        state.tookBZF = tookBZF
        state.tookBZMF = tookBZMF
    }
    
    // Helper functions for MP instruction
    func calculateMultiplyResult(_ operand1: Int, _ operand2: Int) -> (msWord: Int, lsWord: Int) {
        if operand2 == AGC_P0 || operand2 == AGC_M0 {
            return (AGC_P0, AGC_P0)
        }
        
        if operand1 == AGC_P0 || operand1 == AGC_M0 {
            if (operand1 == AGC_P0 && (0o40000 & operand2) != 0) ||
               (operand1 == AGC_M0 && (0o40000 & operand2) == 0) {
                return (AGC_M0, AGC_M0)
            } else {
                return (AGC_P0, AGC_P0)
            }
        }
        
        let product = agc2cpu(signExtend(operand1)) * agc2cpu(signExtend(operand2))
        let agcProduct = cpu2agc2(product)
        
        // Convert to double precision
        let wordPair = decentToSp(agcProduct)
        return (wordPair.0, wordPair.1)
    }
    
    /// Get the number of extra machine cycles needed for an instruction
    func getInstructionTiming(instruction: Int, isExtracode: Bool) -> Int {
        // Get the upper 5 bits of the instruction
        let index = (instruction >> 10) & 0o37
        
        // Add special handling for EDRUPT and BZF/BZMF
        if isExtracode {
            // EDRUPT needs special handling
            if (instruction & 0o7777) == 0o1704 {
                return 2  // EDRUPT timing
            }
            return extracodeTiming[Int(index)]
        } else {
            // BZF/BZMF need special handling
            if (instruction & 0o7000) == 0o6000 && (instruction & 0o1400) != 0 {
                return 1  // BZF/BZMF timing
            }
            return instructionTiming[Int(index)]
        }
    }
    
    /// Execute one simulation cycle
    func executeCycle() -> Bool {
        var overflow: Bool = false

        // For DOWNRUPT
        if state.downruptTimeValid && state.cycleCounter >= state.downruptTime {
            state.interruptRequests[8] = 1  // Request DOWNRUPT
            state.downruptTimeValid = false
        }
        
        // The first time through the loop, light up the DSKY RESTART light
        if state.cycleCounter == 0 {
            state.restartLight = true
        }
        
        state.cycleCounter += 1
        
        // Update the timer that determines when 1/1600 second has passed.
        // 1/1600 is the basic timing used to drive timer registers.
        // 1/1600 second is 160/3 machine cycles.
        let SCALER_DIVIDER = 3
        state.scalerCounter += SCALER_DIVIDER
        state.dskyTimer += SCALER_DIVIDER
        
        // Handle I/O channel communications periodically (nominally every 100ms)
        if state.channelRoutineCount == 0 {
            ioDelegate?.channelRoutine()
        }
        state.channelRoutineCount = (state.channelRoutineCount + 1) & 0o17777
        
        // Update the various hardware-driven DSKY lights
        updateDSKY()
        
        // Get data from input channels
        // Return immediately if an unprogrammed counter-increment was performed
        if channelInput() {
            return false
        }
        
        // Handle extra CPU cycles used by some instructions
        
        // Extra delay needed sometimes after branch instructions
        if state.extraDelay > 0 {
            state.extraDelay -= 1
            return false
        }
        
        // If a multi-cycle instruction is in progress, wait until last cycle
        if state.pendFlag && state.pendDelay > 0 {
            state.pendDelay -= 1
            return false
        }

        if serviceCduFifo() {
            return false
        }
        
        // Handle standby button state
        if (state.inputChannels[0o32] & 0o20000) != 0 {
            state.sbyPressed = false
            state.sbyStillPressed = false
        }
        
        // Handle counter-timers
        while state.scalerCounter >= SCALER_OVERFLOW {
            var triggeredAlarm = false
            
            // Update SCALER1 and SCALER2
            state.scalerCounter -= SCALER_OVERFLOW
            state.inputChannels[ChanSCALER1] += 1
            if state.inputChannels[ChanSCALER1] == 0o40000 {
                state.inputChannels[ChanSCALER1] = 0
                state.inputChannels[ChanSCALER2] = (state.inputChannels[ChanSCALER2] + 1) & 0o37777
            }
            
            // Check alarms first
            if (0o4000 == (0o7777 & state.inputChannels[ChanSCALER1])) {
                // Night Watchman check (1.28s)
                if !state.standby {
                    state.nightWatchman = 1
                }
                
                // Standby circuit check
                if state.sbyPressed && ((state.inputChannels[0o13] & 0o2000) != 0 || state.standby) {
                    if !state.standby {
                        // Enter standby mode
                        state.standby = true
                        state.sbyStillPressed = true
                        triggeredAlarm = true
                        
                        // Update DSKY lights
                        var flags = DSKYFlags(rawValue: state.dskyChannel163)
                        flags.insert([.standby])
                        flags.insert(.elOff)  // Need to add this to DSKYFlags
                        state.dskyChannel163 = flags.rawValue
                        channelOutput(channel: 0o163, value: state.dskyChannel163)
                    } else if !state.sbyStillPressed {
                        // Exit standby mode
                        state.standby = false
                        
                        // Update DSKY lights
                        var flags = DSKYFlags(rawValue: state.dskyChannel163)
                        flags.remove([.standby, .elOff])
                        state.dskyChannel163 = flags.rawValue
                        channelOutput(channel: 0o163, value: state.dskyChannel163)
                    }
                }
            } else if (0o0000 == (0o7777 & state.inputChannels[ChanSCALER1])) {
                // Check standby button state
                if (state.inputChannels[0o32] & 0o20000) == 0 {
                    state.sbyPressed = true
                }
                
                // Night Watchman completion
                if !state.standby && state.nightWatchman != 0 {
                    triggeredAlarm = true
                    state.inputChannels[0o77] |= CH77_NIGHT_WATCHMAN
                    state.nightWatchmanTripped = true
                } else {
                    state.nightWatchmanTripped = false
                }
            }
            
            // Warning filter updates (every 160ms)
            if (0o00 == (0o07 & state.inputChannels[ChanSCALER1])) {
                if (0o400 == (0o777 & state.inputChannels[ChanSCALER1])) &&
                    (state.generatedWarning || (state.inputChannels[0o13] & 0o1000) != 0) {
                    state.generatedWarning = false
                    state.warningFilter += WARNING_FILTER_INCREMENT
                    if state.warningFilter > WARNING_FILTER_MAX {
                        state.warningFilter = WARNING_FILTER_MAX
                    }
                } else {
                    if state.warningFilter >= WARNING_FILTER_DECREMENT {
                        state.warningFilter -= WARNING_FILTER_DECREMENT
                    } else {
                        state.warningFilter = 0
                    }
                }
            }
            
            // Skip timer updates during standby
            if !state.standby {
                if 0o400 == (0o777 & state.inputChannels[ChanSCALER1]) {
                    // Rupt Lock alarm monitoring (starts every 160ms)
                    state.ruptLock = true
                    state.noRupt = true
                } else if (state.ruptLock || state.noRupt) && 
                          0o300 == (0o777 & state.inputChannels[ChanSCALER1]) {
                    // Alarm after 140ms of no interrupts or stuck in interrupt
                    triggeredAlarm = true
                    state.inputChannels[0o77] |= CH77_RUPT_LOCK
                }
                
                if 0o020 == (0o037 & state.inputChannels[ChanSCALER1]) {
                    // TC Trap alarm monitoring (every 5ms)
                    state.tcTrap = true
                    state.noTC = true
                } else if (state.tcTrap || state.noTC) && 
                          0o000 == (0o037 & state.inputChannels[ChanSCALER1]) {
                    // Alarm after 5ms of only/no TC instructions
                    triggeredAlarm = true
                    state.inputChannels[0o77] |= CH77_TC_TRAP
                }
                
                // Timer updates
                if 0o020 == (0o037 & state.inputChannels[ChanSCALER1]) {
                    state.extraDelay += 1
                    
                    // Update TIME1 and TIME2
                    if counterPINC(register: .regTIME1) {
                        state.extraDelay += 1
                        _ = counterPINC(register: .regTIME2)
                    }
                    
                    state.extraDelay += 1
                    if counterPINC(register: .regTIME3) {
                        state.interruptRequests[3] = 1
                    }
                }
                
                // TIME5 (5ms out of phase with TIME3)
                if 0o000 == (0o037 & state.inputChannels[ChanSCALER1]) {
                    state.extraDelay += 1
                    if counterPINC(register: .regTIME5) {
                        state.interruptRequests[2] = 1
                    }
                    
                    // Update radar gate counter if enabled
                    if (state.inputChannels[0o13] & 0o10) != 0 {
                        state.radarGateCounter += 1
                    }
                }
                
                // TIME4 (7.5ms out of phase with TIME3)
                if 0o010 == (0o037 & state.inputChannels[ChanSCALER1]) {
                    state.extraDelay += 1
                    if counterPINC(register: .regTIME4) {
                        state.interruptRequests[4] = 1
                    }
                }
                
                // TIME6 (increments 0.3125ms after TIME1/TIME3 if enabled)
                if (state.inputChannels[0o13] & 0o40000) != 0 && 
                   (state.inputChannels[ChanSCALER1] & 0o1) == 0o1 {
                    state.extraDelay += 1
                    if counterDINC(register: .regTIME6, counterNumber: 0) {
                        state.interruptRequests[1] = 1
                        // Disable T6 by clearing CH13 bit
                        cpuWriteIO(address: 0o13, value: state.inputChannels[0o13] & 0o37777)
                    }
                }
            }
            
            // Check for HANDRUPT conditions
            if state.trap31A && ((state.inputChannels[0o31] & 0o000077) != 0o000077) {
                state.trap31A = false
                state.interruptRequests[10] = 1
            }

            if state.trap31B && ((state.inputChannels[0o31] & 0o007700) != 0o007700) {
                state.trap31B = false
                state.interruptRequests[10] = 1
            }

            if state.trap32 && ((state.inputChannels[0o32] & 0o001777) != 0o001777) {
                state.trap32 = false
                state.interruptRequests[10] = 1
            }

            // Check for radar cycle completion
            if (state.radarGateCounter == 9) &&
                (0o36 == (0o37 & state.inputChannels[ChanSCALER1])) {
                completeRadarSampleGate()
            }
            
            // Handle triggered alarms
            if triggeredAlarm || state.parityFail {
                // Simulate GOJAM sequence
                
                // Two single-MCT instruction sequences
                state.extraDelay += 2
                
                // Store current Z in Q, set Z to 4000
                writeRegister(.regQ, readRegister(.regZ))
                writeRegister(.regZ, 0o4000)
                
                // Clear interrupt state
                state.inIsr = false
                state.allowInterrupt = true
                state.parityFail = false
                
                // Disable HANDRUPT traps
                state.trap31A = false
                state.trap31B = false
                state.trap32 = false
                
                // Clear all interrupt requests
                for i in 1...10 {  // NUM_INTERRUPT_TYPES
                    state.interruptRequests[i] = 0
                }
                
                // Clear I/O channels
                for channel in [0o5, 0o6, 0o10, 0o11, 0o12, 0o13, 0o14] {
                    cpuWriteIO(address: channel, value: 0)
                }
                
                // Clear UPLINK TOO FAST bit in channel 33
                state.inputChannels[0o33] |= 0o2000
                
                // Clear channels 34 and 35 without generating downrupt
                cpuWriteIO(address: 0o34, value: 0)
                cpuWriteIO(address: 0o35, value: 0)
                state.downruptTimeValid = false
                
                // Clear internal state
                state.indexValue = 0  // AGC_P0
                state.extraCode = false
                state.substituteInstruction = false
                state.pendFlag = false
                state.pendDelay = 0
                state.tookBZF = false
                state.tookBZMF = false
                
                // Light RESTART if not in standby
                if !state.standby {
                    state.restartLight = true
                    state.generatedWarning = true
                }
                
                // Push CH77 updates
                channelOutput(channel: 0o77, value: state.inputChannels[0o77])
            }

            // Handle extra delay
            if state.extraDelay > 0 {
                state.extraDelay -= 1
                return false
            }
        }
        
        // If we're in standby mode, this is all we can accomplish --
        // everything else is switched off.
        if state.standby {
            return false
        }
        
        // Process gyro bursts
        if gyroTiming.processBurst(state: state) {
            // If gyro output occurred, notify I/O delegate
            channelOutput(channel: 0o177, value: state.outputChannels[0o177])
        }

        // After updating cycle counter:
        if imuTiming.shouldEmitBurst(state: state, currentCycle: state.cycleCounter) {
            cpuWriteIO(address: 0o14, value: imuTiming.channel14)
        }

        // Handle optics shaft & trunnion CDUs
        // Simple direct output of counter values
        if state.erasableMemory[0][Register.regOPTX.rawValue] != 0 && 
           (state.inputChannels[0o14] & 0o2000) != 0 {
            channelOutput(channel: 0o172, 
                         value: state.erasableMemory[0][Register.regOPTX.rawValue])
            state.erasableMemory[0][Register.regOPTX.rawValue] = 0
        }

        if state.erasableMemory[0][Register.regOPTY.rawValue] != 0 && 
           (state.inputChannels[0o14] & 0o4000) != 0 {
            channelOutput(channel: 0o171, 
                         value: state.erasableMemory[0][Register.regOPTY.rawValue])
            state.erasableMemory[0][Register.regOPTY.rawValue] = 0
        }

        // Instruction decoding setup

        // Reform 16-bit accumulator and check for overflow
        let accumulator = readRegister(.regA) & 0o177777
        state.accumulator = accumulator
        overflow = valueOverflowed(accumulator) != 0

        // Get program counter from Z register (12 bits)
        let programCounter = readRegister(.regZ) & 0o7777

        // Fetch the instruction
        var instruction: Int
        if state.substituteInstruction {
            instruction = readRegister(.regBRUPT)
        } else {
            // Handle indexed instructions using full AGC bank mapping
            let baseInstruction = fetchInstructionWord(at: programCounter)
            instruction = applyIndex(to: baseInstruction)
        }
        instruction &= 0o77777

        let isExtracode = state.extraCode
        let currentBB = readRegister(.regBB)
        let currentEB = readRegister(.regEB)
        let currentFB = readRegister(.regFB)

        // Parse instruction components
        let extendedOpcode = (instruction >> 9) | (isExtracode ? 0o100 : 0)
        let quarterCode = instruction & ~MASK10

        // Handle interrupts
        let canInterrupt = (!state.inIsr && state.allowInterrupt && 
                           !state.extraCode && !state.pendFlag && !overflow && 
                           instruction != 3 && instruction != 4 && instruction != 6) ||
                           extendedOpcode == 0o107  // Always check for EDRUPT

        if canInterrupt {
            var interruptRequested = false
            var interruptVector = 0
            
            // Search for next interrupt request in priority order
            for i in 1...10 {  // NUM_INTERRUPT_TYPES
                if state.interruptRequests[i] != 0 && debuggerInterruptMasks[i] != 0 {
                    // Clear the interrupt request
                    state.interruptRequests[i] = 0
                    state.interruptRequests[0] = i
                    
                    state.nextZ = 0o4000 + 4 * i
                    
                    interruptRequested = true
                    interruptVector = i
                    break
                }
            }
            
            // Handle EDRUPT fallback to vector 0
            if !interruptRequested && extendedOpcode == 0o107 {
                state.nextZ = 0
                interruptRequested = true
                interruptVector = 0
            }
            
            if interruptRequested {
                backtraceAdd(tag: interruptVector, target: state.nextZ)
                // Set up return state
                writeRegister(.regZRUPT, programCounter + 1)
                writeRegister(.regBRUPT, instruction)
                
                // Clear metadata
                state.extraCode = false
                state.indexValue = AGC_P0
                state.substituteInstruction = false
                
                // Vector to interrupt
                state.inIsr = true
                state.extraDelay += 1
                finalizeInstructionCycle(
                    previousEB: currentEB,
                    previousFB: currentFB,
                    previousBB: currentBB,
                    keepExtraCode: false,
                    executedTC: false,
                    tcTransient: false,
                    tookBZF: false,
                    tookBZMF: false
                )
                return false
            }
        }

        // Handle multi-MCT instruction timing
        // (except for EDRUPT, BZF, and BZMF)
        if !state.pendFlag {
            let timingIndex = quarterCode >> 10
            let extraCycles = if state.extraCode {
                extracodeTiming[timingIndex]
            } else {
                instructionTiming[timingIndex]
            }
            
            if extraCycles > 0 {
                state.pendFlag = true
                state.pendDelay = extraCycles - 1
                return false
            }
        } else {
            state.pendFlag = false
        }

        // Clear index value and substitute instruction
        state.indexValue = 0  // AGC_P0
        state.substituteInstruction = false

        // Update program counter (Z register)
        // Only lower 12 bits are used in most cases
        state.nextZ = 1 + readRegister(.regZ)
        writeRegister(.regZ, state.nextZ)

        // Execute the instruction
        executeExtendedInstruction(instruction, opcode: extendedOpcode, overflow: overflow)

        // Continue with instruction execution
        return true
    }
}
