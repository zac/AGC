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

        #expect(abs(scenario.initialState.positionMeters.x) < 20_000)
        #expect(
            scenario.initialState.groundRangeMeters
                > abs(Luminary99LandingPadLoad.rignZMeters) + 100_000,
            "tabletop starts at PDI, ~look-ahead before RIGN, got \(scenario.initialState.groundRangeMeters)"
        )
        #expect(scenario.initialState.massKilograms == 33_000.0 * 0.45359237)
        #expect(abs(scenario.initialState.velocityMetersPerSecond.magnitude - Luminary99LandingPadLoad.vignMetersPerCentisecond * 100) < 5)
        #expect(
            scenario.initialState.verticalSpeedMetersPerSecond < 0,
            "pre-TIG H-dot should be descent, got \(scenario.initialState.verticalSpeedMetersPerSecond)"
        )
        #expect(
            scenario.initialState.verticalSpeedMetersPerSecond > -15,
            "Kepler coast from RIGN should keep H-dot modest, got \(scenario.initialState.verticalSpeedMetersPerSecond)"
        )
        #expect(
            scenario.initialState.altitudeMeters > 12_000
                && scenario.initialState.altitudeMeters < 20_000,
            "PDI altitude should be ~50,000 ft on the sphere, got \(scenario.initialState.altitudeMeters)"
        )
        let thrust = scenario.initialState.attitude.rotated(LMVector3D(z: 1))
        #expect(thrust.y < -0.98)
        #expect(thrust.z < 0)
        #expect(scenario.checkpoints.map(\.program) == [63, 64, 65, 66])
        #expect(!scenario.sourceStatus.sources.isEmpty)
        #expect(!scenario.sourceStatus.unmodeledItems.contains("Apollo 11 powered-descent initial velocity"))
        #expect(!scenario.sourceStatus.unmodeledItems.contains("Apollo 11 powered-descent initial attitude and angular velocity"))
        #expect(scenario.sourceStatus.unmodeledItems.contains("Apollo 11 powered-descent body angular rates"))
        #expect(!scenario.sourceStatus.unmodeledItems.contains("AGC erasable state vector (RN/VN), REFSMMAT, and Average-G at PDI"))
        #expect(!scenario.sourceStatus.unmodeledItems.contains("RN/VN remaining moon-fixed while IGNALG RP-TO-R’s RLS into Basic Reference"))
        #expect(!scenario.sourceStatus.unmodeledItems.contains("PDI range-to-go (RN starts over NASA RLS, not ~260 nmi uprange) and RN/VN remaining moon-fixed while IGNALG RP-TO-R’s RLS into Basic Reference"))
        #expect(!scenario.sourceStatus.unmodeledItems.contains("P63 braking-phase pad loads (TLAND, RBRFG, and related targets)"))
        #expect(!scenario.sourceStatus.unmodeledItems.contains("P63 V99 ignition handshake (engine-arm already asserted; PRO at V99 is still crew)"))
        #expect(!scenario.sourceStatus.unmodeledItems.contains("P63 IGNALG convergence with modeled (not flown) state vector"))
        #expect(!scenario.sourceStatus.unmodeledItems.contains("RCS jet positions, vectors, and thrust"))
        #expect(!scenario.sourceStatus.unmodeledItems.contains("Channel 006 P-axis RCS per-jet geometry (JETSALL group masks only)"))
        #expect(!scenario.sourceStatus.unmodeledItems.contains("LM inertia tensor"))
        #expect(!scenario.sourceStatus.unmodeledItems.contains("DPS engine-to-CG gimbal moment arm"))
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

    @Test func `auto-land frame holds the AUTO panel and landing-radar altitude`() {
        let input = LMFrameInput.autoLand(altitudeMeters: 100)
        #expect(input.rawChannelInputs.map(\.channel) == [0o30, 0o31, 0o33])
        #expect(input.rawChannelInputs.map(\.value) == [
            LMPoweredDescentPanel.channel30,
            LMPoweredDescentPanel.channel31,
            LMPoweredDescentPanel.channel33
        ])
        #expect(input.radarInput?.rawAGCInput?.altitudeMeter != nil)
        #expect(input.descentRateInput?.descendPlus == false)
        #expect(input.descentRateInput?.descendMinus == false)
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

    @Test func `moon-fixed plant tracks Kepler plus R-TO-RP`() {
        let t0 = Luminary99LandingPadLoad.pdiClockCentiseconds
        let initial = LMAGCNavState.vehicleState(
            timeCentiseconds: t0,
            attitude: .identity,
            massKilograms: 14_969
        )
        let dt = 0.25
        let seconds = 100.0
        var state = initial
        for _ in 1...Int((seconds / dt).rounded()) {
            state = LMDynamics.propagate(
                state: state,
                commands: LMVehicleSnapshot(),
                configuration: .sourceBackedDefault,
                deltaTime: dt
            )
        }
        let r0 = LMAGCNavState.basicReferencePositionMeters(from: initial, timeCentiseconds: t0)
        let v0 = LMAGCNavState.basicReferenceVelocityMetersPerCentisecond(
            from: initial,
            timeCentiseconds: t0
        ) * 100.0
        let mu = Luminary099NavScale.lunarMuMetersCubedPerSecondSquared
        let steps = 100
        let step = seconds / Double(steps)
        var r = r0
        var v = v0
        for _ in 0..<steps {
            func accel(_ pos: LMVector3D) -> LMVector3D {
                let r2 = pos.dot(pos)
                return pos * (-mu / (r2 * sqrt(r2)))
            }
            let half = step / 2
            let k1v = accel(r)
            let k1r = v
            let k2v = accel(r + k1r * half)
            let k2r = v + k1v * half
            let k3v = accel(r + k2r * half)
            let k3r = v + k2v * half
            let k4v = accel(r + k3r * step)
            let k4r = v + k3v * step
            r = r + (k1r + k2r * 2.0 + k3r * 2.0 + k4r) * (step / 6)
            v = v + (k1v + k2v * 2.0 + k3v * 2.0 + k4v) * (step / 6)
        }
        let expected = LuminaryMoonOrientation.rToRP(
            r,
            timeCentiseconds: t0 + seconds * 100.0
        )
        let actual = LMAGCNavState.moonCenteredPositionMeters(from: state)
        #expect(
            (actual - expected).magnitude < 300,
            "rotating-frame plant vs Kepler \(Int((actual - expected).magnitude)) m"
        )
    }

    @Test func `moon-fixed plant tracks Kepler across a P63-length coast`() {
        let t0 = Luminary99LandingPadLoad.pdiClockCentiseconds
        let initial = LMAGCNavState.vehicleState(
            timeCentiseconds: t0,
            attitude: .identity,
            massKilograms: 14_969
        )
        let dt = 0.25
        let seconds = 500.0
        var state = initial
        for _ in 1...Int((seconds / dt).rounded()) {
            state = LMDynamics.propagate(
                state: state,
                commands: LMVehicleSnapshot(),
                configuration: .sourceBackedDefault,
                deltaTime: dt
            )
        }
        let r0 = LMAGCNavState.basicReferencePositionMeters(from: initial, timeCentiseconds: t0)
        let v0 = LMAGCNavState.basicReferenceVelocityMetersPerCentisecond(
            from: initial,
            timeCentiseconds: t0
        ) * 100.0
        let mu = Luminary099NavScale.lunarMuMetersCubedPerSecondSquared
        let steps = 500
        let step = seconds / Double(steps)
        var r = r0
        var v = v0
        for _ in 0..<steps {
            func accel(_ pos: LMVector3D) -> LMVector3D {
                let r2 = pos.dot(pos)
                return pos * (-mu / (r2 * sqrt(r2)))
            }
            let half = step / 2
            let k1v = accel(r)
            let k1r = v
            let k2v = accel(r + k1r * half)
            let k2r = v + k1v * half
            let k3v = accel(r + k2r * half)
            let k3r = v + k2v * half
            let k4v = accel(r + k3r * step)
            let k4r = v + k3v * step
            r = r + (k1r + k2r * 2.0 + k3r * 2.0 + k4r) * (step / 6)
            v = v + (k1v + k2v * 2.0 + k3v * 2.0 + k4v) * (step / 6)
        }
        let expected = LuminaryMoonOrientation.rToRP(
            r,
            timeCentiseconds: t0 + seconds * 100.0
        )
        let actual = LMAGCNavState.moonCenteredPositionMeters(from: state)
        #expect(
            (actual - expected).magnitude < 2_000,
            "500s rotating-frame plant vs Kepler \(Int((actual - expected).magnitude)) m"
        )
    }

    @Test func `PDI RIGN state does not contact the site sphere under MUM gravity`() {
        var state = LMPoweredDescentScenario.apollo11SourceBacked.initialState
        let startAltitude = state.altitudeMeters
        for _ in 0..<180 {
            state = LMDynamics.propagate(
                state: state,
                commands: LMVehicleSnapshot(),
                configuration: .sourceBackedDefault,
                deltaTime: 1
            )
        }
        #expect(!state.isLanded, "flat site-up must not eat PDI altitude, alt=\(state.altitudeMeters)")
        #expect(state.altitudeMeters > 10_000, "coasted PDI altitude \(state.altitudeMeters) from \(startAltitude)")
    }

    @Test func `hypersonic contact far from the site is not a landing`() {
        let site = LMAGCNavState.landingSiteMeters()
        let (north, east, up) = LMAGCNavState.moonFixedSiteBasis()
        let radius = site.magnitude
        let theta = 90_000.0 / radius
        let moon = (up * cos(theta) + east * sin(theta)) * radius
        let delta = moon - site
        let initial = LMVehicleStateSnapshot(
            positionMeters: LMVector3D(
                x: delta.dot(north),
                y: delta.dot(east),
                z: delta.dot(up)
            ),
            velocityMetersPerSecond: LMVector3D(x: 0, y: 900, z: -20),
            massKilograms: 14_969
        )
        #expect(initial.groundRangeMeters > 80_000)
        let next = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(),
            configuration: .sourceBackedDefault,
            deltaTime: 0.1
        )
        #expect(!next.isLanded, "orbital-speed contact 50 nmi out is not touchdown")
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

    @Test func `gimbaled DPS produces 1/ACCS L,PVT-CG torque`() {
        let mass = 33_000.0 * 0.45359237
        let arm = LMInertiaMap.descentEnginePivotToCGMeters(massKilograms: mass)
        #expect(arm > 0)
        #expect(arm < 3)

        let source = LMSourceReference(id: "test-source", title: "Test source", detail: "Unit test")
        let config = LMVehicleConfiguration(
            lunarGravityMetersPerSecondSquared: LMVehicleConfiguration.sourceBackedDefault.lunarGravityMetersPerSecondSquared,
            agcCyclesPerSecond: LMVehicleConfiguration.sourceBackedDefault.agcCyclesPerSecond,
            mainEngine: LMMainEngineConfiguration(
                maximumRatedThrustNewtons: LMSourceValue(10_500 * 4.4482216152605, source: source),
                engineOnThrustNewtons: LMSourceValue(10_500 * 4.4482216152605, source: source)
            )
        )
        let initial = LMVehicleStateSnapshot(
            positionMeters: LMVector3D(z: 100),
            massKilograms: mass,
            dpsPitchGimbalRadians: 2 * .pi / 180
        )
        let next = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(outputChannel11: 0o10000),
            configuration: config,
            deltaTime: 1
        )
        #expect(next.angularVelocityRadiansPerSecond.x < 0)
        #expect(abs(next.angularVelocityRadiansPerSecond.y) < 1e-12)
        #expect(abs(next.angularVelocityRadiansPerSecond.z) < 1e-12)
    }

    @Test func `P63 pace is accelerated until PROG 64`() {
        #expect(LMSimulationPace.pace(programNumber: 63) == .accelerated)
        #expect(LMSimulationPace.pace(programNumber: nil) == .accelerated)
        #expect(LMSimulationPace.pace(programNumber: 64) == .realtime)
        #expect(LMSimulationPace.pace(programNumber: 65) == .realtime)
        #expect(LMSimulationPace.pace(programNumber: 66) == .realtime)
        #expect(LMSimulationPace.pace(programNumber: 63).simulationDelta(wallDelta: 0.016) == 0.25)
        #expect(!LMSimulationPace.pace(programNumber: 63).shouldSleepToFrameRate)
        #expect(LMSimulationPace.pace(programNumber: 64).shouldSleepToFrameRate)
        #expect(abs(LMSimulationPace.pace(programNumber: 64).simulationDelta(wallDelta: 0.016) - 0.016) < 1e-12)
    }

    @Test func `boot and enter P63 keys V37E63E after the boot horizon`() async throws {
        let runtime = try LMSimulationRuntime(coreImage: Data(), scenario: .apollo11SourceBacked)
        let snapshot = await runtime.bootAndEnterP63(bootCycles: 100, cyclesPerKey: 10)
        #expect(snapshot.agc.cycle >= 100 + UInt64(DSKYScript.v37e63e.keys.count) * 10)
        #expect(abs(snapshot.vehicleState.velocityMetersPerSecond.magnitude - Luminary99LandingPadLoad.vignMetersPerCentisecond * 100) < 5)
        #expect(
            snapshot.vehicleState.verticalSpeedMetersPerSecond < 0,
            "boot PDI H-dot should be descent, got \(snapshot.vehicleState.verticalSpeedMetersPerSecond) alt=\(snapshot.vehicleState.altitudeMeters)"
        )
    }

    @Test func `RP-TO-R preserves NASA RLS magnitude and roundtrips`() {
        let time = Luminary99LandingPadLoad.pdiClockCentiseconds
        let rls = Luminary99CoordinatePadLoad.landingSiteMeters
        let reference = LuminaryMoonOrientation.rpToR(rls, timeCentiseconds: time)
        let back = LuminaryMoonOrientation.rToRP(reference, timeCentiseconds: time)
        #expect(abs(reference.magnitude - rls.magnitude) < 1)
        #expect((back - rls).magnitude < 1)

        let matrix = LuminaryMoonOrientation.moonMatrix(timeCentiseconds: time)
        #expect(abs(matrix.r0.magnitude - 1) < 1e-8)
        #expect(abs(matrix.r1.magnitude - 1) < 1e-8)
        #expect(abs(matrix.r2.magnitude - 1) < 1e-8)
        #expect(abs(matrix.r0.dot(matrix.r1)) < 1e-8)
        #expect(abs(matrix.r0.dot(matrix.r2)) < 1e-8)
        #expect(abs(matrix.r1.dot(matrix.r2)) < 1e-8)
    }

    @Test func `landing REFSMMAT puts RIGN on SM X and Z`() {
        let time = Luminary99LandingPadLoad.pdiClockCentiseconds
        let matrix = LMAGCNavState.refsmmat(timeCentiseconds: time)
        let landingNow = LuminaryMoonOrientation.rpToR(
            LMAGCNavState.landingSiteMeters(),
            timeCentiseconds: time
        )
        let landing = LMAGCNavState.landBasic(pipTimeCentiseconds: time)
        let position = LMAGCNavState.rignPositionMeters(pipTimeCentiseconds: time)
        let xsm = matrix.r0
        let ysm = matrix.r1
        let zsm = matrix.r2
        #expect((xsm - landingNow.normalized()).magnitude < 1e-9)
        #expect(abs(xsm.dot(ysm)) < 1e-8)
        #expect(abs(xsm.dot(zsm)) < 1e-8)
        #expect(abs(ysm.dot(zsm)) < 1e-8)
        #expect(abs(xsm.cross(ysm).dot(zsm) - 1) < 1e-8)
        let rgu = LMVector3D(
            x: (position - landing).dot(xsm),
            y: (position - landing).dot(ysm),
            z: (position - landing).dot(zsm)
        )
        #expect(abs(rgu.x - Luminary99LandingPadLoad.rignXMeters) < 2)
        #expect(abs(rgu.y) < 2)
        #expect(abs(rgu.z - Luminary99LandingPadLoad.rignZMeters) < 2)
        let velocity = LMAGCNavState.rignVelocityMetersPerCentisecond(pipTimeCentiseconds: time)
        let vsm = LMVector3D(x: velocity.dot(xsm), y: velocity.dot(ysm), z: velocity.dot(zsm))
        let polarSM = matrix.times(
            LuminaryMoonOrientation.rpToR(LMVector3D(z: 1), timeCentiseconds: time)
        )
        let wm = polarSM * (
            LuminaryMoonOrientation.moonRateRadiansPerCentisecond
                * Luminary099NavScale.guidinitMoonRateHalfUnits
        )
        let rsm = LMVector3D(x: position.dot(xsm), y: position.dot(ysm), z: position.dot(zsm))
        let vgu = vsm + rsm.cross(wm)
        #expect(abs(vgu.magnitude - Luminary99LandingPadLoad.vignMetersPerCentisecond) < 1e-6)
        #expect(vgu.z > 0)
    }

    @Test func `PDI state coasts look-ahead to RIGN with Luminary MUM`() {
        let time = Luminary99LandingPadLoad.pdiClockCentiseconds
        let rign = LMAGCNavState.rignPositionMeters(pipTimeCentiseconds: time)
        let pdi = LMAGCNavState.pdiPositionMeters(pipTimeCentiseconds: time)
        let velocity = LMAGCNavState.pdiVelocityMetersPerCentisecond(pipTimeCentiseconds: time)
        let coastMeters = Luminary99LandingPadLoad.ignalgLookaheadCentiseconds * velocity.magnitude
        #expect(abs((rign - pdi).magnitude - coastMeters) < 5_000)
        #expect((rign - pdi).dot(velocity) > 0)
    }

    @Test func `PDI nav load writes NASA RLS at ECADR 02022 and RP-TO-R RN`() async throws {
        let runtime = try LMSimulationRuntime(coreImage: Data(), scenario: .apollo11SourceBacked)
        await runtime.loadP63PadLoads()
        await runtime.loadPDINavState()

        let rlsX = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.rls)
        #expect(rlsX.high == 0o00301)
        #expect(rlsX.low == 0o34760)
        #expect(await runtime.readErasable(ecadr: 0o1422) == 0)
        #expect(await runtime.readErasable(ecadr: 0o2222) == 0)

        let clock = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.time2)
        let time = clock.decoded(scale: 28)
        let expectedRN = LMAGCNavState.pdiPositionMeters(pipTimeCentiseconds: time)
        let moonFixed = LuminaryMoonOrientation.rToRP(expectedRN, timeCentiseconds: time)
        #expect((expectedRN - moonFixed).magnitude > 1_000)

        let rnX = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.rn)
        let rnY = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.rn + 2)
        let rnZ = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.rn + 4)
        let rn = LMVector3D(
            x: rnX.decoded(scale: Luminary099NavScale.positionScale),
            y: rnY.decoded(scale: Luminary099NavScale.positionScale),
            z: rnZ.decoded(scale: Luminary099NavScale.positionScale)
        )
        #expect(abs(rn.x - expectedRN.x) < 2)
        #expect(abs(rn.y - expectedRN.y) < 2)
        #expect(abs(rn.z - expectedRN.z) < 2)

        let vnX = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.vn)
        let vnY = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.vn + 2)
        let vnZ = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.vn + 4)
        let vn = LMVector3D(
            x: vnX.decoded(scale: Luminary099NavScale.velocityScale),
            y: vnY.decoded(scale: Luminary099NavScale.velocityScale),
            z: vnZ.decoded(scale: Luminary099NavScale.velocityScale)
        )
        let expectedVN = LMAGCNavState.pdiVelocityMetersPerCentisecond(pipTimeCentiseconds: time)
        #expect(abs(vn.x - expectedVN.x) < 1e-6)
        #expect(abs(vn.y - expectedVN.y) < 1e-6)
        #expect(abs(vn.z - expectedVN.z) < 1e-6)

        let tet = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.tetLEM)
        #expect(abs(tet.decoded(scale: 28) - time) < 1)

        let ref00 = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.refsmmat)
        let expectedRef = LMAGCNavState.refsmmat(timeCentiseconds: time)
        let expectedHalf = AGCDoublePrecision.encode(
            value: expectedRef.entry(row: 0, column: 0) * Luminary099NavScale.refsmmatHalfUnit,
            scale: 0
        )
        #expect(ref00.high == expectedHalf.high)
        #expect(ref00.high != 0o20000)

        let moonflag = await runtime.readErasable(ecadr: Luminary099Flag.ecadr(decimalIndex: Luminary099Flag.moonflag))
        let moonBit = 1 << (Luminary099Flag.bit(decimalIndex: Luminary099Flag.moonflag) - 1)
        #expect((moonflag & moonBit) != 0)
        let refsm = await runtime.readErasable(ecadr: Luminary099Flag.ecadr(decimalIndex: Luminary099Flag.refsmflg))
        let refsmBit = 1 << (Luminary099Flag.bit(decimalIndex: Luminary099Flag.refsmflg) - 1)
        #expect((refsm & refsmBit) != 0)
    }

    @Test func `P63 pad load matches NASA Luminary 99 octal and asserts MODE CONTROL AUTO`() async throws {
        let runtime = try LMSimulationRuntime(coreImage: Data(), scenario: .apollo11SourceBacked)
        await runtime.loadP63PadLoads()
        await runtime.applyPoweredDescentPanel()
        _ = await runtime.step(cycles: 1)

        let tlandNASA = Luminary99LandingPadLoad.erasableWords().first { $0.ecadr == Luminary099Erasable.tland }
        #expect(tlandNASA?.value == 0o04247)

        let tland = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.tland)
        let clock = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.time2)
        #expect(
            abs(
                tland.decoded(scale: 28)
                    - Luminary99LandingPadLoad.tlandCentiseconds(fromClock: clock.decoded(scale: 28))
            ) < 1
        )

        let rbrfgX = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.rbrfg)
        #expect(rbrfgX.high == 0o00000)
        #expect(rbrfgX.low == 0o01506)

        let v2fgX = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.v2fg)
        #expect(v2fgX.high == 0o77777)
        #expect(v2fgX.low == 0o73242)

        #expect(await runtime.readErasable(ecadr: Luminary099Erasable.tephem + 1) == 0o20017)
        #expect(await runtime.readErasable(ecadr: Luminary099Erasable.azo) == 0o30624)
        let rlsX = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.rls)
        #expect(rlsX.high == 0o00301)
        #expect(rlsX.low == 0o34760)

        let rignX = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.rignx)
        #expect(rignX.high == 0o77731)
        #expect(rignX.low == 0o44630)

        let snapshot = await runtime.snapshot()
        #expect(snapshot.agc.inputChannels[0o31] == LMPoweredDescentPanel.channel31)
        #expect(snapshot.agc.inputChannels[0o30] == LMPoweredDescentPanel.channel30)
        #expect((snapshot.agc.inputChannels[0o31]! & 0o20000) == 0)
        #expect((snapshot.agc.inputChannels[0o30]! & 0o20) == 0)
    }

    @Test func `P63 crew handshake skips fine-align then holds PROCEED for R60 and V99`() {
        var handshake = LMP63CrewHandshake()
        #expect(handshake.advance(verb: "06", noun: "63", deltaTime: 0.016) == nil)

        #expect(handshake.advance(verb: "06", noun: "61", deltaTime: 0.016) == .pro(pressed: true))
        #expect(handshake.advance(verb: "06", noun: "61", deltaTime: 0.16) == .pro(pressed: false))
        #expect(handshake.advance(verb: "06", noun: "61", deltaTime: 0.016) == nil)

        #expect(handshake.advance(verb: "50", noun: "25", deltaTime: 0.016) == .enter)
        #expect(handshake.advance(verb: "50", noun: "25", deltaTime: 0.016) == nil)
        #expect(handshake.advance(verb: "  ", noun: "  ", deltaTime: 0.016) == nil)

        #expect(handshake.advance(verb: "50", noun: "18", deltaTime: 0.016) == .enter)
        #expect(handshake.advance(verb: "50", noun: "18", deltaTime: 0.016) == nil)
        #expect(handshake.advance(verb: "  ", noun: "  ", deltaTime: 0.016) == nil)

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

    @Test func `DPS FMAX burns mass at Luminary DPSVEX`() {
        let mass = 33_000.0 * 0.45359237
        let dt = 10.0
        let initial = LMVehicleStateSnapshot(
            positionMeters: LMVector3D(z: 20_000),
            massKilograms: mass,
            propellantMassKilograms: 8_000
        )
        let next = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(outputChannel11: 0o10000)
                .withCommandedThrust(LMDPSThrottleMap.fmaxNewtons),
            configuration: .sourceBackedDefault,
            deltaTime: dt
        )
        let expectedBurn = LMDPSThrottleMap.fmaxNewtons
            / LMDPSThrottleMap.dpsExhaustVelocityMetersPerSecond * dt
        #expect(abs((next.massKilograms ?? 0) - (mass - expectedBurn)) < 1e-9)
        #expect(abs((next.propellantMassKilograms ?? 0) - (8_000 - expectedBurn)) < 1e-9)
        #expect(expectedBurn > 100)
        #expect(LMDPSThrottleMap.dpsExhaustVelocityMetersPerSecond == 2.95588868e3)
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

    @Test func `channel 5 plus-U jets produce NASA plus-Q torque`() {
        let initial = LMVehicleStateSnapshot(positionMeters: LMVector3D(z: 100), massKilograms: 14_969)
        let next = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(out0: 0o204),
            configuration: .sourceBackedDefault,
            deltaTime: 1
        )
        #expect(Set(LMVehicleSnapshot(out0: 0o204).rcsJets.map(\.jet)) == Set([.jet5, .jet14]))
        #expect(next.angularVelocityRadiansPerSecond.x > 0)
        #expect(abs(next.angularVelocityRadiansPerSecond.y) < 1e-9)
        #expect(abs(next.angularVelocityRadiansPerSecond.z) < 1e-9)
    }

    @Test func `channel 5 plus-V jets produce NASA plus-Q torque`() {
        let initial = LMVehicleStateSnapshot(positionMeters: LMVector3D(z: 100), massKilograms: 14_969)
        let next = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(out0: 0o041),
            configuration: .sourceBackedDefault,
            deltaTime: 1
        )
        #expect(Set(LMVehicleSnapshot(out0: 0o041).rcsJets.map(\.jet)) == Set([.jet1, .jet10]))
        #expect(next.angularVelocityRadiansPerSecond.x > 0)
        #expect(abs(next.angularVelocityRadiansPerSecond.y) < 1e-9)
        #expect(abs(next.angularVelocityRadiansPerSecond.z) < 1e-9)
    }

    @Test func `plus-U at PDI increases CDUY`() {
        let pdi = LMQuaternion.fromAxisAngle(axis: LMVector3D(x: 1), radians: 95 * .pi / 180)
        let initial = LMVehicleStateSnapshot(
            positionMeters: LMVector3D(y: -400_000, z: 15_000),
            attitude: pdi,
            massKilograms: 14_969
        )
        let next = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(out0: 0o204),
            configuration: .sourceBackedDefault,
            deltaTime: 1
        )
        let before = LMIMUGimbalMap.cduCounts(from: pdi)
        let after = LMIMUGimbalMap.cduCounts(from: next.attitude)
        var delta = after.y - before.y
        if delta > 16_384 { delta -= 32_768 }
        if delta < -16_384 { delta += 32_768 }
        #expect(delta > 0, " +U / +Q should increase CDUY, Δ=\(delta)")
    }

    @Test func `FMAX GTS jerk matches 1/ACCS T L omega-g / I`() {
        let mass = 33_000.0 * 0.45359237
        let thrust = LMDPSThrottleMap.fmaxNewtons
        let plant = LMDPSGimbalMap.qJerkMagnitudeRadiansPerSecondCubed(
            massKilograms: mass,
            thrustNewtons: thrust
        )
        let oneJetQ = LMInertiaMap.oneJetAcceleration(massKilograms: mass, axis: .q, stage: .descent)
        let leverFeet = LMInertiaMap.descentEnginePivotToCGMeters(massKilograms: mass) / 0.3048
        let thrustLbf = thrust / LMDPSThrottleMap.poundsToNewtons
        // TORKJET1 DEC .03757 is 550/0.2 at (+16) 64/180. ACCDOT = T L 1JACC / TORKJET1
        // at PI/2^7, which is T L ω_g / I with ω_g = 0.2 deg/s.
        let tComputer = thrustLbf / 16_384.0
        let lComputer = leverFeet / 8.0
        let jaccComputer = oneJetQ / (.pi / 4.0)
        let torkJet1 = 0.03757
        let accDotComputer = tComputer * lComputer * jaccComputer / torkJet1
        let accDot = accDotComputer * .pi / 128.0
        #expect(plant > 0)
        #expect(abs(plant - accDot) / plant < 0.05, "plant \(plant) 1/ACCS \(accDot)")
    }

    @Test func `minus pitch GTS at FMAX increases CDUY`() {
        let pdi = LMQuaternion.fromAxisAngle(axis: LMVector3D(x: 1), radians: 95 * .pi / 180)
        let mass = 33_000.0 * 0.45359237
        let initial = LMVehicleStateSnapshot(
            positionMeters: LMVector3D(y: -400_000, z: 15_000),
            attitude: pdi,
            massKilograms: mass,
            dpsPitchGimbalRadians: -2 * .pi / 180
        )
        let next = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(outputChannel11: 0o10000)
                .withCommandedThrust(LMDPSThrottleMap.fmaxNewtons),
            configuration: .sourceBackedDefault,
            deltaTime: 1
        )
        #expect(next.angularVelocityRadiansPerSecond.x > 0)
        let before = LMIMUGimbalMap.cduCounts(from: pdi)
        let after = LMIMUGimbalMap.cduCounts(from: next.attitude)
        var delta = after.y - before.y
        if delta > 16_384 { delta -= 32_768 }
        if delta < -16_384 { delta += 32_768 }
        #expect(delta > 0, "minus-pitch GTS / +Q should increase CDUY, Δ=\(delta)")
    }

    @Test func `RCS DAP sampling splits a P63 GET step into T5 slices`() {
        let cps = LMVehicleConfiguration.sourceBackedDefault.agcCyclesPerSecond.value
        let slices = LMRCSSampling.slices(totalCycles: 21_333, deltaTime: 0.25, cyclesPerSecond: cps)
        let sliceCycles = max(1, UInt64((LMRCSSampling.dapPeriodSeconds * cps).rounded(.down)))
        #expect(slices.count >= 20)
        #expect(slices.reduce(UInt64(0)) { $0 + $1.cycles } == 21_333)
        #expect(abs(slices.reduce(0.0) { $0 + $1.deltaTime } - 0.25) < 1e-12)
        #expect(slices.dropLast().allSatisfy { $0.cycles == sliceCycles })
    }

    @Test func `1/ACCS descent inertia is finite at Apollo 11 separation mass`() {
        let mass = 33_000.0 * 0.45359237
        let inertia = LMInertiaMap.diagonalInertiaKilogramMetersSquared(massKilograms: mass, stage: .descent)
        let alphaP = LMInertiaMap.oneJetAcceleration(massKilograms: mass, axis: .p, stage: .descent)

        #expect(inertia.x > 0 && inertia.y > 0 && inertia.z > 0)
        #expect(alphaP > 0)
        #expect(abs(inertia.z * alphaP - LMInertiaMap.oneJetTorqueNewtonMeters) < 1e-6)
        #expect(LMInertiaMap.modelingStatus.isSourceBacked)
        let arm = LMInertiaMap.descentEnginePivotToCGMeters(massKilograms: mass)
        #expect(arm > 0.5 && arm < 2.0)
        #expect(LMInertiaMap.descentEnginePivotBodyMeters(massKilograms: mass).z == -arm)
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
        let pipax = inputs.filter { $0.channel == (0o200 | Register.regPIPAX.rawValue) }
        #expect(pipax.count == Int((2.0 / 0.01).rounded(.towardZero)))
        #expect(pipax.allSatisfy { $0.value == 0 })
        #expect(inputs.filter { $0.channel == (0o200 | Register.regPIPAZ.rawValue) }.isEmpty)
    }

    @Test func `SM specific force matches ENU map at the REFSMMAT epoch`() {
        let time = Luminary99LandingPadLoad.pdiClockCentiseconds
        let ref = LMAGCNavState.refsmmat(timeCentiseconds: time)
        let pdi = LMQuaternion.fromAxisAngle(axis: LMVector3D(x: 1), radians: 95.0 * .pi / 180.0)
        let body = LMVector3D(z: 2)
        let sm = LMAGCNavState.specificForceSM(
            body: body,
            attitude: pdi,
            refsmmat: ref,
            timeCentiseconds: time
        )
        let enu = LMIMUGimbalMap.nasaBody(fromSim: pdi.rotated(body))
        // Libration is in XSM = RP-TO-R(RLS) but not in the ENU shuffle.
        #expect((sm - enu).magnitude < 2e-4)
    }

    @Test func `SM specific force stays within lunar rotation of the ENU map`() {
        let t0 = Luminary99LandingPadLoad.pdiClockCentiseconds
        let t1 = t0 + 80_000
        let ref = LMAGCNavState.refsmmat(timeCentiseconds: t0)
        let pdi = LMQuaternion.fromAxisAngle(axis: LMVector3D(x: 1), radians: 95.0 * .pi / 180.0)
        let body = LMVector3D(z: 2)
        let sm0 = LMAGCNavState.specificForceSM(
            body: body,
            attitude: pdi,
            refsmmat: ref,
            timeCentiseconds: t0
        )
        let sm1 = LMAGCNavState.specificForceSM(
            body: body,
            attitude: pdi,
            refsmmat: ref,
            timeCentiseconds: t1
        )
        let boot0: Double = 1_000
        let bootRef = LMAGCNavState.refsmmat(timeCentiseconds: boot0)
        let boot1 = LMAGCNavState.specificForceSM(
            body: body,
            attitude: pdi,
            refsmmat: bootRef,
            timeCentiseconds: boot0 + 80_000
        )
        let bootEpoch = LMAGCNavState.specificForceSM(
            body: body,
            attitude: pdi,
            refsmmat: bootRef,
            timeCentiseconds: boot0
        )
        let nasa = LMIMUGimbalMap.nasaBody(fromSim: pdi.rotated(body))
        let lunarAngle = LuminaryMoonOrientation.moonRateRadiansPerSecond * 800
        #expect(
            (sm1 - sm0).magnitude < 2 * nasa.magnitude * sin(lunarAngle) + 1e-3,
            "NASA-epoch 800s SM drift \((sm1 - sm0).magnitude) vs 0.12° bound \(2 * nasa.magnitude * sin(lunarAngle))"
        )
        #expect(
            (boot1 - bootEpoch).magnitude < 2 * nasa.magnitude * sin(lunarAngle) + 1e-3,
            "boot-GET 800s SM drift \((boot1 - bootEpoch).magnitude) vs nasa \(nasa.magnitude)"
        )
        #expect((bootEpoch - nasa).magnitude < 2e-4, "boot epoch SM vs ENU \((bootEpoch - nasa).magnitude)")
    }

    @Test func `PDI attitude puts body thrust on PIPAZ, not PIPAX`() {
        var feedback = LMSensorFeedbackState()
        let pdi = LMQuaternion.fromAxisAngle(axis: LMVector3D(x: 1), radians: 95 * .pi / 180)
        let inputs = feedback.increments(
            specificForceBody: LMVector3D(z: 2),
            attitude: pdi,
            deltaTime: 1
        )
        let pipax = inputs.filter { $0.channel == (0o200 | Register.regPIPAX.rawValue) }
        let pipaz = inputs.filter { $0.channel == (0o200 | Register.regPIPAZ.rawValue) }
        #expect(pipaz.count > 180, "95° Q puts thrust on SM -Z (PIPAZ), got \(pipaz.count)")
        #expect(pipax.count < 30, "PDI should not dump DPS ΔV on PIPAX, got \(pipax.count)")
    }

    @Test func `CDU pulses catch up after the first attitude sample`() {
        var feedback = LMSensorFeedbackState()
        let first = feedback.increments(
            specificForceBody: .zero,
            attitude: .identity,
            deltaTime: 0.1
        )
        #expect(first.filter { $0.channel == (0o200 | Register.regCDUX.rawValue) }.isEmpty)

        let tilted = LMQuaternion.fromAxisAngle(axis: LMVector3D(x: 1), radians: .pi / 4)
        let second = feedback.increments(
            specificForceBody: .zero,
            attitude: tilted,
            deltaTime: 0.1
        )
        let cduy = second.filter { $0.channel == (0o200 | Register.regCDUY.rawValue) }
        #expect(!cduy.isEmpty)
        #expect(cduy.allSatisfy { $0.value == 0o21 }, "IMU follow must use high-rate PCDU, got \(cduy.first?.value ?? -1)")
        let pdi = LMIMUGimbalMap.cduCounts(
            from: LMQuaternion.fromAxisAngle(axis: LMVector3D(x: 1), radians: 95 * .pi / 180)
        )
        #expect(pdi.x < 50, "PDI pitch is NASA Q (CDUY), not P (CDUX), got CDUX=\(pdi.x)")
        #expect(abs(pdi.y - 8_642) < 20, "95° → CDUY, got \(pdi.y)")
        #expect(pdi.z < 50)
    }

    @Test func `CDU follow pulses track a 1° Q step at PDI without a 180° jump`() {
        let pdi = LMQuaternion.fromAxisAngle(axis: LMVector3D(x: 1), radians: 95 * .pi / 180)
        let next = LMQuaternion.fromAxisAngle(axis: LMVector3D(x: 1), radians: 96 * .pi / 180)
        var feedback = LMSensorFeedbackState()
        _ = feedback.increments(specificForceBody: .zero, attitude: pdi, deltaTime: 0.01)
        let pulses = feedback.increments(specificForceBody: .zero, attitude: next, deltaTime: 0.01)
        let cduy = pulses.filter { $0.channel == (0o200 | Register.regCDUY.rawValue) }
        let cdux = pulses.filter { $0.channel == (0o200 | Register.regCDUX.rawValue) }
        let cduz = pulses.filter { $0.channel == (0o200 | Register.regCDUZ.rawValue) }
        let expected = Int((1.0 * .pi / 180.0 / LMSensorScale.cduRadiansPerCount.value).rounded(.towardZero))
        #expect(cduy.count == min(expected, LMSensorFeedbackState.maxCDUPulsesPerAxis))
        #expect(cduy.allSatisfy { $0.value == 0o21 })
        #expect(cdux.isEmpty)
        #expect(cduz.isEmpty)
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

    @Test func `Luminary V37E63E enters PROG 63 and IGNALG with pad-load nav`() async throws {
        let romURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AGCTests/Luminary099.bin")
        try #require(FileManager.default.fileExists(atPath: romURL.path))
        let agc = try AGCRuntime(binFile: romURL)
        _ = await agc.step(cycles: 1_000_000)
        await agc.writeErasable(Luminary99LandingPadLoad.erasableWords())
        let time2 = await agc.readErasable(ecadr: Luminary099Erasable.time2)
        let time1 = await agc.readErasable(ecadr: Luminary099Erasable.time1)
        await agc.writeErasable(Luminary99LandingPadLoad.tlandWords(
            fromClock: AGCDoublePrecision(high: time2, low: time1).decoded(scale: 28)
        ))
        await agc.writeErasable(
            LMAGCNavState.erasableWords(
                vehicle: LMPoweredDescentScenario.apollo11SourceBacked.initialState,
                time2: time2,
                time1: time1
            )
        )
        for flag in LMAGCNavState.lunarSphereFlags() {
            await agc.setErasableBit(ecadr: flag.ecadr, bit: flag.bit)
        }
        var snapshot = await agc.snapshot()
        for key in DSKYScript.v37e63e.keys {
            await agc.sendDSKYKey(key)
            snapshot = await agc.step(cycles: 50_000)
        }
        await agc.enqueueInputs(LMPoweredDescentPanel.channelInputs)
        #expect(snapshot.dsky.programNumber == 63, "after V37E63E PROG='\(snapshot.dsky.mode)'")

        func dump() async -> String {
            let fail0 = await agc.readErasable(ecadr: 0o375)
            let fail1 = await agc.readErasable(ecadr: 0o376)
            let fail2 = await agc.readErasable(ecadr: 0o377)
            let nign = await agc.readErasable(ecadr: Luminary099Erasable.nignLoop)
            let tigH = await agc.readErasable(ecadr: Luminary099Erasable.tig)
            let tigL = await agc.readErasable(ecadr: Luminary099Erasable.tig + 1)
            let time2 = await agc.readErasable(ecadr: Luminary099Erasable.time2)
            let time1 = await agc.readErasable(ecadr: Luminary099Erasable.time1)
            let tigMinusGet = AGCDoublePrecision(high: tigH, low: tigL).decoded(scale: 28)
                - AGCDoublePrecision(high: time2, low: time1).decoded(scale: 28)
            let snap = await agc.snapshot()
            let engine = ((snap.outputChannels[0o11] ?? 0) & 0o10000) != 0
            return "NIGN=\(nign) TIG-GET=\(Int(tigMinusGet.rounded())) FAIL=\(String(fail0, radix: 8)),\(String(fail1, radix: 8)),\(String(fail2, radix: 8)) PROG='\(snap.dsky.mode)' V\(snap.dsky.verb) N\(snap.dsky.noun) ENG=\(engine)"
        }

        var trail = "after V37 \(await dump())"
        var last = trail
        var sawEventTimer = false
        var enteredFineAlign = false
        var skippedR60 = false
        var enabledEngine = false
        for step in 1...200 {
            await agc.enqueueInputs(LMPoweredDescentPanel.channelInputs)
            snapshot = await agc.step(cycles: 250_000)
            let now = await dump()
            if now != last {
                trail += " | +\(step * 250_000) \(now)"
                last = now
            }
            let fail1 = await agc.readErasable(ecadr: 0o376)
            let fail2 = await agc.readErasable(ecadr: 0o377)
            if fail1 == 0o1406 || fail1 == 0o1412 || fail1 == 0o1204
                || fail1 == 0o1703 || fail1 == 0o430 || fail2 == 0o430 { break }
            if snapshot.dsky.verb == "06", snapshot.dsky.noun == "61", !sawEventTimer {
                sawEventTimer = true
                await agc.sendPRO(pressed: true)
                snapshot = await agc.step(cycles: 200_000)
                await agc.sendPRO(pressed: false)
                trail += " | PRO V06N61 \(await dump())"
                last = ""
            } else if snapshot.dsky.verb == "50", snapshot.dsky.noun == "25", !enteredFineAlign {
                enteredFineAlign = true
                await agc.sendDSKYKey(.enter)
                trail += " | ENTER V50N25"
                last = ""
            } else if snapshot.dsky.verb == "50", snapshot.dsky.noun == "18", !skippedR60 {
                skippedR60 = true
                await agc.sendDSKYKey(.enter)
                trail += " | ENTER V50N18"
                last = ""
            } else if snapshot.dsky.verb == "99", !enabledEngine {
                enabledEngine = true
                await agc.sendPRO(pressed: true)
                snapshot = await agc.step(cycles: 200_000)
                await agc.sendPRO(pressed: false)
                trail += " | PRO V99 \(await dump())"
                last = ""
            }
            let engineOn = ((snapshot.outputChannels[0o11] ?? 0) & 0o10000) != 0
            if enabledEngine, engineOn { break }
            if skippedR60, snapshot.dsky.programNumber != 63 { break }
        }
        #expect(await agc.readErasable(ecadr: 0o376) != 0o1406, "IGNALG ROOTPSRS POODOO \(trail)")
        #expect(await agc.readErasable(ecadr: 0o376) != 0o1412, "IGNALG 40-loop 01412 \(trail)")
        #expect(await agc.readErasable(ecadr: 0o376) != 0o1204, "WAITLIST 01204 \(trail)")
        #expect(await agc.readErasable(ecadr: 0o376) != 0o1703, "MIDTOAV 01703 TIG slipped \(trail)")
        #expect(await agc.readErasable(ecadr: 0o376) != 0o430, "integration 00430 \(trail)")
        #expect(await agc.readErasable(ecadr: 0o377) != 0o430, "integration 00430 \(trail)")
        #expect(sawEventTimer, "IGNALG should flash V06N61 after DDUM \(trail)")
        #expect(enteredFineAlign, "should flash V50N25 after V06N61 PROCEED \(trail)")
        #expect(skippedR60, "R60 should flash V50N18 \(trail)")
        #expect(enabledEngine, "BURNBABY should paste V99 at TIG-5 \(trail)")
        #expect(snapshot.dsky.programNumber == 63, "during P63 \(trail)")
        #expect(
            ((snapshot.outputChannels[0o11] ?? 0) & 0o10000) != 0,
            "V99 PROCEED should light the engine at TIG \(trail)"
        )
    }

    @Test func `Luminary P63 closed-loop burn after V99 keeps PROG 63 under DPS`() async throws {
        let romURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AGCTests/Luminary099.bin")
        try #require(FileManager.default.fileExists(atPath: romURL.path))
        let runtime = try LMSimulationRuntime(binFile: romURL, scenario: .apollo11SourceBacked)
        var snapshot = await runtime.bootAndEnterP63()
        #expect(snapshot.agc.dsky.programNumber == 63, "after V37E63E PROG='\(snapshot.agc.dsky.mode)'")

        let panel = LMFrameInput(rawChannelInputs: LMPoweredDescentPanel.channelInputs)
        let dt = LMSimulationPace.acceleratedDeltaSeconds

        func dump() async -> String {
            let fail0 = await runtime.readErasable(ecadr: 0o375)
            let fail1 = await runtime.readErasable(ecadr: 0o376)
            let fail2 = await runtime.readErasable(ecadr: 0o377)
            let wch = await runtime.readErasable(ecadr: Luminary099Erasable.wchPhase)
            let abdelv = await runtime.readErasable(ecadr: Luminary099Erasable.abdelv)
            let dvthrush = await runtime.readErasable(ecadr: Luminary099Erasable.dvthrush)
            let dvcntr = await runtime.readErasable(ecadr: Luminary099Erasable.dvcntr)
            let flag2 = await runtime.readErasable(ecadr: Luminary099Erasable.flagwrd2)
            let avegH = await runtime.readErasable(ecadr: Luminary099Erasable.avegExit)
            let avegL = await runtime.readErasable(ecadr: Luminary099Erasable.avegExit + 1)
            let snap = await runtime.snapshot()
            let thrust = snap.vehicleCommands.dps.commandedThrustNewtons ?? 0
            let steer = (flag2 & (1 << (Luminary099Flag.bit(decimalIndex: Luminary099Flag.steersw) - 1))) != 0
            return "FAIL=\(String(fail0, radix: 8)),\(String(fail1, radix: 8)),\(String(fail2, radix: 8)) PROG='\(snap.agc.dsky.mode)' V\(snap.agc.dsky.verb) N\(snap.agc.dsky.noun) WCH=\(wch) ABD=\(abdelv) THR=\(dvthrush) DVC=\(dvcntr) STEER=\(steer) AVEG=\(String(avegH, radix: 8)),\(String(avegL, radix: 8)) ENG=\(snap.vehicleCommands.mainEngineOn) F=\(Int(thrust.rounded()))"
        }

        func aborting(_ fail1: Int, _ fail2: Int) -> Bool {
            fail1 == 0o1406 || fail1 == 0o1412 || fail1 == 0o1204
                || fail1 == 0o1703 || fail1 == 0o430 || fail2 == 0o430
        }

        var trail = "after V37 \(await dump())"
        var last = trail
        var ignited = false
        for step in 1...500 {
            snapshot = await runtime.step(deltaTime: dt, input: panel)
            let now = await dump()
            if now != last {
                trail += " | +\(String(format: "%.1f", Double(step) * dt))s \(now)"
                last = now
            }
            let fail1 = await runtime.readErasable(ecadr: 0o376)
            let fail2 = await runtime.readErasable(ecadr: 0o377)
            if aborting(fail1, fail2) { break }
            if snapshot.vehicleCommands.mainEngineOn {
                ignited = true
                break
            }
            if snapshot.agc.dsky.programNumber != 63 { break }
        }
        #expect(ignited, "V99 should light the engine \(trail)")
        #expect(snapshot.agc.dsky.programNumber == 63, "at TIG \(trail)")
        let avegAtIgnition = (
            await runtime.readErasable(ecadr: Luminary099Erasable.avegExit),
            await runtime.readErasable(ecadr: Luminary099Erasable.avegExit + 1)
        )

        func rnMeters() async -> LMVector3D {
            let x = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.rn)
            let y = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.rn + 2)
            let z = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.rn + 4)
            return LMVector3D(
                x: x.decoded(scale: Luminary099NavScale.positionScale),
                y: y.decoded(scale: Luminary099NavScale.positionScale),
                z: z.decoded(scale: Luminary099NavScale.positionScale)
            )
        }

        let igniteState = snapshot.vehicleState
        let igniteRN = await rnMeters()
        let igniteTime = snapshot.timeSeconds
        let zoomDeadline = Luminary99LandingPadLoad.zoomTimeCentiseconds / 100.0 + 2.0
        var fiveSecond: LMSimulationSnapshot?
        let zoomSteps = Int((zoomDeadline / dt).rounded(.up))
        for step in 1...zoomSteps {
            snapshot = await runtime.step(deltaTime: dt, input: panel)
            let now = await dump()
            if now != last {
                trail += " | +\(String(format: "%.1f", snapshot.timeSeconds - igniteTime))s \(now)"
                last = now
            }
            let fail1 = await runtime.readErasable(ecadr: 0o376)
            let fail2 = await runtime.readErasable(ecadr: 0o377)
            let burned = snapshot.timeSeconds - igniteTime
            if fiveSecond == nil, burned >= 5 {
                fiveSecond = snapshot
                trail += " | burn+5 \(now)"
            }
            if aborting(fail1, fail2) || snapshot.agc.dsky.programNumber != 63 {
                trail += " | abort t=\(String(format: "%.1f", burned)) \(now)"
                break
            }
            if step == zoomSteps {
                trail += " | ZOOM \(now)"
            }
        }
        let early = fiveSecond ?? snapshot
        var coasted = igniteState
        let coastSteps = Int((5.0 / dt).rounded(.up))
        for _ in 1...coastSteps {
            coasted = LMDynamics.propagate(
                state: coasted,
                commands: LMVehicleSnapshot(),
                configuration: .sourceBackedDefault,
                deltaTime: dt
            )
        }
        let burnedRN = await rnMeters()
        let zoomThrust = snapshot.vehicleCommands.dps.commandedThrustNewtons ?? 0
        let avegAtZoom = (
            await runtime.readErasable(ecadr: Luminary099Erasable.avegExit),
            await runtime.readErasable(ecadr: Luminary099Erasable.avegExit + 1)
        )
        let lunlandSeconds = 30.0
        let lunlandSteps = Int((lunlandSeconds / dt).rounded(.up))
        for step in 1...lunlandSteps {
            snapshot = await runtime.step(deltaTime: dt, input: panel)
            let now = await dump()
            if now != last {
                trail += " | +\(String(format: "%.1f", snapshot.timeSeconds - igniteTime))s \(now)"
                last = now
            }
            let fail1 = await runtime.readErasable(ecadr: 0o376)
            let fail2 = await runtime.readErasable(ecadr: 0o377)
            if aborting(fail1, fail2) || snapshot.agc.dsky.programNumber != 63 {
                trail += " | abort t=\(String(format: "%.1f", snapshot.timeSeconds - igniteTime)) \(now)"
                break
            }
            if step == lunlandSteps {
                trail += " | LUNLAND+30 \(now)"
            }
        }
        let lunlandThrust = snapshot.vehicleCommands.dps.commandedThrustNewtons ?? 0
        let avegAfter = (
            await runtime.readErasable(ecadr: Luminary099Erasable.avegExit),
            await runtime.readErasable(ecadr: Luminary099Erasable.avegExit + 1)
        )
        let flag2 = await runtime.readErasable(ecadr: Luminary099Erasable.flagwrd2)
        let steerMask = 1 << (Luminary099Flag.bit(decimalIndex: Luminary099Flag.steersw) - 1)
        let wch = await runtime.readErasable(ecadr: Luminary099Erasable.wchPhase)
        let abdelv = await runtime.readErasable(ecadr: Luminary099Erasable.abdelv)
        let dvthrush = await runtime.readErasable(ecadr: Luminary099Erasable.dvthrush)

        #expect(await runtime.readErasable(ecadr: 0o376) != 0o1406, "IGNALG ROOTPSRS POODOO \(trail)")
        #expect(await runtime.readErasable(ecadr: 0o376) != 0o1412, "IGNALG 40-loop 01412 \(trail)")
        #expect(await runtime.readErasable(ecadr: 0o376) != 0o1204, "WAITLIST 01204 \(trail)")
        #expect(await runtime.readErasable(ecadr: 0o376) != 0o1703, "MIDTOAV 01703 TIG slipped \(trail)")
        #expect(await runtime.readErasable(ecadr: 0o376) != 0o430, "integration 00430 \(trail)")
        #expect(snapshot.agc.dsky.programNumber == 63, "SERVICER should keep P63 \(trail)")
        #expect(snapshot.vehicleCommands.mainEngineOn, "engine should stay on after TIG \(trail)")
        #expect(
            (early.vehicleCommands.dps.commandedThrustNewtons ?? 0) >= LMDPSThrottleMap.minimumThrustNewtons * 0.99,
            "DPS min throttle with engine on \(trail)"
        )
        #expect(
            (early.vehicleState.velocityMetersPerSecond - coasted.velocityMetersPerSecond).magnitude > 0.5,
            "95° DPS should change moon-relative velocity vs a 5 s coast \(trail)"
        )
        #expect(
            (burnedRN - igniteRN).magnitude > 1,
            "Average-G should move RN \(trail)"
        )
        #expect(fiveSecond != nil, "should still be in P63 at TIG+5 \(trail)")
        #expect(
            zoomThrust >= LMDPSThrottleMap.fmaxNewtons * 0.8,
            "P63ZOOM FLATOUT should throttle up at TIG+ZOOMTIME \(trail)"
        )
        #expect(avegAtZoom != avegAtIgnition, "P63ZOOM should connect LUNLAND on AVEGEXIT \(trail)")
        #expect(avegAfter == avegAtZoom, "LUNLAND should stay on AVEGEXIT after ZOOM \(trail)")
        #expect(wch == 0, "WCHPHASE should stay BRAKQUAD after ZOOM \(trail)")
        #expect((flag2 & steerMask) != 0, "DVMON should set STEERSW so LUNLAND can steer \(trail)")
        #expect(abdelv > dvthrush, "ABDELV should stay above DVTHRUSH after FLATOUT \(trail)")
        #expect(
            lunlandThrust >= LMDPSThrottleMap.fmaxNewtons * 0.8,
            "LUNLAND braking should keep DPS near FMAX \(trail)"
        )
        #expect(snapshot.agc.dsky.programNumber == 63, "LUNLAND should keep P63 \(trail)")
        #expect(snapshot.vehicleCommands.mainEngineOn, "engine should stay on under LUNLAND \(trail)")

        let p64Deadline = Luminary99LandingPadLoad.guidDurnCentiseconds / 100.0
        let remainingToLand = max(dt, p64Deadline - (snapshot.timeSeconds - igniteTime))
        let p64Steps = Int((remainingToLand / dt).rounded(.up))
        var reachedP64 = snapshot.agc.dsky.programNumber == 64
        var lastLogged = -10.0
        for _ in 1...p64Steps {
            if reachedP64 { break }
            snapshot = await runtime.step(deltaTime: dt, input: panel)
            let burned = snapshot.timeSeconds - igniteTime
            let now = await dump()
            let fail1 = await runtime.readErasable(ecadr: 0o376)
            let fail2 = await runtime.readErasable(ecadr: 0o377)
            let ttf8 = AGCSinglePrecision(
                word: await runtime.readErasable(ecadr: Luminary099Erasable.ttf8)
            ).decoded(scale: 17)
            let interesting = now != last || snapshot.agc.dsky.programNumber == 64
            if interesting || burned - lastLogged >= 10 {
                trail += " | +\(String(format: "%.1f", burned))s TTF/8=\(Int(ttf8.rounded())) \(now)"
                last = now
                lastLogged = burned
            }
            if aborting(fail1, fail2) {
                trail += " | abort t=\(String(format: "%.1f", burned)) \(now)"
                break
            }
            if snapshot.agc.dsky.programNumber == 64 {
                reachedP64 = true
                trail += " | P64 t=\(String(format: "%.1f", burned)) \(now)"
                break
            }
            if snapshot.agc.dsky.programNumber != 63 {
                trail += " | left P63 t=\(String(format: "%.1f", burned)) \(now)"
                break
            }
        }
        let p64Wch = await runtime.readErasable(ecadr: Luminary099Erasable.wchPhase)
        #expect(await runtime.readErasable(ecadr: 0o376) != 0o1204, "WAITLIST 01204 before P64 \(trail)")
        #expect(reachedP64, "TENDBRAK should start P64 before GUIDDURN \(trail)")
        #expect(snapshot.agc.dsky.programNumber == 64, "STARTP64 NEWMODEX 64 \(trail)")
        #expect(p64Wch == 1, "WCHPHASE should be APPRQUAD in P64 \(trail)")
        #expect(snapshot.vehicleCommands.mainEngineOn, "engine should stay on into P64 \(trail)")

        let remainingToP65 = max(dt, p64Deadline - (snapshot.timeSeconds - igniteTime))
        let p65Steps = Int((remainingToP65 / dt).rounded(.up))
        var reachedP65 = snapshot.agc.dsky.programNumber == 65
        lastLogged = -10.0
        for _ in 1...p65Steps {
            if reachedP65 { break }
            snapshot = await runtime.step(deltaTime: dt, input: panel)
            let burned = snapshot.timeSeconds - igniteTime
            let now = await dump()
            let fail1 = await runtime.readErasable(ecadr: 0o376)
            let fail2 = await runtime.readErasable(ecadr: 0o377)
            let ttf8 = AGCSinglePrecision(
                word: await runtime.readErasable(ecadr: Luminary099Erasable.ttf8)
            ).decoded(scale: 17)
            let interesting = now != last || snapshot.agc.dsky.programNumber == 65
            if interesting || burned - lastLogged >= 10 {
                trail += " | +\(String(format: "%.1f", burned))s TTF/8=\(Int(ttf8.rounded())) \(now)"
                last = now
                lastLogged = burned
            }
            if aborting(fail1, fail2) {
                trail += " | abort t=\(String(format: "%.1f", burned)) \(now)"
                break
            }
            if snapshot.agc.dsky.programNumber == 65 {
                reachedP65 = true
                trail += " | P65 t=\(String(format: "%.1f", burned)) \(now)"
                break
            }
            if snapshot.agc.dsky.programNumber != 64 {
                trail += " | left P64 t=\(String(format: "%.1f", burned)) \(now)"
                break
            }
        }
        let p65Wch = await runtime.readErasable(ecadr: Luminary099Erasable.wchPhase)
        #expect(await runtime.readErasable(ecadr: 0o376) != 0o1204, "WAITLIST 01204 before P65 \(trail)")
        #expect(reachedP65, "TENDAPPR should start P65 before GUIDDURN \(trail)")
        #expect(snapshot.agc.dsky.programNumber == 65, "P65START NEWMODEX 65 \(trail)")
        #expect(p65Wch == 2, "WCHPHASE should be VERTICAL in P65 \(trail)")
        #expect(snapshot.vehicleCommands.mainEngineOn, "engine should stay on into P65 \(trail)")

        let p65Time = snapshot.timeSeconds
        let vertHold = 30.0
        let vertSteps = Int((vertHold / dt).rounded(.up))
        var heldVertical = 0.0
        lastLogged = -10.0
        for _ in 1...vertSteps {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .autoLand(altitudeMeters: snapshot.vehicleState.altitudeMeters)
            )
            heldVertical = snapshot.timeSeconds - p65Time
            let now = await dump()
            let fail1 = await runtime.readErasable(ecadr: 0o376)
            let fail2 = await runtime.readErasable(ecadr: 0o377)
            let interesting = now != last
            if interesting || heldVertical - lastLogged >= 10 {
                trail += " | P65+\(String(format: "%.1f", heldVertical))s \(now)"
                last = now
                lastLogged = heldVertical
            }
            if aborting(fail1, fail2) {
                trail += " | abort P65+\(String(format: "%.1f", heldVertical))s \(now)"
                break
            }
            if snapshot.agc.dsky.programNumber != 65 {
                trail += " | left P65+\(String(format: "%.1f", heldVertical))s \(now)"
                break
            }
        }
        let vertWch = await runtime.readErasable(ecadr: Luminary099Erasable.wchPhase)
        let vertFlag2 = await runtime.readErasable(ecadr: Luminary099Erasable.flagwrd2)
        #expect(await runtime.readErasable(ecadr: 0o376) != 0o1204, "WAITLIST 01204 under VERTGUID \(trail)")
        #expect(heldVertical >= vertHold - dt, "VERTGUID should hold P65 for 30 s \(trail)")
        #expect(snapshot.agc.dsky.programNumber == 65, "VERTGUID should keep P65 \(trail)")
        #expect(vertWch == 2, "WCHPHASE should stay VERTICAL \(trail)")
        #expect((vertFlag2 & steerMask) != 0, "STEERSW should stay set under VERTGUID \(trail)")
        #expect(snapshot.vehicleCommands.mainEngineOn, "engine should stay on under VERTGUID \(trail)")
    }

    @Test func `post-TIG CDUY error stays bounded through ZOOM`() async throws {
        let romURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AGCTests/Luminary099.bin")
        try #require(FileManager.default.fileExists(atPath: romURL.path))
        let runtime = try LMSimulationRuntime(binFile: romURL, scenario: .apollo11SourceBacked)
        var snapshot = await runtime.bootAndEnterP63()
        let dt = LMSimulationPace.acceleratedDeltaSeconds

        func wrappedCDUDelta(_ actual: Int, _ desired: Int) -> Int {
            var delta = (actual & 0o77777) - (desired & 0o77777)
            if delta > 16_384 { delta -= 32_768 }
            if delta < -16_384 { delta += 32_768 }
            return delta
        }

        func spFraction(_ word: Int) -> Double {
            AGCSinglePrecision(word: word).decoded(scale: 0)
        }

        func dump() async -> String {
            let fail0 = await runtime.readErasable(ecadr: 0o375)
            let fail1 = await runtime.readErasable(ecadr: 0o376)
            let fail2 = await runtime.readErasable(ecadr: 0o377)
            let cduy = await runtime.readErasable(ecadr: Register.regCDUY.rawValue)
            let cdud = await runtime.readErasable(ecadr: Luminary099Erasable.cduxd + 1)
            let flag2 = await runtime.readErasable(ecadr: Luminary099Erasable.flagwrd2)
            let accDotQ = await runtime.readErasable(ecadr: Luminary099Erasable.accDotQ)
            let qAccDot = await runtime.readErasable(ecadr: Luminary099Erasable.qAccDot)
            let allowGts = await runtime.readErasable(ecadr: Luminary099Erasable.allowGts)
            let omegaQ = await runtime.readErasable(ecadr: Luminary099Erasable.omegaq)
            let omegaQD = await runtime.readErasable(ecadr: Luminary099Erasable.omegaQD)
            let aosQ = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.aosQ)
            let oneJetQ = await runtime.readErasable(ecadr: Luminary099Erasable.oneJetAccQ)
            let pivot = await runtime.readErasable(ecadr: Luminary099Erasable.pivotToCG)
            let mass = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.mass)
            let abdelv = await runtime.readErasable(ecadr: Luminary099Erasable.abdelv)
            let unfcX = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.unfc2)
            let unfcY = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.unfc2 + 2)
            let unfcZ = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.unfc2 + 4)
            let ttf8 = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.ttf8)
            let rguX = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.rgu)
            let rguZ = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.rgu + 4)
            let wch = await runtime.readErasable(ecadr: Luminary099Erasable.wchPhase)
            let err = Double(wrappedCDUDelta(cduy, cdud)) * 360.0 / 32_768.0
            let gimbal = snapshot.vehicleState.dpsPitchGimbalRadians * 180 / .pi
            let rate = snapshot.vehicleState.angularVelocityRadiansPerSecond.x * 180 / .pi
            let thrust = snapshot.vehicleState.attitude.rotated(LMVector3D(z: 1))
            let tz = thrust.z
            let ty = thrust.y
            let plantJerk = LMDPSGimbalMap.qJerkMagnitudeRadiansPerSecondCubed(
                massKilograms: snapshot.vehicleState.massKilograms ?? 0,
                thrustNewtons: snapshot.vehicleCommands.dps.commandedThrustNewtons ?? 0
            ) * 180 / .pi
            _ = (fail0, fail2, accDotQ, qAccDot, allowGts, omegaQ, omegaQD, aosQ, oneJetQ, pivot, mass, plantJerk)
            return String(
                format: "t=%.1f P\(snapshot.agc.dsky.programNumber ?? 0) CDUY=%o/%o err=%+.1f° gimb=%+.2f° ωx=%+.1f°/s tz=%+.2f ty=%+.2f STEER=%d CH12=%o FAIL=%o ENG=%@ WCH=%d TTF8=%.0f UNFC=%.2f,%.2f,%.2f RGU=%.0f,%.0f ABDELV=%.0f",
                snapshot.timeSeconds,
                cduy,
                cdud,
                err,
                gimbal,
                rate,
                tz,
                ty,
                (flag2 & 0o2000) != 0 ? 1 : 0,
                snapshot.vehicleCommands.outputChannel12,
                fail1,
                snapshot.vehicleCommands.mainEngineOn ? "ON" : "off",
                wch,
                ttf8.decoded(scale: 17),
                unfcX.decoded(scale: 1),
                unfcY.decoded(scale: 1),
                unfcZ.decoded(scale: 1),
                rguX.decoded(scale: 24),
                rguZ.decoded(scale: 24),
                AGCSinglePrecision(word: abdelv).decoded(scale: 13)
            )
        }

        var trail = "after V37 \(await dump())"
        var lastLoggedPre = snapshot.timeSeconds
        var ignited = false
        for _ in 1...500 {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .autoLand(altitudeMeters: snapshot.vehicleState.altitudeMeters)
            )
            let fail1 = await runtime.readErasable(ecadr: 0o376)
            if snapshot.timeSeconds - lastLoggedPre >= 5 || snapshot.vehicleCommands.mainEngineOn {
                trail += " | \(await dump())"
                lastLoggedPre = snapshot.timeSeconds
            }
            if fail1 == 0o401 || fail1 == 0o1406 || fail1 == 0o1412 || fail1 == 0o1204 {
                trail += " | alarm \(await dump())"
                break
            }
            if snapshot.vehicleCommands.mainEngineOn {
                ignited = true
                break
            }
            if snapshot.agc.dsky.programNumber != 63 { break }
        }
        #expect(ignited, "V99 should light the engine \(trail)")

        let igniteTime = snapshot.timeSeconds
        let zoomTime = Luminary99LandingPadLoad.zoomTimeCentiseconds / 100.0
        let holdAfterZoom = 40.0
        let steps = Int(((zoomTime + holdAfterZoom) / dt).rounded(.up))
        var errorAtIgnition = 0.0
        var errorAtZoom = 0.0
        var errorAfterZoom = 0.0
        var cduxErrorAfterZoom = 0.0
        var gimbalAfterZoom = 0.0
        var sawZoom = false
        var lastLogged = -10.0
        for _ in 1...steps {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .autoLand(altitudeMeters: snapshot.vehicleState.altitudeMeters)
            )
            let burned = snapshot.timeSeconds - igniteTime
            let cduy = await runtime.readErasable(ecadr: Register.regCDUY.rawValue)
            let cdudy = await runtime.readErasable(ecadr: Luminary099Erasable.cduxd + 1)
            let cdux = await runtime.readErasable(ecadr: Register.regCDUX.rawValue)
            let cdudx = await runtime.readErasable(ecadr: Luminary099Erasable.cduxd)
            let err = Double(wrappedCDUDelta(cduy, cdudy)) * 360.0 / 32_768.0
            if burned < dt * 1.5 {
                errorAtIgnition = err
            }
            if !sawZoom, burned >= zoomTime {
                sawZoom = true
                errorAtZoom = err
            }
            if burned >= zoomTime + 10 {
                errorAfterZoom = err
                cduxErrorAfterZoom = Double(wrappedCDUDelta(cdux, cdudx)) * 360.0 / 32_768.0
                gimbalAfterZoom = snapshot.vehicleState.dpsPitchGimbalRadians * 180 / .pi
            }
            let now = await dump()
            let fail1 = await runtime.readErasable(ecadr: 0o376)
            if burned - lastLogged >= 2 || fail1 == 0o401 {
                trail += " | burn+\(String(format: "%.1f", burned))s \(now)"
                lastLogged = burned
            }
            if fail1 == 0o401 || fail1 == 0o1406 || fail1 == 0o1412 || fail1 == 0o1204 {
                trail += " | alarm burn+\(String(format: "%.1f", burned))s \(now)"
                break
            }
        }
        let fail1 = await runtime.readErasable(ecadr: 0o376)
        #expect(fail1 != 0o401, "FINDCDUW 00401 gimbal lock \(trail)")
        #expect(sawZoom, "should reach TIG+ZOOM \(trail)")
        #expect(
            abs(errorAfterZoom) < 20,
            "CDUY error should stay <20° after ZOOM (TIG \(String(format: "%+.1f", errorAtIgnition))° ZOOM \(String(format: "%+.1f", errorAtZoom))° later \(String(format: "%+.1f", errorAfterZoom))° gimb=\(String(format: "%+.2f", gimbalAfterZoom))°) \(trail)"
        )
        #expect(
            abs(cduxErrorAfterZoom) < 20,
            "CDUX should not spin away from CDUXD (\(String(format: "%+.1f", cduxErrorAfterZoom))°) \(trail)"
        )
        let cdudyFinal = await runtime.readErasable(ecadr: Luminary099Erasable.cduxd + 1)
        var cdudDeg = Double(cdudyFinal & 0o77777) * 360.0 / 32_768.0
        if cdudDeg > 180 { cdudDeg -= 360 }
        #expect(
            abs(cdudDeg) < 130,
            "CDUYD should stay a braking attitude, not dive through 180° (\(String(format: "%.1f", cdudDeg))°) \(trail)"
        )
    }

    @Test func `at TIG RN tracks the vehicle and LAND is near RLS`() async throws {
        let romURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AGCTests/Luminary099.bin")
        try #require(FileManager.default.fileExists(atPath: romURL.path))
        let runtime = try LMSimulationRuntime(binFile: romURL, scenario: .apollo11SourceBacked)
        var snapshot = await runtime.bootAndEnterP63()
        let dt = LMSimulationPace.acceleratedDeltaSeconds
        for _ in 1...800 {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .autoLand(altitudeMeters: snapshot.vehicleState.altitudeMeters)
            )
            if snapshot.vehicleCommands.mainEngineOn { break }
        }
        let fail1 = await runtime.readErasable(ecadr: 0o376)
        let tigRangeNmi = snapshot.vehicleState.groundRangeMeters / 1852.0
        #expect(
            snapshot.vehicleCommands.mainEngineOn,
            "V99 should light DPS FAIL=\(String(fail1, radix: 8)) PROG=\(snapshot.agc.dsky.programNumber ?? 0) rng=\(Int(tigRangeNmi))nmi"
        )
        for _ in 1...40 {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .autoLand(altitudeMeters: snapshot.vehicleState.altitudeMeters)
            )
        }

        func vec(_ ecadr: Int, scale: Int) async -> LMVector3D {
            let x = await runtime.readDoublePrecision(ecadr: ecadr)
            let y = await runtime.readDoublePrecision(ecadr: ecadr + 2)
            let z = await runtime.readDoublePrecision(ecadr: ecadr + 4)
            return LMVector3D(
                x: x.decoded(scale: scale),
                y: y.decoded(scale: scale),
                z: z.decoded(scale: scale)
            )
        }

        let time2 = await runtime.readErasable(ecadr: Luminary099Erasable.time2)
        let time1 = await runtime.readErasable(ecadr: Luminary099Erasable.time1)
        let get = AGCDoublePrecision(high: time2, low: time1).decoded(scale: 28)
        let pip = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.pipTime)
        let pipTime = pip.decoded(scale: 28)
        let rn27 = await vec(Luminary099Erasable.rn, scale: Luminary099NavScale.positionScale)
        let rn29 = await vec(Luminary099Erasable.rn, scale: 29)
        let landRaw = await vec(Luminary099Erasable.land, scale: Luminary099NavScale.positionScale)
        let rls = LMAGCNavState.landingSiteMeters()
        let vehicleMoon = LMAGCNavState.moonCenteredPositionMeters(from: snapshot.vehicleState)
        let vehicleBasic = LMAGCNavState.basicReferencePositionMeters(
            from: snapshot.vehicleState,
            timeCentiseconds: get
        )
        let vehicleVel = LMAGCNavState.basicReferenceVelocityMetersPerCentisecond(
            from: snapshot.vehicleState,
            timeCentiseconds: get
        ) * 100.0
        let lag = (get - pipTime) / 100.0
        let vehicleAtPip = vehicleBasic - vehicleVel * lag
        let vehicleAhead = vehicleBasic + vehicleVel * 2.0
        let rn = rn29.magnitude > 1_000_000 ? rn29 : rn27
        let rnMoon = LuminaryMoonOrientation.rToRP(rn, timeCentiseconds: get)
        // IGNALG: RP-TO-R then VSL4 MXV REFSMMAT → LAND in SM at 8 × B27.
        let ref = LMAGCNavState.refsmmat(timeCentiseconds: get)
        let landSM = landRaw * 0.125
        let landBasic = ref.timesTranspose(landSM)
        let landMoon = LuminaryMoonOrientation.rToRP(landBasic, timeCentiseconds: get)
        let (north, east, _) = LMAGCNavState.moonFixedSiteBasis()
        func horizontal(_ a: LMVector3D, _ b: LMVector3D) -> Double {
            let delta = a - b
            return hypot(delta.dot(north), delta.dot(east))
        }
        let navErr = (rn - vehicleBasic).magnitude
        let navErrPip = (rn - vehicleAtPip).magnitude
        let navErrAhead = (rn - vehicleAhead).magnitude
        let navErrMoon = horizontal(rnMoon, vehicleMoon)
        let landErr = horizontal(landMoon, rls)
        let rignNmi = abs(Luminary99LandingPadLoad.rignZMeters) / 1852.0
        #expect(
            tigRangeNmi > rignNmi - 5,
            "TIG range \(String(format: "%.1f", tigRangeNmi)) nmi vs NASA RIGN \(String(format: "%.1f", rignNmi)) nmi"
        )
        #expect(
            navErrAhead < 1_000,
            "Average-G RN vs plant \(Int(navErr)) m pip=\(Int(navErrPip)) m ahead2s=\(Int(navErrAhead)) m lag=\(String(format: "%.2f", lag))s moonH=\(Int(navErrMoon)) m |RN29|=\(Int(rn29.magnitude)) |plant|=\(Int(vehicleBasic.magnitude))"
        )
        #expect(
            landErr < 8_000,
            "IGNALG LAND vs RLS \(Int(landErr)) m (\(String(format: "%.1f", landErr / 1852)) nmi)"
        )
    }

    @Test func `at P64 MUNRVG R in SM tracks the plant`() async throws {
        let romURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AGCTests/Luminary099.bin")
        try #require(FileManager.default.fileExists(atPath: romURL.path))
        let runtime = try LMSimulationRuntime(binFile: romURL, scenario: .apollo11SourceBacked)
        var snapshot = await runtime.bootAndEnterP63()
        let dt = LMSimulationPace.acceleratedDeltaSeconds
        for _ in 1...3_200 {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .autoLand(altitudeMeters: snapshot.vehicleState.altitudeMeters)
            )
            if snapshot.agc.dsky.programNumber == 64 { break }
        }
        #expect(snapshot.agc.dsky.programNumber == 64, "should reach P64")

        func dpVector(ecadr: Int, scale: Int) async -> LMVector3D {
            let x = await runtime.readDoublePrecision(ecadr: ecadr)
            let y = await runtime.readDoublePrecision(ecadr: ecadr + 2)
            let z = await runtime.readDoublePrecision(ecadr: ecadr + 4)
            return LMVector3D(
                x: x.decoded(scale: scale),
                y: y.decoded(scale: scale),
                z: z.decoded(scale: scale)
            )
        }
        func readRefsmmat() async -> LMMatrix3 {
            var rows: [LMVector3D] = []
            for row in 0..<3 {
                var components: [Double] = []
                for column in 0..<3 {
                    let dp = await runtime.readDoublePrecision(
                        ecadr: Luminary099Erasable.refsmmat + (row * 3 + column) * 2
                    )
                    components.append(
                        dp.decoded(scale: 0) / Luminary099NavScale.refsmmatHalfUnit
                    )
                }
                rows.append(LMVector3D(x: components[0], y: components[1], z: components[2]))
            }
            return LMMatrix3(r0: rows[0], r1: rows[1], r2: rows[2])
        }

        let time2 = await runtime.readErasable(ecadr: Luminary099Erasable.time2)
        let time1 = await runtime.readErasable(ecadr: Luminary099Erasable.time1)
        let get = AGCDoublePrecision(high: time2, low: time1).decoded(scale: 28)
        let ref = await readRefsmmat()
        let rSM = await dpVector(ecadr: Luminary099Erasable.servicerR, scale: 24)
        let vSM = await dpVector(ecadr: Luminary099Erasable.servicerV, scale: 7)
        let landSM = await dpVector(ecadr: Luminary099Erasable.land, scale: 24)
        let rgu = await dpVector(ecadr: Luminary099Erasable.rgu, scale: 24)
        let rn29 = await dpVector(ecadr: Luminary099Erasable.rn, scale: 29)
        let flag11 = await runtime.readErasable(ecadr: 0o107)
        let vehicleMoon = LMAGCNavState.moonCenteredPositionMeters(from: snapshot.vehicleState)
        let vehicleBasic = LuminaryMoonOrientation.rpToR(vehicleMoon, timeCentiseconds: get)
        let vehicleSM = ref.times(vehicleBasic)
        let vehicleVSM = ref.times(
            LuminaryMoonOrientation.moonRelativeVelocityToReference(
                velocityMetersPerCentisecond: LMAGCNavState.velocityMetersPerCentisecond(
                    from: snapshot.vehicleState
                ),
                moonFixedPosition: vehicleMoon,
                timeCentiseconds: get
            )
        )
        let rls = LMAGCNavState.landingSiteMeters()
        let (north, east, up) = LMAGCNavState.moonFixedSiteBasis()
        let landMoon = LuminaryMoonOrientation.rToRP(ref.timesTranspose(landSM), timeCentiseconds: get)
        func horizontal(_ a: LMVector3D, _ b: LMVector3D) -> Double {
            let delta = a - b
            return hypot(delta.dot(north), delta.dot(east))
        }
        let navErr = (rSM - vehicleSM).magnitude
        let vehicleENUSM = LMVector3D(
            x: vehicleMoon.dot(up),
            y: vehicleMoon.dot(north),
            z: vehicleMoon.dot(east)
        )
        let navErrENU = (rSM - vehicleENUSM).magnitude
        let dV = vSM - vehicleVSM
        let velErr = dV.magnitude * 100.0
        let dR = rSM - vehicleSM
        let vehicleAhead = vehicleSM + vehicleVSM * 200.0
        let navErrAhead = (rSM - vehicleAhead).magnitude
        let plantToRLS = horizontal(vehicleMoon, rls)
        let plantToLand = horizontal(vehicleMoon, landMoon)
        let rnSM = ref.times(rn29)
        #expect(
            navErrAhead < 2_000,
            "MUNRVG R vs plant SM \(Int(navErr)) m ahead2s=\(Int(navErrAhead)) enu=\(Int(navErrENU)) dR=\(Int(dR.x)),\(Int(dR.y)),\(Int(dR.z)) dV=\(String(format: "%.2f,%.2f,%.2f", dV.x * 100, dV.y * 100, dV.z * 100)) velErr=\(Int(velErr))m/s rguZ=\(Int(rgu.z)) plantRLS=\(Int(plantToRLS)) plantLAND=\(Int(plantToLand)) |R|=\(Int(rSM.magnitude)) |LAND|=\(Int(landSM.magnitude)) |RN-R|=\(Int((rnSM - rSM).magnitude)) GET=\(Int(get)) FLG11=\(String(flag11, radix: 8)) P\(snapshot.agc.dsky.programNumber ?? 0) rng=\(String(format: "%.1f", snapshot.vehicleState.groundRangeMeters / 1852))nmi"
        )
    }

    @Test func `Auto-land headless trajectory until land or abort`() async throws {
        let romURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AGCTests/Luminary099.bin")
        try #require(FileManager.default.fileExists(atPath: romURL.path))
        let runtime = try LMSimulationRuntime(binFile: romURL, scenario: .apollo11SourceBacked)
        var snapshot = await runtime.bootAndEnterP63()
        let dt = LMSimulationPace.acceleratedDeltaSeconds
        let deadline = Luminary99LandingPadLoad.guidDurnCentiseconds / 100.0 + 120.0

        func dpVector(ecadr: Int, scale: Int) async -> LMVector3D {
            let x = await runtime.readDoublePrecision(ecadr: ecadr)
            let y = await runtime.readDoublePrecision(ecadr: ecadr + 2)
            let z = await runtime.readDoublePrecision(ecadr: ecadr + 4)
            return LMVector3D(
                x: x.decoded(scale: scale),
                y: y.decoded(scale: scale),
                z: z.decoded(scale: scale)
            )
        }

        func vehicleLine() async -> String {
            let fail1 = await runtime.readErasable(ecadr: 0o376)
            let dap = await runtime.readErasable(ecadr: Luminary099Erasable.dapbools)
            let cdux = await runtime.readErasable(ecadr: Register.regCDUX.rawValue)
            let cduy = await runtime.readErasable(ecadr: Register.regCDUY.rawValue)
            let cdudx = await runtime.readErasable(ecadr: Luminary099Erasable.cduxd)
            let cdudy = await runtime.readErasable(ecadr: Luminary099Erasable.cduxd + 1)
            let flag2 = await runtime.readErasable(ecadr: Luminary099Erasable.flagwrd2)
            let imodes33 = await runtime.readErasable(ecadr: Luminary099Erasable.imodes33)
            let time2 = await runtime.readErasable(ecadr: Luminary099Erasable.time2)
            let time1 = await runtime.readErasable(ecadr: Luminary099Erasable.time1)
            let get = AGCDoublePrecision(high: time2, low: time1).decoded(scale: 28)
            let landRaw = await dpVector(
                ecadr: Luminary099Erasable.land,
                scale: Luminary099NavScale.positionScale
            )
            let rgu = await dpVector(ecadr: Luminary099Erasable.rgu, scale: 24)
            let ttf8 = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.ttf8)
            let ref = LMAGCNavState.refsmmat(timeCentiseconds: get)
            let landMoon = LuminaryMoonOrientation.rToRP(
                ref.timesTranspose(landRaw * 0.125),
                timeCentiseconds: get
            )
            let vehicleMoon = LMAGCNavState.moonCenteredPositionMeters(from: snapshot.vehicleState)
            let toLand = vehicleMoon - landMoon
            let (north, east, _) = LMAGCNavState.moonFixedSiteBasis()
            let rangeToLand = hypot(toLand.dot(north), toLand.dot(east))
            let v = snapshot.vehicleState
            let hvel = hypot(v.velocityMetersPerSecond.x, v.velocityMetersPerSecond.y)
            let thrust = v.attitude.rotated(LMVector3D(z: 1))
            let engine = snapshot.vehicleCommands.mainEngineOn ? "ON" : "off"
            let force = snapshot.vehicleCommands.dps.commandedThrustNewtons ?? 0
            return String(
                format: "t=%.0fs P\(snapshot.agc.dsky.programNumber ?? 0) alt=%.0fft hd=%+.0f hv=%.0f rng=%.1fnmi r2l=%.1fnmi rguZ=%.0f ttf=%.0f %@ RCS=%d ENG=%@ F=%.0f m=%.0f FAIL=%o landed=%@ tz=%+.2f DAP=%o CDU=%o/%o,%o/%o CH12=%o STEER=%d IMU33=%o",
                snapshot.timeSeconds,
                v.altitudeMeters / 0.3048,
                v.verticalSpeedMetersPerSecond,
                hvel,
                abs(v.downrangeMeters) / 1852.0,
                rangeToLand / 1852.0,
                rgu.z,
                ttf8.decoded(scale: 17),
                v.downrangeMeters > 50 ? "past" : "togo",
                snapshot.vehicleCommands.rcsJets.count,
                engine,
                force,
                v.massKilograms ?? 0,
                fail1,
                v.isLanded ? "yes" : "no",
                thrust.z,
                dap,
                cdux,
                cdudx,
                cduy,
                cdudy,
                snapshot.vehicleCommands.outputChannel12,
                (flag2 & 0o2000) != 0 ? 1 : 0,
                imodes33
            )
        }

        var trail = await vehicleLine()
        var lastLogged = -100.0
        var minRange = snapshot.vehicleState.groundRangeMeters
        var maxAltitude = snapshot.vehicleState.altitudeMeters
        var sawP64 = snapshot.agc.dsky.programNumber == 64
        var sawP65 = snapshot.agc.dsky.programNumber == 65
        var ignited = snapshot.vehicleCommands.mainEngineOn
        var outcome = "running"
        let steps = Int((deadline / dt).rounded(.up))
        for _ in 1...steps {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .autoLand(altitudeMeters: snapshot.vehicleState.altitudeMeters)
            )
            ignited = ignited || snapshot.vehicleCommands.mainEngineOn
            sawP64 = sawP64 || snapshot.agc.dsky.programNumber == 64
            sawP65 = sawP65 || snapshot.agc.dsky.programNumber == 65
            minRange = min(minRange, snapshot.vehicleState.groundRangeMeters)
            maxAltitude = max(maxAltitude, snapshot.vehicleState.altitudeMeters)
            let fail1 = await runtime.readErasable(ecadr: 0o376)
            let range = snapshot.vehicleState.groundRangeMeters
            let past = snapshot.vehicleState.downrangeMeters > 50
            let escaped = snapshot.vehicleState.altitudeMeters > 80_000
            let overshot = past && range > 20_000 && minRange < 10_000
            if snapshot.timeSeconds - lastLogged >= 20
                || snapshot.vehicleState.isLanded
                || escaped
                || overshot
            {
                trail += " | " + (await vehicleLine())
                lastLogged = snapshot.timeSeconds
            }
            if snapshot.vehicleState.isLanded {
                outcome = "landed"
                break
            }
            if escaped {
                outcome = "escaped"
                break
            }
            if overshot {
                outcome = "overshot"
                break
            }
            if fail1 == 0o1406 || fail1 == 0o1412 || fail1 == 0o1204
                || fail1 == 0o1703 || fail1 == 0o430 || fail1 == 0o1107 {
                outcome = "alarm"
                trail += " | " + (await vehicleLine())
                break
            }
        }
        if outcome == "running" {
            outcome = "timeout"
            trail += " | " + (await vehicleLine())
        }
        #expect(ignited, "V99 should light DPS \(trail)")
        #expect(sawP64, "TENDBRAK should start P64 \(trail)")
        #expect(sawP65, "TENDAPPR should start P65 \(trail)")
        #expect(outcome != "escaped", "tabletop should not leave the Moon \(trail)")
        #expect(outcome != "overshot", "should not cross the site still fast \(trail)")
        #expect(
            maxAltitude < 30_000,
            "PDI is ~50 kft; max alt \(Int(maxAltitude / 0.3048)) ft \(trail)"
        )
        #expect(
            minRange < 2_000,
            "closest approach \(Int(minRange / 1852)) nmi \(trail)"
        )
        #expect(outcome == "landed", "Auto-land should reach the site \(trail)")
    }

    @Test func `Luminary idle boot keeps RP-TO-R RN and NASA RLS`() async throws {
        let romURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AGCTests/Luminary099.bin")
        try #require(FileManager.default.fileExists(atPath: romURL.path))
        let agc = try AGCRuntime(binFile: romURL)
        _ = await agc.step(cycles: 1_000_000)

        await agc.writeErasable(Luminary99LandingPadLoad.erasableWords())
        let time2 = await agc.readErasable(ecadr: Luminary099Erasable.time2)
        let time1 = await agc.readErasable(ecadr: Luminary099Erasable.time1)
        await agc.writeErasable(Luminary99LandingPadLoad.tlandWords(
            fromClock: AGCDoublePrecision(high: time2, low: time1).decoded(scale: 28)
        ))
        await agc.writeErasable(
            LMAGCNavState.erasableWords(
                vehicle: LMPoweredDescentScenario.apollo11SourceBacked.initialState,
                time2: time2,
                time1: time1
            )
        )
        for flag in LMAGCNavState.lunarSphereFlags() {
            await agc.setErasableBit(ecadr: flag.ecadr, bit: flag.bit)
        }
        _ = await agc.step(cycles: 1)

        let rlsX = await agc.readDoublePrecision(ecadr: Luminary099Erasable.rls)
        #expect(rlsX.high == 0o00301)
        #expect(rlsX.low == 0o34760)

        let time = AGCDoublePrecision(high: time2, low: time1).decoded(scale: 28)
        let expectedRN = LMAGCNavState.pdiPositionMeters(pipTimeCentiseconds: time)
        let rnX = await agc.readDoublePrecision(ecadr: Luminary099Erasable.rn)
        #expect(abs(rnX.decoded(scale: Luminary099NavScale.positionScale) - expectedRN.x) < 2)

        let refsm = await agc.readErasable(ecadr: Luminary099Flag.ecadr(decimalIndex: Luminary099Flag.refsmflg))
        let refsmBit = 1 << (Luminary099Flag.bit(decimalIndex: Luminary099Flag.refsmflg) - 1)
        #expect((refsm & refsmBit) != 0)
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
