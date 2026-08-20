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
}

/// NASA IMU 3-2-1 CDUs in the sim body frame. Luminary P/Q/R are
/// sim Z/X/Y, so the PDI rotation about sim X is CDUY (Q), not CDUX (P).
/// PIPAs live on the stable member: body specific force is rotated into
/// SM (same map as identity: sim +Z thrust → PIPAX) before PINC.
public enum LMIMUGimbalMap {
    public static func nasaBody(fromSim sim: LMVector3D) -> LMVector3D {
        LMVector3D(x: sim.z, y: sim.x, z: sim.y)
    }

    /// Luminary CALCGA / FLESHPOT (OIM=XYZ): CDUX outer, CDUY inner, CDUZ middle.
    /// Body axes in SM via `nasaBody` of world-rotated sim axes.
    public static func cduRadians(from attitude: LMQuaternion) -> (x: Double, y: Double, z: Double) {
        let xnb = nasaBody(fromSim: attitude.rotated(LMVector3D(z: 1)))
        let ynb = nasaBody(fromSim: attitude.rotated(LMVector3D(x: 1)))
        let znb = nasaBody(fromSim: attitude.rotated(LMVector3D(y: 1)))
        let ysm = LMVector3D(y: 1)
        let mga = xnb.cross(ysm)
        guard mga.magnitude > 1e-12 else {
            return (x: 0, y: attitude.yawPitchRollRadians.x, z: 0)
        }
        let mgaN = mga.normalized()
        let og = atan2(mgaN.dot(ynb), mgaN.dot(znb))
        let mgaCrossX = mgaN.cross(xnb)
        let mg = atan2(ysm.dot(xnb), ysm.dot(mgaCrossX))
        let ig = atan2(mgaN.x, mgaN.z)
        return (x: og, y: ig, z: mg)
    }

    public static func cduCounts(from attitude: LMQuaternion) -> (x: Int, y: Int, z: Int) {
        let radians = cduRadians(from: attitude)
        return (
            x: count(radians.x),
            y: count(radians.y),
            z: count(radians.z)
        )
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
    mutating func increments(
        specificForceSM: LMVector3D,
        attitude: LMQuaternion,
        deltaTime: Double
    ) -> [AGCChannelInput] {
        var inputs: [AGCChannelInput] = []
        inputs.append(contentsOf: pipaIncrements(
            specificForceSM: specificForceSM,
            deltaTime: deltaTime
        ))
        inputs.append(contentsOf: cduIncrements(attitude: attitude))
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

    mutating func cduIncrements(attitude: LMQuaternion) -> [AGCChannelInput] {
        let scale = LMSensorScale.cduRadiansPerCount.value
        guard scale > 0 else { return [] }

        guard let previousAttitude = lastAttitude, let previousCounts = lastCDUCounts else {
            lastAttitude = attitude
            lastCDUCounts = LMIMUGimbalMap.cduCounts(from: attitude)
            cduRemainder = .zero
            return []
        }

        let target = LMIMUGimbalMap.cduCounts(from: attitude)
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

enum LMRadarConversion {
    static func rawInput(from measurement: LMRadarMeasurementInput) -> AGCRadarInput {
        AGCRadarInput(
            rendezvousRadar: measurement.rangeMeters.map { word(meters: $0) },
            altitudeMeter: measurement.altitudeMeters.map { word(meters: $0) }
        )
    }

    private static func word(meters: Double, scale: Double = LMSensorScale.landingRadarAltitudeMetersPerBit.value) -> Int {
        let bits = Int((meters / scale).rounded())
        return max(0, min(0o37777, bits))
    }
}
