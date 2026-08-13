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

        #expect(jets == Set(LMRCSJet.allCases))
        #expect(snapshot.discreteGroups.contains { $0.name.contains("positive pitch") && $0.mask == 0o125 })
        #expect(snapshot.discreteGroups.contains { $0.name.contains("negative pitch") && $0.mask == 0o252 })
        #expect(!snapshot.unmappedBits.contains { $0.channel == 0o6 && $0.bit <= 8 })
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

    @Test func `named commands carry structured source references`() {
        let snapshot = LMVehicleSnapshot(
            out0: 0o1,
            out1: 0o125,
            outputChannel11: 0o30000,
            outputChannel12: 0o7400,
            outputChannel13: 0o1420,
            outputChannel14: 0o10,
            inputChannel16: 0o60000
        )

        #expect(snapshot.rcsJets.allSatisfy { !$0.source.reference.id.isEmpty })
        #expect(snapshot.discreteGroups.allSatisfy { !$0.source.reference.id.isEmpty })
        #expect(snapshot.mainEngineCommands.allSatisfy { !$0.source.reference.id.isEmpty })
        #expect(snapshot.gimbalTrimCommands.allSatisfy { !$0.source.reference.id.isEmpty })
        #expect(snapshot.controlCommands.allSatisfy { !$0.source.reference.id.isEmpty })
        #expect(snapshot.descentRateCommands.allSatisfy { !$0.source.reference.id.isEmpty })
        #expect(snapshot.sourceReferences.contains(.luminaryIOChannels))
    }
}

@Suite("LMCore scenarios and dynamics")
struct LMCoreScenarioAndDynamicsTests {
    @Test func `source backed scenario exposes sources and unknowns`() {
        let scenario = LMPoweredDescentScenario.apollo11SourceBacked

        #expect(abs(scenario.initialState.altitudeMeters - 48_814.0 * 0.3048) < 1e-9)
        #expect(scenario.initialState.massKilograms == 33_000.0 * 0.45359237)
        #expect(abs(scenario.initialState.velocityMetersPerSecond.y - 5_560.0 * 0.3048) < 1e-9)
        #expect(abs(scenario.initialState.velocityMetersPerSecond.z + 4.0 * 0.3048) < 1e-9)
        let thrust = scenario.initialState.attitude.rotated(LMVector3D(z: 1))
        #expect(thrust.y < -0.98)
        #expect(thrust.z < 0)
        #expect(scenario.checkpoints.map(\.program) == [63, 64, 65, 66])
        #expect(!scenario.sourceStatus.sources.isEmpty)
        #expect(!scenario.sourceStatus.unmodeledItems.contains("Apollo 11 powered-descent initial velocity"))
        #expect(!scenario.sourceStatus.unmodeledItems.contains("Apollo 11 powered-descent initial attitude and angular velocity"))
        #expect(scenario.sourceStatus.unmodeledItems.contains("Apollo 11 powered-descent body angular rates"))
        #expect(!scenario.sourceStatus.unmodeledItems.contains("AGC erasable state vector (RN/VN), REFSMMAT, and Average-G at PDI"))
        #expect(scenario.sourceStatus.unmodeledItems.contains("PDI range-to-go (RN starts over NASA RLS, not ~260 nmi uprange) and RN/VN remaining moon-fixed while IGNALG RP-TO-R’s RLS into Basic Reference"))
        #expect(!scenario.sourceStatus.unmodeledItems.contains("P63 braking-phase pad loads (TLAND, RBRFG, and related targets)"))
        #expect(!scenario.sourceStatus.unmodeledItems.contains("P63 V99 ignition handshake (engine-arm already asserted; PRO at V99 is still crew)"))
        #expect(scenario.sourceStatus.unmodeledItems.contains("P63 IGNALG convergence with modeled (not flown) state vector"))
        #expect(!scenario.sourceStatus.unmodeledItems.contains("RCS jet positions, vectors, and thrust"))
        #expect(!scenario.sourceStatus.unmodeledItems.contains("Channel 006 P-axis RCS per-jet geometry (JETSALL group masks only)"))
        #expect(!scenario.sourceStatus.unmodeledItems.contains("LM inertia tensor"))
        #expect(LMVehicleConfiguration.sourceBackedDefault.mainEngine?.engineOnThrustNewtons == nil)
        #expect(LMVehicleConfiguration.sourceBackedDefault.rcsJets.count == 16)
        #expect(LMVehicleConfiguration.sourceBackedDefault.rcsJets[.jet3] != nil)
        #expect(LMVehicleSnapshot().dps.throttleMappingStatus.isSourceBacked)
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

    @Test func `frame input step is deterministic for repeated fixed-step runs`() async throws {
        let input = LMFrameInput(
            descentRateInput: LMDescentRateControlInput(descendPlus: true),
            rawChannelInputs: [
                AGCChannelInput(channel: 0o15, value: 0o1),
                AGCChannelInput(channel: 0o15, value: 0o2)
            ]
        )
        let firstRuntime = try LMSimulationRuntime(coreImage: Data())
        let secondRuntime = try LMSimulationRuntime(coreImage: Data())

        let first = await firstRuntime.step(cycles: 20, input: input)
        let second = await secondRuntime.step(cycles: 20, input: input)

        #expect(first.agc.cycle == second.agc.cycle)
        #expect(first.vehicleState == second.vehicleState)
        #expect(first.traceSample.channelDeltas == second.traceSample.channelDeltas)
    }

    @Test func `ordered raw frame inputs remain ordered in channel trace`() async throws {
        let runtime = try LMSimulationRuntime(coreImage: Data())
        let snapshot = await runtime.step(cycles: 10, input: LMFrameInput(rawChannelInputs: [
            AGCChannelInput(channel: 0o15, value: 0o1),
            AGCChannelInput(channel: 0o15, value: 0o2),
            AGCChannelInput(channel: 0o15, value: 0o3)
        ]))

        let values = snapshot.traceSample.channelDeltas
            .filter { $0.direction == AGCChannelTraceDirection.input.rawValue && $0.channel == 0o15 }
            .map(\.value)
        #expect(values == [0o1, 0o2, 0o3])
    }

    @Test func `atomic frame input matches equivalent explicit input flow`() async throws {
        let frameInput = LMFrameInput(
            rotationalHandControllerInput: LMRotationalHandControllerInput(pitch: 0o11, yaw: 0o22, roll: 0o33),
            descentRateInput: LMDescentRateControlInput(descendMinus: true),
            rawChannelInputs: [AGCChannelInput(channel: 0o15, value: 0o7)]
        )
        let atomic = try LMSimulationRuntime(coreImage: Data())
        let explicit = try LMSimulationRuntime(coreImage: Data())

        let atomicSnapshot = await atomic.step(cycles: 20, input: frameInput)
        await explicit.setRotationalHandControllerInput(LMRotationalHandControllerInput(pitch: 0o11, yaw: 0o22, roll: 0o33))
        await explicit.enqueueInput(AGCChannelInput(channel: 0o15, value: 0o7))
        await explicit.setDescentRateControlInput(descendPlus: false, descendMinus: true)
        let explicitSnapshot = await explicit.step(cycles: 20)

        #expect(atomicSnapshot.agc.inputChannels[0o16] == explicitSnapshot.agc.inputChannels[0o16])
        #expect(atomicSnapshot.agc.cycle == explicitSnapshot.agc.cycle)
        #expect(atomicSnapshot.vehicleState == explicitSnapshot.vehicleState)
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

    @Test func `plus pitch gimbal trim tilts DPS thrust off the body Z axis`() {
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
        let next = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(outputChannel11: 0o10000, outputChannel12: 0o1000),
            configuration: config,
            deltaTime: 1
        )
        #expect(abs(next.dpsPitchGimbalRadians - LMDPSGimbalMap.radiansPerSecond) < 1e-12)
        #expect(next.dpsRollGimbalRadians == 0)
        #expect(next.velocityMetersPerSecond.y < 0)
    }

    @Test func `boot and enter P63 keys V37E63E after the boot horizon`() async throws {
        let runtime = try LMSimulationRuntime(coreImage: Data(), scenario: .apollo11SourceBacked)
        let snapshot = await runtime.bootAndEnterP63(bootCycles: 100, cyclesPerKey: 10)
        #expect(snapshot.agc.cycle >= 100 + UInt64(DSKYScript.v37e63e.keys.count) * 10)
        #expect(abs(snapshot.vehicleState.velocityMetersPerSecond.y - 5_560.0 * 0.3048) < 1)
    }

    @Test func `PDI nav load writes NASA RLS at ECADR 02022 and identity REFSMMAT`() async throws {
        let runtime = try LMSimulationRuntime(coreImage: Data(), scenario: .apollo11SourceBacked)
        await runtime.loadPDINavState()

        let rlsX = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.rls)
        #expect(rlsX.high == 0o00301)
        #expect(rlsX.low == 0o34760)
        #expect(await runtime.readErasable(ecadr: 0o1422) == 0)
        #expect(await runtime.readErasable(ecadr: 0o2222) == 0)

        let site = Luminary99CoordinatePadLoad.landingSiteMeters
        let expectedRN = site.magnitude + 48_814.0 * 0.3048
        let rnX = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.rn)
        let rnY = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.rn + 2)
        let rnZ = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.rn + 4)
        let rn = LMVector3D(
            x: rnX.decoded(scale: Luminary099NavScale.positionScale),
            y: rnY.decoded(scale: Luminary099NavScale.positionScale),
            z: rnZ.decoded(scale: Luminary099NavScale.positionScale)
        )
        #expect(abs(rn.magnitude - expectedRN) < 2)

        let vnX = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.vn)
        let vnY = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.vn + 2)
        let vnZ = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.vn + 4)
        let vn = LMVector3D(
            x: vnX.decoded(scale: Luminary099NavScale.velocityScale),
            y: vnY.decoded(scale: Luminary099NavScale.velocityScale),
            z: vnZ.decoded(scale: Luminary099NavScale.velocityScale)
        )
        let expectedSpeed = hypot(5_560.0 * 0.3048, 4.0 * 0.3048) / 100.0
        #expect(abs(vn.magnitude - expectedSpeed) < 1e-6)

        let ref00 = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.refsmmat)
        #expect(ref00.high == 0o20000)

        let moonflag = await runtime.readErasable(ecadr: Luminary099Flag.ecadr(decimalIndex: Luminary099Flag.moonflag))
        let moonBit = 1 << (Luminary099Flag.bit(decimalIndex: Luminary099Flag.moonflag) - 1)
        #expect((moonflag & moonBit) != 0)
    }

    @Test func `P63 pad load matches NASA Luminary 99 octal and asserts MODE CONTROL AUTO`() async throws {
        let runtime = try LMSimulationRuntime(coreImage: Data(), scenario: .apollo11SourceBacked)
        await runtime.loadP63PadLoads()
        await runtime.applyPoweredDescentPanel()
        _ = await runtime.step(cycles: 1)

        let tland = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.tland)
        #expect(tland.high == 0o04247)
        #expect(tland.low == 0o34030)

        let rbrfgX = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.rbrfg)
        #expect(rbrfgX.high == 0o00000)
        #expect(rbrfgX.low == 0o01506)

        let v2fgX = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.v2fg)
        #expect(v2fgX.high == 0o77777)
        #expect(v2fgX.low == 0o73242)

        let clock = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.time2)
        #expect(abs(clock.decoded(scale: 28) - Luminary99LandingPadLoad.pdiClockCentiseconds) < 1)

        #expect(await runtime.readErasable(ecadr: Luminary099Erasable.tephem + 1) == 0o20017)
        #expect(await runtime.readErasable(ecadr: Luminary099Erasable.azo) == 0o30624)
        let rlsX = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.rls)
        #expect(rlsX.high == 0o00301)
        #expect(rlsX.low == 0o34760)

        let snapshot = await runtime.snapshot()
        #expect(snapshot.agc.inputChannels[0o31] == LMPoweredDescentPanel.channel31)
        #expect(snapshot.agc.inputChannels[0o30] == LMPoweredDescentPanel.channel30)
        #expect((snapshot.agc.inputChannels[0o31]! & 0o20000) == 0)
        #expect((snapshot.agc.inputChannels[0o30]! & 0o20) == 0)
    }

    @Test func `P63 crew handshake skips fine-align then holds PROCEED for R60 and V99`() {
        var handshake = LMP63CrewHandshake()
        #expect(handshake.advance(verb: "06", noun: "63", deltaTime: 0.016) == nil)

        #expect(handshake.advance(verb: "50", noun: "25", deltaTime: 0.016) == .enter)
        #expect(handshake.advance(verb: "50", noun: "25", deltaTime: 0.016) == nil)
        #expect(handshake.advance(verb: "  ", noun: "  ", deltaTime: 0.016) == nil)

        #expect(handshake.advance(verb: "50", noun: "18", deltaTime: 0.016) == .pro(pressed: true))
        #expect(handshake.advance(verb: "  ", noun: "  ", deltaTime: 0.12) == nil)
        #expect(handshake.advance(verb: "50", noun: "18", deltaTime: 0.04) == .pro(pressed: false))
        #expect(handshake.advance(verb: "50", noun: "18", deltaTime: 0.016) == nil)

        #expect(handshake.advance(verb: "99", noun: "62", deltaTime: 0.016) == .pro(pressed: true))
        #expect(handshake.advance(verb: "99", noun: "62", deltaTime: 0.16) == .pro(pressed: false))
        #expect(handshake.advance(verb: "99", noun: "62", deltaTime: 0.016) == nil)
        #expect(handshake.advance(verb: "  ", noun: "  ", deltaTime: 0.016) == nil)

        #expect(handshake.advance(verb: "06", noun: "63", deltaTime: 0.016) == nil)
        #expect(handshake.advance(verb: "99", noun: "62", deltaTime: 0.016) == .pro(pressed: true))
    }

    @Test func `PROCEED press and release drive inverted channel 32 bit 14`() async throws {
        let runtime = try LMSimulationRuntime(coreImage: Data(), scenario: .apollo11SourceBacked)
        let before = await runtime.step(cycles: 1)
        #expect((before.agc.inputChannels[0o32]! & 0o20000) != 0)

        await runtime.sendPRO(pressed: true)
        let pressed = await runtime.step(cycles: 10)
        #expect((pressed.agc.inputChannels[0o32]! & 0o20000) == 0)
        #expect(pressed.agc.dsky.proKeyPressed)

        await runtime.sendPRO(pressed: false)
        let released = await runtime.step(cycles: 10)
        #expect((released.agc.inputChannels[0o32]! & 0o20000) != 0)
        #expect(!released.agc.dsky.proKeyPressed)
    }

    @Test func `unsourced DPS engine command does not change vertical acceleration`() {
        let initial = LMVehicleStateSnapshot(positionMeters: LMVector3D(z: 100), massKilograms: 1_000)
        let gravityOnly = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(),
            configuration: .sourceBackedDefault,
            deltaTime: 1
        )
        let commanded = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(outputChannel11: 0o10000),
            configuration: .sourceBackedDefault,
            deltaTime: 1
        )

        #expect(commanded.velocityMetersPerSecond.z == gravityOnly.velocityMetersPerSecond.z)
    }

    @Test func `mapped DPS throttle at minimum increases vertical acceleration when engine is on`() {
        let initial = LMVehicleStateSnapshot(positionMeters: LMVector3D(z: 100), massKilograms: 1_000)
        let gravityOnly = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(),
            configuration: .sourceBackedDefault,
            deltaTime: 1
        )
        let powered = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(outputChannel11: 0o10000)
                .withCommandedThrust(LMDPSThrottleMap.minimumThrustNewtons),
            configuration: .sourceBackedDefault,
            deltaTime: 1
        )

        #expect(powered.velocityMetersPerSecond.z > gravityOnly.velocityMetersPerSecond.z)
        #expect(LMDPSThrottleMap.onesComplement15(0o10000) == 4096)
        #expect(abs((LMDPSThrottleMap.fmaxNewtons / LMDPSThrottleMap.fmaxPulseUnits) - LMDPSThrottleMap.newtonsPerPulse) < 1e-9)
    }

    @Test func `default channel 5 RCS geometry produces +X translation for jet 10`() {
        let initial = LMVehicleStateSnapshot(positionMeters: LMVector3D(z: 100), massKilograms: 1_000)
        let gravityOnly = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(),
            configuration: .sourceBackedDefault,
            deltaTime: 1
        )
        let next = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(out0: 0o40),
            configuration: .sourceBackedDefault,
            deltaTime: 1
        )

        #expect(LMVehicleSnapshot(out0: 0o40).rcsJets.map(\.jet) == [.jet10])
        #expect(next.velocityMetersPerSecond.z > gravityOnly.velocityMetersPerSecond.z)
        #expect(LMVehicleConfiguration.sourceBackedDefault.rcsJets.count == 16)
    }

    @Test func `channel 6 plus-P jets produce NASA plus-X torque`() {
        let initial = LMVehicleStateSnapshot(positionMeters: LMVector3D(z: 100), massKilograms: 1_000)
        let gravityOnly = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(),
            configuration: .sourceBackedDefault,
            deltaTime: 1
        )
        let next = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(out1: 0o125),
            configuration: .sourceBackedDefault,
            deltaTime: 1
        )

        #expect(Set(LMVehicleSnapshot(out1: 0o125).rcsJets.map(\.jet)) == Set([.jet3, .jet7, .jet11, .jet15]))
        #expect(next.angularVelocityRadiansPerSecond.z > gravityOnly.angularVelocityRadiansPerSecond.z)
    }

    @Test func `1/ACCS descent inertia is finite at Apollo 11 separation mass`() {
        let mass = 33_000.0 * 0.45359237
        let inertia = LMInertiaMap.diagonalInertiaKilogramMetersSquared(massKilograms: mass, stage: .descent)
        let alphaP = LMInertiaMap.oneJetAcceleration(massKilograms: mass, axis: .p, stage: .descent)

        #expect(inertia.x > 0 && inertia.y > 0 && inertia.z > 0)
        #expect(alphaP > 0)
        #expect(abs(inertia.z * alphaP - LMInertiaMap.oneJetTorqueNewtonMeters) < 1e-6)
        #expect(LMInertiaMap.modelingStatus.isSourceBacked)
    }

    @Test func `raw radar frame input is retained by simulation snapshots`() async throws {
        let raw = LMRadarInput.raw(LMRadarRawInput(rendezvousRadarWord: 0o12345, altitudeMeterWord: 0o54321))
        let runtime = try LMSimulationRuntime(coreImage: Data())
        let snapshot = await runtime.step(deltaTime: 0.001, input: LMFrameInput(radarInput: raw))

        #expect(snapshot.sensorState.radarInput == raw)
        #expect(snapshot.sensorState.radarInput?.rawAGCInput?.rendezvousRadar == 0o12345)
        #expect(snapshot.sensorState.radarInput?.rawAGCInput?.altitudeMeter == 0o54321)
        #expect(snapshot.sourceStatus.sources.contains(.yaAGCRadarRequest))
    }

    @Test func `AGC raw radar input reaches registers when requested`() async throws {
        let raw = LMRadarInput.raw(LMRadarRawInput(rendezvousRadarWord: 0o12345, altitudeMeterWord: 0o54321))
        let runtime = try AGCRuntime(coreImage: Data())
        await runtime.setRadarInput(raw.rawAGCInput)
        let snapshot = await runtime.integrationTestCompleteRadarSampleGate()

        #expect(snapshot.registers.rendezvousRadar == 0o12345)
        #expect(snapshot.registers.altitudeMeter == 0o54321)
        #expect(raw.conversionStatus.source?.reference == .yaAGCRadarRequest)
    }

    @Test func `SI radar frame input converts altitude at landing-radar low scale`() async throws {
        let runtime = try LMSimulationRuntime(coreImage: Data())
        let snapshot = await runtime.step(deltaTime: 0.001, input: LMFrameInput(
            radarInput: .measurement(LMRadarMeasurementInput(rangeMeters: 100, altitudeMeters: 80))
        ))

        #expect(snapshot.sensorState.radarInput?.conversionStatus.isSourceBacked == true)
        #expect(snapshot.sensorState.radarInput?.rawAGCInput?.altitudeMeter == Int((80.0 / (1.079 * 0.3048)).rounded()))
        #expect(snapshot.sourceStatus.sources.contains(.luminaryLandingRadarScale))
        #expect(!snapshot.sourceStatus.unmodeledItems.contains("SI radar measurement conversion into AGC raw words is unmodeled."))
    }

    @Test func `PIPA pulses accumulate from body specific force`() {
        var feedback = LMSensorFeedbackState()
        let inputs = feedback.increments(
            specificForceBody: LMVector3D(z: 2),
            attitude: .identity,
            deltaTime: 1
        )
        let pipaz = inputs.filter { $0.channel == (0o200 | Register.regPIPAZ.rawValue) }
        #expect(pipaz.count == Int((2.0 / 0.0585).rounded(.towardZero)))
        #expect(pipaz.allSatisfy { $0.value == 0 })
        #expect(inputs.filter { $0.channel == (0o200 | Register.regPIPAX.rawValue) }.isEmpty)
    }

    @Test func `CDU pulses catch up after the first attitude sample`() {
        var feedback = LMSensorFeedbackState()
        let first = feedback.increments(
            specificForceBody: .zero,
            attitude: .identity,
            deltaTime: 0.1
        )
        #expect(first.filter { $0.channel == (0o200 | Register.regCDUX.rawValue) }.isEmpty)

        let tilted = LMQuaternion(w: cos(.pi / 8), x: 0, y: sin(.pi / 8), z: 0)
        let second = feedback.increments(
            specificForceBody: .zero,
            attitude: tilted,
            deltaTime: 0.1
        )
        let cduy = second.filter { $0.channel == (0o200 | Register.regCDUY.rawValue) }
        #expect(!cduy.isEmpty)
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

    @Test func `powered descent validation records checkpoint and channel activity`() async throws {
        let runtime = try LMSimulationRuntime(coreImage: Data(), scenario: .apollo11SourceBacked)
        let snapshot = await runtime.sendDSKYScript(.v37e63e, cyclesPerKey: 10)
        let samples = await runtime.simulationTrace()
        let result = LMPoweredDescentValidationResult(
            scenario: .apollo11SourceBacked,
            samples: samples,
            finalSnapshot: snapshot
        )

        #expect(result.checkpointResults.first { $0.id == "p63" }?.status == .observed)
        #expect((result.channelActivityCounts[0o15] ?? 0) >= DSKYScript.v37e63e.keys.count)
        #expect(result.finalState != nil)
        #expect(!result.unmodeledItems.isEmpty)
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
