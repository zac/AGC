import Foundation

/// Sourced DPS throttle and RCS geometry. Pulse/force scales come from Luminary099
/// `CONTROLLED_CONSTANTS` / `THROTTLE_CONTROL_ROUTINES`; jet directions from
/// `Q_R-AXIS_RCS_AUTOPILOT` ALLJETS + TYPEPOLY; 100 lbf jets from `FRCS4`;
/// 5.5 ft moment arm from `TORKJET1` (550 ft-lbf / 100 lbf).
public enum LMDPSThrottleMap {
    public static let poundsToNewtons = 4.4482216152605

    /// NASA TN D-7143 / Luminary: 100% = 10,500 lbf.
    public static let ratedMaxThrustNewtons = 10_500.0 * poundsToNewtons

    /// THROTTLE_CONTROL_ROUTINES: throttleable region 10%–94%.
    public static let minimumThrottleFraction = 0.10
    public static let maximumThrottleFraction = 0.94

    /// FMAXPOS DEC +3467, comment FMAX +4.34546769E+4 (newtons).
    public static let fmaxPulseUnits = 3467.0
    public static let fmaxNewtons = 4.34546769e4

    /// FRATE is 32 pulse units per centisecond.
    public static let pulseUnitsPerCentisecond = 32.0

    public static var newtonsPerPulse: Double {
        fmaxNewtons / fmaxPulseUnits
    }

    public static var minimumThrustNewtons: Double {
        minimumThrottleFraction * ratedMaxThrustNewtons
    }

    public static var modelingStatus: LMModelingStatus {
        .sourceBacked(
            detail: "THRUST (055) pulse units map through FMAXPOS 3467 = 4.34546769e4 N; 10%–94% of 10,500 lbf; FRATE 32 units/cs.",
            source: .luminaryThrottleConstants
        )
    }

    public static func onesComplement15(_ value: Int) -> Int {
        let word = value & 0o77777
        if (word & 0o40000) != 0 {
            return -((~word) & 0o37777)
        }
        return word
    }

    public static func thrustNewtons(pulsePosition: Double, engineOn: Bool) -> Double? {
        guard engineOn else { return 0 }
        let span = fmaxNewtons - minimumThrustNewtons
        let fraction = pulsePosition / fmaxPulseUnits
        let newtons = minimumThrustNewtons + fraction * span
        return min(max(newtons, minimumThrustNewtons), fmaxNewtons)
    }
}

struct LMDPSThrottleState {
    var pulsePosition = 0.0
    var pendingPulses = 0.0
    var lastDriveActive = false
    var lastThrustRegister = 0

    mutating func reset() {
        pulsePosition = 0
        pendingPulses = 0
        lastDriveActive = false
        lastThrustRegister = 0
    }

    mutating func advance(thrustRegister: Int, driveActive: Bool, deltaTime: Double) {
        let register = thrustRegister & 0o77777
        let newCommand = driveActive && register != 0 && (register != lastThrustRegister || !lastDriveActive)
        if newCommand {
            pendingPulses += Double(LMDPSThrottleMap.onesComplement15(register))
        }
        lastThrustRegister = register
        lastDriveActive = driveActive

        guard deltaTime > 0, pendingPulses != 0 else { return }
        let maxThisStep = LMDPSThrottleMap.pulseUnitsPerCentisecond * deltaTime * 100.0
        let applied = min(abs(pendingPulses), maxThisStep) * pendingPulses.sign.rawValue
        pendingPulses -= applied
        pulsePosition = min(max(pulsePosition + applied, 0), LMDPSThrottleMap.fmaxPulseUnits)
    }

    func commandedThrustNewtons(engineOn: Bool) -> Double? {
        LMDPSThrottleMap.thrustNewtons(pulsePosition: pulsePosition, engineOn: engineOn)
    }
}

private extension FloatingPointSign {
    var rawValue: Double { self == .minus ? -1 : 1 }
}

public enum LMRCSGeometry {
    public static let jetThrustNewtons = 100.0 * LMDPSThrottleMap.poundsToNewtons

    /// TORKJET1 comment: 550 ft-lbf for a 100 lbf jet → 5.5 ft arm.
    public static let momentArmMeters = 5.5 * 0.3048

    /// Body frame used by LMDynamics: +Z is NASA +X (DPS), +X is NASA +Y, +Y is NASA +Z.
    public static let sourceBackedChannel5Jets: [LMRCSJet: LMRCSJetConfiguration] = {
        let s = momentArmMeters / sqrt(2.0)
        let source = LMSourceReference.luminaryRCSGeometry
        func jet(
            _ id: LMRCSJet,
            simPosition: LMVector3D,
            simThrust: LMVector3D
        ) -> LMRCSJetConfiguration {
            LMRCSJetConfiguration(
                jet: id,
                positionMeters: LMSourceValue(simPosition, source: source),
                thrustDirectionBody: LMSourceValue(simThrust, source: source),
                thrustNewtons: LMSourceValue(jetThrustNewtons, source: source)
            )
        }

        let plusZ = LMVector3D(z: 1)
        let minusZ = LMVector3D(z: -1)
        return [
            .jet10: jet(.jet10, simPosition: LMVector3D(x: s, y: s), simThrust: plusZ),
            .jet14: jet(.jet14, simPosition: LMVector3D(x: -s, y: s), simThrust: plusZ),
            .jet6: jet(.jet6, simPosition: LMVector3D(x: s, y: -s), simThrust: plusZ),
            .jet2: jet(.jet2, simPosition: LMVector3D(x: -s, y: -s), simThrust: plusZ),
            .jet1: jet(.jet1, simPosition: LMVector3D(x: s, y: -s), simThrust: minusZ),
            .jet5: jet(.jet5, simPosition: LMVector3D(x: -s, y: -s), simThrust: minusZ),
            .jet9: jet(.jet9, simPosition: LMVector3D(x: -s, y: s), simThrust: minusZ),
            .jet13: jet(.jet13, simPosition: LMVector3D(x: s, y: s), simThrust: minusZ)
        ]
    }()

    /// Channel 006 P-axis jets. Bit packing follows ALLJETS (channel 005 bits 1–8
    /// are jets 1,2,5,6,9,10,13,14); the remaining numbers 3,4,7,8,11,12,15,16
    /// are the P-axis set named in P-AXIS_RCS_AUTOPILOT failure policies.
    /// Force axes come from JETSALL ±Y/±Z masks; +P/−P from OCT 00125 / 00252.
    public static let sourceBackedChannel6Jets: [LMRCSJet: LMRCSJetConfiguration] = {
        let s = momentArmMeters / sqrt(2.0)
        let source = LMSourceReference.luminaryRCSGeometry
        func jet(
            _ id: LMRCSJet,
            simPosition: LMVector3D,
            simThrust: LMVector3D
        ) -> LMRCSJetConfiguration {
            LMRCSJetConfiguration(
                jet: id,
                positionMeters: LMSourceValue(simPosition, source: source),
                thrustDirectionBody: LMSourceValue(simThrust, source: source),
                thrustNewtons: LMSourceValue(jetThrustNewtons, source: source)
            )
        }

        let plusX = LMVector3D(x: 1)
        let minusX = LMVector3D(x: -1)
        let plusY = LMVector3D(y: 1)
        let minusY = LMVector3D(y: -1)
        return [
            .jet3: jet(.jet3, simPosition: LMVector3D(x: s, y: s), simThrust: plusY),
            .jet4: jet(.jet4, simPosition: LMVector3D(x: s, y: -s), simThrust: minusY),
            .jet7: jet(.jet7, simPosition: LMVector3D(x: -s, y: -s), simThrust: minusY),
            .jet8: jet(.jet8, simPosition: LMVector3D(x: -s, y: s), simThrust: plusY),
            .jet11: jet(.jet11, simPosition: LMVector3D(x: s, y: -s), simThrust: plusX),
            .jet12: jet(.jet12, simPosition: LMVector3D(x: -s, y: -s), simThrust: minusX),
            .jet15: jet(.jet15, simPosition: LMVector3D(x: -s, y: s), simThrust: minusX),
            .jet16: jet(.jet16, simPosition: LMVector3D(x: s, y: s), simThrust: plusX)
        ]
    }()

    public static var sourceBackedJets: [LMRCSJet: LMRCSJetConfiguration] {
        var jets = sourceBackedChannel5Jets
        for (id, configuration) in sourceBackedChannel6Jets {
            jets[id] = configuration
        }
        return jets
    }
}

/// Luminary099 1/ACCS INERCON curve fits: 1JACC = A/(MASS+C)+B, then
/// I = TORKJET1 / 1JACC. NASA P/Q/R are sim Z/X/Y.
public enum LMInertiaStage: String, Sendable, Codable {
    case descent
    case ascent
}

public enum LMInertiaMap {
    public static let massScaleKilograms = 65_536.0
    public static let accelerationScale = Double.pi / 4.0
    public static let oneJetTorqueNewtonMeters = 550.0 * 0.3048 * LMDPSThrottleMap.poundsToNewtons

    public static let source = LMSourceReference.luminary1ACCS

    public static var modelingStatus: LMModelingStatus {
        .sourceBacked(
            detail: "Diagonal inertia is TORKJET1/1JACC with 1JACC = A/(MASS+C)+B from INERCONA/B/C.",
            source: .luminary1ACCS
        )
    }

    private struct JetAccelerationFit {
        let aComputer: Double
        let bComputer: Double
        let cComputer: Double
    }

    private static let descentP = JetAccelerationFit(aComputer: 0.0059347674, bComputer: 0.002989, cComputer: 0.008721)
    private static let descentQ = JetAccelerationFit(aComputer: 0.0014979264, bComputer: 0.018791, cComputer: -0.068163)
    private static let descentR = JetAccelerationFit(aComputer: 0.0010451889, bComputer: 0.021345, cComputer: -0.066027)
    private static let ascentP = JetAccelerationFit(aComputer: 0.0065443852, bComputer: 0.000032, cComputer: -0.006923)
    private static let ascentQ = JetAccelerationFit(aComputer: 0.0035784354, bComputer: 0.162862, cComputer: 0.002588)
    private static let ascentR = JetAccelerationFit(aComputer: 0.0056946631, bComputer: 0.009312, cComputer: -0.023608)

    public static func oneJetAcceleration(
        massKilograms: Double,
        axis: LMInertiaAxis,
        stage: LMInertiaStage
    ) -> Double {
        let fit = Self.fit(axis: axis, stage: stage)
        let a = fit.aComputer * accelerationScale * massScaleKilograms
        let b = fit.bComputer * accelerationScale
        let c = fit.cComputer * massScaleKilograms
        return a / (massKilograms + c) + b
    }

    public static func diagonalInertiaKilogramMetersSquared(
        massKilograms: Double,
        stage: LMInertiaStage = .descent
    ) -> LMVector3D {
        let inertiaP = oneJetTorqueNewtonMeters / oneJetAcceleration(massKilograms: massKilograms, axis: .p, stage: stage)
        let inertiaQ = oneJetTorqueNewtonMeters / oneJetAcceleration(massKilograms: massKilograms, axis: .q, stage: stage)
        let inertiaR = oneJetTorqueNewtonMeters / oneJetAcceleration(massKilograms: massKilograms, axis: .r, stage: stage)
        return LMVector3D(x: inertiaQ, y: inertiaR, z: inertiaP)
    }

    private static func fit(axis: LMInertiaAxis, stage: LMInertiaStage) -> JetAccelerationFit {
        switch (stage, axis) {
        case (.descent, .p): return descentP
        case (.descent, .q): return descentQ
        case (.descent, .r): return descentR
        case (.ascent, .p): return ascentP
        case (.ascent, .q): return ascentQ
        case (.ascent, .r): return ascentR
        }
    }
}

public enum LMInertiaAxis: String, Sendable {
    case p
    case q
    case r
}
