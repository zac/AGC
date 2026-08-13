import AGC
import Foundation

/// Sourced IMU/radar scales used to close the AGC sensor loop.
public enum LMSensorScale {
    /// LM PIPA scale factor: 5.85 cm/s per pulse (NASA R-567 / Luminary GSOP).
    public static let pipaMetersPerSecondPerPulse = LMSourceValue(
        0.0585,
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

struct LMSensorFeedbackState {
    static let maxPulsesPerAxis = 64

    var pipaRemainder = LMVector3D.zero
    var lastCDUCounts: (x: Int, y: Int, z: Int)?

    mutating func reset() {
        pipaRemainder = .zero
        lastCDUCounts = nil
    }

    /// PIPA pulses from specific force, plus CDU catch-up toward the current attitude.
    mutating func increments(
        specificForceBody: LMVector3D,
        attitude: LMQuaternion,
        deltaTime: Double
    ) -> [AGCChannelInput] {
        var inputs: [AGCChannelInput] = []
        inputs.append(contentsOf: pipaIncrements(specificForceBody: specificForceBody, deltaTime: deltaTime))
        inputs.append(contentsOf: cduIncrements(attitude: attitude))
        return inputs
    }

    mutating func pipaIncrements(specificForceBody: LMVector3D, deltaTime: Double) -> [AGCChannelInput] {
        guard deltaTime > 0 else { return [] }
        let scale = LMSensorScale.pipaMetersPerSecondPerPulse.value
        guard scale > 0 else { return [] }

        let deltaV = specificForceBody * deltaTime + pipaRemainder
        let x = quantizedPulses(deltaV.x / scale)
        let y = quantizedPulses(deltaV.y / scale)
        let z = quantizedPulses(deltaV.z / scale)
        pipaRemainder = LMVector3D(x: x.remainder * scale, y: y.remainder * scale, z: z.remainder * scale)

        var inputs: [AGCChannelInput] = []
        inputs.append(contentsOf: counterPulses(register: .regPIPAX, count: x.pulses, cdu: false))
        inputs.append(contentsOf: counterPulses(register: .regPIPAY, count: y.pulses, cdu: false))
        inputs.append(contentsOf: counterPulses(register: .regPIPAZ, count: z.pulses, cdu: false))
        return inputs
    }

    mutating func cduIncrements(attitude: LMQuaternion) -> [AGCChannelInput] {
        let euler = attitude.yawPitchRollRadians
        let scale = LMSensorScale.cduRadiansPerCount.value
        guard scale > 0 else { return [] }

        let target = (
            x: wrappedCount(euler.x / scale),
            y: wrappedCount(euler.y / scale),
            z: wrappedCount(euler.z / scale)
        )

        guard let last = lastCDUCounts else {
            lastCDUCounts = target
            return []
        }

        let dx = shortestCountDelta(from: last.x, to: target.x)
        let dy = shortestCountDelta(from: last.y, to: target.y)
        let dz = shortestCountDelta(from: last.z, to: target.z)
        lastCDUCounts = (
            x: wrappedCount(Double(last.x + clampedPulseCount(dx))),
            y: wrappedCount(Double(last.y + clampedPulseCount(dy))),
            z: wrappedCount(Double(last.z + clampedPulseCount(dz)))
        )

        var inputs: [AGCChannelInput] = []
        inputs.append(contentsOf: counterPulses(register: .regCDUX, count: clampedPulseCount(dx), cdu: true))
        inputs.append(contentsOf: counterPulses(register: .regCDUY, count: clampedPulseCount(dy), cdu: true))
        inputs.append(contentsOf: counterPulses(register: .regCDUZ, count: clampedPulseCount(dz), cdu: true))
        return inputs
    }

    private func quantizedPulses(_ value: Double) -> (pulses: Int, remainder: Double) {
        let truncated = value.rounded(.towardZero)
        var pulses = Int(truncated)
        pulses = clampedPulseCount(pulses)
        return (pulses, value - Double(pulses))
    }

    private func clampedPulseCount(_ value: Int) -> Int {
        min(max(value, -Self.maxPulsesPerAxis), Self.maxPulsesPerAxis)
    }

    private func wrappedCount(_ value: Double) -> Int {
        var count = Int(value.rounded()) % 32_768
        if count < 0 { count += 32_768 }
        return count
    }

    private func shortestCountDelta(from: Int, to: Int) -> Int {
        var delta = (to - from) % 32_768
        if delta > 16_384 { delta -= 32_768 }
        if delta < -16_384 { delta += 32_768 }
        return delta
    }

    private func counterPulses(register: Register, count: Int, cdu: Bool) -> [AGCChannelInput] {
        guard count != 0 else { return [] }
        let up = count > 0
        let type = cdu ? (up ? 1 : 3) : (up ? 0 : 2)
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
