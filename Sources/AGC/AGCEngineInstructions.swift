import Foundation

extension AGCEngine {
    /// Handle CCS instruction logic
    func handleCCS(address10: Int) {
        var operand16: Int
        var valueK: Int = 0

        if address10 < REG16 {
            valueK = readRegister(Register(rawValue: address10)!) & 0o177777
            operand16 = overflowCorrected(valueK)
            writeRegister(.regA, odabs(valueK))
        } else {
            let whereWord = findMemoryWord(address10)
            operand16 = whereWord & 0o77777
            writeRegister(.regA, dabs(operand16))
            assignFromPointer(address10, operand16)
        }
        
        if address10 < REG16 && valueOverflowed(valueK) == 1 {
            // No change
        } else if address10 < REG16 && valueOverflowed(valueK) == -1 {
            state.nextZ += 2
        } else if operand16 == AGC_P0 {
            state.nextZ += 1
        } else if operand16 == AGC_M0 {
            state.nextZ += 3
        } else if (operand16 & 0o40000) != 0 {
            state.nextZ += 2
        }
    }
    
    /// Handle DDOUBL behavior of DAS instruction
    func doubleRegisters() {
        var lsw = addSP16(readRegister(.regL) & 0o177777, readRegister(.regL) & 0o177777)
        var msw = addSP16(state.accumulator, state.accumulator)
        
        if (0o140000 & lsw) == 0o40000 {
            msw = addSP16(msw, AGC_P1)
        } else if (0o140000 & lsw) == 0o100000 {
            msw = addSP16(msw, signExtend(AGC_M1))
        }
        lsw = overflowCorrected(lsw)
        writeRegister(.regA, msw & 0o177777)
        writeRegister(.regL, signExtend(lsw) & 0o177777)
    }
    
    /// Handle DXCH swaps
    func handleDXCH(address10: Int) {
        if isL(address10) {
            writeRegister(.regL, signExtend(overflowCorrected(readRegister(.regL))))
            return
        }
        
        let liveWord = findMemoryWord(address10)
        
        if address10 < REG16 {
            let operand16 = readRegister(Register(rawValue: address10)!)
            writeRegister(Register(rawValue: address10)!, readRegister(.regL))
            writeRegister(.regL, operand16)
            
            if address10 == Register.regZ.rawValue {
                state.nextZ = readRegister(.regZ)
            }
        } else {
            let operand16 = signExtend(liveWord)
            assignFromPointer(address10, overflowCorrected(readRegister(.regL)))
            writeRegister(.regL, operand16)
        }
        
        writeRegister(.regL, signExtend(overflowCorrected(readRegister(.regL))))
        
        let bottomAddress = (address10 &- 1) & 0o7777
        
        if address10 < REG16 + 1 {
            let operand16 = readRegister(Register(rawValue: bottomAddress)!)
            writeRegister(Register(rawValue: bottomAddress)!, readRegister(.regA))
            writeRegister(.regA, operand16)
            
            if address10 == Register.regZ.rawValue + 1 {
                state.nextZ = readRegister(.regZ)
            }
        } else {
            let lowerWord = findMemoryWord(bottomAddress)
            let operand16 = signExtend(lowerWord)
            assignFromPointer(bottomAddress, overflowCorrected(readRegister(.regA)))
            writeRegister(.regA, operand16)
        }
    }

    func performResume() {
        state.nextZ = (readRegister(.regZRUPT) - 1) & 0o177777
        let tag = state.inIsr ? 255 : 0
        backtraceAdd(tag: tag, target: state.nextZ)
        state.inIsr = false
        state.substituteInstruction = true
    }

    func performMask(address12: Int) {
        if address12 < REG16 {
            writeRegister(.regA, state.accumulator & readRegister(Register(rawValue: address12)!))
        } else {
            writeRegister(.regA, overflowCorrected(state.accumulator))
            let whereWord = findMemoryWord(address12)
            writeRegister(.regA, signExtend(readRegister(.regA) & whereWord))
        }
    }

    func performTCF(address12: Int) {
        backtraceAdd(tag: 0, target: address12)
        state.nextZ = address12
    }

    func applyIndex(to baseInstruction: Int) -> Int {
        return overflowCorrected(
            addSP16(signExtend(state.indexValue),
                    signExtend(baseInstruction))
        )
    }

    func performRead(address9: Int) {
        if isL(address9) || isQ(address9) {
            writeRegister(.regA, readRegister(Register(rawValue: address9)!))
        } else {
            writeRegister(.regA, signExtend(readIO(address: address9)))
        }
    }

    func performWrite(address9: Int) {
        if isL(address9) || isQ(address9) {
            writeRegister(Register(rawValue: address9)!, state.accumulator)
        } else {
            cpuWriteIO(address: address9, value: overflowCorrected(state.accumulator))
        }
    }

    func performRand(address9: Int) {
        if isL(address9) || isQ(address9) {
            writeRegister(.regA, state.accumulator & readRegister(Register(rawValue: address9)!))
        } else {
            var operand16 = overflowCorrected(state.accumulator)
            operand16 &= readIO(address: address9)
            writeRegister(.regA, signExtend(operand16))
        }
    }

    func performWand(address9: Int) {
        if isL(address9) || isQ(address9) {
            let result = state.accumulator & readRegister(Register(rawValue: address9)!)
            writeRegister(.regA, result)
            writeRegister(Register(rawValue: address9)!, result)
        } else {
            var operand16 = overflowCorrected(state.accumulator)
            operand16 &= readIO(address: address9)
            cpuWriteIO(address: address9, value: operand16)
            writeRegister(.regA, signExtend(operand16))
        }
    }

    func performLXCH(address10: Int) {
        if isL(address10) {
            return
        }

        if isReg(address10, .regZERO) {
            writeRegister(.regL, AGC_P0)
            return
        }

        if address10 < REG16 {
            let operand16 = readRegister(.regL)
            writeRegister(.regL, readRegister(Register(rawValue: address10)!))

            if address10 >= 0o20 && address10 <= 0o23 {
                assignFromPointer(address10, overflowCorrected(operand16 & 0o177777))
            } else {
                writeRegister(Register(rawValue: address10)!, operand16)
            }

            if address10 == Register.regZ.rawValue {
                state.nextZ = readRegister(.regZ)
            }
        } else {
            let whereWord = findMemoryWord(address10)
            let operand16 = overflowCorrected(readRegister(.regL) & 0o177777)
            assignFromPointer(address10, operand16)
            writeRegister(.regL, signExtend(whereWord))
        }
    }

    func performINCR(address10: Int) {
        let whereWord = findMemoryWord(address10)

        if address10 < REG16 {
            let current = readRegister(Register(rawValue: address10)!) & 0o177777
            writeRegister(Register(rawValue: address10)!, addSP16(AGC_P1, current))
        } else {
            let sum = addSP16(AGC_P1, signExtend(whereWord))
            assignFromPointer(address10, overflowCorrected(sum))
            interruptRequests(address10, sum)
        }
    }

    func performADS(address10: Int) {
        if isA(address10) {
            state.accumulator = addSP16(state.accumulator, state.accumulator)
        } else if address10 < REG16 {
            let operand = readRegister(Register(rawValue: address10)!) & 0o177777
            state.accumulator = addSP16(state.accumulator, operand)
            writeRegister(Register(rawValue: address10)!, state.accumulator)
        } else {
            let whereWord = findMemoryWord(address10)
            state.accumulator = addSP16(state.accumulator, signExtend(whereWord))
            assignFromPointer(address10, overflowCorrected(state.accumulator))
        }
        writeRegister(.regA, state.accumulator)
    }

    func performCA(address12: Int) {
        if isA(address12) {
            return
        }

        if address12 < REG16 {
            writeRegister(.regA, readRegister(Register(rawValue: address12)!))
            return
        }

        let whereWord = findMemoryWord(address12)
        writeRegister(.regA, signExtend(whereWord))
        assignFromPointer(address12, whereWord)
    }

    func performCS(address12: Int) {
        if isA(address12) {
            writeRegister(.regA, ~state.accumulator)
            return
        }

        if address12 < REG16 {
            writeRegister(.regA, ~readRegister(Register(rawValue: address12)!))
            return
        }

        let whereWord = findMemoryWord(address12)
        writeRegister(.regA, signExtend(negateSP(whereWord)))
        assignFromPointer(address12, whereWord)
    }

    func performTS(address10: Int, overflow: Bool) {
        if isA(address10) {
            if overflow {
                state.nextZ += AGC_P1
            }
            return
        }

        if isZ(address10) {
            state.nextZ = state.accumulator & 0o77777
            if overflow {
                writeRegister(.regA, signExtend(valueOverflowed(state.accumulator)))
            }
            return
        }

        _ = findMemoryWord(address10)

        if address10 < REG16 {
            writeRegister(Register(rawValue: address10)!, state.accumulator)
        } else {
            assignFromPointer(address10, overflowCorrected(state.accumulator))
        }

        if address10 == Register.regZ.rawValue {
            state.nextZ = readRegister(.regZ)
        }

        if overflow {
            writeRegister(.regA, signExtend(valueOverflowed(state.accumulator)))
            state.nextZ += AGC_P1
        }
    }

    func performIndex(address10: Int) {
        if address10 == 0o17 {
            performResume()
            return
        }
        loadIndexValue(address: address10)
    }

    func performExtracodeIndex(address12: Int) -> Bool {
        if address12 == (0o17 << 1) {
            performResume()
            return false
        }
        loadIndexValue(address: address12)
        return true
    }

    func loadIndexValue(address: Int) {
        if address < REG16 {
            state.indexValue = overflowCorrected(readRegister(Register(rawValue: address)!) & 0o177777)
        } else {
            state.indexValue = findMemoryWord(address)
        }
    }

    func performXCH(address10: Int) {
        if isA(address10) {
            return
        }

        if address10 < REG16 {
            writeRegister(.regA, readRegister(Register(rawValue: address10)!))
            writeRegister(Register(rawValue: address10)!, state.accumulator)

            if address10 == Register.regZ.rawValue {
                state.nextZ = readRegister(.regZ)
            }
            return
        }

        let whereWord = findMemoryWord(address10)
        writeRegister(.regA, signExtend(whereWord))
        assignFromPointer(address10, overflowCorrected(state.accumulator))
    }

    func performAD(address12: Int) {
        if isA(address12) {
            state.accumulator = addSP16(state.accumulator, state.accumulator)
        } else if address12 < REG16 {
            let operand = readRegister(Register(rawValue: address12)!) & 0o177777
            state.accumulator = addSP16(state.accumulator, operand)
        } else {
            let whereWord = findMemoryWord(address12)
            state.accumulator = addSP16(state.accumulator, signExtend(whereWord))
            assignFromPointer(address12, whereWord)
        }
        writeRegister(.regA, state.accumulator)
    }

    func performBZF(address12: Int) -> Bool {
        if state.accumulator == 0 || state.accumulator == 0o177777 {
            state.nextZ = address12
            backtraceAdd(tag: 0, target: address12)
            return true
        }
        return false
    }

    func performBZMF(address12: Int) -> Bool {
        if state.accumulator == 0 || (state.accumulator & 0o100000) != 0 {
            state.nextZ = address12
            backtraceAdd(tag: 0, target: address12)
            return true
        }
        return false
    }

    func performDV(address10: Int) {
        let accMSW = overflowCorrected(state.accumulator)
        let accLSW = readRegister(.regL) & 0o177777
        let dividend = spToDecent(msw: accMSW, lsw: accLSW)

        let absA = absSP(accMSW)
        let absL = absSP(accLSW)

        var div16: Int
        if isA(address10) {
            div16 = readRegister(.regA)
            if (readRegister(.regA) & 0o100000) == 0 {
                div16 = 0o177777 & ~div16
            }
        } else if isL(address10) {
            div16 = readRegister(.regL)
            if ((absA == 0 && (0o100000 & readRegister(.regL)) != 0) ||
                (absA != 0 && (0o100000 & readRegister(.regA)) != 0)) {
                div16 = 0o177777 & ~div16
            }
            div16 = signExtend(overflowCorrected(addSP16(div16, 0o40000)))
        } else if isZ(address10) {
            div16 = readRegister(.regZ)
            if ((absA == 0 && (0o100000 & readRegister(.regL)) != 0) ||
                (absA != 0 && (0o100000 & readRegister(.regA)) != 0)) {
                div16 |= 0o100000
            }
        } else if address10 < REG16 {
            div16 = readRegister(Register(rawValue: address10)!)
        } else {
            div16 = signExtend(findMemoryWord(address10))
        }

        let absK = absSP(overflowCorrected(div16))

        if absA > absK || (absA == absK && absL != AGC_P0) ||
            valueOverflowed(div16) != AGC_P0 {
            simulateDV(div16)
        } else if absA == 0 && absL == 0 {
            let operand16: Int
            if (0o40000 & accLSW) == (0o40000 & overflowCorrected(div16)) {
                operand16 = absK == 0 ? 0o37777 : AGC_P0
            } else {
                operand16 = absK == 0 ? (0o77777 & ~0o37777) : AGC_M0
            }
            writeRegister(.regA, signExtend(operand16))
        } else if absA == absK && absL == AGC_P0 {
            let operand16 = accMSW == overflowCorrected(div16) ?
                0o37777 : (0o77777 & ~0o37777)
            writeRegister(.regL, signExtend(accMSW))
            writeRegister(.regA, signExtend(operand16))
        } else {
            let dividendCPU = agc2cpu2(dividend)
            let divisorCPU = agc2cpu(overflowCorrected(div16))
            let quotient = dividendCPU / divisorCPU
            let remainder = dividendCPU % divisorCPU

            writeRegister(.regA, signExtend(cpu2agc(quotient)))

            if remainder == 0 {
                writeRegister(.regL, dividendCPU >= 0 ? AGC_P0 : signExtend(AGC_M0))
            } else {
                writeRegister(.regL, signExtend(cpu2agc(remainder)))
            }
        }
    }

    func performQXCH(address10: Int) {
        if isQ(address10) {
            return
        }

        if isReg(address10, .regZERO) {
            writeRegister(.regQ, AGC_P0)
        } else if address10 < REG16 {
            let operand16 = readRegister(.regQ)
            writeRegister(.regQ, readRegister(Register(rawValue: address10)!))
            writeRegister(Register(rawValue: address10)!, operand16)

            if address10 == Register.regZ.rawValue {
                state.nextZ = readRegister(.regZ)
            }
        } else {
            let whereWord = findMemoryWord(address10)
            let operand16 = overflowCorrected(readRegister(.regQ))
            writeRegister(.regQ, signExtend(whereWord))
            assignFromPointer(address10, operand16)
        }
    }

    func performMSU(address10: Int) {
        let whereWord = findMemoryWord(address10)
        let ui: Int
        let uj: Int
        if address10 < REG16 {
            ui = 0o177777 & state.accumulator
            uj = 0o177777 & ~readRegister(Register(rawValue: address10)!)
        } else {
            ui = 0o77777 & overflowCorrected(state.accumulator)
            uj = 0o77777 & ~whereWord
        }
        var diff = ui + uj + 1

        if (diff & 0o40000) != 0 {
            diff |= 0o100000
            diff -= 1
        }

        if isQ(address10) {
            writeRegister(.regA, diff & 0o177777)
        } else {
            writeRegister(.regA, signExtend(diff & 0o77777))
        }

        if address10 >= 0o20 && address10 <= 0o23 {
            assignFromPointer(address10, whereWord)
        }
    }

    func performAUG(address10: Int) {
        let whereWord = findMemoryWord(address10)
        var operand = address10 < REG16 ?
            readRegister(Register(rawValue: address10)!) :
            signExtend(whereWord)

        operand &= 0o177777
        let increment = (operand & 0o100000) == 0 ? AGC_P1 : signExtend(AGC_M1)
        let sum = addSP16(increment & 0o177777, operand)

        if address10 < REG16 {
            writeRegister(Register(rawValue: address10)!, sum)
        } else {
            assignFromPointer(address10, overflowCorrected(sum))
            interruptRequests(address10, sum)
        }
    }

    func performDIM(address10: Int) {
        let whereWord = findMemoryWord(address10)
        var operand = address10 < REG16 ?
            readRegister(Register(rawValue: address10)!) :
            signExtend(whereWord)

        operand &= 0o177777
        if operand == AGC_P0 || operand == signExtend(AGC_M0) {
            return
        }

        let increment = (operand & 0o100000) == 0 ? signExtend(AGC_M1) : AGC_P1
        let sum = addSP16(increment & 0o177777, operand)

        if address10 < REG16 {
            writeRegister(Register(rawValue: address10)!, sum)
        } else {
            assignFromPointer(address10, overflowCorrected(sum))
        }
    }

    func performRor(address9: Int) {
        if isL(address9) || isQ(address9) {
            writeRegister(.regA, state.accumulator | readRegister(Register(rawValue: address9)!))
        } else {
            var operand16 = overflowCorrected(state.accumulator)
            operand16 |= readIO(address: address9)
            writeRegister(.regA, signExtend(operand16))
        }
    }

    func performWor(address9: Int) {
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
    }

    func performRxor(address9: Int) {
        if isL(address9) || isQ(address9) {
            writeRegister(.regA, state.accumulator ^ readRegister(Register(rawValue: address9)!))
        } else {
            var operand16 = overflowCorrected(state.accumulator)
            operand16 ^= readIO(address: address9)
            writeRegister(.regA, signExtend(operand16))
        }
    }

    func performDCA(address12: Int) {
        if isL(address12) {
            writeRegister(.regL, signExtend(overflowCorrected(readRegister(.regL))))
            return
        }

        let topOriginal = readRawWord(address12)
        let topSigned = signExtend(topOriginal)
        writeRegister(.regL, signExtend(overflowCorrected(topSigned)))

        let bottomAddress = (address12 &- 1) & 0o7777
        let bottomOriginal = readRawWord(bottomAddress)
        writeRegister(.regA, signExtend(bottomOriginal))

        if address12 >= 0o20 && address12 <= 0o23 {
            assignFromPointer(address12, topOriginal)
        }
        if bottomAddress >= 0o21 && bottomAddress <= 0o24 {
            assignFromPointer(bottomAddress, bottomOriginal)
        }
    }

    func performDCS(address12: Int) {
        if isL(address12) {
            writeRegister(.regA, ~state.accumulator)
            let complementedL = (~readRegister(.regL)) & 0o177777
            writeRegister(.regL, signExtend(overflowCorrected(complementedL)))
            return
        }

        let topOriginal = readRawWord(address12)
        let topSigned = signExtend(topOriginal)
        let complementedTop = (~topSigned) & 0o177777
        writeRegister(.regL, signExtend(overflowCorrected(complementedTop)))

        let bottomAddress = (address12 &- 1) & 0o7777
        let bottomOriginal = readRawWord(bottomAddress)
        let bottomSigned = signExtend(bottomOriginal)
        let complementedBottom = (~bottomSigned) & 0o177777
        writeRegister(.regA, signExtend(complementedBottom))

        if address12 >= 0o20 && address12 <= 0o23 {
            assignFromPointer(address12, topOriginal)
        }
        if bottomAddress >= 0o21 && bottomAddress <= 0o24 {
            assignFromPointer(bottomAddress, bottomOriginal)
        }
    }

    func performSU(address10: Int) {
        if isA(address10) {
            state.accumulator = signExtend(AGC_M0)
        } else if address10 < REG16 {
            let operand = readRegister(Register(rawValue: address10)!)
            state.accumulator = addSP16(state.accumulator, 0o177777 & ~operand)
        } else {
            let whereWord = findMemoryWord(address10)
            state.accumulator = addSP16(state.accumulator, signExtend(negateSP(whereWord)))
            assignFromPointer(address10, whereWord)
        }
        writeRegister(.regA, state.accumulator)
    }

    func performMP(address12: Int) {
        let operand16 = overflowCorrected(state.accumulator)
        let otherOperand16: Int

        if address12 < REG16 {
            otherOperand16 = overflowCorrected(readRegister(Register(rawValue: address12)!))
        } else {
            otherOperand16 = findMemoryWord(address12)
        }

        let (msWord, lsWord) = calculateMultiplyResult(operand16, otherOperand16)
        writeRegister(.regA, signExtend(msWord))
        writeRegister(.regL, signExtend(lsWord))
    }

    // Add these helper functions:
    /// Convert SP value to negative
    func negateSP(_ value: Int) -> Int {
        return 0o77777 & ~value
    }

    /// Get absolute value in SP format
    func absSP(_ value: Int) -> Int {
        if (value & 0o40000) != 0 {
            return 0o37777 & ~value
        }
        return value & 0o37777
    }

    /// Convert SP value pair to decent format (29-bit 1's complement)
    func spToDecent(msw: Int, lsw: Int) -> Int {
        var msw = msw & 0o177777
        var lsw = lsw & 0o177777

        if msw == AGC_P0 || msw == AGC_M0 {
            var value = signExtend(lsw)
            if (value & 0o100000) != 0 {
                value |= ~0o177777
            }
            return value & 0o7777777777
        }

        if (0o40000 & lsw) != (0o40000 & msw) {
            if lsw == AGC_P0 || lsw == AGC_M0 {
                lsw = (0o40000 & msw) == 0 ? AGC_P0 : AGC_M0
            } else {
                let complement = (0o40000 & msw) != 0
                if complement {
                    msw = 0o77777 & ~msw
                    lsw = 0o77777 & ~lsw
                }
                msw -= 1
                lsw = (lsw + 0o40000 + AGC_P1) & 0o77777
                if complement {
                    msw = 0o77777 & ~msw
                    lsw = 0o77777 & ~lsw
                }
            }
        }

        var value = (0o3777740000 & (msw << 14)) | (0o37777 & lsw)
        if (value & 0o2000000000) != 0 {
            value |= 0o4000000000
        }
        return value
    }

    /// Simulate DV hardware behavior to match yaAGC's "total nonsense" cases
    func simulateDV(_ divisorInput: Int) {
        var a = readRegister(.regA) & 0o177777
        var l = readRegister(.regL) & 0o177777
        var divisor = divisorInput & 0o177777
        
        var dividendSign = a & 0o100000
        
        if dividendSign == 0 {
            a = 0o177777 & ~a
        }
        if a == 0o177777 {
            dividendSign = l & 0o100000
        }
        if dividendSign != 0 {
            l = 0o177777 & ~l
        }
        
        l = addSP16(l, 0o40000)
        if valueOverflowed(l) != AGC_P1 {
            a = addSP16(a, AGC_P1)
        }
        var remainder = a
        
        let divisorSign = divisor & 0o100000
        if divisorSign != 0 {
            divisor = 0o177777 & ~divisor
        }
        
        let quotientSign = l & 0o100000
        var quotient = quotientSign | ((l & 0o37777) << 1) | (quotientSign >> 15)
        quotient &= 0o177777
        
        for _ in 0..<14 {
            quotient = (quotient << 1) & 0o177777
            let remainderSign = remainder & 0o100000
            remainder = remainderSign | ((remainder & 0o37777) << 1)
            remainder &= 0o177777
            
            if (quotient & 0o100000) == 0 {
                remainder |= (remainderSign >> 15)
            }
            
            let sum = addSP16(remainder, divisor)
            if (sum & 0o100000) != 0 {
                quotient |= 1
                remainder = sum
            }
        }
        
        var newA = quotientSign | (quotient & 0o77777)
        if dividendSign != divisorSign {
            newA = 0o177777 & ~newA
        }
        
        var newL = remainder
        if dividendSign == 0 {
            newL = 0o177777 & ~remainder
        }
        
        writeRegister(.regA, signExtend(newA))
        writeRegister(.regL, signExtend(newL))
    }

    /// Handle interrupt requests generated by counter instructions
}
