import Foundation
import Testing

@testable import AGC

@Suite("AGC checkpoints")
struct AGCCheckpointTests {
    private var luminaryROM: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AGCTests/Luminary099.bin")
    }

    @Test func `sha256 matches published test vectors`() {
        #expect(AGCSHA256.hexDigest(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(AGCSHA256.hexDigest(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(
            AGCSHA256.hexDigest(Data(String(repeating: "a", count: 1_000_000).utf8))
                == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
        )
    }

    @Test func `checkpoint round trip preserves fixture bytes`() async throws {
        let runtime = try AGCRuntime(binFile: luminaryROM)
        _ = await runtime.step(cycles: 100_000)
        let checkpoint = await runtime.captureCheckpoint()

        let decoded = try AGCRuntimeCheckpoint.decodeFixture(try checkpoint.encodedFixture())

        #expect(decoded == checkpoint)
        #expect(decoded.schemaVersion == AGCRuntimeCheckpoint.schemaVersion)
        #expect(decoded.coreImageSHA256.count == 64)
        #expect(decoded.cycleCounter == 100_000)
    }

    @Test func `restored runtime reproduces instruction stream exactly`() async throws {
        let original = try AGCRuntime(binFile: luminaryROM)
        let restored = try AGCRuntime(binFile: luminaryROM)

        for _ in 0..<12 {
            _ = await original.step(cycles: 50_000)
            _ = await restored.step(cycles: 50_000)
        }
        // Pending external channel inputs plus queued DSKY traffic must ride
        // through the fixture instead of being dropped at the capture point.
        await original.enqueueInputs([
            AGCChannelInput(channel: 0o31, value: 0o77775),
            AGCChannelInput(channel: 0o30, value: 0o37777)
        ])
        await original.sendDSKYKey(.verb)

        let checkpoint = await original.captureCheckpoint()
        try await restored.applyCheckpoint(
            try AGCRuntimeCheckpoint.decodeFixture(checkpoint.encodedFixture())
        )

        for step in 0..<24 {
            if step % 6 == 0 {
                let input = AGCChannelInput(channel: 0o16, value: step % 12 == 0 ? 0o40 : 0)
                await original.enqueueInput(input)
                await restored.enqueueInput(input)
            }
            let expected = await original.step(cycles: 12_345)
            let actual = await restored.step(cycles: 12_345)

            #expect(actual.cycle == expected.cycle)
            #expect(actual.registers == expected.registers)
            #expect(actual.inputChannels == expected.inputChannels)
            #expect(actual.outputChannels == expected.outputChannels)
            #expect(actual.interruptRequests == expected.interruptRequests)
            #expect(actual.dsky == expected.dsky)
        }
    }

    @Test func `incompatible fixtures are refused without partial restore`() async throws {
        let original = try AGCRuntime(binFile: luminaryROM)
        _ = await original.step(cycles: 250_000)
        let checkpoint = await original.captureCheckpoint()

        let fresh = try AGCRuntime(binFile: luminaryROM)
        let before = await fresh.snapshot()

        var wrongSchema = checkpoint
        wrongSchema.schemaVersion = AGCRuntimeCheckpoint.schemaVersion + 1
        var thrown: AGCCheckpointError?
        do {
            try await fresh.applyCheckpoint(wrongSchema)
        } catch {
            thrown = error as? AGCCheckpointError
        }
        #expect(thrown == AGCCheckpointError.schemaVersionMismatch(
            expected: AGCRuntimeCheckpoint.schemaVersion,
            found: AGCRuntimeCheckpoint.schemaVersion + 1
        ))

        let romData = try Data(contentsOf: luminaryROM)
        var wrongImage = checkpoint
        wrongImage.coreImageSHA256 = String(repeating: "0", count: 64)
        thrown = nil
        do {
            try await fresh.applyCheckpoint(wrongImage)
        } catch {
            thrown = error as? AGCCheckpointError
        }
        #expect(thrown == AGCCheckpointError.coreImageMismatch(
            expected: AGCRuntimeCheckpoint.coreImageSHA256(of: romData),
            found: String(repeating: "0", count: 64)
        ))

        var truncated = checkpoint
        truncated.erasableMemory = Array(truncated.erasableMemory.prefix(3))
        thrown = nil
        do {
            try await fresh.applyCheckpoint(truncated)
        } catch {
            thrown = error as? AGCCheckpointError
        }
        #expect(thrown == AGCCheckpointError.corruptState(
            "erasable memory must be 8 banks of 1024 words"
        ))

        let after = await fresh.snapshot()
        #expect(after == before, "refused fixtures must not mutate any state")
    }
}
