import Foundation

/// DSKY (Display/Keyboard) implementation for Apollo Guidance Computer
/// Handles bidirectional communication with AGC via I/O channels
public final class DSKY: AGCIOProtocol, @unchecked Sendable {
    private final class KeypressQueue: @unchecked Sendable {
        private let lock = NSLock()
        private var queue: [AGCChannelInput] = []

        func append(_ item: AGCChannelInput) {
            lock.lock()
            queue.append(item)
            lock.unlock()
        }

        /// Returns one queued I/O event per call so multi-key sequences are not collapsed.
        func dequeueOne() -> AGCChannelInput? {
            lock.lock()
            defer { lock.unlock() }
            guard !queue.isEmpty else { return nil }
            return queue.removeFirst()
        }
    }

    private let keypressQueue = KeypressQueue()
    
    // MARK: - Display State
    
    /// 7-segment display registers (R1, R2, R3)
    public struct DisplayRegister {
        var signBits: Int = 0  // Bit 2 = +, Bit 1 = - (matching yaDSKY)
        var digits: [Int] = [-1, -1, -1, -1, -1]  // 5 digits; -1 is blank
        
        public var sign: String {
            if (signBits & 2) != 0 {
                return "+"
            } else if (signBits & 1) != 0 {
                return "-"
            } else {
                return " "
            }
        }
    }
    
    public var r1 = DisplayRegister()
    public var r2 = DisplayRegister()
    public var r3 = DisplayRegister()
    
    /// VERB and NOUN displays (2 digits each)
    public var verbDigits: [Int] = [-1, -1]
    public var nounDigits: [Int] = [-1, -1]
    
    /// MODE display (2 digits)
    public var modeDigits: [Int] = [-1, -1]
    
    /// Indicator light states
    public struct IndicatorState {
        var isOn: Bool = false
    }
    
    public var indicators: [Int: IndicatorState] = [:]
    
    /// Channel 163 status flags
    public var channel163: Int = 0
    
    /// Channel 11 status
    public var channel11: Int = 0
    
    /// Channel 13 status (lamp test, TIME6 enable, etc.)
    public var channel13: Int = 0

    /// Channel 32 status (PROCEED/STANDBY is inverted bit 14)
    public var channel32: Int = 0o20000
    
    /// Channel 10 latched values (16 rows)
    private var channel10Rows: [Int] = Array(repeating: 0, count: 16)
    
    /// Current channel 10 value for indicator evaluation (value matching mask 0o74000 == 0o60000)
    private var channel10IndicatorValue: Int = 0
    
    /// Verb/Noun flash state
    public var verbNounFlash: Bool = false
    
    /// Lamp test mode
    public var lampTest: Bool {
        return (channel13 & 0o1000) != 0
    }
    
    /// PRO key state (channel 032 bit 14, inverted: 0 = pressed)
    public var proKeyPressed: Bool {
        return (channel32 & 0o20000) == 0
    }
    
    /// COMP ACTY indicator
    public var compActy: Bool {
        return (channel11 & 0o2) != 0
    }
    
    // MARK: - Initialization
    
    public init() {
        // Initialize indicator states
        for id in [11, 12, 13, 14, 15, 16, 17, 21, 22, 23, 24, 25, 26, 27] {
            indicators[id] = IndicatorState()
        }
    }
    
    // MARK: - AGCIOProtocol Implementation
    
    public func channelOutput(channel: Int, value: Int) {
        let normalizedChannel = channel & 0o777
        let maskedValue = value & 0o77777
        
        switch normalizedChannel {
        case 0o10:
            handleChannel10(value: maskedValue)
        case 0o11:
            handleChannel11(value: maskedValue)
        case 0o13:
            handleChannel13(value: maskedValue)
        case 0o163:
            handleChannel163(value: maskedValue)
        default:
            // Store other channel outputs if needed
            break
        }
    }
    
    public func channelInput() -> [AGCChannelInput]? {
        guard let item = keypressQueue.dequeueOne() else { return nil }
        return [item]
    }
    
    public func requestRadarData() {
        // Not applicable for DSKY
    }
    
    public func shiftToDeda(data: Int) {
        // Not applicable for DSKY (DEDA is for AGS)
    }
    
    public func channelRoutine() {
        // Periodic updates if needed
    }
    
    // MARK: - Channel Handlers
    
    private func handleChannel10(value: Int) {
        // Channel 10 format:
        // Bits 0-4: Right digit (DDDDD)
        // Bits 5-9: Left digit (CCCCC)
        // Bit 10: Sign bit (0=+, 1=-)
        // Bits 11-15: Row selector (AAAAA) - selects which display register
        
        let rowSelector = (value >> 11) & 0o37  // 5 bits
        let leftDigit = (value >> 5) & 0o37
        let rightDigit = value & 0o37
        let signBit = (value & 0o400) != 0
        
        // Store in latched row (row selector is 5 bits, but we use lower 4 bits for array index)
        let rowIndex = rowSelector & 0o17
        channel10Rows[rowIndex] = value
        
        // Track channel 10 value for indicator evaluation (mask 0o74000, match 0o60000)
        if (value & 0o74000) == 0o60000 {
            channel10IndicatorValue = value
        }
        
        // Decode based on row selector (matching yaDSKY callbacks.c ActOnIncomingIO).
        // Row selector values are decimal: 11D=0x5800, 10D=0x5000, 9D=0x4800, etc.
        switch rowSelector {
        case 11:    // AAAA=11D (0x5800) - MODE display (MD1, MD2)
            modeDigits[0] = decode7Segment(leftDigit)
            modeDigits[1] = decode7Segment(rightDigit)
            
        case 10:    // AAAA=10D (0x5000) - VERB display (VD1, VD2)
            verbDigits[0] = decode7Segment(leftDigit)
            verbDigits[1] = decode7Segment(rightDigit)
            
        case 9:     // AAAA=9D (0x4800) - NOUN display (ND1, ND2)
            nounDigits[0] = decode7Segment(leftDigit)
            nounDigits[1] = decode7Segment(rightDigit)
            
        case 8:     // AAAA=8D (0x4000) - R1 digit 1
            r1.digits[0] = decode7Segment(rightDigit)
            
        case 7:     // AAAA=7D (0x3800) - R1 sign and digits 2-3
            // Sign bit handling: bit 2 = +, bit 1 = -
            if signBit {
                r1.signBits |= 2  // Set + bit
            } else {
                r1.signBits &= ~2  // Clear + bit
            }
            r1.digits[1] = decode7Segment(leftDigit)
            r1.digits[2] = decode7Segment(rightDigit)
            
        case 6:     // AAAA=6D (0x3000) - R1 digits 4-5
            // Sign bit handling for second part
            if signBit {
                r1.signBits |= 1  // Set - bit
            } else {
                r1.signBits &= ~1  // Clear - bit
            }
            r1.digits[3] = decode7Segment(leftDigit)
            r1.digits[4] = decode7Segment(rightDigit)
            
        case 5:     // AAAA=5D (0x2800) - R2 sign and digits 1-2
            if signBit {
                r2.signBits |= 2  // Set + bit
            } else {
                r2.signBits &= ~2  // Clear + bit
            }
            r2.digits[0] = decode7Segment(leftDigit)
            r2.digits[1] = decode7Segment(rightDigit)
            
        case 4:     // AAAA=4D (0x2000) - R2 digits 3-4
            if signBit {
                r2.signBits |= 1  // Set - bit
            } else {
                r2.signBits &= ~1  // Clear - bit
            }
            r2.digits[2] = decode7Segment(leftDigit)
            r2.digits[3] = decode7Segment(rightDigit)
            
        case 3:     // AAAA=3D (0x1800) - R2 digit 5 and R3 digit 1
            r2.digits[4] = decode7Segment(leftDigit)
            r3.digits[0] = decode7Segment(rightDigit)
            
        case 2:     // AAAA=2D (0x1000) - R3 sign and digits 2-3
            if signBit {
                r3.signBits |= 2  // Set + bit
            } else {
                r3.signBits &= ~2  // Clear + bit
            }
            r3.digits[1] = decode7Segment(leftDigit)
            r3.digits[2] = decode7Segment(rightDigit)
            
        case 1:     // AAAA=1D (0x0800) - R3 digits 4-5
            if signBit {
                r3.signBits |= 1  // Set - bit
            } else {
                r3.signBits &= ~1  // Clear - bit
            }
            r3.digits[3] = decode7Segment(leftDigit)
            r3.digits[4] = decode7Segment(rightDigit)
            
        default:
            break
        }
        
        // Update indicators that depend on channel 10 with masks
        // These indicators require specific channel 10 values with masks
        updateChannel10Indicators()
    }
    
    private func updateChannel10Indicators() {
        // Indicators controlled by channel 10 with masks (from yaDSKY callbacks.c)
        // All these indicators check the same channel 10 value with mask 0o74000 == 0o60000
        // Bit positions are 1-indexed in yaDSKY, so we use (bitPosition - 1) for mask
        
        // NO ATT (indicator 12): channel 10, bit 4 (1-indexed), mask 0o74000, match 0o60000
        updateIndicator(id: 12, isOn: (channel10IndicatorValue & 0o10) != 0)  // bit 4 = 1<<3 = 0o10
        
        // GIMBAL LOCK (indicator 22): channel 10, bit 6 (1-indexed), mask 0o74000, match 0o60000
        updateIndicator(id: 22, isOn: (channel10IndicatorValue & 0o40) != 0)  // bit 6 = 1<<5 = 0o40
        
        // PROG (indicator 23): channel 10, bit 9 (1-indexed), mask 0o74000, match 0o60000
        updateIndicator(id: 23, isOn: (channel10IndicatorValue & 0o400) != 0)  // bit 9 = 1<<8 = 0o400
        
        // TRACKER (indicator 25): channel 10, bit 8 (1-indexed), mask 0o74000, match 0o60000
        updateIndicator(id: 25, isOn: (channel10IndicatorValue & 0o200) != 0)  // bit 8 = 1<<7 = 0o200
        
        // ALT (indicator 26): channel 10, bit 5 (1-indexed), mask 0o74000, match 0o60000
        updateIndicator(id: 26, isOn: (channel10IndicatorValue & 0o20) != 0)  // bit 5 = 1<<4 = 0o20
        
        // VEL (indicator 27): channel 10, bit 3 (1-indexed), mask 0o74000, match 0o60000
        updateIndicator(id: 27, isOn: (channel10IndicatorValue & 0o4) != 0)  // bit 3 = 1<<2 = 0o4
        
        // PRIO DISP (indicator 16): channel 10, bit 1 (1-indexed), mask 0o74000, match 0o60000
        updateIndicator(id: 16, isOn: (channel10IndicatorValue & 0o1) != 0)  // bit 1 = 1<<0 = 0o1
        
        // NO DAP (indicator 17): channel 10, bit 2 (1-indexed), mask 0o74000, match 0o60000
        updateIndicator(id: 17, isOn: (channel10IndicatorValue & 0o2) != 0)  // bit 2 = 1<<1 = 0o2
    }
    
    private func handleChannel11(value: Int) {
        channel11 = value
        
        // Update indicators from channel 11
        // UPLINK ACTY (indicator 11): channel 11, bit 3
        updateIndicator(id: 11, isOn: (value & 0o4) != 0)
        
        // COMP ACTY is not an indicator light, it's a separate annunciator
        // but we track it in the compActy property
    }
    
    private func handleChannel13(value: Int) {
        channel13 = value
        
        // PRO key state is bit 14 (inverted: 0 = pressed)
        // Lamp test is bit 10
    }
    
    private func handleChannel163(value: Int) {
        channel163 = value
        
        // Decode indicator lights from channel 163
        // Bit 0: AGC_WARN (0o000001)
        // Bit 1: TEMP (0o000010)
        // Bit 2: KEY_REL (0o000020)
        // Bit 3: VN_FLASH (0o000040)
        // Bit 4: OPER_ERR (0o000100)
        // Bit 5: RESTART (0o000200)
        // Bit 6: STBY (0o000400)
        // Bit 7: EL_OFF (0o001000) - not used for indicators
        
        verbNounFlash = (value & 0o40) != 0
        
        // Update indicators based on channel 163
        // Indicator IDs match yaDSKY configuration (from callbacks.c Inds array)
        // Note: UPLINK ACTY (11) comes from channel 11, not 163
        updateIndicator(id: 13, isOn: (value & 0o400) != 0)  // STBY (bit 6)
        updateIndicator(id: 14, isOn: (value & 0o20) != 0)   // KEY REL (bit 2)
        updateIndicator(id: 15, isOn: (value & 0o100) != 0)  // OPER ERR (bit 4)
        updateIndicator(id: 21, isOn: (value & 0o10) != 0)   // TEMP (bit 1)
        updateIndicator(id: 24, isOn: (value & 0o200) != 0)  // RESTART (bit 5)
        
        // Other indicators are controlled by channel 10 with masks or channel 11
    }
    
    // MARK: - 7-Segment Decoding
    
    /// Decode 7-segment display value to digit (0-9). Returns -1 for blank/unknown.
    /// Mapping from yaDSKY callbacks.c SevenSegmentFilenames array
    private func decode7Segment(_ value: Int) -> Int {
        switch value {
        case 0: return -1
        case 21: return 0
        case 3: return 1
        case 25: return 2
        case 27: return 3
        case 15: return 4
        case 30: return 5
        case 28: return 6
        case 19: return 7
        case 29: return 8
        case 31: return 9
        default:
            return -1
        }
    }
    
    // MARK: - Indicator Management
    
    private func updateIndicator(id: Int, isOn: Bool) {
        if var indicator = indicators[id] {
            indicator.isOn = isOn
            indicators[id] = indicator
        } else {
            indicators[id] = IndicatorState(isOn: isOn)
        }
    }
    
    public func indicatorIsOn(_ id: Int) -> Bool {
        return indicators[id]?.isOn ?? false
    }
    
    // MARK: - Keypress Handling
    
    /// Send a keypress to the AGC
    /// - Parameter keycode: Keycode value (matching yaDSKY callbacks.c)
    public func sendKeycode(_ keycode: Int) async {
        keypressQueue.append(AGCChannelInput(channel: 0o15, value: keycode & 0o77777))
    }

    /// Send a typed DSKY key to the AGC.
    public func send(_ key: DSKYKeyCode) async {
        switch key {
        case .pro:
            await sendProKey(true)
        default:
            await sendKeycode(key.rawValue)
        }
    }
    
    /// Send PRO key press state.
    /// PROCEED/STANDBY is inverted bit 14 of channel 032. A 0432 mask packet
    /// limits the write to that bit, matching yaAGC/yaDSKY.
    /// - Parameter pressed: true when pressed, false when released
    public func sendProKey(_ pressed: Bool) async {
        keypressQueue.append(AGCChannelInput(channel: 0o432, value: 0o20000))
        keypressQueue.append(AGCChannelInput(channel: 0o32, value: pressed ? 0 : 0o20000))
        channel32 = (channel32 & ~0o20000) | (pressed ? 0 : 0o20000)
    }
    
    // MARK: - Display Helpers
    
    /// Get formatted display string for a register
    public func formatRegister(_ reg: DisplayRegister) -> String {
        let digits = reg.digits.map(formatDigit).joined()
        return "\(reg.sign)\(digits)"
    }
    
    /// Get formatted VERB display
    public func formatVerb() -> String {
        return verbDigits.map(formatDigit).joined()
    }
    
    /// Get formatted NOUN display
    public func formatNoun() -> String {
        return nounDigits.map(formatDigit).joined()
    }

    private func formatDigit(_ digit: Int) -> String {
        return digit >= 0 ? String(digit) : " "
    }

    public var snapshot: DSKYSnapshot {
        var statuses: [Int: Bool] = [:]
        for id in DSKYSnapshot.indicatorIDs {
            statuses[id] = indicatorIsOn(id)
        }

        return DSKYSnapshot(
            channel10Rows: channel10Rows,
            channel11: channel11,
            channel13: channel13,
            channel163: channel163,
            r1: formatRegister(r1),
            r2: formatRegister(r2),
            r3: formatRegister(r3),
            verb: formatVerb(),
            noun: formatNoun(),
            mode: modeDigits.map(formatDigit).joined(),
            verbNounFlash: verbNounFlash,
            lampTest: lampTest,
            compActy: compActy,
            proKeyPressed: proKeyPressed,
            indicators: statuses
        )
    }
}
