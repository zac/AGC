import AGC
import Foundation

/// Sourced IMU/radar scales used to close the AGC sensor loop.
public enum LMSensorScale {
    /// One PINC on PIPAX/Y/Z is 1 cm/s. SERVICER stores `|DELV|` as ABDELV
    /// “CM/SEC*2(-14)” and DVMON compares that to DPSTHRSH (36 cm/s, ~600 lbf).
    /// NASA R-567’s 5.85 cm/s is the analog IMU quantum; using that as the PINC
    /// size left ABDELV ≈ 10 at 10% DPS and tripped COMFAIL / WAITLIST 01204.
    public static let pipaMetersPerSecondPerPulse = LMSourceValue(
        0.01,
        source: .luminaryPIPAScale
    )

    /// 32768 CDU counts per revolution.
    public static let cduRadiansPerCount = LMSourceValue(
        (2.0 * Double.pi) / 32_768.0,
        source: .agcCDUEncoding
    )

    /// Landing radar low-scale altitude: 1.079 ft/bit.
    public static let landingRadarAltitudeMetersPerBit = LMSourceValue(
        1.079 * 0.3048,
        source: .luminaryLandingRadarScale
    )
    /// LRSCK `DDOUBL` twice. High-scale quantum is 4.316 ft/bit.
    public static let landingRadarAltitudeHighScaleMultiplier = 4.0
    /// Luminary `HISCALIM DEC 460` comment: 2481.7 ft.
    public static let landingRadarAltitudeHighScaleThresholdMeters = 2481.7 * 0.3048

    /// LVELBIAS count at zero Doppler (CONTROLLED_CONSTANTS DEC −12288).
    public static let landingRadarVelocityBiasCounts = 12_288

    /// LRVELX −0.644 ft/s per bit.
    public static let landingRadarVelocityXFeetPerSecondPerBit = LMSourceValue(
        -0.644,
        source: .luminaryLandingRadarScale
    )

    /// LRVELY 1.212 ft/s per bit.
    public static let landingRadarVelocityYFeetPerSecondPerBit = LMSourceValue(
        1.212,
        source: .luminaryLandingRadarScale
    )

    /// LRVELZ 0.8668 ft/s per bit.
    public static let landingRadarVelocityZFeetPerSecondPerBit = LMSourceValue(
        0.8668,
        source: .luminaryLandingRadarScale
    )
}

/// NASA IMU 3-2-1 CDUs in the sim body frame. Luminary P/Q/R are
/// sim Z/X/Y, so the PDI rotation about sim X is CDUY (Q), not CDUX (P).
/// PIPAs live on the stable member: body specific force is rotated into
/// SM (same map as identity: sim +Z thrust → PIPAX) before PINC.
public enum LMIMUGimbalMap {
    public static func nasaBody(fromSim sim: LMVector3D) -> LMVector3D {
        LMVector3D(x: sim.z, y: sim.x, z: sim.y)
    }

    public static func sim(fromNasa nasa: LMVector3D) -> LMVector3D {
        LMVector3D(x: nasa.y, y: nasa.z, z: nasa.x)
    }

    /// Luminary CALCGA / FLESHPOT (OIM=XYZ): CDUX outer, CDUY inner, CDUZ middle.
    /// Body axes in SM via `nasaBody` of world-rotated sim axes.
    public static func cduRadians(from attitude: LMQuaternion) -> (x: Double, y: Double, z: Double) {
        cduRadians(
            xnb: nasaBody(fromSim: attitude.rotated(LMVector3D(z: 1))),
            ynb: nasaBody(fromSim: attitude.rotated(LMVector3D(x: 1))),
            znb: nasaBody(fromSim: attitude.rotated(LMVector3D(y: 1))),
            fallbackInner: attitude.yawPitchRollRadians.x
        )
    }

    /// Diagnostic CALCGA: body axes in frozen SM via live `RP-TO-R`.
    /// Not for `LMSimulation.stepExact` until CDUY tracks CDUYD through ZOOM
    /// on this map (the production SM wiring hit −148° CDUY error).
    public static func cduRadians(
        from attitude: LMQuaternion,
        refsmmat: LMMatrix3,
        timeCentiseconds: Double
    ) -> (x: Double, y: Double, z: Double) {
        cduRadians(
            xnb: LMAGCNavState.specificForceSM(
                body: LMVector3D(z: 1),
                attitude: attitude,
                refsmmat: refsmmat,
                timeCentiseconds: timeCentiseconds
            ),
            ynb: LMAGCNavState.specificForceSM(
                body: LMVector3D(x: 1),
                attitude: attitude,
                refsmmat: refsmmat,
                timeCentiseconds: timeCentiseconds
            ),
            znb: LMAGCNavState.specificForceSM(
                body: LMVector3D(y: 1),
                attitude: attitude,
                refsmmat: refsmmat,
                timeCentiseconds: timeCentiseconds
            ),
            fallbackInner: attitude.yawPitchRollRadians.x
        )
    }

    public static func cduCounts(from attitude: LMQuaternion) -> (x: Int, y: Int, z: Int) {
        counts(cduRadians(from: attitude))
    }

    public static func cduCounts(
        from attitude: LMQuaternion,
        refsmmat: LMMatrix3,
        timeCentiseconds: Double
    ) -> (x: Int, y: Int, z: Int) {
        counts(cduRadians(from: attitude, refsmmat: refsmmat, timeCentiseconds: timeCentiseconds))
    }

    private static func cduRadians(
        xnb: LMVector3D,
        ynb: LMVector3D,
        znb: LMVector3D,
        fallbackInner: Double
    ) -> (x: Double, y: Double, z: Double) {
        let ysm = LMVector3D(y: 1)
        let mga = xnb.cross(ysm)
        guard mga.magnitude > 1e-12 else {
            return (x: 0, y: fallbackInner, z: 0)
        }
        let mgaN = mga.normalized()
        let og = atan2(mgaN.dot(ynb), mgaN.dot(znb))
        let mgaCrossX = mgaN.cross(xnb)
        let mg = atan2(ysm.dot(xnb), ysm.dot(mgaCrossX))
        let ig = atan2(mgaN.x, mgaN.z)
        return (x: og, y: ig, z: mg)
    }

    private static func counts(_ radians: (x: Double, y: Double, z: Double)) -> (x: Int, y: Int, z: Int) {
        (x: count(radians.x), y: count(radians.y), z: count(radians.z))
    }

    /// Shortest signed CDU tick delta in `[-16384, 16383]`.
    public static func shortestCountDelta(from: Int, to: Int) -> Int {
        var delta = (to & 0o77777) - (from & 0o77777)
        if delta > 16_384 { delta -= 32_768 }
        if delta < -16_384 { delta += 32_768 }
        return delta
    }

    /// Body-frame rotation vector taking `from` into `to` (same convention as
    /// `LMQuaternion.integrated`). Mapped through `nasaBody` this is the IMU
    /// CDU increment; it stays continuous through the 95° PDI inner gimbal
    /// where 3-2-1 Euler extraction can jump.
    public static func bodyRotation(from: LMQuaternion, to: LMQuaternion) -> LMVector3D {
        var q = from.conjugated.multiplied(by: to).normalized()
        if q.w < 0 {
            q = LMQuaternion(w: -q.w, x: -q.x, y: -q.y, z: -q.z)
        }
        let mag = sqrt(q.x * q.x + q.y * q.y + q.z * q.z)
        guard mag > 1e-15 else { return .zero }
        return LMVector3D(x: q.x, y: q.y, z: q.z) * (2 * atan2(mag, q.w) / mag)
    }

    private static func count(_ radians: Double) -> Int {
        let scale = LMSensorScale.cduRadiansPerCount.value
        guard scale > 0 else { return 0 }
        var wrapped = Int((radians / scale).rounded()) % 32_768
        if wrapped < 0 { wrapped += 32_768 }
        return wrapped
    }
}

struct LMSensorFeedbackState {
    /// 0.25 s at FMAX is ~73 cm/s. 256 PINCs at 1 cm/s covers that with margin.
    static let maxPIPAPulsesPerAxis = 256
    /// yaAGC high-rate CDU FIFO (type 021/023, 13 MCT) is ~70°/s. 64 pulses
    /// per 10 ms T5 slice matches that ceiling so DAP OMEGA sees body rate.
    static let maxCDUPulsesPerAxis = 64

    var pipaRemainder = LMVector3D.zero
    var cduRemainder = LMVector3D.zero
    var lastCDUCounts: (x: Int, y: Int, z: Int)?
    var lastAttitude: LMQuaternion?

    mutating func reset() {
        pipaRemainder = .zero
        cduRemainder = .zero
        lastCDUCounts = nil
        lastAttitude = nil
    }

    /// PIPA pulses from SM specific force, plus CDU catch-up toward the current
    /// attitude. PIPAs sit on the stable member (inertial), not moon-fixed ENU.
    ///
    /// `refsmmat` is a diagnostic CDU map. Do not pass it from the simulation
    /// hot path: that coupling left CDUY 148° off CDUYD after ZOOM.
    mutating func increments(
        specificForceSM: LMVector3D,
        attitude: LMQuaternion,
        deltaTime: Double,
        refsmmat: LMMatrix3? = nil,
        timeCentiseconds: Double? = nil
    ) -> [AGCChannelInput] {
        var inputs: [AGCChannelInput] = []
        inputs.append(contentsOf: pipaIncrements(
            specificForceSM: specificForceSM,
            deltaTime: deltaTime
        ))
        let target: (x: Int, y: Int, z: Int)
        if let refsmmat, let timeCentiseconds {
            target = LMIMUGimbalMap.cduCounts(
                from: attitude,
                refsmmat: refsmmat,
                timeCentiseconds: timeCentiseconds
            )
        } else {
            target = LMIMUGimbalMap.cduCounts(from: attitude)
        }
        inputs.append(contentsOf: cduIncrements(attitude: attitude, targetCounts: target))
        return inputs
    }

    /// Unit-test path: treat sim ENU as SM (true only at the REFSMMAT epoch).
    mutating func increments(
        specificForceBody: LMVector3D,
        attitude: LMQuaternion,
        deltaTime: Double
    ) -> [AGCChannelInput] {
        increments(
            specificForceSM: LMIMUGimbalMap.nasaBody(fromSim: attitude.rotated(specificForceBody)),
            attitude: attitude,
            deltaTime: deltaTime
        )
    }

    /// PIPAs sit on the stable member. Identity attitude: NASA +X = SM +X = PIPAX.
    mutating func pipaIncrements(
        specificForceSM: LMVector3D,
        deltaTime: Double
    ) -> [AGCChannelInput] {
        guard deltaTime > 0 else { return [] }
        let scale = LMSensorScale.pipaMetersPerSecondPerPulse.value
        guard scale > 0 else { return [] }

        let deltaV = specificForceSM * deltaTime + pipaRemainder
        let x = quantizedPulses(deltaV.x / scale, limit: Self.maxPIPAPulsesPerAxis)
        let y = quantizedPulses(deltaV.y / scale, limit: Self.maxPIPAPulsesPerAxis)
        let z = quantizedPulses(deltaV.z / scale, limit: Self.maxPIPAPulsesPerAxis)
        pipaRemainder = LMVector3D(x: x.remainder * scale, y: y.remainder * scale, z: z.remainder * scale)

        var inputs: [AGCChannelInput] = []
        inputs.append(contentsOf: counterPulses(register: .regPIPAX, count: x.pulses, cdu: false))
        inputs.append(contentsOf: counterPulses(register: .regPIPAY, count: y.pulses, cdu: false))
        inputs.append(contentsOf: counterPulses(register: .regPIPAZ, count: z.pulses, cdu: false))
        return inputs
    }

    mutating func cduIncrements(
        attitude: LMQuaternion,
        targetCounts: (x: Int, y: Int, z: Int)
    ) -> [AGCChannelInput] {
        let scale = LMSensorScale.cduRadiansPerCount.value
        guard scale > 0 else { return [] }

        guard let previousAttitude = lastAttitude, let previousCounts = lastCDUCounts else {
            lastAttitude = attitude
            lastCDUCounts = targetCounts
            cduRemainder = .zero
            return []
        }

        let target = targetCounts
        let euler = LMVector3D(
            x: Double(LMIMUGimbalMap.shortestCountDelta(from: previousCounts.x, to: target.x)),
            y: Double(LMIMUGimbalMap.shortestCountDelta(from: previousCounts.y, to: target.y)),
            z: Double(LMIMUGimbalMap.shortestCountDelta(from: previousCounts.z, to: target.z))
        )
        let jump = max(abs(euler.x), max(abs(euler.y), abs(euler.z))) > 4_096
        let ticks: LMVector3D
        if jump {
            let nasa = LMIMUGimbalMap.nasaBody(
                fromSim: LMIMUGimbalMap.bodyRotation(from: previousAttitude, to: attitude)
            )
            ticks = nasa / scale + cduRemainder
        } else {
            ticks = euler
        }
        let dx = quantizedPulses(ticks.x, limit: Self.maxCDUPulsesPerAxis)
        let dy = quantizedPulses(ticks.y, limit: Self.maxCDUPulsesPerAxis)
        let dz = quantizedPulses(ticks.z, limit: Self.maxCDUPulsesPerAxis)
        cduRemainder = jump
            ? LMVector3D(x: dx.remainder, y: dy.remainder, z: dz.remainder)
            : .zero
        lastAttitude = attitude
        lastCDUCounts = (
            x: wrappedCount(Double(previousCounts.x + dx.pulses)),
            y: wrappedCount(Double(previousCounts.y + dy.pulses)),
            z: wrappedCount(Double(previousCounts.z + dz.pulses))
        )

        var inputs: [AGCChannelInput] = []
        inputs.append(contentsOf: counterPulses(register: .regCDUX, count: dx.pulses, cdu: true))
        inputs.append(contentsOf: counterPulses(register: .regCDUY, count: dy.pulses, cdu: true))
        inputs.append(contentsOf: counterPulses(register: .regCDUZ, count: dz.pulses, cdu: true))
        return inputs
    }

    private func quantizedPulses(_ value: Double, limit: Int) -> (pulses: Int, remainder: Double) {
        let truncated = value.rounded(.towardZero)
        var pulses = Int(truncated)
        pulses = clampedPulseCount(pulses, limit: limit)
        return (pulses, value - Double(pulses))
    }

    private func clampedPulseCount(_ value: Int, limit: Int) -> Int {
        min(max(value, -limit), limit)
    }

    private func wrappedCount(_ value: Double) -> Int {
        var count = Int(value.rounded()) % 32_768
        if count < 0 { count += 32_768 }
        return count
    }

    private func counterPulses(register: Register, count: Int, cdu: Bool) -> [AGCChannelInput] {
        guard count != 0 else { return [] }
        let up = count > 0
        // IMU *following* vehicle attitude uses yaAGC high-rate PCDU/MCDU
        // (021/023, 13 MCT). Types 1/3 are the ~4.4°/s coarse-align drive
        // and leave DAP OMEGA blind to powered-descent body rates.
        let type = cdu ? (up ? 0o21 : 0o23) : (up ? 0 : 2)
        return Array(
            repeating: AGCChannelInput(channel: 0o200 | register.rawValue, value: type),
            count: abs(count)
        )
    }
}

/// Landing-radar geometry for R12. Luminary SETPOS transforms antenna vectors
/// to NASA body with the position-specific LRALPHA/LRBETA pad loads.
enum LMLandingRadar {
    /// Luminary `CONTROLLED_CONSTANTS` `HBEAMANT`, half-unit in antenna coords.
    static let hBeamAntenna = LMVector3D(x: -0.4687018041, y: 0, z: -0.1741224271)
    /// Skip data-good when the range beam points at the sky. Against the
    /// vehicle's local vertical, 95° PDI sees the ground at `towardGround`
    /// ≈ 0.59, so this gate only closes when the beam really is skyward.
    static let minTowardGround = 0.2

    static let alphaRadians = 6.0 * .pi / 180
    static let beta1Radians = 24.0 * .pi / 180
    static let beta2Radians = 0.0

    /// Luminary's `*SMNB*` transform for CDUSPOT = (beta, 0, alpha):
    /// antenna-to-NB = Rx(-alpha) Ry(-beta).
    static func nasaBodyVector(fromAntenna vector: LMVector3D, position2: Bool) -> LMVector3D {
        let beta = position2 ? beta2Radians : beta1Radians
        let cosBeta = cos(beta)
        let sinBeta = sin(beta)
        let afterY = LMVector3D(
            x: cosBeta * vector.x - sinBeta * vector.z,
            y: vector.y,
            z: sinBeta * vector.x + cosBeta * vector.z
        )
        let cosAlpha = cos(alphaRadians)
        let sinAlpha = sin(alphaRadians)
        return LMVector3D(
            x: afterY.x,
            y: cosAlpha * afterY.y + sinAlpha * afterY.z,
            z: -sinAlpha * afterY.y + cosAlpha * afterY.z
        )
    }

    static func measurement(
        from state: LMVehicleStateSnapshot,
        position2: Bool = false
    ) -> LMRadarMeasurementInput? {
        let hBeamNasa = nasaBodyVector(fromAntenna: hBeamAntenna.normalized(), position2: position2)
        let beamWorld = state.attitude.rotated(
            LMIMUGimbalMap.sim(fromNasa: hBeamNasa)
        )
        // Project onto the vehicle's own local vertical, not the site's. Site
        // ENU is a tangent plane pinned at RLS; at PDI the LM is 21° of lunar
        // arc uprange of it, so `-beamWorld.z` overstates the slant range by
        // 2.2x (56.7 km against a true 25.3 km).
        let (north, east, up) = LMAGCNavState.moonFixedSiteBasis()
        let beamMoon = north * beamWorld.x + east * beamWorld.y + up * beamWorld.z
        let moon = LMAGCNavState.moonCenteredPositionMeters(from: state)
        guard moon.magnitude > 0 else { return nil }
        let towardGround = -beamMoon.dot(moon.normalized())
        guard towardGround > minTowardGround else { return nil }
        let nasaBodyVelocity = LMIMUGimbalMap.nasaBody(
            fromSim: state.attitude.inverseRotated(state.velocityMetersPerSecond)
        )
        let xBeam = nasaBodyVector(fromAntenna: LMVector3D(x: 1), position2: position2)
        let yBeam = nasaBodyVector(fromAntenna: LMVector3D(y: 1), position2: position2)
        let zBeam = xBeam.cross(yBeam)
        return LMRadarMeasurementInput(
            altitudeMeters: max(0, state.altitudeMeters / towardGround),
            landingRadarBeamVelocityMetersPerSecond: LMVector3D(
                x: nasaBodyVelocity.dot(xBeam),
                y: nasaBodyVelocity.dot(yBeam),
                z: nasaBodyVelocity.dot(zBeam)
            )
        )
    }
}

enum LMRadarConversion {
    static func rawInput(from measurement: LMRadarMeasurementInput) -> AGCRadarInput {
        let altitudeHighScale = measurement.altitudeMeters.map {
            $0 > LMSensorScale.landingRadarAltitudeHighScaleThresholdMeters
        } ?? false
        let altitudeScale = LMSensorScale.landingRadarAltitudeMetersPerBit.value
            * (altitudeHighScale ? LMSensorScale.landingRadarAltitudeHighScaleMultiplier : 1.0)
        let altitude = measurement.altitudeMeters.map { word(meters: $0, scale: altitudeScale) }
        let velocity = measurement.landingRadarBeamVelocityMetersPerSecond
            ?? measurement.nasaBodyVelocityMetersPerSecond
        return AGCRadarInput(
            rendezvousRadar: measurement.rangeMeters.map { word(meters: $0) },
            altitudeMeter: altitude,
            landingRadarVelocityX: velocity.map {
                velocityWord($0.x, feetPerSecondPerBit: LMSensorScale.landingRadarVelocityXFeetPerSecondPerBit.value)
            },
            landingRadarVelocityY: velocity.map {
                velocityWord($0.y, feetPerSecondPerBit: LMSensorScale.landingRadarVelocityYFeetPerSecondPerBit.value)
            },
            landingRadarVelocityZ: velocity.map {
                velocityWord($0.z, feetPerSecondPerBit: LMSensorScale.landingRadarVelocityZFeetPerSecondPerBit.value)
            },
            landingRadarAltitude: altitude,
            landingRadarAltitudeHighScale: altitudeHighScale
        )
    }

    private static func word(meters: Double, scale: Double = LMSensorScale.landingRadarAltitudeMetersPerBit.value) -> Int {
        let bits = Int((meters / scale).rounded())
        return max(0, min(0o77777, bits))
    }

    private static func velocityWord(_ metersPerSecond: Double, feetPerSecondPerBit: Double) -> Int {
        guard feetPerSecondPerBit != 0 else { return LMSensorScale.landingRadarVelocityBiasCounts }
        let feetPerSecond = metersPerSecond / 0.3048
        let counts = Double(LMSensorScale.landingRadarVelocityBiasCounts) + feetPerSecond / feetPerSecondPerBit
        return max(0, min(0o37777, Int(counts.rounded())))
    }
}
