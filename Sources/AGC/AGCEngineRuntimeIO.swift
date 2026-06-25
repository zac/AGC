import Foundation

extension AGCEngine {
    /// Start the simulation engine.
    /// This initializes the AGC state and starts the main execution loop running at 11.7 microsecond intervals
    public func startEngine() {
        state.resetForBoot()
        resetPeripheralTiming()
        try? loadBinFile()

        // Start main execution loop
        engineTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // Run one machine cycle
                _ = await self.executeCycle()
                // Wait 11.7 microseconds between cycles
                try? await Task.sleep(nanoseconds: 11_700)
            }
        }
    }

    /// Runs the simulation for a fixed number of cycles, or until `Task` cancellation when `cycles == UInt64.max`.
    ///
    /// For visionOS / RealityKit, prefer driving the engine from your frame loop with a bounded cycle count
    /// (deterministic coupling to physics). Use `startEngine()` for wall-clock–paced stepping (~11.7µs/cycle).
    public func runEngine(for cycles: UInt64) async {
        if cycles == UInt64.max {
            while !Task.isCancelled {
                _ = await self.executeCycle()
            }
        } else {
            var remaining = cycles
            while remaining > 0 {
                if Task.isCancelled { break }
                _ = await self.executeCycle()
                remaining -= 1
            }
        }
    }

    /// Stop the simulation engine
    public func stopEngine() {
        engineTask?.cancel()
    }
    
    /// Updates the DSKY display and status lights
    func updateDSKY() {
        let lastChannel163 = state.dskyChannel163
        
        // Clear all status bits
        var flags = DSKYFlags(rawValue: state.dskyChannel163)
        flags.subtract(DSKYFlags.allFlags)
        
        // Light test active - light RESTART and STBY
        if (state.inputChannels[0o13] & 0o1000) != 0 {
            flags.formUnion(.lightTest)
        }
        
        // Standby light
        if state.standby {
            flags.insert(.standby)
        }
        
        // Restart light
        if state.restartLight {
            flags.insert(.restart)
        }
        
        // Temperature warning
        if (state.inputChannels[0o11] & 0o10) != 0 || 
           (state.inputChannels[0o30] & 0o40000) != 0 {
            flags.insert(.temperature)
        }
        
        // Key Release and Operator Error from channel 11
        if (state.inputChannels[0o11] & DSKYFlags.keyRelease.rawValue) != 0 {
            flags.insert(.keyRelease)
        }
        if (state.inputChannels[0o11] & DSKYFlags.operatorError.rawValue) != 0 {
            flags.insert(.operatorError)
        }
        
        // AGC warning light
        if state.warningFilter > WARNING_FILTER_THRESHOLD {
            flags.insert(.agcWarning)
            // Set AGC Warning input bit in channel 33
            state.inputChannels[0o33] &= 0o57777
        }
        
        // Update the DSKY flash counter based on the DSKY timer.
        while state.dskyTimer >= DSKY_OVERFLOW {
            state.dskyTimer -= DSKY_OVERFLOW
            state.dskyFlash = (state.dskyFlash + 1) % DSKY_FLASH_PERIOD
        }

        // Handle flashing lights (1.28s period, 75% duty cycle)
        if !state.standby && state.dskyFlash == 0 {
            // V/N Flash
            if (state.inputChannels[0o11] & DSKYFlags.verbNounFlash.rawValue) != 0 {
                flags.insert(.verbNounFlash)
            }
            
            // Flash off KEY REL and OPER ERR
            flags.remove(.keyRelease)
            flags.remove(.operatorError)
        }
        
        // Update state and output if changed
        state.dskyChannel163 = flags.rawValue
        if state.dskyChannel163 != lastChannel163 {
            channelOutput(channel: 0o163, value: state.dskyChannel163)
        }
    }
    
    /// Output a value to an I/O channel
    func channelOutput(channel: Int, value: Int) {
        let normalizedChannel = channel & 0o777
        let maskedValue = value & 0o77777

        if normalizedChannel == 0o7 {
            let superbankValue = maskedValue & 0o160
            state.outputChannel7 = superbankValue
            state.inputChannels[0o7] = superbankValue
            state.outputChannels[0o7] = superbankValue
            return
        }

        if normalizedChannel == 0o13 && (maskedValue & 0o600) == 0o600 {
            state.erasableMemory[0][Register.regRHCP.rawValue] = lastRhcPitch
            state.erasableMemory[0][Register.regRHCY.rawValue] = lastRhcYaw
            state.erasableMemory[0][Register.regRHCR.rawValue] = lastRhcRoll
        }

        state.outputChannels[normalizedChannel] = maskedValue
        ioDelegate?.channelOutput(channel: normalizedChannel, value: maskedValue)
    }
}
