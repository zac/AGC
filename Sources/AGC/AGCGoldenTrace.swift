import Foundation

/// One architectural sample in the yaAGC golden-trace JSONL format.
///
/// Field names stay short so the C tracer and Swift encoder emit identical lines.
public struct AGCGoldenTraceSample: Equatable, Sendable, Codable {
    public var c: UInt64
    public var a: Int
    public var l: Int
    public var q: Int
    public var z: Int
    public var eb: Int
    public var fb: Int
    public var bb: Int
    public var t1: Int
    public var t3: Int
    public var ch7: Int
    public var ch11: Int
    public var ch13: Int
    public var ch32: Int
    public var ch77: Int
    public var s1: Int
    public var s2: Int
    public var ec: Int
    public var isr: Int
    public var ie: Int
    public var pf: Int
    public var ir: [Int]

    public init(
        c: UInt64,
        a: Int,
        l: Int,
        q: Int,
        z: Int,
        eb: Int,
        fb: Int,
        bb: Int,
        t1: Int,
        t3: Int,
        ch7: Int,
        ch11: Int,
        ch13: Int,
        ch32: Int,
        ch77: Int,
        s1: Int,
        s2: Int,
        ec: Int,
        isr: Int,
        ie: Int,
        pf: Int,
        ir: [Int]
    ) {
        self.c = c
        self.a = a
        self.l = l
        self.q = q
        self.z = z
        self.eb = eb
        self.fb = fb
        self.bb = bb
        self.t1 = t1
        self.t3 = t3
        self.ch7 = ch7
        self.ch11 = ch11
        self.ch13 = ch13
        self.ch32 = ch32
        self.ch77 = ch77
        self.s1 = s1
        self.s2 = s2
        self.ec = ec
        self.isr = isr
        self.ie = ie
        self.pf = pf
        self.ir = ir
    }

    public init(state: AGCState) {
        let e0 = state.erasableMemory[0]
        self.init(
            c: state.cycleCounter,
            a: e0[Register.regA.rawValue] & 0o177777,
            l: e0[Register.regL.rawValue] & 0o177777,
            q: e0[Register.regQ.rawValue] & 0o177777,
            z: e0[Register.regZ.rawValue] & 0o177777,
            eb: e0[Register.regEB.rawValue] & 0o177777,
            fb: e0[Register.regFB.rawValue] & 0o177777,
            bb: e0[Register.regBB.rawValue] & 0o177777,
            t1: e0[Register.regTIME1.rawValue] & 0o77777,
            t3: e0[Register.regTIME3.rawValue] & 0o77777,
            ch7: state.outputChannel7 & 0o77777,
            ch11: state.inputChannels[0o11] & 0o77777,
            ch13: state.inputChannels[0o13] & 0o77777,
            ch32: state.inputChannels[0o32] & 0o77777,
            ch77: state.inputChannels[0o77] & 0o77777,
            s1: state.inputChannels[0o4] & 0o77777,
            s2: state.inputChannels[0o3] & 0o77777,
            ec: state.extraCode ? 1 : 0,
            isr: state.inIsr ? 1 : 0,
            ie: state.allowInterrupt ? 1 : 0,
            pf: state.pendFlag ? 1 : 0,
            ir: state.interruptRequests
        )
    }

    /// Canonical one-line JSON matching `Tools/yaagc-trace/main.c`.
    public func jsonLine() -> String {
        let irList = ir.map(String.init).joined(separator: ",")
        return "{\"c\":\(c),\"a\":\(a),\"l\":\(l),\"q\":\(q),\"z\":\(z),\"eb\":\(eb),\"fb\":\(fb),\"bb\":\(bb),"
            + "\"t1\":\(t1),\"t3\":\(t3),\"ch7\":\(ch7),\"ch11\":\(ch11),\"ch13\":\(ch13),\"ch32\":\(ch32),\"ch77\":\(ch77),"
            + "\"s1\":\(s1),\"s2\":\(s2),\"ec\":\(ec),\"isr\":\(isr),\"ie\":\(ie),\"pf\":\(pf),"
            + "\"ir\":[\(irList)]}"
    }

    public var octalDescription: String {
        "c=\(c) Z=\(oct5(z)) A=\(oct6(a)) L=\(oct6(l)) Q=\(oct6(q)) EB=\(oct5(eb)) FB=\(oct5(fb)) BB=\(oct5(bb)) "
            + "TIME1=\(oct5(t1)) TIME3=\(oct5(t3)) CH7=\(oct5(ch7)) CH11=\(oct5(ch11)) CH13=\(oct5(ch13)) CH32=\(oct5(ch32)) "
            + "CH77=\(oct5(ch77)) SCALER1=\(oct5(s1)) SCALER2=\(oct5(s2)) extra=\(ec) isr=\(isr) ie=\(ie) pend=\(pf) ir=\(ir)"
    }
}

public struct AGCGoldenTraceKeyEvent: Equatable, Sendable {
    public var cycle: UInt64
    public var key: DSKYKeyCode

    public init(cycle: UInt64, key: DSKYKeyCode) {
        self.cycle = cycle
        self.key = key
    }
}

extension DSKYScript {
    /// Key injection cycles matching `Tools/yaagc-trace` `--keys` after a boot horizon.
    /// The first key is consumed when `cycleCounter` becomes `bootCycles + 1`.
    public func goldenTraceKeys(bootCycles: UInt64 = 1_000_000, cyclesPerKey: UInt64 = 50_000) -> [AGCGoldenTraceKeyEvent] {
        keys.enumerated().map { index, key in
            AGCGoldenTraceKeyEvent(cycle: bootCycles + 1 + UInt64(index) * cyclesPerKey, key: key)
        }
    }

    public func goldenTraceHorizon(bootCycles: UInt64 = 1_000_000, cyclesPerKey: UInt64 = 50_000) -> UInt64 {
        bootCycles + UInt64(keys.count) * cyclesPerKey
    }
}

/// Sampling cadence shared with `Tools/yaagc-trace/main.c`.
public enum AGCGoldenTraceSchedule: Sendable {
    public static let denseUntil: UInt64 = 200
    public static let midUntil: UInt64 = 100_000
    public static let midStride: UInt64 = 1_000
    public static let farUntil: UInt64 = 1_000_000
    public static let farStride: UInt64 = 10_000
    public static let defaultHorizon: UInt64 = farUntil

    public static func shouldSample(_ cycle: UInt64) -> Bool {
        if cycle <= denseUntil { return true }
        if cycle <= midUntil && cycle.isMultiple(of: midStride) { return true }
        if cycle.isMultiple(of: farStride) { return true }
        return false
    }

    public static func nextSample(after cycle: UInt64, through maxCycle: UInt64) -> UInt64? {
        var candidate = cycle + 1
        while candidate <= maxCycle {
            if shouldSample(candidate) {
                return candidate
            }
            if candidate < denseUntil {
                candidate += 1
            } else if candidate < midUntil {
                candidate = ((candidate / midStride) + 1) * midStride
            } else {
                candidate = ((candidate / farStride) + 1) * farStride
            }
        }
        return nil
    }
}

public enum AGCGoldenTrace {
    public static func loadJSONL(_ data: Data) throws -> [AGCGoldenTraceSample] {
        let decoder = JSONDecoder()
        return try data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true).map { line in
            try decoder.decode(AGCGoldenTraceSample.self, from: Data(line))
        }
    }

    public static func jsonl(from samples: [AGCGoldenTraceSample]) -> String {
        samples.map { $0.jsonLine() }.joined(separator: "\n") + "\n"
    }

    /// First mismatch, or `nil` if `actual` covers `expected` exactly.
    public static func firstMismatch(
        expected: [AGCGoldenTraceSample],
        actual: [AGCGoldenTraceSample]
    ) -> (index: Int, expected: AGCGoldenTraceSample, actual: AGCGoldenTraceSample?)? {
        let actualByCycle = Dictionary(uniqueKeysWithValues: actual.map { ($0.c, $0) })
        for (index, gold) in expected.enumerated() {
            guard let got = actualByCycle[gold.c] else {
                return (index, gold, nil)
            }
            if got != gold {
                return (index, gold, got)
            }
        }
        return nil
    }
}

private func oct5(_ value: Int) -> String {
    String(format: "%05o", value & 0o77777)
}

private func oct6(_ value: Int) -> String {
    String(format: "%06o", value & 0o177777)
}
