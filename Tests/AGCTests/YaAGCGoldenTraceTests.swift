import Foundation
import Testing
@testable import AGC

@Suite("yaAGC golden traces")
struct YaAGCGoldenTraceTests {
    private var luminaryURL: URL? {
        Bundle.module.url(forResource: "Luminary099", withExtension: "bin")
    }

    private func fixtureNamed(_ name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures")
    }

    private var fixtureURL: URL? {
        fixtureNamed("luminary099-boot")
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var liveTracerURL: URL? {
        let env = ProcessInfo.processInfo.environment["AGC_YAAGC_TRACE"].map(URL.init(fileURLWithPath:))
        let fallback = repoRoot.appendingPathComponent("Tools/yaagc-trace/yaagc-trace")
        let url = env ?? fallback
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    @Test func luminaryBootMatchesCommittedYaAGCFixture() async throws {
        let fixtureURL = try #require(fixtureURL)
        let expected = try AGCGoldenTrace.loadJSONL(try Data(contentsOf: fixtureURL))
        #expect(!expected.isEmpty)

        let runtime = try AGCRuntime(binFile: try #require(luminaryURL))
        let actual = await runtime.collectGoldenTrace()
        assertTracesMatch(expected: expected, actual: actual, source: "committed yaAGC fixture")
    }

    @Test(.enabled(if: YaAGCGoldenTraceTests.liveTracerURL != nil))
    func luminaryBootMatchesLiveYaAGCWhenTracerIsPresent() async throws {
        let tracer = try #require(Self.liveTracerURL)
        let rom = try #require(luminaryURL)
        let live = try runTracer(tracer, rom: rom)
        #expect(!live.isEmpty)

        let runtime = try AGCRuntime(binFile: rom)
        let actual = await runtime.collectGoldenTrace()
        assertTracesMatch(expected: live, actual: actual, source: "live yaAGC")
    }

    @Test func luminaryV35EMatchesCommittedYaAGCFixture() async throws {
        try await assertKeyedScriptMatchesFixture(.v35e, fixture: "luminary099-v35e")
    }

    @Test func luminaryV37E63EMatchesCommittedYaAGCFixture() async throws {
        try await assertKeyedScriptMatchesFixture(.v37e63e, fixture: "luminary099-v37e63e")
    }

    @Test(.enabled(if: YaAGCGoldenTraceTests.liveTracerURL != nil))
    func luminaryV35EMatchesLiveYaAGCWhenTracerIsPresent() async throws {
        try await assertKeyedScriptMatchesLive(.v35e)
    }

    private func assertKeyedScriptMatchesFixture(_ script: DSKYScript, fixture: String) async throws {
        let fixtureURL = try #require(fixtureNamed(fixture))
        let expected = try AGCGoldenTrace.loadJSONL(try Data(contentsOf: fixtureURL))
        #expect(!expected.isEmpty)

        let keys = script.goldenTraceKeys()
        let runtime = try AGCRuntime(binFile: try #require(luminaryURL))
        let actual = await runtime.collectGoldenTrace(throughCycle: script.goldenTraceHorizon(), keys: keys)
        assertTracesMatch(expected: expected, actual: actual, source: "committed yaAGC \(script.id)")
    }

    private func assertKeyedScriptMatchesLive(_ script: DSKYScript) async throws {
        let tracer = try #require(Self.liveTracerURL)
        let rom = try #require(luminaryURL)
        let keys = script.goldenTraceKeys()
        let keySpec = keys.map { "\($0.cycle):\(String($0.key.rawValue, radix: 8))" }.joined(separator: ",")
        let live = try runTracer(
            tracer,
            rom: rom,
            arguments: ["\(script.goldenTraceHorizon())", "--keys", keySpec]
        )
        let runtime = try AGCRuntime(binFile: rom)
        let actual = await runtime.collectGoldenTrace(throughCycle: script.goldenTraceHorizon(), keys: keys)
        assertTracesMatch(expected: live, actual: actual, source: "live yaAGC \(script.id)")
    }

    private func runTracer(_ tracer: URL, rom: URL, arguments: [String] = ["\(AGCGoldenTraceSchedule.defaultHorizon)"]) throws -> [AGCGoldenTraceSample] {
        let process = Process()
        process.executableURL = tracer
        process.arguments = [rom.path] + arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let err = String(data: errData, encoding: .utf8) ?? ""
        try #require(process.terminationStatus == 0, "yaAGC tracer failed: \(err)")
        return try AGCGoldenTrace.loadJSONL(outData)
    }

    private func assertTracesMatch(
        expected: [AGCGoldenTraceSample],
        actual: [AGCGoldenTraceSample],
        source: String
    ) {
        if let mismatch = AGCGoldenTrace.firstMismatch(expected: expected, actual: actual) {
            let got = mismatch.actual.map(\.octalDescription) ?? "missing sample"
            let lo = mismatch.expected.c > 5 ? mismatch.expected.c - 5 : 0
            let hi = mismatch.expected.c + 2
            let expectedWindow = expected.filter { $0.c >= lo && $0.c <= hi }.map(\.octalDescription).joined(separator: "\n")
            let actualWindow = actual.filter { $0.c >= lo && $0.c <= hi }.map(\.octalDescription).joined(separator: "\n")
            Issue.record(
                Comment(rawValue: """
                First golden-trace mismatch vs \(source) at cycle \(mismatch.expected.c):
                expected \(mismatch.expected.octalDescription)
                actual   \(got)

                expected window:
                \(expectedWindow)

                actual window:
                \(actualWindow)
                """)
            )
        }
        #expect(
            AGCGoldenTrace.firstMismatch(expected: expected, actual: actual) == nil,
            "Swift engine diverged from \(source)"
        )
        #expect(actual.count >= expected.count)
    }
}

