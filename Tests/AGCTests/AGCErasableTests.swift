import Foundation
import Testing

@testable import AGC

@Suite("AGC erasable encoding")
struct AGCErasableTests {
    @Test func `504RM 2DEC 1738090 B-29 matches the Luminary listing`() {
        let encoded = AGCDoublePrecision.encode(value: 1_738_090, scale: 29)
        #expect(encoded.high == 0o00065)
        #expect(encoded.low == 0o01265)
        #expect(abs(encoded.decoded(scale: 29) - 1_738_090) < 1)
    }

    @Test func `double precision round-trips a negative lunar radius`() {
        let encoded = AGCDoublePrecision.encode(value: -1_738_090, scale: 29)
        #expect(encoded.high == (0o77777 & ~0o00065))
        #expect(encoded.low == (0o77777 & ~0o01265))
        #expect(abs(encoded.decoded(scale: 29) + 1_738_090) < 1)
    }

    @Test func `half-unit identity component is 20000 octal`() {
        let encoded = AGCDoublePrecision.encode(value: 0.5, scale: 0)
        #expect(encoded.high == 0o20000)
        #expect(encoded.low == 0)
    }

    @Test func `ECADR write uses the bank in the high bits not current EB`() async throws {
        let runtime = try AGCRuntime(coreImage: Data())
        await runtime.writeErasable(ecadr: 0o2222, value: 0o12345)

        #expect(await runtime.readErasable(ecadr: 0o2222) == 0o12345)
        #expect(await runtime.readErasable(ecadr: 0o1422) == 0)
    }

    @Test func `setErasableBit ORs without clearing neighbors`() async throws {
        let runtime = try AGCRuntime(coreImage: Data())
        await runtime.writeErasable(ecadr: 0o74, value: 0o00001)
        await runtime.setErasableBit(ecadr: 0o74, bit: 12)

        #expect(await runtime.readErasable(ecadr: 0o74) == 0o04001)
    }
}
