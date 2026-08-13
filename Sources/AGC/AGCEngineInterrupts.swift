import Foundation

extension AGCEngine {
    func interruptRequests(_ address: Int, _ value: Int) {
        // Only care about values that overflowed
        if valueOverflowed(value) == AGC_P0 {
            return
        }
        
        switch address {
        case Register.regTIME1.rawValue:
            // Overflowing TIME1 increments TIME2 via PINC
            _ = counterPINC(register: .regTIME2)
        case Register.regTIME5.rawValue:
            state.interruptRequests[2] = 1
        case Register.regTIME3.rawValue:
            state.interruptRequests[3] = 1
        case Register.regTIME4.rawValue:
            state.interruptRequests[4] = 1
        default:
            // TIME6 requires hardware ZOUT side-effects which are handled elsewhere
            break
        }
    }
}
