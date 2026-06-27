import Foundation
import Testing

@testable import AGC
@testable import LMCore

@Suite("LMCore command decoding")
struct LMCoreCommandDecodingTests {
    @Test func `vehicle snapshot decodes AGC raw channels`() {
        let agc = makeAGCSnapshot(
            inputChannels: [0o16: 0o60000],
            outputChannels: [
                0o5: 0o12121,
                0o6: 0o06060,
                0o11: 0o30000,
                0o12: 0o7400,
                0o13: 0o1420,
                0o14: 0o10
            ]
        )

        let snapshot = LMVehicleSnapshot(agcSnapshot: agc)

        #expect(snapshot.out0 == 0o12121)
        #expect(snapshot.out1 == 0o06060)
        #expect(snapshot.outputChannel11 == 0o30000)
        #expect(snapshot.outputChannel12 == 0o7400)
        #expect(snapshot.outputChannel13 == 0o1420)
        #expect(snapshot.outputChannel14 == 0o10)
        #expect(snapshot.inputChannel16 == 0o60000)
        #expect(snapshot.mainEngineOn)
        #expect(snapshot.mainEngineOff)
        #expect(snapshot.thrustDriveActive)
    }

    @Test func `vehicle snapshot decodes source backed RCS and preserves unknown bits`() {
        let snapshot = LMVehicleSnapshot(out0: 0o377, out1: 0o377)
        let jets = Set(snapshot.rcsJets.map(\.jet))

        #expect(jets == Set([.jet1, .jet2, .jet5, .jet6, .jet9, .jet10, .jet13, .jet14]))
        #expect(snapshot.discreteGroups.contains { $0.name.contains("positive pitch") && $0.mask == 0o125 })
        #expect(snapshot.discreteGroups.contains { $0.name.contains("negative pitch") && $0.mask == 0o252 })
        #expect(snapshot.unmappedBits.contains { $0.channel == 0o6 && $0.bit == 1 })
    }

    @Test func `vehicle snapshot decodes source backed engine gimbal control and crew inputs`() {
        let snapshot = LMVehicleSnapshot(
            outputChannel11: 0o30001,
            outputChannel12: 0o7400,
            outputChannel13: 0o1420,
            outputChannel14: 0o10,
            inputChannel16: 0o60000
        )

        #expect(snapshot.mainEngineCommands.map(\.name).contains("main engine on command"))
        #expect(snapshot.mainEngineCommands.map(\.name).contains("main engine off command"))
        #expect(snapshot.gimbalTrimCommands.count == 4)
        #expect(snapshot.controlCommands.map(\.name).contains("radar activity"))
        #expect(snapshot.controlCommands.map(\.name).contains("RHC counter enable"))
        #expect(snapshot.controlCommands.map(\.name).contains("start RHC read"))
        #expect(snapshot.controlCommands.map(\.name).contains("thrust drive activity"))
        #expect(snapshot.descentRateCommands.map(\.name).contains("DESCEND+ crew input"))
        #expect(snapshot.descentRateCommands.map(\.name).contains("DESCEND- crew input"))
        #expect(snapshot.unmappedBits.contains { $0.channel == 0o11 && $0.bit == 1 })
    }
}

@Suite("LMCore scenarios and dynamics")
struct LMCoreScenarioAndDynamicsTests {
    @Test func `source backed scenario exposes sources and unknowns`() {
        let scenario = LMPoweredDescentScenario.apollo11SourceBacked

        #expect(scenario.initialState.altitudeMeters == 15_240)
        #expect(scenario.initialState.massKilograms == 33_000.0 * 0.45359237)
        #expect(scenario.checkpoints.map(\.program) == [63, 64, 65, 66])
        #expect(!scenario.sourceStatus.sources.isEmpty)
        #expect(scenario.sourceStatus.unmodeledItems.contains("RCS jet positions, vectors, and thrust"))
        #expect(LMVehicleConfiguration.sourceBackedDefault.mainEngine?.engineOnThrustNewtons == nil)
    }

    @Test func `simulation runtime step advances AGC and gravity deterministically`() async throws {
        let initial = LMVehicleStateSnapshot(positionMeters: LMVector3D(z: 10))
        let runtime = try LMSimulationRuntime(coreImage: Data(), initialState: initial)

        let first = await runtime.step(deltaTime: 0.001)
        let second = await runtime.step(deltaTime: 0.001)

        #expect(first.agc.cycle == 85)
        #expect(second.agc.cycle == 170)
        #expect(second.vehicleState.altitudeMeters < first.vehicleState.altitudeMeters)
    }

    @Test func `gravity only propagation is deterministic`() {
        let initial = LMVehicleStateSnapshot(positionMeters: LMVector3D(z: 100))
        let first = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(),
            configuration: .sourceBackedDefault,
            deltaTime: 1
        )
        let second = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(),
            configuration: .sourceBackedDefault,
            deltaTime: 1
        )

        #expect(first == second)
        #expect(first.velocityMetersPerSecond.z < 0)
        #expect(first.altitudeMeters < initial.altitudeMeters)
    }

    @Test func `main engine thrust changes vertical acceleration when sourced`() {
        let source = LMSourceReference(id: "test-source", title: "Test source", detail: "Unit test")
        let initial = LMVehicleStateSnapshot(positionMeters: LMVector3D(z: 100), massKilograms: 1_000)
        let config = LMVehicleConfiguration(
            lunarGravityMetersPerSecondSquared: LMVehicleConfiguration.sourceBackedDefault.lunarGravityMetersPerSecondSquared,
            agcCyclesPerSecond: LMVehicleConfiguration.sourceBackedDefault.agcCyclesPerSecond,
            mainEngine: LMMainEngineConfiguration(
                maximumRatedThrustNewtons: LMSourceValue(2_000, source: source),
                engineOnThrustNewtons: LMSourceValue(2_000, source: source)
            )
        )

        let gravityOnly = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(),
            configuration: config,
            deltaTime: 1
        )
        let powered = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(outputChannel11: 0o10000),
            configuration: config,
            deltaTime: 1
        )

        #expect(powered.velocityMetersPerSecond.z > gravityOnly.velocityMetersPerSecond.z)
    }

    @Test func `RCS commands use only sourced jet geometry`() {
        let source = LMSourceReference(id: "test-rcs-source", title: "Test RCS source", detail: "Unit test")
        let jet = LMRCSJetConfiguration(
            jet: .jet1,
            positionMeters: LMSourceValue(LMVector3D(y: 1), source: source),
            thrustDirectionBody: LMSourceValue(LMVector3D(x: 1), source: source),
            thrustNewtons: LMSourceValue(10, source: source)
        )
        let config = LMVehicleConfiguration(
            lunarGravityMetersPerSecondSquared: LMVehicleConfiguration.sourceBackedDefault.lunarGravityMetersPerSecondSquared,
            agcCyclesPerSecond: LMVehicleConfiguration.sourceBackedDefault.agcCyclesPerSecond,
            rcsJets: [.jet1: jet],
            diagonalInertiaKilogramMetersSquared: LMSourceValue(LMVector3D(x: 1, y: 1, z: 1), source: source)
        )
        let initial = LMVehicleStateSnapshot(positionMeters: LMVector3D(z: 100), massKilograms: 100)

        let next = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(out0: 0o1),
            configuration: config,
            deltaTime: 1
        )

        #expect(next.velocityMetersPerSecond.x > 0)
        #expect(next.angularVelocityRadiansPerSecond.z < 0)
    }
}

private func makeAGCSnapshot(
    inputChannels: [Int: Int] = [:],
    outputChannels: [Int: Int] = [:]
) -> AGCSnapshot {
    let state = AGCState()
    return AGCSnapshot(
        cycle: 0,
        registers: AGCRegisterSnapshot(state: state),
        inputChannels: inputChannels,
        outputChannels: outputChannels,
        interruptRequests: [],
        backtrace: [],
        dsky: DSKYSnapshot(),
        channelTrace: []
    )
}
