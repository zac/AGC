import Foundation

/// One 15-bit erasable word at an 11-bit ECADR (banks 0–7 × 256 words).
public struct AGCErasableWord: Equatable, Sendable {
    public let ecadr: Int
    public let value: Int

    public init(ecadr: Int, value: Int) {
        self.ecadr = ecadr & 0o3777
        self.value = value & 0o77777
    }
}

/// AGC double-precision ones’-complement pair (two 15-bit words).
///
/// A quantity scaled **B-n** is stored so the 28-bit integer N satisfies
/// `physical = N × 2^(n−28)`. This matches yaYUL `2DEC` (e.g. `504RM 2DEC 1738090 B-29`).
public struct AGCDoublePrecision: Equatable, Sendable {
    public let high: Int
    public let low: Int

    public init(high: Int, low: Int) {
        self.high = high & 0o77777
        self.low = low & 0o77777
    }

    public static func encode(value: Double, scale: Int) -> AGCDoublePrecision {
        let factor = pow(2.0, Double(28 - scale))
        var n = Int64((value * factor).rounded())
        let maxMagnitude = Int64((1 << 28) - 1)
        n = min(max(n, -maxMagnitude), maxMagnitude)
        if n < 0 {
            let magnitude = Int(-n)
            let highMag = (magnitude >> 14) & 0o37777
            let lowMag = magnitude & 0o37777
            return AGCDoublePrecision(high: 0o77777 & ~highMag, low: 0o77777 & ~lowMag)
        }
        let magnitude = Int(n)
        return AGCDoublePrecision(
            high: (magnitude >> 14) & 0o37777,
            low: magnitude & 0o37777
        )
    }

    public func decoded(scale: Int) -> Double {
        Double(signedInteger) * pow(2.0, Double(scale - 28))
    }

    public var words: (high: Int, low: Int) { (high, low) }

    var signedInteger: Int64 {
        if (high & 0o40000) != 0 {
            let highMag = (~high) & 0o37777
            let lowMag = (~low) & 0o37777
            return -Int64((highMag << 14) | lowMag)
        }
        return Int64(((high & 0o37777) << 14) | (low & 0o37777))
    }
}

/// AGC single-precision ones’-complement word.
///
/// Scaled **B-n** means `physical = N × 2^(n−14)`.
public struct AGCSinglePrecision: Equatable, Sendable {
    public let word: Int

    public init(word: Int) {
        self.word = word & 0o77777
    }

    public static func encode(value: Double, scale: Int) -> AGCSinglePrecision {
        let factor = pow(2.0, Double(14 - scale))
        var n = Int((value * factor).rounded())
        let maxMagnitude = 0o37777
        n = min(max(n, -maxMagnitude), maxMagnitude)
        if n < 0 {
            return AGCSinglePrecision(word: 0o77777 & ~(-n))
        }
        return AGCSinglePrecision(word: n & 0o37777)
    }

    public func decoded(scale: Int) -> Double {
        let signed: Int
        if (word & 0o40000) != 0 {
            signed = -((~word) & 0o37777)
        } else {
            signed = word & 0o37777
        }
        return Double(signed) * pow(2.0, Double(scale - 14))
    }
}

extension AGCEngine {
    func writeErasableECADR(_ ecadr: Int, _ value: Int) {
        let address = ecadr & 0o3777
        assign(bank: (address >> 8) & 7, offset: address & 0o377, value: value)
    }

    func readErasableECADR(_ ecadr: Int) -> Int {
        let address = ecadr & 0o3777
        let bank = (address >> 8) & 7
        let offset = address & 0o377
        return state.erasableMemory[bank][offset] & 0o77777
    }
}
