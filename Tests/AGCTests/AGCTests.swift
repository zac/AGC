import Testing
import Foundation

@testable import AGC

@Suite("AGC Tests")
class AGCTests {

    private var library: AGC = {
        let url = Bundle.module.url(forResource: "Luminary099", withExtension: "bin")
        return try! AGC(binFile: url!)
    }()

    @Test func engineCreation() async throws {
        try library.reset()

        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        #expect(library != nil)
    }

    @Test func runEngineFor1000Cycles() async throws {
        try library.reset()
        await library.run(for: 1000)
        #expect(library.state.cycleCounter == 1000)
    }
}
