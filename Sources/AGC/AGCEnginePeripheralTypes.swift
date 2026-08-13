import Foundation

/// IMU CDU drive timing constants
struct IMUTiming {
    static let COARSE_SMOOTH = 8
    static let BURST_CYCLES: UInt64 = (600 * 1024000) / (1000 * 12 * UInt64(COARSE_SMOOTH))

    var cycleCount: UInt64 = 0
    var channel14: Int = 0
    var countCDUX = 0
    var countCDUY = 0
    var countCDUZ = 0
    
    mutating func shouldEmitBurst(state: AGCState, currentCycle: UInt64) -> Bool {
        let imuBits = state.inputChannels[0o14] & 0o70000  // Check IMU CDU drive bits
        
        // If suddenly active, start drive
        if channel14 == 0 && imuBits != 0 {
            cycleCount = currentCycle - IMUTiming.BURST_CYCLES
        }
        
        // Time for next burst?
        if imuBits != 0 && (currentCycle - cycleCount) >= IMUTiming.BURST_CYCLES {
            // Adjust cycle counter
            cycleCount += IMUTiming.BURST_CYCLES
            
            // Determine pulses wanted on each axis
            channel14 = burstOutput(state: state,
                                    driveBitMask: 0o40000,
                                    counterRegister: .regCDUXCMD,
                                    channel: 0o174)
            channel14 |= burstOutput(state: state,
                                     driveBitMask: 0o20000,
                                     counterRegister: .regCDUYCMD,
                                     channel: 0o175)
            channel14 |= burstOutput(state: state,
                                     driveBitMask: 0o10000,
                                     counterRegister: .regCDUZCMD,
                                     channel: 0o176)
            return true
        }
        
        return false
    }

    /// Process burst output for one IMU CDU drive axis.
    /// Returns non-0 if a non-zero count remains on the axis, 0 otherwise.
    mutating func burstOutput(
        state: AGCState,
        driveBitMask: Int,
        counterRegister: Register,
        channel: Int
    ) -> Int {
        var driveCountSaved: Int
        switch counterRegister {
        case .regCDUXCMD: driveCountSaved = countCDUX
        case .regCDUYCMD: driveCountSaved = countCDUY
        case .regCDUZCMD: driveCountSaved = countCDUZ
        default: return 0
        }

        var driveCount = 0
        var direction = 0

        let driveBit = state.inputChannels[0o14] & driveBitMask
        if driveBit != 0 {
            driveCount = state.erasableMemory[0][counterRegister.rawValue]
            state.erasableMemory[0][counterRegister.rawValue] = 0
        }

        direction = driveCount & 0o40000
        if direction != 0 {
            driveCount ^= 0o77777
            driveCountSaved -= driveCount
        } else {
            driveCountSaved += driveCount
        }

        if driveCountSaved < 0 {
            driveCountSaved = -driveCountSaved
            direction = 0o40000
        } else {
            direction = 0
        }

        var delta = driveCountSaved
        if delta >= 192 / IMUTiming.COARSE_SMOOTH {
            delta = 192 / IMUTiming.COARSE_SMOOTH
        }

        if delta > 0 {
            state.outputChannels[channel] = direction | delta
            driveCountSaved -= delta
        }

        if direction != 0 {
            driveCountSaved = -driveCountSaved
        }

        switch counterRegister {
        case .regCDUXCMD: countCDUX = driveCountSaved
        case .regCDUYCMD: countCDUY = driveCountSaved
        case .regCDUZCMD: countCDUZ = driveCountSaved
        default: break
        }

        return driveCountSaved
    }
}

/// Gyro timing and state management
struct GyroTiming {
    // Constants
    static let BURST = 800
    static let BURST2 = 1024
    static let OVERFLOW = 160  // Same as SCALER_OVERFLOW
    static let DIVIDER = 2 * 3 // yaAGC GYRO_DIVIDER
    
    // State
    var timer: Int = 0
    var count: Int = 0
    var oldChannel14: Int = 0
    
    /// Process any pending gyro operations
    mutating func processBurst(state: AGCState) -> Bool {
        // Check if gyro torquing is enabled
        guard (state.inputChannels[0o14] & 0o1000) != 0 else {
            return false
        }
        
        // Check if there's a new torque value
        let gyroCounter = state.erasableMemory[0][Register.regGYROCTR.rawValue]
        if gyroCounter != 0 {
            // Process any pending torques first
            while count > 0 {
                var burstSize = count
                if burstSize > 0o3777 {
                    burstSize = 0o3777
                }
                state.outputChannels[0o177] = oldChannel14 | burstSize
                count -= burstSize
            }
            
            // Set up new torque counter
            count = gyroCounter
            state.erasableMemory[0][Register.regGYROCTR.rawValue] = 0
            oldChannel14 = ((state.inputChannels[0o14] & 0o740) << 6)
            timer = Self.OVERFLOW * Self.BURST - Self.DIVIDER
        }
        
        // Update 3200 pps gyro pulse counter
        timer += Self.DIVIDER
        var didOutput = false
        
        while timer >= Self.BURST * Self.OVERFLOW {
            timer -= Self.BURST * Self.OVERFLOW
            if count > 0 {
                var burstSize = count
                if burstSize > Self.BURST2 {
                    burstSize = Self.BURST2
                }
                state.outputChannels[0o177] = oldChannel14 | burstSize
                count -= burstSize
                didOutput = true
            }
        }
        
        return didOutput
    }
}

// MARK: - CDU FIFO (yaAGC `PushCduFifo` / `ServiceCduFifo` in agc_engine.c)

enum CDUFifoConstants {
    static let maxEntries = 128
    static let fifoCount = 3
    /// Erasable offsets `RegCDUX`…`RegCDUZ` (octal 032–034).
    static let firstCounter = Register.regCDUX.rawValue
}

struct CDUFifoState {
    var ptr: Int = 0
    var size: Int = 0
    var intervalType: Int = 0
    var nextUpdate: UInt64 = 0
    var counts: [Int32] = Array(repeating: 0, count: CDUFifoConstants.maxEntries)
}
