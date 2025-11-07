import Testing
import Foundation

@testable import AGC

@Suite("AGC Tests")
class AGCTests {

    private var library: AGC? = {
        guard let url = Bundle.module.url(forResource: "Luminary099", withExtension: "bin") else {
            return nil
        }
        return try? AGC(binFile: url)
    }()

    @Test func engineCreation() async throws {
        let library = try #require(self.library)
        try library.reset()
    }

    @Test func runEngineFor1000Cycles() async throws {
        let library = try #require(self.library)
        try library.reset()
        await library.run(for: 1000)
        #expect(library.state.cycleCounter == 1000)
    }
}
