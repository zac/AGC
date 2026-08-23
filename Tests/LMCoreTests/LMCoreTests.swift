import Foundation
import Testing

@testable import AGC
@testable import LMCore

@Suite("LMCore command decoding")
struct LMCoreCommandDecodingTests {
    @Test func `vehicle snapshot decodes AGC raw channels`() {
        let agc = makeAGCSnapshot(
            inputChannels: [0o16: 0o140],
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
        #expect(snapshot.inputChannel16 == 0o140)
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
            inputChannel16: 0o140
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
            inputChannel16: 0o140
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
    @Test func `flight recording round trips and replay interpolates the verified state`() throws {
        let start = LMFlightFrame(
            timeSeconds: 100,
            cycle: 1_000,
            programNumber: 66,
            vehicleState: LMVehicleStateSnapshot(
                positionMeters: LMVector3D(z: 10),
                velocityMetersPerSecond: LMVector3D(z: -1),
                massKilograms: 7_000
            ),
            vehicleCommands: LMVehicleSnapshot(outputChannel11: 0o10000),
            panelState: .p66AttitudeHold,
            rhcPitch: 0o10,
            descentRateChannel16: 0o100
        )
        let contact = LMSurfaceContactSnapshot(
            groundRangeMeters: 0.1,
            horizontalSpeedMetersPerSecond: 0.1,
            verticalSpeedMetersPerSecond: 0.2,
            tiltRadians: 0.01
        )
        let end = LMFlightFrame(
            timeSeconds: 102,
            cycle: 2_000,
            programNumber: 66,
            vehicleState: LMVehicleStateSnapshot(
                positionMeters: LMVector3D(x: 10),
                attitude: .fromAxisAngle(axis: LMVector3D(y: 1), radians: .pi / 2),
                massKilograms: 6_998,
                flightOutcome: .softLanding,
                surfaceContact: contact
            ),
            vehicleCommands: LMVehicleSnapshot(outputChannel11: 0o20000),
            panelState: .p66AttitudeHold
        )
        let recording = LMFlightRecording(
            controlMode: .astronautP66,
            frames: [end, start]
        )

        let data = try recording.encoded()
        let encodedAgain = try recording.encoded()
        let decoded = try LMFlightRecording.decode(data)
        #expect(data == encodedAgain)
        #expect(decoded == recording)
        #expect(recording.durationSeconds == 2)
        #expect(recording.flightOutcome == .softLanding)

        let replay = LMFlightReplay(recording: recording)
        let middle = try #require(replay.frame(at: 1))
        #expect(abs(middle.vehicleState.positionMeters.x - 5) < 1e-9)
        #expect(abs((middle.vehicleState.massKilograms ?? 0) - 6_999) < 1e-9)
        let thrustAxis = middle.vehicleState.attitude.rotated(LMVector3D(z: 1))
        #expect(abs(thrustAxis.x - sqrt(0.5)) < 1e-9)
        #expect(abs(thrustAxis.z - sqrt(0.5)) < 1e-9)
        #expect(middle.vehicleCommands.outputChannel11 == 0o10000)
        #expect(middle.rhcPitch == 0o10)
        #expect(middle.descentRateChannel16 == 0o100)
        #expect(middle.vehicleState.flightOutcome == .inFlight)

        let landed = try #require(replay.frame(at: 99))
        #expect(landed.vehicleState.flightOutcome == .softLanding)
        #expect(landed.vehicleState.surfaceContact == contact)
    }

    @Test func `P66 pilot encodes signed ACA counts`() {
        let input = LMRotationalHandControllerInput.signedCounts(
            pitch: -1,
            yaw: 1,
            roll: -2
        )

        #expect(input.pitch == 0o77776)
        #expect(input.yaw == 0o1)
        #expect(input.roll == 0o77775)
        #expect(input.outOfDetent)
    }

    @Test func `P66 pilot tilts thrust against horizontal velocity`() {
        let pilot = LMP66Pilot()
        let northbound = pilot.attitudeController(for: LMVehicleStateSnapshot(
            velocityMetersPerSecond: LMVector3D(x: 10)
        ))
        let eastbound = pilot.attitudeController(for: LMVehicleStateSnapshot(
            velocityMetersPerSecond: LMVector3D(y: 10)
        ))

        #expect(northbound.roll == 0o77767)
        #expect(northbound.yaw == 0)
        #expect(eastbound.pitch == 0o10)
        #expect(eastbound.roll == 0)
        let pulsedPilot = LMP66Pilot(correctionIntervalFrames: 4)
        #expect(
            pulsedPilot.attitudeController(
                for: LMVehicleStateSnapshot(velocityMetersPerSecond: LMVector3D(x: 10)),
                frameIndex: 1
            ) == .signedCounts()
        )
    }

    @Test func `P66 pilot damps tilt and body rate back toward upright`() {
        let pilot = LMP66Pilot()
        let tilt = 5 * Double.pi / 180
        let tilted = pilot.attitudeController(for: LMVehicleStateSnapshot(
            attitude: LMQuaternion(w: cos(tilt / 2), x: sin(tilt / 2)),
            angularVelocityRadiansPerSecond: LMVector3D(x: 0.02)
        ))

        #expect(tilted.pitch == 0o77767)
        #expect(tilted.yaw == 0)
        #expect(tilted.roll == 0)
    }

    @Test func `P66 pilot uses momentary ROD clicks to follow terminal descent profile`() {
        let pilot = LMP66Pilot()
        let hoveringHigh = pilot.descentRateController(for: LMVehicleStateSnapshot(
            positionMeters: LMVector3D(z: 40),
            velocityMetersPerSecond: LMVector3D(z: 0)
        ))
        let descendingFastLow = pilot.descentRateController(for: LMVehicleStateSnapshot(
            positionMeters: LMVector3D(z: 5),
            velocityMetersPerSecond: LMVector3D(z: -1)
        ))

        #expect(hoveringHigh.descendMinus)
        #expect(!hoveringHigh.descendPlus)
        #expect(descendingFastLow.descendPlus)
        #expect(!descendingFastLow.descendMinus)
        #expect(
            pilot.descentRateController(
                for: LMVehicleStateSnapshot(positionMeters: LMVector3D(z: 40)),
                frameIndex: 1
            ).channel16Value == 0
        )
    }

    @Test func `source backed scenario exposes sources and unknowns`() {
        let scenario = LMPoweredDescentScenario.apollo11SourceBacked

        #expect(abs(scenario.initialState.positionMeters.x) < 20_000)
        #expect(
            scenario.initialState.groundRangeMeters
                > abs(Luminary99LandingPadLoad.rignZMeters) + 100_000,
            "tabletop starts at the pre-ignition lead, before PDI and RIGN, got \(scenario.initialState.groundRangeMeters)"
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
            "pre-ignition lead altitude should remain near 50,000 ft, got \(scenario.initialState.altitudeMeters)"
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
        #expect(input.poweredDescentPanelState == nil)
        #expect(input.rawChannelInputs.map(\.channel) == [0o30, 0o31, 0o33])
        #expect(input.rawChannelInputs.map(\.value) == [
            LMPoweredDescentPanel.channel30,
            LMPoweredDescentPanel.channel31,
            LMPoweredDescentPanel.channel33
        ])
        #expect(input.radarInput?.rawAGCInput?.altitudeMeter != nil)
        #expect(input.radarInput?.rawAGCInput?.landingRadarVelocityX == nil)
        #expect(input.descentRateInput?.descendPlus == false)
        #expect(input.descentRateInput?.descendMinus == false)
    }

    @Test func `astronaut landing frame holds ATT HOLD ACA and ROD controls`() {
        let aca = LMRotationalHandControllerInput(pitch: 0o11, yaw: 0o22, roll: 0o33)
        let input = LMFrameInput.astronautLand(
            from: LMVehicleStateSnapshot(positionMeters: LMVector3D(z: 100)),
            panelState: .p66AttitudeHold,
            attitudeController: aca,
            descendMinus: true
        )

        #expect(input.poweredDescentPanelState == .p66AttitudeHold)
        #expect(
            input.poweredDescentPanelState?.channel31Value
                == (LMPoweredDescentPanel.channel31 & ~LMPoweredDescentPanel.channel31AttitudeHold)
        )
        #expect(input.rotationalHandControllerInput == aca)
        #expect(input.descentRateInput == LMDescentRateControlInput(descendMinus: true))
        #expect(aca.outOfDetent)
        #expect(
            input.poweredDescentPanelState?
                .channel31Value(rhcOutOfDetent: aca.outOfDetent)
                == (LMPoweredDescentPanel.channel31
                    & ~LMPoweredDescentPanel.channel31AttitudeHold
                    & ~LMPoweredDescentPanel.channel31RHCOutOfDetent)
        )
    }

    @Test func `astronaut frame drives ATT HOLD and RHC out-of-detent discretes`() async throws {
        let runtime = try LMSimulationRuntime(coreImage: Data())
        let state = LMVehicleStateSnapshot(positionMeters: LMVector3D(z: 100))
        let snapshot = await runtime.step(
            deltaTime: 0.001,
            input: .astronautLand(
                from: state,
                panelState: .p66AttitudeHold,
                attitudeController: LMRotationalHandControllerInput(pitch: 0o1)
            )
        )
        let channel31 = try #require(snapshot.agc.inputChannels[0o31])
        #expect((channel31 & LMPoweredDescentPanel.channel31AttitudeHold) == 0)
        #expect((channel31 & LMPoweredDescentPanel.channel31RHCOutOfDetent) == 0)
        let snufferMask = 1 << (
            Luminary099Flag.bit(decimalIndex: Luminary099Flag.snuffer) - 1
        )
        let snufferWord = await runtime.readErasable(
            ecadr: Luminary099Flag.ecadr(decimalIndex: Luminary099Flag.snuffer)
        )
        #expect((snufferWord & snufferMask) == 0, "P66 ACA rate command requires rotational RCS")
    }

    @Test func `auto-land CH33 altitude data-good survives the panel word`() async throws {
        let runtime = try LMSimulationRuntime(coreImage: Data())
        let snapshot = await runtime.step(deltaTime: 0.001, input: .autoLand(altitudeMeters: 100))
        let ch33 = snapshot.agc.inputChannels[0o33] ?? 0
        #expect(
            (ch33 & LMPoweredDescentPanel.channel33LRAltitudeDataGood) == 0,
            "INITREAD latches CH33 into OLDATAGD; panel 77337 must not win, got \(String(ch33, radix: 8))"
        )
        #expect((ch33 & LMPoweredDescentPanel.channel33LRPosition1) == 0)
        #expect((ch33 & 0o400) == 0, "low scale bit 9 must stay 0, got \(String(ch33, radix: 8))")
    }

    @Test func `auto-land from vehicle encodes LR velocity at LVELBIAS`() {
        let state = LMVehicleStateSnapshot(
            velocityMetersPerSecond: LMVector3D(z: 0.644 * 0.3048),
            attitude: .identity
        )
        let input = LMFrameInput.autoLand(from: state)
        let raw = input.radarInput?.rawAGCInput
        #expect(raw?.landingRadarVelocityX == 12_287)
        #expect(raw?.landingRadarVelocityY == 12_288)
        #expect(raw?.landingRadarVelocityZ == 12_288)
        #expect(raw?.rnradWord(channel13Low3: 0o4) == 12_287)
        #expect(raw?.rnradWord(channel13Low3: 0o7) == raw?.altitudeMeter)
    }

    @Test func `auto-land from vehicle withholds LR until the range beam sees the ground`() {
        let upright = LMVehicleStateSnapshot(
            positionMeters: LMVector3D(z: 1_000),
            velocityMetersPerSecond: LMVector3D(z: 0.644 * 0.3048)
        )
        #expect(LMFrameInput.autoLand(from: upright).radarInput != nil)

        let pdi = LMVehicleStateSnapshot(
            positionMeters: LMVector3D(z: 1_000),
            attitude: .fromAxisAngle(axis: LMVector3D(x: 1), radians: 95 * .pi / 180)
        )
        #expect(
            LMFrameInput.autoLand(from: pdi).radarInput != nil,
            "PDI 95° still illuminates the surface; STILBADH needs those samples before HIGATE"
        )

        let skyward = LMVehicleStateSnapshot(
            positionMeters: LMVector3D(z: 1_000),
            attitude: .fromAxisAngle(axis: LMVector3D(x: 1), radians: .pi)
        )
        #expect(LMFrameInput.autoLand(from: skyward).radarInput == nil)
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

    @Test func `PDI FMAX plant SM accel matches PIPA plus MUNGRAV`() {
        let t0 = 10_000.0
        let pdi = LMQuaternion.fromAxisAngle(axis: LMVector3D(x: 1), radians: 95 * .pi / 180)
        var state = LMAGCNavState.vehicleState(
            timeCentiseconds: t0,
            attitude: pdi,
            massKilograms: 14_969
        )
        let commands = LMVehicleSnapshot(
            outputChannel11: 0o10000,
            commandedThrustNewtons: LMDPSThrottleMap.fmaxNewtons
        )
        let dt = 0.25
        let seconds = 46.0
        let ref = LMAGCNavState.refsmmat(timeCentiseconds: t0)
        func smVelocity(_ vehicle: LMVehicleStateSnapshot, time: Double) -> LMVector3D {
            ref.times(
                LuminaryMoonOrientation.moonRelativeVelocityToReference(
                    velocityMetersPerCentisecond: LMAGCNavState.velocityMetersPerCentisecond(from: vehicle),
                    moonFixedPosition: LMAGCNavState.moonCenteredPositionMeters(from: vehicle),
                    timeCentiseconds: time
                )
            ) * 100.0
        }
        let startV = smVelocity(state, time: t0)
        var time = t0
        for _ in 1...Int((seconds / dt).rounded()) {
            state = LMDynamics.propagate(
                state: state,
                commands: commands,
                configuration: .sourceBackedDefault,
                deltaTime: dt
            )
            time += dt * 100.0
        }
        let dVPlant = smVelocity(state, time: time) - startV
        let bodyForce = LMDynamics.specificForceBody(
            state: state,
            commands: commands,
            configuration: .sourceBackedDefault
        )
        let pipaENU = LMIMUGimbalMap.nasaBody(fromSim: pdi.rotated(bodyForce))
        let rSM = ref.times(LMAGCNavState.basicReferencePositionMeters(
            from: LMAGCNavState.vehicleState(timeCentiseconds: t0, attitude: pdi, massKilograms: 14_969),
            timeCentiseconds: t0
        ))
        let r2 = rSM.dot(rSM)
        let gSM = rSM * (
            -Luminary099NavScale.lunarMuMetersCubedPerSecondSquared / (r2 * sqrt(r2))
        )
        let dVENU = (pipaENU + gSM) * seconds
        #expect(
            (dVPlant - dVENU).magnitude < 2.0,
            "46s plant ΔV \(String(format: "%.2f,%.2f,%.2f", dVPlant.x, dVPlant.y, dVPlant.z)) ENU-PIPA \(String(format: "%.2f,%.2f,%.2f", dVENU.x, dVENU.y, dVENU.z)) err \(String(format: "%.2f,%.2f,%.2f", (dVPlant - dVENU).x, (dVPlant - dVENU).y, (dVPlant - dVENU).z))"
        )
    }

    @Test func `plant inertial specific force matches ENU thrust at PDI epoch`() {
        let t0 = 10_000.0
        let pdi = LMQuaternion.fromAxisAngle(axis: LMVector3D(x: 1), radians: 95 * .pi / 180)
        let state = LMAGCNavState.vehicleState(
            timeCentiseconds: t0,
            attitude: pdi,
            massKilograms: 14_969
        )
        let commands = LMVehicleSnapshot(
            outputChannel11: 0o10000,
            commandedThrustNewtons: LMDPSThrottleMap.fmaxNewtons
        )
        let dt = 0.01
        let ref = LMAGCNavState.refsmmat(timeCentiseconds: t0)
        let sm0 = LMAGCNavState.stableMemberKinematics(from: state, refsmmat: ref, timeCentiseconds: t0)
        let next = LMDynamics.propagate(
            state: state,
            commands: commands,
            configuration: .sourceBackedDefault,
            deltaTime: dt
        )
        let sm1 = LMAGCNavState.stableMemberKinematics(
            from: next,
            refsmmat: ref,
            timeCentiseconds: t0 + dt * 100.0
        )
        let inertial = LMAGCNavState.nongravitationalAccelerationSM(
            previousVelocityMetersPerSecond: sm0.velocityMetersPerSecond,
            positionMeters: sm1.positionMeters,
            velocityMetersPerSecond: sm1.velocityMetersPerSecond,
            deltaTime: dt
        )
        let body = LMDynamics.specificForceBody(
            state: state,
            commands: commands,
            configuration: .sourceBackedDefault
        )
        let enu = LMIMUGimbalMap.nasaBody(fromSim: pdi.rotated(body))
        #expect(
            (inertial - enu).magnitude < 0.05,
            "inertial \(String(format: "%.3f,%.3f,%.3f", inertial.x, inertial.y, inertial.z)) ENU \(String(format: "%.3f,%.3f,%.3f", enu.x, enu.y, enu.z))"
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

    @Test func `landing contact criteria distinguish soft hard and crash outcomes`() {
        let nominal = LMSurfaceContactSnapshot(
            groundRangeMeters: 0,
            horizontalSpeedMetersPerSecond: 0.008 * 0.3048,
            verticalSpeedMetersPerSecond: 3.0 * 0.3048,
            tiltRadians: 0
        )
        #expect(nominal.flightOutcome == .softLanding)

        let hard = LMSurfaceContactSnapshot(
            groundRangeMeters: 100,
            horizontalSpeedMetersPerSecond: 3.0 * 0.3048,
            verticalSpeedMetersPerSecond: 7.5 * 0.3048,
            tiltRadians: 5.0 * .pi / 180.0
        )
        #expect(hard.flightOutcome == .hardLanding)

        let lateralCrash = LMSurfaceContactSnapshot(
            groundRangeMeters: 200,
            horizontalSpeedMetersPerSecond: 31.2,
            verticalSpeedMetersPerSecond: 0,
            tiltRadians: 0
        )
        #expect(lateralCrash.flightOutcome == .crashed)

        #expect(
            abs(LMLandingContactCriteria.maximumVerticalSpeedMetersPerSecond(
                horizontalSpeedMetersPerSecond: 0
            ) - 10.0 * 0.3048) < 1e-12
        )
        #expect(
            abs(LMLandingContactCriteria.maximumVerticalSpeedMetersPerSecond(
                horizontalSpeedMetersPerSecond: 4.0 * 0.3048
            ) - 7.0 * 0.3048) < 1e-12
        )
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
        #expect((snapshot.agc.inputChannels[0o30] ?? 0o77777) & 0o400 == 0)
        #expect((await runtime.readErasable(ecadr: Luminary099Erasable.imodes30) & 0o400) == 0)
        #expect((await runtime.readErasable(ecadr: Luminary099Erasable.imodes33) & 0o40) == 0)
        #expect((snapshot.vehicleCommands.outputChannel12 & 0o20) == 0)
        #expect(abs(snapshot.vehicleState.velocityMetersPerSecond.magnitude - Luminary99LandingPadLoad.vignMetersPerCentisecond * 100) < 5)
        #expect(
            snapshot.vehicleState.verticalSpeedMetersPerSecond < 0,
            "boot PDI H-dot should be descent, got \(snapshot.vehicleState.verticalSpeedMetersPerSecond) alt=\(snapshot.vehicleState.altitudeMeters)"
        )
    }

    @Test func `Luminary boot finishes IMU operate initialization before PDI seed`() async throws {
        let romURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AGCTests/Luminary099.bin")
        try #require(FileManager.default.fileExists(atPath: romURL.path))
        let runtime = try LMSimulationRuntime(binFile: romURL, scenario: .apollo11SourceBacked)
        let snapshot = await runtime.bootAndEnterP63()
        let imodes30 = await runtime.readErasable(ecadr: Luminary099Erasable.imodes30)
        let imodes33 = await runtime.readErasable(ecadr: Luminary099Erasable.imodes33)
        let cduy = await runtime.readErasable(ecadr: Register.regCDUY.rawValue)
        let expectedCDUY = LMIMUGimbalMap.cduCounts(from: snapshot.vehicleState.attitude).y

        #expect((snapshot.agc.inputChannels[0o30] ?? 0o77777) & 0o400 == 0)
        #expect((imodes30 & 0o400) == 0, "T4 must have sampled inverted IMU OPERATE")
        #expect((imodes33 & 0o40) == 0, "operate-only initialization must re-enable the DAP")
        #expect((snapshot.vehicleCommands.outputChannel12 & 0o20) == 0, "ICDU zero discrete must be released")
        #expect(cduy == expectedCDUY, "PDI CDUY seed must survive completed IMU initialization")
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

    @Test func `runtime lead state coasts toward RIGN with Luminary MUM`() {
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
        #expect(Luminary099Erasable.unfc2 == 0o3253)
        #expect(Luminary099Erasable.unwc2 == 0o3261)
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

        #expect(await runtime.readErasable(ecadr: Luminary099Erasable.lrhmax) == 0o35610)
        #expect(await runtime.readErasable(ecadr: Luminary099Erasable.delqfix + 1) == 0o01717)
        #expect(await runtime.readErasable(ecadr: Luminary099Erasable.rpcrtime) == 0o01407)
        #expect(await runtime.readErasable(ecadr: Luminary099Erasable.rpcrtqsw) == 0o77777)
        #expect(await runtime.readErasable(ecadr: Luminary099Erasable.lralpha) == 0o01042)
        #expect(await runtime.readErasable(ecadr: Luminary099Erasable.lrbeta1) == 0o04211)
        #expect(await runtime.readErasable(ecadr: Luminary099Erasable.lralpha2) == 0o01042)
        #expect(await runtime.readErasable(ecadr: Luminary099Erasable.lrbeta2) == 0o00000)
        #expect(await runtime.readErasable(ecadr: Luminary099Erasable.rodScale) == 0o14370)
        #expect(await runtime.readErasable(ecadr: Luminary099Erasable.tauRod) == 0o11300)
        #expect(await runtime.readErasable(ecadr: Luminary099Erasable.tauRod + 1) == 0o00000)
        #expect(await runtime.readErasable(ecadr: Luminary099Erasable.lagOverTau) == 0o15164)
        #expect(await runtime.readErasable(ecadr: Luminary099Erasable.lagOverTau + 1) == 0o01420)
        #expect(await runtime.readErasable(ecadr: Luminary099Erasable.minForce) == 0o00001)
        #expect(await runtime.readErasable(ecadr: Luminary099Erasable.minForce + 1) == 0o27631)
        #expect(await runtime.readErasable(ecadr: Luminary099Erasable.maxForce) == 0o00013)
        #expect(await runtime.readErasable(ecadr: Luminary099Erasable.maxForce + 1) == 0o06551)
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

    @Test func `channel 5 plus-U jets produce NASA plus-Q plus-R torque`() {
        let initial = LMVehicleStateSnapshot(positionMeters: LMVector3D(z: 100), massKilograms: 14_969)
        let next = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(out0: 0o204),
            configuration: .sourceBackedDefault,
            deltaTime: 1
        )
        #expect(Set(LMVehicleSnapshot(out0: 0o204).rcsJets.map(\.jet)) == Set([.jet5, .jet14]))
        #expect(next.angularVelocityRadiansPerSecond.x > 0)
        #expect(next.angularVelocityRadiansPerSecond.y > 0)
        #expect(abs(next.angularVelocityRadiansPerSecond.z) < 1e-9)
    }

    @Test func `channel 5 plus-V jets produce NASA minus-Q plus-R torque`() {
        let initial = LMVehicleStateSnapshot(positionMeters: LMVector3D(z: 100), massKilograms: 14_969)
        let next = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(out0: 0o041),
            configuration: .sourceBackedDefault,
            deltaTime: 1
        )
        #expect(Set(LMVehicleSnapshot(out0: 0o041).rcsJets.map(\.jet)) == Set([.jet1, .jet10]))
        #expect(next.angularVelocityRadiansPerSecond.x < 0)
        #expect(next.angularVelocityRadiansPerSecond.y > 0)
        #expect(abs(next.angularVelocityRadiansPerSecond.z) < 1e-9)
    }

    @Test func `Luminary U-V pairs produce pure Q torque`() {
        let initial = LMVehicleStateSnapshot(positionMeters: LMVector3D(z: 100), massKilograms: 14_969)
        let positiveQ = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(out0: 0o226),
            configuration: .sourceBackedDefault,
            deltaTime: 1
        )
        let negativeQ = LMDynamics.propagate(
            state: initial,
            commands: LMVehicleSnapshot(out0: 0o151),
            configuration: .sourceBackedDefault,
            deltaTime: 1
        )

        #expect(positiveQ.angularVelocityRadiansPerSecond.x > 0)
        #expect(abs(positiveQ.angularVelocityRadiansPerSecond.y) < 1e-9)
        #expect(negativeQ.angularVelocityRadiansPerSecond.x < 0)
        #expect(abs(negativeQ.angularVelocityRadiansPerSecond.y) < 1e-9)
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

    @Test func `missing radar frame clears the previous sample and data-good`() async throws {
        let raw = LMRadarInput.raw(
            LMRadarRawInput(rendezvousRadarWord: 0o12345, altitudeMeterWord: 0o54321)
        )
        let runtime = try LMSimulationRuntime(coreImage: Data())
        _ = await runtime.step(deltaTime: 0.001, input: LMFrameInput(radarInput: raw))
        let snapshot = await runtime.step(deltaTime: 0.001, input: LMFrameInput())

        #expect(snapshot.sensorState.radarInput == nil)
        // CH33 radar discretes are inverted: set means altitude data is not good.
        #expect(
            (snapshot.agc.inputChannels[0o33] ?? 0)
                & LMPoweredDescentPanel.channel33LRAltitudeDataGood != 0
        )
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

    @Test func `Luminary radar gate latches LRALT after CH13 activity`() async throws {
        let romURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AGCTests/Luminary099.bin")
        try #require(FileManager.default.fileExists(atPath: romURL.path))
        let runtime = try AGCRuntime(binFile: romURL)
        _ = await runtime.step(cycles: 1_000_000)
        await runtime.setRadarInput(
            AGCRadarInput(landingRadarVelocityX: 0o11111, landingRadarAltitude: 0o12345)
        )
        await runtime.enqueueInput(AGCChannelInput(channel: 0o13, value: 0o17))
        _ = await runtime.step(cycles: 200_000)
        let snapshot = await runtime.snapshot()
        #expect(
            snapshot.registers.rendezvousRadar == 0o12345,
            "idle Luminary plus CH13=17 should latch LRALT, RNRAD=\(String(snapshot.registers.rendezvousRadar, radix: 8)) CH13=\(String(snapshot.outputChannels[0o13] ?? snapshot.inputChannels[0o13] ?? 0, radix: 8))"
        )
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

    @Test func `landing radar selects high altitude scale above its crossover`() async throws {
        let low = LMFrameInput.autoLand(altitudeMeters: 2_000 * 0.3048)
        #expect(low.radarInput?.rawAGCInput?.landingRadarAltitude == Int((2_000 / 1.079).rounded()))
        #expect(low.radarInput?.rawAGCInput?.landingRadarAltitudeHighScale == false)

        let high = LMFrameInput.autoLand(altitudeMeters: 30_000 * 0.3048)
        #expect(high.radarInput?.rawAGCInput?.landingRadarAltitude == Int((30_000 / 5.395).rounded()))
        #expect(high.radarInput?.rawAGCInput?.landingRadarAltitudeHighScale == true)

        let runtime = try LMSimulationRuntime(coreImage: Data())
        let snapshot = await runtime.step(deltaTime: 0.001, input: high)
        #expect((snapshot.agc.inputChannels[0o33] ?? 0) & LMPoweredDescentPanel.channel33LRAltitudeHighScale != 0)
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

    @Test func `SM CDUs match ENU map at the REFSMMAT epoch`() {
        let time = Luminary99LandingPadLoad.pdiClockCentiseconds
        let ref = LMAGCNavState.refsmmat(timeCentiseconds: time)
        let pdi = LMQuaternion.fromAxisAngle(axis: LMVector3D(x: 1), radians: 95.0 * .pi / 180.0)
        let enu = LMIMUGimbalMap.cduCounts(from: pdi)
        let sm = LMIMUGimbalMap.cduCounts(from: pdi, refsmmat: ref, timeCentiseconds: time)
        #expect(
            abs(LMIMUGimbalMap.shortestCountDelta(from: enu.x, to: sm.x)) <= 2
                && abs(LMIMUGimbalMap.shortestCountDelta(from: enu.y, to: sm.y)) <= 1
                && abs(LMIMUGimbalMap.shortestCountDelta(from: enu.z, to: sm.z)) <= 1,
            "ENU \(enu) SM \(sm)"
        )
    }

    @Test func `plant interpolator recovers the sample at an exact GET`() {
        let t0 = 10_000.0
        let pdi = LMQuaternion.fromAxisAngle(axis: LMVector3D(x: 1), radians: 95 * .pi / 180)
        let v0 = LMAGCNavState.vehicleState(
            timeCentiseconds: t0,
            attitude: pdi,
            massKilograms: 14_969
        )
        let v1 = LMVehicleStateSnapshot(
            positionMeters: v0.positionMeters + LMVector3D(y: 200),
            velocityMetersPerSecond: v0.velocityMetersPerSecond,
            attitude: v0.attitude,
            massKilograms: v0.massKilograms
        )
        let samples = [
            PlantGETSample(getCs: t0, vehicle: v0),
            PlantGETSample(getCs: t0 + 100, vehicle: v1)
        ]
        let ref = LMAGCNavState.refsmmat(timeCentiseconds: t0)
        let exact = interpolatePlant(samples: samples, getCs: t0, refsmmat: ref)
        let expected = LMAGCNavState.stableMemberKinematics(
            from: v0,
            refsmmat: ref,
            timeCentiseconds: t0
        )
        #expect(
            exact != nil
                && (exact!.positionMeters - expected.positionMeters).magnitude < 1
                && (exact!.velocityMetersPerSecond - expected.velocityMetersPerSecond).magnitude < 0.01
        )
        let mid = interpolatePlant(samples: samples, getCs: t0 + 50, refsmmat: ref)
        let midVehicle = LMVehicleStateSnapshot(
            positionMeters: v0.positionMeters + LMVector3D(y: 100),
            velocityMetersPerSecond: v0.velocityMetersPerSecond,
            attitude: v0.attitude,
            massKilograms: v0.massKilograms
        )
        let midExpected = LMAGCNavState.stableMemberKinematics(
            from: midVehicle,
            refsmmat: ref,
            timeCentiseconds: t0 + 50
        )
        #expect(
            mid != nil && (mid!.positionMeters - midExpected.positionMeters).magnitude < 1,
            "midpoint interpolation should track site-east lerp"
        )
    }

    @Test func `SM CDUY at 95° PDI only moves by lunar rotation over 120 s`() {
        let t0 = 1_000.0
        let t1 = t0 + 12_000
        let ref = LMAGCNavState.refsmmat(timeCentiseconds: t0)
        let pdi = LMQuaternion.fromAxisAngle(axis: LMVector3D(x: 1), radians: 95.0 * .pi / 180.0)
        let enu = LMIMUGimbalMap.cduRadians(from: pdi)
        let sm0 = LMIMUGimbalMap.cduRadians(from: pdi, refsmmat: ref, timeCentiseconds: t0)
        let sm1 = LMIMUGimbalMap.cduRadians(from: pdi, refsmmat: ref, timeCentiseconds: t1)
        let lunar = LuminaryMoonOrientation.moonRateRadiansPerSecond * 120
        func deg(_ radians: Double) -> Double { radians * 180 / .pi }
        #expect(abs(deg(enu.y) - 95) < 0.2, "ENU CDUY \(deg(enu.y))°")
        #expect(abs(deg(sm0.y) - deg(enu.y)) < 0.05, "epoch SM CDUY \(deg(sm0.y))° vs ENU \(deg(enu.y))°")
        #expect(
            abs(deg(sm1.y) - deg(sm0.y)) < deg(lunar) + 0.2,
            "120s SM CDUY \(deg(sm0.y))° → \(deg(sm1.y))° vs lunar \(deg(lunar))°. CDUX \(deg(sm0.x))°→\(deg(sm1.x))° CDUZ \(deg(sm0.z))°→\(deg(sm1.z))°"
        )
        #expect(abs(deg(sm1.x) - deg(sm0.x)) < 2, "CDUX should not pick up the Q rotation")
        #expect(
            abs(deg(sm1.x) - deg(enu.x)) < 1 && abs(deg(sm1.z) - deg(enu.z)) < 1,
            "SM vs ENU at +120s CDUX \(deg(sm1.x))°/\(deg(enu.x))° CDUY \(deg(sm1.y))°/\(deg(enu.y))° CDUZ \(deg(sm1.z))°/\(deg(enu.z))°"
        )
    }

    @Test func `SM and ENU CDUY share the sim-X Q sign through PDI pitch`() {
        let t0 = 1_000.0
        let t1 = t0 + 12_000
        let ref = LMAGCNavState.refsmmat(timeCentiseconds: t0)
        let dq = 1.0 * .pi / 180.0
        func deg(_ radians: Double) -> Double { radians * 180 / .pi }
        func wrappedDelta(_ from: Double, _ to: Double) -> Double {
            var d = to - from
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
            return d
        }
        var trail = ""
        for pitchDeg in [95.0, 80.0, 55.0] {
            let base = LMQuaternion.fromAxisAngle(axis: LMVector3D(x: 1), radians: pitchDeg * .pi / 180.0)
            let plus = LMQuaternion.fromAxisAngle(axis: LMVector3D(x: 1), radians: (pitchDeg * .pi / 180.0) + dq)
            for (label, time) in [("epoch", t0), ("+120s", t1)] {
                let enu0 = LMIMUGimbalMap.cduRadians(from: base)
                let enu1 = LMIMUGimbalMap.cduRadians(from: plus)
                let sm0 = LMIMUGimbalMap.cduRadians(from: base, refsmmat: ref, timeCentiseconds: time)
                let sm1 = LMIMUGimbalMap.cduRadians(from: plus, refsmmat: ref, timeCentiseconds: time)
                let dENU = wrappedDelta(enu0.y, enu1.y)
                let dSM = wrappedDelta(sm0.y, sm1.y)
                let dENUX = wrappedDelta(enu0.x, enu1.x)
                let dSMX = wrappedDelta(sm0.x, sm1.x)
                trail += String(
                    format: " \(label) Q=%.0f° dENUY=%+.3f° dSMY=%+.3f° dENUX=%+.3f° dSMX=%+.3f°",
                    pitchDeg,
                    deg(dENU),
                    deg(dSM),
                    deg(dENUX),
                    deg(dSMX)
                )
                #expect(
                    dENU * dSM > 0,
                    "sim +X should move SM CDUY the same way as ENU CDUY\(trail)"
                )
                #expect(
                    abs(deg(dSM) - deg(dENU)) < 0.2,
                    "Q gain should match within 0.2°/°\(trail)"
                )
                #expect(
                    abs(deg(dSMX)) < 0.3,
                    "sim +X must not leak into SM CDUX\(trail)"
                )
            }
        }
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

        // GUIDDURN is the nominal ignition-to-landing duration, not a hard
        // deadline for EXTLOGIC. The emulated guidance cycle reaches it with
        // TTF/8 a few seconds short of TENDAPPR, so leave a bounded transition
        // margin to observe the actual P64 -> P65 phase change. Inputs stay on
        // the static AUTO panel until Luminary itself enters P65.
        let p65TransitionMargin = 10.0
        let remainingToP65 = max(
            dt,
            p64Deadline + p65TransitionMargin - (snapshot.timeSeconds - igniteTime)
        )
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
        func dpVector(_ ecadr: Int, scale: Int) async -> LMVector3D {
            let x = await runtime.readDoublePrecision(ecadr: ecadr)
            let y = await runtime.readDoublePrecision(ecadr: ecadr + 2)
            let z = await runtime.readDoublePrecision(ecadr: ecadr + 4)
            return LMVector3D(
                x: x.decoded(scale: scale),
                y: y.decoded(scale: scale),
                z: z.decoded(scale: scale)
            )
        }
        var refsmmatRows: [LMVector3D] = []
        for row in 0..<3 {
            var values: [Double] = []
            for column in 0..<3 {
                let value = await runtime.readDoublePrecision(
                    ecadr: Luminary099Erasable.refsmmat + (row * 3 + column) * 2
                )
                values.append(value.decoded(scale: 0) / Luminary099NavScale.refsmmatHalfUnit)
            }
            refsmmatRows.append(LMVector3D(x: values[0], y: values[1], z: values[2]))
        }
        let refsmmat = LMMatrix3(r0: refsmmatRows[0], r1: refsmmatRows[1], r2: refsmmatRows[2])
        let get = AGCDoublePrecision(
            high: await runtime.readErasable(ecadr: Luminary099Erasable.time2),
            low: await runtime.readErasable(ecadr: Luminary099Erasable.time1)
        ).decoded(scale: 28)
        let pipTime = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.pipTime)
            .decoded(scale: 28)
        let plantNow = LMAGCNavState.stableMemberKinematics(
            from: snapshot.vehicleState,
            refsmmat: refsmmat,
            timeCentiseconds: get
        )
        let plantAtPip = plantNow.positionMeters
            - plantNow.velocityMetersPerSecond * ((get - pipTime) / 100.0)
        let navR = await dpVector(Luminary099Erasable.servicerR, scale: 24)
        let navV = await dpVector(Luminary099Erasable.servicerV, scale: 7) * 100.0
        let inertialPositionError = (navR - plantAtPip).magnitude
        let inertialVelocityError = (navV - plantNow.velocityMetersPerSecond).magnitude
        #expect(
            inertialPositionError < 2_000,
            "inertial MUNRVG R should track plant at PIPTIME; error \(Int(inertialPositionError)) m \(trail)"
        )
        #expect(
            inertialVelocityError < 10,
            "inertial MUNRVG V should track plant; error \(String(format: "%.1f", inertialVelocityError)) m/s \(trail)"
        )
        let p65Wch = await runtime.readErasable(ecadr: Luminary099Erasable.wchPhase)
        #expect(await runtime.readErasable(ecadr: 0o376) != 0o1204, "WAITLIST 01204 before P65 \(trail)")
        #expect(reachedP65, "TENDAPPR should start P65 near GUIDDURN \(trail)")
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
                input: .autoLand(from: snapshot.vehicleState)
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
                input: .autoLand(from: snapshot.vehicleState)
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
                input: .autoLand(from: snapshot.vehicleState)
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
            abs(cdudDeg) > 75 && abs(cdudDeg) < 130,
            "CDUYD should stay a braking attitude near 95° through ZOOM+40s, not pitch to high gate (\(String(format: "%.1f", cdudDeg))°) \(trail)"
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
                input: .autoLand(from: snapshot.vehicleState)
            )
            if snapshot.vehicleCommands.mainEngineOn { break }
        }
        let fail1 = await runtime.readErasable(ecadr: 0o376)
        let tigRangeNmi = snapshot.vehicleState.groundRangeMeters / 1852.0
        #expect(
            snapshot.vehicleCommands.mainEngineOn,
            "V99 should light DPS FAIL=\(String(fail1, radix: 8)) PROG=\(snapshot.agc.dsky.programNumber ?? 0) rng=\(Int(tigRangeNmi))nmi"
        )
        let tigTime = AGCDoublePrecision(
            high: await runtime.readErasable(ecadr: Luminary099Erasable.time2),
            low: await runtime.readErasable(ecadr: Luminary099Erasable.time1)
        ).decoded(scale: 28)
        let tigInertialSpeed = LMAGCNavState.basicReferenceVelocityMetersPerCentisecond(
            from: snapshot.vehicleState,
            timeCentiseconds: tigTime
        ).magnitude * 100.0
        #expect(
            abs(snapshot.vehicleState.altitudeMeters - Luminary99LandingPadLoad.pdiAltitudeMeters) < 100,
            "V99 PDI altitude \(snapshot.vehicleState.altitudeMeters) m should match NASA 48,814 ft"
        )
        #expect(
            abs(snapshot.vehicleState.verticalSpeedMetersPerSecond - Luminary99LandingPadLoad.pdiAltitudeRateMetersPerCentisecond * 100) < 0.5,
            "V99 PDI H-dot \(snapshot.vehicleState.verticalSpeedMetersPerSecond) m/s should match NASA -4 ft/s"
        )
        #expect(
            abs(tigInertialSpeed - Luminary99LandingPadLoad.pdiSpeedMetersPerCentisecond * 100) < 2,
            "V99 PDI inertial speed \(tigInertialSpeed) m/s should match NASA 5,560 ft/s"
        )
        for _ in 1...40 {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .autoLand(from: snapshot.vehicleState)
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
            navErrPip < 1_000,
            "Average-G RN vs plant \(Int(navErr)) m pip=\(Int(navErrPip)) m ahead2s=\(Int(navErrAhead)) m lag=\(String(format: "%.2f", lag))s moonH=\(Int(navErrMoon)) m |RN29|=\(Int(rn29.magnitude)) |plant|=\(Int(vehicleBasic.magnitude))"
        )
        #expect(
            landErr < 8_000,
            "IGNALG LAND vs RLS \(Int(landErr)) m (\(String(format: "%.1f", landErr / 1852)) nmi)"
        )
    }

    /// AVERAGEG should integrate the same SM ΔV the plant produces. A window
    /// that straddles ZOOM is biased by the 2 s SERVICER tag (plant includes
    /// two extra seconds of FMAX). Measure after FLATOUT so both sides are FMAX.
    @Test func `Average-G ΔV matches plant thrust through ZOOM`() async throws {
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
                input: .autoLand(from: snapshot.vehicleState)
            )
            if snapshot.vehicleCommands.mainEngineOn { break }
        }
        #expect(snapshot.vehicleCommands.mainEngineOn, "need DPS before measuring ΔV")
        let fmax = LMDPSThrottleMap.fmaxNewtons
        for _ in 1...200 {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .autoLand(from: snapshot.vehicleState)
            )
            if (snapshot.vehicleCommands.dps.commandedThrustNewtons ?? 0) > 0.9 * fmax { break }
        }
        #expect(
            (snapshot.vehicleCommands.dps.commandedThrustNewtons ?? 0) > 0.9 * fmax,
            "need FMAX before measuring ΔV"
        )
        for _ in 1...16 {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .autoLand(from: snapshot.vehicleState)
            )
        }

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
        func plantSM(get: Double, ref: LMMatrix3) -> (r: LMVector3D, v: LMVector3D) {
            let moon = LMAGCNavState.moonCenteredPositionMeters(from: snapshot.vehicleState)
            let r = ref.times(LuminaryMoonOrientation.rpToR(moon, timeCentiseconds: get))
            let v = ref.times(
                LuminaryMoonOrientation.moonRelativeVelocityToReference(
                    velocityMetersPerCentisecond: LMAGCNavState.velocityMetersPerCentisecond(
                        from: snapshot.vehicleState
                    ),
                    moonFixedPosition: moon,
                    timeCentiseconds: get
                )
            )
            return (r, v)
        }
        func sample() async -> (
            get: Double,
            lag: Double,
            rSM: LMVector3D,
            vSM: LMVector3D,
            plantR: LMVector3D,
            plantV: LMVector3D
        ) {
            let time2 = await runtime.readErasable(ecadr: Luminary099Erasable.time2)
            let time1 = await runtime.readErasable(ecadr: Luminary099Erasable.time1)
            let get = AGCDoublePrecision(high: time2, low: time1).decoded(scale: 28)
            let pip = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.pipTime)
            let ref = await readRefsmmat()
            let rSM = await dpVector(ecadr: Luminary099Erasable.servicerR, scale: 24)
            let vSM = await dpVector(ecadr: Luminary099Erasable.servicerV, scale: 7)
            let plant = plantSM(get: get, ref: ref)
            return (get, (get - pip.decoded(scale: 28)) / 100.0, rSM, vSM, plant.r, plant.v)
        }

        let start = await sample()
        let startVelErr = (start.vSM - start.plantV) * 100.0
        let delvx = await runtime.readErasable(ecadr: Luminary099Erasable.delv)
        let delvz = await runtime.readErasable(ecadr: Luminary099Erasable.delv + 4)
        let zoomSteps = Int((Luminary99LandingPadLoad.zoomTimeCentiseconds / 100.0 + 20.0) / dt)
        let frozenRef = await readRefsmmat()
        var accPipaG = LMVector3D.zero
        var accThrust = LMVector3D.zero
        var sumDelv = LMVector3D.zero
        var delvCycles = 0
        var lastPip = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.pipTime)
        for _ in 1...zoomSteps {
            let force = LMDynamics.specificForceBody(
                state: snapshot.vehicleState,
                commands: snapshot.vehicleCommands,
                configuration: .sourceBackedDefault
            )
            let pipa = LMIMUGimbalMap.nasaBody(fromSim: snapshot.vehicleState.attitude.rotated(force))
            let getNow = AGCDoublePrecision(
                high: await runtime.readErasable(ecadr: Luminary099Erasable.time2),
                low: await runtime.readErasable(ecadr: Luminary099Erasable.time1)
            ).decoded(scale: 28)
            let live = LMAGCNavState.stableMemberKinematics(
                from: snapshot.vehicleState,
                refsmmat: frozenRef,
                timeCentiseconds: getNow
            )
            let r2 = live.positionMeters.dot(live.positionMeters)
            let gSM = r2 > 0
                ? live.positionMeters * (
                    -Luminary099NavScale.lunarMuMetersCubedPerSecondSquared
                        / (r2 * sqrt(r2))
                )
                : .zero
            accPipaG = accPipaG + (pipa + gSM) * dt
            accThrust = accThrust + pipa * dt
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .autoLand(from: snapshot.vehicleState)
            )
            let pip = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.pipTime)
            if pip.high != lastPip.high || pip.low != lastPip.low {
                func delvAxis(_ offset: Int) async -> Double {
                    AGCSinglePrecision(
                        word: await runtime.readErasable(ecadr: Luminary099Erasable.delv + offset)
                    ).decoded(scale: 14) * 0.01
                }
                sumDelv = LMVector3D(
                    x: sumDelv.x + (await delvAxis(0)),
                    y: sumDelv.y + (await delvAxis(2)),
                    z: sumDelv.z + (await delvAxis(4))
                )
                delvCycles += 1
                lastPip = pip
            }
        }
        let end = await sample()
        let dtGET = (end.get - start.get) / 100.0
        let dRAGC = end.rSM - start.rSM
        let dRPlant = end.plantR - start.plantR
        let dVAGC = (end.vSM - start.vSM) * 100.0
        let dVPlant = (end.plantV - start.plantV) * 100.0
        let dRErr = dRAGC - dRPlant
        let dVErr = dVAGC - dVPlant
        let endVelErr = (end.vSM - end.plantV) * 100.0
        let aheadStart = (start.rSM - (start.plantR + start.plantV * 200.0)).magnitude
        let aheadEnd = (end.rSM - (end.plantR + end.plantV * 200.0)).magnitude
        let cduy0 = await runtime.readErasable(ecadr: Register.regCDUY.rawValue)
        let pguide = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.abdelv + 1)
        let abdelv = AGCSinglePrecision(
            word: await runtime.readErasable(ecadr: Luminary099Erasable.abdelv)
        ).decoded(scale: 14)
        let gdt = await dpVector(ecadr: Luminary099Erasable.pipTime + 2, scale: 7)
        let pipTime1 = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.pipTime1)
        let pipaz = await runtime.readErasable(ecadr: Register.regPIPAZ.rawValue)
        let force = LMDynamics.specificForceBody(
            state: snapshot.vehicleState,
            commands: snapshot.vehicleCommands,
            configuration: .sourceBackedDefault
        )
        let pipaENU = LMIMUGimbalMap.nasaBody(fromSim: snapshot.vehicleState.attitude.rotated(force))
        #expect(
            abdelv > 550 && abdelv < 650,
            "ABDELV \(String(format: "%.0f", abdelv)) cm/s should match 2 s of FMAX PIPA (~600 cm/s)"
        )
        #expect(
            dVErr.magnitude < 3,
            "ΔV AGC \(String(format: "%.1f,%.1f,%.1f", dVAGC.x, dVAGC.y, dVAGC.z)) plant \(String(format: "%.1f,%.1f,%.1f", dVPlant.x, dVPlant.y, dVPlant.z)) pipaG \(String(format: "%.1f,%.1f,%.1f", accPipaG.x, accPipaG.y, accPipaG.z)) thrust \(String(format: "%.1f,%.1f,%.1f", accThrust.x, accThrust.y, accThrust.z)) ΣDELV \(String(format: "%.1f,%.1f,%.1f", sumDelv.x, sumDelv.y, sumDelv.z)) n=\(delvCycles) err \(String(format: "%.2f,%.2f,%.2f", dVErr.x, dVErr.y, dVErr.z)) m/s ΔR=\(Int(dRErr.x)),\(Int(dRErr.y)),\(Int(dRErr.z)) m dt=\(String(format: "%.1f", dtGET))s lag=\(String(format: "%.2f→%.2f", start.lag, end.lag)) ahead=\(Int(aheadStart))→\(Int(aheadEnd)) v0err=\(String(format: "%.2f,%.2f,%.2f", startVelErr.x, startVelErr.y, startVelErr.z)) v1err=\(String(format: "%.2f,%.2f,%.2f", endVelErr.x, endVelErr.y, endVelErr.z)) ABDELV=\(String(format: "%.0f", abdelv))cm/s GDT/2=\(String(format: "%.4f,%.4f,%.4f", gdt.x, gdt.y, gdt.z)) PIPA=\(String(format: "%.2f,%.2f,%.2f", pipaENU.x, pipaENU.y, pipaENU.z)) GET=\(String(format: "%.0f", end.get)) PIPTIME1=\(String(format: "%.0f", pipTime1.decoded(scale: 28))) PIPAZ=\(pipaz) DELV=\(delvx),\(delvz) CDUY=\(cduy0) PGUIDE=\(String(format: "%.2f", pguide.decoded(scale: 28)))cs thrust=\(Int(snapshot.vehicleCommands.dps.commandedThrustNewtons ?? 0))N P\(snapshot.agc.dsky.programNumber ?? 0)"
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
        let fmax = LMDPSThrottleMap.fmaxNewtons
        var history: [PlantGETSample] = []

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
        func readGET() async -> Double {
            let time2 = await runtime.readErasable(ecadr: Luminary099Erasable.time2)
            let time1 = await runtime.readErasable(ecadr: Luminary099Erasable.time1)
            return AGCDoublePrecision(high: time2, low: time1).decoded(scale: 28)
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
        func recordPlant() async {
            history.append(
                PlantGETSample(getCs: await readGET(), vehicle: snapshot.vehicleState)
            )
        }
        func sampleLine() async -> (
            pipPositionError: Double,
            pipVelocityError: Double,
            text: String
        ) {
            let get = await readGET()
            let pip = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.pipTime)
            let pipTime = pip.decoded(scale: 28)
            let lag = (get - pipTime) / 100.0
            let ref = await readRefsmmat()
            let rSM = await dpVector(ecadr: Luminary099Erasable.servicerR, scale: 24)
            let vSM = await dpVector(ecadr: Luminary099Erasable.servicerV, scale: 7)
            let landSM = await dpVector(ecadr: Luminary099Erasable.land, scale: 24)
            let rgu = await dpVector(ecadr: Luminary099Erasable.rgu, scale: 24)
            let ttf8 = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.ttf8)
            let unfc = await dpVector(ecadr: Luminary099Erasable.unfc2, scale: 1)
            let cdux = await runtime.readErasable(ecadr: Register.regCDUX.rawValue)
            let cduy = await runtime.readErasable(ecadr: Register.regCDUY.rawValue)
            let cduz = await runtime.readErasable(ecadr: Register.regCDUZ.rawValue)
            let cdudx = await runtime.readErasable(ecadr: Luminary099Erasable.cduxd)
            let cdudy = await runtime.readErasable(ecadr: Luminary099Erasable.cduxd + 1)
            let cdudz = await runtime.readErasable(ecadr: Luminary099Erasable.cduxd + 2)
            let allowGts = await runtime.readErasable(ecadr: Luminary099Erasable.allowGts)
            let plantNow = LMAGCNavState.stableMemberKinematics(
                from: snapshot.vehicleState,
                refsmmat: ref,
                timeCentiseconds: get
            )
            let plantPip = interpolatePlant(samples: history, getCs: pipTime, refsmmat: ref)
                ?? plantNow
            let rls = LMAGCNavState.landingSiteMeters()
            let (north, east, _) = LMAGCNavState.moonFixedSiteBasis()
            let vehicleMoon = LMAGCNavState.moonCenteredPositionMeters(from: snapshot.vehicleState)
            let landMoon = LuminaryMoonOrientation.rToRP(
                ref.timesTranspose(landSM),
                timeCentiseconds: get
            )
            func horizontal(_ a: LMVector3D, _ b: LMVector3D) -> Double {
                let delta = a - b
                return hypot(delta.dot(north), delta.dot(east))
            }
            let navErrNow = (rSM - plantNow.positionMeters).magnitude
            let dRPip = rSM - plantPip.positionMeters
            let dVPip = vSM * 100.0 - plantPip.velocityMetersPerSecond
            let navErrPip = dRPip.magnitude
            let velErrPip = dVPip.magnitude
            let navErrAhead = (
                rSM - (plantNow.positionMeters + plantNow.velocityMetersPerSecond * 2.0)
            ).magnitude
            let errY = signedCDUDegrees(cduy) - signedCDUDegrees(cdudy)
            let text = String(
                format: "P\(snapshot.agc.dsky.programNumber ?? 0) GET=%.0f PIPTIME=%.0f lag=%.2fs now=%d pip=%d ahead=%d dRpip=%d,%d,%d dVpip=%.1f,%.1f,%.1f rguZ=%d ttf8=%.0f UNFC=%.2f,%.2f,%.2f CDU=%.1f/%.1f,%.1f/%.1f,%.1f/%.1f errY=%+.1f° gimb=%+.2f° RCS=%d GTS=%o plantRLS=%d plantLAND=%d rng=%.1fnmi alt=%.0fft F=%.0f",
                get,
                pipTime,
                lag,
                Int(navErrNow),
                Int(navErrPip),
                Int(navErrAhead),
                Int(dRPip.x),
                Int(dRPip.y),
                Int(dRPip.z),
                dVPip.x,
                dVPip.y,
                dVPip.z,
                Int(rgu.z),
                ttf8.decoded(scale: 17),
                unfc.x,
                unfc.y,
                unfc.z,
                signedCDUDegrees(cdux),
                signedCDUDegrees(cdudx),
                signedCDUDegrees(cduy),
                signedCDUDegrees(cdudy),
                signedCDUDegrees(cduz),
                signedCDUDegrees(cdudz),
                errY,
                snapshot.vehicleState.dpsPitchGimbalRadians * 180 / .pi,
                snapshot.vehicleCommands.rcsJets.count,
                allowGts,
                Int(horizontal(vehicleMoon, rls)),
                Int(horizontal(vehicleMoon, landMoon)),
                snapshot.vehicleState.groundRangeMeters / 1852.0,
                snapshot.vehicleState.altitudeMeters / 0.3048,
                snapshot.vehicleCommands.dps.commandedThrustNewtons ?? 0
            )
            return (navErrPip, velErrPip, text)
        }

        await recordPlant()
        var trail = ""
        var sawTIG = false
        var sawFMAX = false
        var maxRadarSelect = 0
        var hmeasBeforeHigate = 0
        var stilbadhMin = 0o77777
        var lrPreHigate = ""
        var wrapTrail = ""
        var lastWrapR: LMVector3D?
        var maxWrapStep = 0.0
        for _ in 1...3_200 {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .autoLand(from: snapshot.vehicleState)
            )
            await recordPlant()
            let getNow = await readGET()
            if getNow >= 15_500 && getNow <= 17_500 {
                let rNow = await dpVector(ecadr: Luminary099Erasable.servicerR, scale: 24)
                if let previous = lastWrapR {
                    let step = (rNow - previous).magnitude
                    if step > maxWrapStep { maxWrapStep = step }
                    if step > 200 {
                        wrapTrail += String(format: " GET=%.0f |ΔR|=%.0f", getNow, step)
                    }
                }
                lastWrapR = rNow
            }
            if !sawTIG && snapshot.vehicleCommands.mainEngineOn {
                sawTIG = true
                trail += " TIG " + (await sampleLine()).text
            }
            if !sawFMAX && (snapshot.vehicleCommands.dps.commandedThrustNewtons ?? 0) > 0.9 * fmax {
                sawFMAX = true
                trail += " FMAX " + (await sampleLine()).text
            }
            let radarSelect = (snapshot.agc.inputChannels[0o13] ?? 0) & 0o17
            if radarSelect > maxRadarSelect { maxRadarSelect = radarSelect }
            if sawTIG {
                let flg11Now = await runtime.readErasable(ecadr: Luminary099Erasable.flagwrd11)
                let hmeasHigh = await runtime.readErasable(ecadr: Luminary099Erasable.hmeas)
                let hmeasLow = await runtime.readErasable(ecadr: Luminary099Erasable.hmeas + 1)
                let stilNow = await runtime.readErasable(ecadr: Luminary099Erasable.stilbadh)
                if stilNow < stilbadhMin { stilbadhMin = stilNow }
                // PSTHIBIT (bit 11) means HIGATASK has already inhibited LRHJOB.
                if (flg11Now & 0o40) != 0 && (flg11Now & 0o2000) == 0 {
                    if (hmeasHigh != 0 || hmeasLow != 0) && hmeasBeforeHigate == 0 {
                        hmeasBeforeHigate = hmeasLow != 0 ? hmeasLow : hmeasHigh
                    }
                    if lrPreHigate.isEmpty {
                        let ch33 = snapshot.agc.inputChannels[0o33] ?? 0
                        let radmodes = await runtime.readErasable(ecadr: Luminary099Erasable.flagwrd12)
                        let phase2 = await runtime.readErasable(ecadr: Luminary099Erasable.phase2)
                        lrPreHigate = String(
                            format: " READLR CH13=%o CH33=%o RADMODES=%o PHASE2=%o HMEAS=%o,%o STIL=%o radar=%@",
                            radarSelect,
                            ch33,
                            radmodes,
                            phase2,
                            hmeasHigh,
                            hmeasLow,
                            stilNow,
                            snapshot.sensorState.radarInput == nil ? "nil" : "on"
                        )
                    }
                }
            }
            if snapshot.agc.dsky.programNumber == 64 { break }
        }
        #expect(snapshot.agc.dsky.programNumber == 64, "should reach P64 \(trail)")
        let p64 = await sampleLine()
        trail += " P64 " + p64.text
        trail += " wrapMax=\(Int(maxWrapStep))m\(wrapTrail)"
        // SERVICER writes R every ~2 s. At PDI that is ~3.3 km/update, decaying
        // through braking. TIME1 overflow would spike one update; a smooth
        // 3 km cadence is the healthy AVERAGEG step, not a wrap discontinuity.
        #expect(
            maxWrapStep < 4_000 || lastWrapR == nil,
            "TIME1 overflow should not jump MUNRVG R beyond one AVERAGEG step \(Int(maxWrapStep)) m \(trail)"
        )
        #expect(
            p64.pipPositionError < 2_000,
            "MUNRVG R vs plant at exact PIPTIME \(Int(p64.pipPositionError)) m \(trail)"
        )
        // 2 km over ~500 s of braking is 4 m/s average. 10 m/s at the P64
        // snapshot still flags a runaway without hiding a 5 km position miss.
        #expect(
            p64.pipVelocityError < 10,
            "MUNRVG V vs plant at exact PIPTIME \(String(format: "%.1f", p64.pipVelocityError)) m/s \(trail)"
        )
        let flg11 = await runtime.readErasable(ecadr: Luminary099Erasable.flagwrd11)
        let hcalc = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.hcalc)
        let hmeasHigh = await runtime.readErasable(ecadr: Luminary099Erasable.hmeas)
        let hmeasLow = await runtime.readErasable(ecadr: Luminary099Erasable.hmeas + 1)
        let stilbadh = await runtime.readErasable(ecadr: Luminary099Erasable.stilbadh)
        let radmodes = await runtime.readErasable(ecadr: Luminary099Erasable.flagwrd12)
        let phase2 = await runtime.readErasable(ecadr: Luminary099Erasable.phase2)
        let fail0 = await runtime.readErasable(ecadr: 0o375)
        let fail1 = await runtime.readErasable(ecadr: 0o376)
        let fail2 = await runtime.readErasable(ecadr: 0o377)
        let ch33 = snapshot.agc.inputChannels[0o33] ?? 0
        let lrTrail = String(
            format: " FLG11=%o HCALC=%.0fm HMEAS=%o,%o STILBADH=%o minSTIL=%o preH=%o CH13max=%o CH33=%o RADMODES=%o PHASE2=%o FAIL=%o/%o/%o radar=%@%@",
            flg11,
            hcalc.decoded(scale: 24),
            hmeasHigh,
            hmeasLow,
            stilbadh,
            stilbadhMin,
            hmeasBeforeHigate,
            maxRadarSelect,
            ch33,
            radmodes,
            phase2,
            fail0,
            fail1,
            fail2,
            snapshot.sensorState.radarInput == nil ? "nil" : "on",
            lrPreHigate
        )
        #expect((flg11 & 0o40000) == 0, "FLAGORGY should clear LRBYPASS \(lrTrail) \(trail)")
        #expect((flg11 & 0o40) != 0, "READLR should be set below 35 kft \(lrTrail) \(trail)")
        #expect(
            hmeasBeforeHigate != 0 || hmeasHigh != 0 || hmeasLow != 0,
            "LRHJOB should store HMEAS before HIGATE \(lrTrail) \(trail)"
        )
    }

    @Test func `perfect IMU compensation zeros PBIAS and skips 1/PIPA`() async throws {
        let romURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AGCTests/Luminary099.bin")
        try #require(FileManager.default.fileExists(atPath: romURL.path))
        let runtime = try LMSimulationRuntime(binFile: romURL, scenario: .apollo11SourceBacked)
        _ = await runtime.bootAndEnterP63()
        let gcomp = await runtime.readErasable(ecadr: Luminary099Erasable.gcompsw)
        let pbiasx = await runtime.readErasable(ecadr: Luminary099Erasable.pbiasx)
        let pipascfx = await runtime.readErasable(ecadr: Luminary099Erasable.pipascfx)
        let pbiasz = await runtime.readErasable(ecadr: Luminary099Erasable.pbiasz)
        let pipascfz = await runtime.readErasable(ecadr: Luminary099Erasable.pipascfz)
        let pipadt = await runtime.readErasable(ecadr: Luminary099Erasable.pipadt)
        #expect(gcomp == 0o77776, "GCOMPSW −1 skips 1/PIPA; −0 (077777) takes it. got \(String(gcomp, radix: 8))")
        #expect(gcomp != 0 && gcomp != 0o77777)
        #expect(pbiasx == 0 && pipascfx == 0, "PBIASX/PIPASCFX must be 0, got \(pbiasx),\(pipascfx)")
        #expect(pbiasz == 0 && pipascfz == 0, "PBIASZ/PIPASCFZ must be 0, got \(pbiasz),\(pipascfz)")
        #expect(pipadt == 0, "PIPADT must be 0 with GCOMPSW negative, got \(pipadt)")
    }

    @Test func `closed-loop trajectory reaches P65 and soft landing`() async throws {
        let romURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AGCTests/Luminary099.bin")
        try #require(FileManager.default.fileExists(atPath: romURL.path))
        let runtime = try LMSimulationRuntime(binFile: romURL, scenario: .apollo11SourceBacked)
        var snapshot = await runtime.bootAndEnterP63()
        let dt = LMSimulationPace.acceleratedDeltaSeconds
        let deadline = Luminary99LandingPadLoad.guidDurnCentiseconds / 100.0 + 240.0

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
            let vgu = await dpVector(ecadr: Luminary099Erasable.vgu, scale: 7)
            let vSM = await dpVector(ecadr: Luminary099Erasable.servicerV, scale: 7)
            let ttf8 = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.ttf8)
            let flg11 = await runtime.readErasable(ecadr: Luminary099Erasable.flagwrd11)
            let hmeasHigh = await runtime.readErasable(ecadr: Luminary099Erasable.hmeas)
            let hmeasLow = await runtime.readErasable(ecadr: Luminary099Erasable.hmeas + 1)
            let hcalc = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.hcalc)
            let ref = LMAGCNavState.refsmmat(timeCentiseconds: get)
            let plantSM = LMAGCNavState.stableMemberKinematics(
                from: snapshot.vehicleState,
                refsmmat: ref,
                timeCentiseconds: get
            )
            let dV = vSM * 100.0 - plantSM.velocityMetersPerSecond
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
                format: "t=%.0fs P\(snapshot.agc.dsky.programNumber ?? 0) alt=%.0fft hd=%+.2f hv=%.1f rng=%.2fnmi r2l=%.2fnmi rguZ=%.0f vguX=%.2f dV=%.1f,%.1f,%.1f ttf=%.0f H=%.0f HMEAS=%o,%o FLG11=%o radar=%@ %@ RCS=%d ENG=%@ F=%.0f m=%.0f FAIL=%o outcome=%@ tz=%+.2f DAP=%o CDU=%.1f/%.1f,%.1f/%.1f CH12=%o STEER=%d IMU33=%o",
                snapshot.timeSeconds,
                v.altitudeMeters / 0.3048,
                v.verticalSpeedMetersPerSecond,
                hvel,
                abs(v.downrangeMeters) / 1852.0,
                rangeToLand / 1852.0,
                rgu.z,
                vgu.x * 100.0,
                dV.x,
                dV.y,
                dV.z,
                ttf8.decoded(scale: 17),
                hcalc.decoded(scale: 24),
                hmeasHigh,
                hmeasLow,
                flg11,
                snapshot.sensorState.radarInput == nil ? "nil" : "on",
                v.downrangeMeters > 50 ? "past" : "togo",
                snapshot.vehicleCommands.rcsJets.count,
                engine,
                force,
                v.massKilograms ?? 0,
                fail1,
                v.flightOutcome.rawValue,
                thrust.z,
                dap,
                signedCDUDegrees(cdux),
                signedCDUDegrees(cdudx),
                signedCDUDegrees(cduy),
                signedCDUDegrees(cdudy),
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
                input: .autoLand(from: snapshot.vehicleState)
            )
            ignited = ignited || snapshot.vehicleCommands.mainEngineOn
            sawP64 = sawP64 || snapshot.agc.dsky.programNumber == 64
            sawP65 = sawP65 || snapshot.agc.dsky.programNumber == 65
            minRange = min(minRange, snapshot.vehicleState.groundRangeMeters)
            if snapshot.agc.dsky.programNumber != 65 {
                maxAltitude = max(maxAltitude, snapshot.vehicleState.altitudeMeters)
            }
            let fail1 = await runtime.readErasable(ecadr: 0o376)
            let range = snapshot.vehicleState.groundRangeMeters
            let past = snapshot.vehicleState.downrangeMeters > 50
            let escaped = snapshot.vehicleState.altitudeMeters > 80_000
            let overshot = past && range > 20_000 && minRange < 10_000
            if snapshot.timeSeconds - lastLogged >= 20
                || snapshot.vehicleState.flightOutcome.isTerminal
                || escaped
                || overshot
            {
                trail += " | " + (await vehicleLine())
                lastLogged = snapshot.timeSeconds
            }
            if snapshot.vehicleState.flightOutcome.isTerminal {
                outcome = snapshot.vehicleState.flightOutcome.rawValue
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
        #expect(
            sawP65 || snapshot.vehicleState.flightOutcome.isTerminal,
            "TENDAPPR should start P65 unless physical contact ends P64 first \(trail)"
        )
        let lrUpdateMask = 1 << (
            Luminary099Flag.bit(decimalIndex: Luminary099Flag.landingRadarUpdates) - 1
        )
        #expect(
            (await runtime.readErasable(ecadr: Luminary099Erasable.flagwrd11) & lrUpdateMask) != 0,
            "Apollo 11 TIG+5:00 V57 should permit LR updates before landing \(trail)"
        )
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
        #expect(outcome == LMFlightOutcome.softLanding.rawValue, "P65 should settle into soft contact \(trail)")
        let contact = try #require(snapshot.vehicleState.surfaceContact)
        #expect(contact.groundRangeMeters < 2_000, "contact should preserve the near-site repro \(trail)")
        #expect(
            contact.horizontalSpeedMetersPerSecond
                <= LMLandingContactCriteria.softHorizontalSpeedMetersPerSecond,
            "soft contact should stay within the lateral-speed envelope \(trail)"
        )
        #expect(
            contact.verticalSpeedMetersPerSecond
                <= LMLandingContactCriteria.softVerticalSpeedMetersPerSecond,
            "soft contact should stay within the descent-rate envelope \(trail)"
        )
        #expect(contact.tiltRadians <= LMLandingContactCriteria.softTiltRadians)
    }

    @Test func `P66 pilot takes over in ATT HOLD and reaches soft contact`() async throws {
        let romURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AGCTests/Luminary099.bin")
        try #require(FileManager.default.fileExists(atPath: romURL.path))
        let runtime = try LMSimulationRuntime(binFile: romURL, scenario: .apollo11SourceBacked)
        var snapshot = await runtime.bootAndEnterP63()
        let dt = LMSimulationPace.acceleratedDeltaSeconds
        let deadline = Luminary99LandingPadLoad.guidDurnCentiseconds / 100.0 + 180.0

        let pilot = LMP66Pilot()

        while snapshot.timeSeconds < deadline,
              snapshot.agc.dsky.programNumber != 65,
              !snapshot.vehicleState.flightOutcome.isTerminal {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .autoLand(from: snapshot.vehicleState)
            )
        }
        try #require(snapshot.agc.dsky.programNumber == 65)
        var handController = pilot.attitudeController(for: snapshot.vehicleState)

        snapshot = await runtime.step(
            deltaTime: dt,
            input: .astronautLand(
                from: snapshot.vehicleState,
                panelState: .p66AttitudeHold,
                attitudeController: handController,
                descendPlus: true
            )
        )
        for _ in 0..<80 where snapshot.agc.dsky.programNumber != 66 {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .astronautLand(
                    from: snapshot.vehicleState,
                    panelState: .p66AttitudeHold,
                    attitudeController: handController
                )
            )
        }
        #expect(snapshot.agc.dsky.programNumber == 66)
        #expect(snapshot.sensorState.poweredDescentPanelState == .p66AttitudeHold)

        // P66 is selected and sustained by MODE CONTROL ATT HOLD. Returning
        // to AUTO takes GUILDENSTERN through GUILDRET, which clears RODCOUNT
        // before the one-second ROD task can consume a crew click.
        for _ in 0..<4 {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .astronautLand(
                    from: snapshot.vehicleState,
                    panelState: .p66AttitudeHold,
                    attitudeController: handController
                )
            )
        }
        #expect(snapshot.agc.dsky.programNumber == 66)
        #expect(snapshot.sensorState.poweredDescentPanelState == .p66AttitudeHold)
        let desiredBefore = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.vdgVert)
        snapshot = await runtime.step(
            deltaTime: dt,
            input: .astronautLand(
                from: snapshot.vehicleState,
                panelState: .p66AttitudeHold,
                attitudeController: handController,
                descendPlus: true
            )
        )
        for _ in 0..<20 {
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .astronautLand(
                    from: snapshot.vehicleState,
                    panelState: .p66AttitudeHold,
                    attitudeController: handController
                )
            )
        }
        let desiredAfter = await runtime.readDoublePrecision(ecadr: Luminary099Erasable.vdgVert)

        #expect(desiredAfter != desiredBefore, "one ROD closure should update VDGVERT")
        #expect(snapshot.agc.dsky.programNumber == 66)
        #expect(snapshot.sensorState.descentRateChannel16 == 0, "the momentary ROD switch should release")
        #expect(snapshot.sensorState.rotationalHandControllerInput == handController)
        #expect(snapshot.sensorState.rotationalHandControllerInput.outOfDetent)

        let contactDeadline = snapshot.timeSeconds + 180
        var manualStep = 0
        var manualTrail: [String] = []
        while snapshot.timeSeconds < contactDeadline,
              !snapshot.vehicleState.flightOutcome.isTerminal {
            handController = pilot.attitudeController(
                for: snapshot.vehicleState,
                frameIndex: manualStep
            )
            let descentRateController = pilot.descentRateController(
                for: snapshot.vehicleState,
                frameIndex: manualStep
            )
            snapshot = await runtime.step(
                deltaTime: dt,
                input: .astronautLand(
                    from: snapshot.vehicleState,
                    panelState: .p66AttitudeHold,
                    attitudeController: handController,
                    descendPlus: descentRateController.descendPlus,
                    descendMinus: descentRateController.descendMinus
                )
            )
            if manualStep.isMultiple(of: 20) {
                let state = snapshot.vehicleState
                let tilt = acos(min(max(state.attitude.rotated(LMVector3D(z: 1)).z, -1), 1))
                let omegaQ = AGCSinglePrecision(
                    word: await runtime.readErasable(ecadr: Luminary099Erasable.omegaq)
                ).decoded(scale: 0) * .pi / 4
                let cduy = await runtime.readErasable(ecadr: Register.regCDUY.rawValue)
                let cduyd = await runtime.readErasable(ecadr: Luminary099Erasable.cduxd + 1)
                var cduError = (cduy & 0o77777) - (cduyd & 0o77777)
                if cduError > 16_384 { cduError -= 32_768 }
                if cduError < -16_384 { cduError += 32_768 }
                manualTrail.append(String(
                    format: "t=%.1f alt=%.0fft v=%.1f,%.1f,%.1f tilt=%.1fdeg wx=%.2f oq=%.2f qerr=%.1fdeg aca=%05o,%05o,%05o out=%03o,%03o jets=%d",
                    snapshot.timeSeconds,
                    state.altitudeMeters / 0.3048,
                    state.velocityMetersPerSecond.x,
                    state.velocityMetersPerSecond.y,
                    state.velocityMetersPerSecond.z,
                    tilt * 180 / .pi,
                    state.angularVelocityRadiansPerSecond.x,
                    omegaQ,
                    Double(cduError) * 360 / 32_768,
                    handController.pitch,
                    handController.yaw,
                    handController.roll,
                    snapshot.vehicleCommands.out0,
                    snapshot.vehicleCommands.out1,
                    snapshot.vehicleCommands.rcsJets.count
                ))
            }
            manualStep += 1
        }

        let final = snapshot.vehicleState
        let summary = String(
            format: "outcome=%@ alt=%.1fft vx=%.2f vy=%.2f vz=%.2f tilt=%.1fdeg",
            final.flightOutcome.rawValue,
            final.altitudeMeters / 0.3048,
            final.velocityMetersPerSecond.x,
            final.velocityMetersPerSecond.y,
            final.velocityMetersPerSecond.z,
            acos(min(max(final.attitude.rotated(LMVector3D(z: 1)).z, -1), 1)) * 180 / .pi
        ) + " | " + manualTrail.joined(separator: " | ")
        #expect(final.flightOutcome == .softLanding, "P66 pilot should make soft contact: \(summary)")
        let contact = try #require(final.surfaceContact, "P66 pilot should reach the surface: \(summary)")
        #expect(contact.horizontalSpeedMetersPerSecond <= LMLandingContactCriteria.softHorizontalSpeedMetersPerSecond)
        #expect(contact.verticalSpeedMetersPerSecond <= LMLandingContactCriteria.softVerticalSpeedMetersPerSecond)
        #expect(contact.tiltRadians <= LMLandingContactCriteria.softTiltRadians)
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

private struct PlantGETSample {
    var getCs: Double
    var vehicle: LMVehicleStateSnapshot
}

private func signedCDUDegrees(_ counts: Int) -> Double {
    var wrapped = counts & 0o77777
    if wrapped > 16_384 { wrapped -= 32_768 }
    return Double(wrapped) * 360.0 / 32_768.0
}

private func interpolatePlant(
    samples: [PlantGETSample],
    getCs: Double,
    refsmmat: LMMatrix3
) -> (positionMeters: LMVector3D, velocityMetersPerSecond: LMVector3D)? {
    guard let first = samples.first, let last = samples.last else { return nil }
    let vehicle: LMVehicleStateSnapshot
    if getCs <= first.getCs {
        vehicle = first.vehicle
    } else if getCs >= last.getCs {
        vehicle = last.vehicle
    } else {
        var lo = 0
        var hi = samples.count - 1
        while lo + 1 < hi {
            let mid = (lo + hi) / 2
            if samples[mid].getCs <= getCs {
                lo = mid
            } else {
                hi = mid
            }
        }
        let a = samples[lo]
        let b = samples[hi]
        let span = b.getCs - a.getCs
        let t = span > 0 ? (getCs - a.getCs) / span : 0
        vehicle = LMVehicleStateSnapshot(
            positionMeters: a.vehicle.positionMeters
                + (b.vehicle.positionMeters - a.vehicle.positionMeters) * t,
            velocityMetersPerSecond: a.vehicle.velocityMetersPerSecond
                + (b.vehicle.velocityMetersPerSecond - a.vehicle.velocityMetersPerSecond) * t,
            attitude: t < 0.5 ? a.vehicle.attitude : b.vehicle.attitude,
            angularVelocityRadiansPerSecond: a.vehicle.angularVelocityRadiansPerSecond
                + (b.vehicle.angularVelocityRadiansPerSecond
                    - a.vehicle.angularVelocityRadiansPerSecond) * t,
            massKilograms: a.vehicle.massKilograms,
            propellantMassKilograms: a.vehicle.propellantMassKilograms,
            flightOutcome: a.vehicle.flightOutcome,
            surfaceContact: a.vehicle.surfaceContact,
            dpsPitchGimbalRadians: a.vehicle.dpsPitchGimbalRadians
                + (b.vehicle.dpsPitchGimbalRadians - a.vehicle.dpsPitchGimbalRadians) * t,
            dpsRollGimbalRadians: a.vehicle.dpsRollGimbalRadians
                + (b.vehicle.dpsRollGimbalRadians - a.vehicle.dpsRollGimbalRadians) * t
        )
    }
    return LMAGCNavState.stableMemberKinematics(
        from: vehicle,
        refsmmat: refsmmat,
        timeCentiseconds: getCs
    )
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
