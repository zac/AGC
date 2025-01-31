import Testing
import Foundation

@testable import AGC

@Test func engineCreation() async throws {
    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    let url = Bundle.module.url(forResource: "Luminary099", withExtension: "bin")
    let library = try AGC(coreFile: url!)
    #expect(library != nil)
}
