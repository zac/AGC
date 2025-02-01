import Testing
import Foundation

@testable import AGC

@Test func engineCreation() async throws {
    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    let url = Bundle.module.url(forResource: "Luminary099", withExtension: "bin")
    let library = try AGC(binFile: url!)
    #expect(library != nil)
}

@Test func engineRunning() async throws {
    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    let url = Bundle.module.url(forResource: "Luminary099", withExtension: "bin")
    let library = try AGC(binFile: url!)
    library.start()

    try! await Task.sleep(for: .seconds(1))

    library.stop()
    #expect(library != nil)
}
