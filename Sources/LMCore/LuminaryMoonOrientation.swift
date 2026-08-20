import AGC
import Foundation

/// Luminary 099 `MOONMX` / `RP-TO-R` from `PLANETARY_INERTIAL_ORIENTATION.agc`.
///
/// `R = Mᵀ(T) * (RP + L × RP)` converts a moon-fixed vector into Basic Reference.
/// Angles follow `NEWANGLE`: `X = X0 + XDOT*(T + TEPHEM)` in revolutions.
/// `COSI`/`SINI`/`BSUBO`/`BDOT`/`NODIO`/`NODDOT`/`FSUBO`/`FDOT` are Luminary
/// fixed-memory constants; `TEPHEM` and `504LM` are the NASA launch-tape values.
public enum LuminaryMoonOrientation {
    /// `COSI 2DEC .99964173 B-1` — cos(1°32.1′) of mean lunar equator to ecliptic.
    public static let cosi = 0.99964173
    /// `SINI 2DEC .02676579 B-1`.
    public static let sini = 0.02676579
    /// `NODDOT 2DEC -.457335121 E-2` at B+28, revolutions per centisecond.
    public static let noddotRevolutionsPerCentisecond = -0.457335121e-2 * pow(2.0, -28)
    /// `FDOT 2DEC .570863327` at B+27, revolutions per centisecond.
    public static let fdotRevolutionsPerCentisecond = 0.570863327 * pow(2.0, -27)
    /// `BDOT 2DEC -3.07500686 E-8` at B+28, revolutions per centisecond.
    public static let bdotRevolutionsPerCentisecond = -3.07500686e-8 * pow(2.0, -28)
    /// `NODIO 2DEC .986209434` revolutions B0.
    public static let nodioRevolutions = 0.986209434
    /// `FSUBO 2DEC .829090536` revolutions B0.
    public static let fsuboRevolutions = 0.829090536
    /// `BSUBO 2DEC .0651201393` revolutions B0.
    public static let bsuboRevolutions = 0.0651201393
    /// `OMEGMOON 2DEC* 2.66169947 E-8 B+23*` radians per centisecond.
    public static let moonRateRadiansPerCentisecond = 2.66169947e-8
    /// Sidereal lunar rate in SI, along moon-fixed +Z.
    public static var moonRateRadiansPerSecond: Double {
        moonRateRadiansPerCentisecond * 100.0
    }

    public static func moonMatrix(timeCentiseconds: Double) -> LMMatrix3 {
        let b = newAngle(
            x0: bsuboRevolutions,
            xDot: bdotRevolutionsPerCentisecond,
            timeCentiseconds: timeCentiseconds
        )
        let f = newAngle(
            x0: fsuboRevolutions,
            xDot: fdotRevolutionsPerCentisecond,
            timeCentiseconds: timeCentiseconds
        )
        let node = newAngle(
            x0: nodioRevolutions,
            xDot: noddotRevolutionsPerCentisecond,
            timeCentiseconds: timeCentiseconds
        )
        let (sinB, cosB) = sincos(revolutions: b)
        let (sinF, cosF) = sincos(revolutions: f)
        let (sinNode, cosNode) = sincos(revolutions: node)

        let a = LMVector3D(x: cosNode, y: sinNode * cosB, z: sinNode * sinB)
        let bVector = LMVector3D(x: -sinNode, y: cosNode * cosB, z: cosNode * sinB)
        let c = LMVector3D(x: 0, y: -sinB, z: cosB)
        let m2 = bVector * sini + c * cosi
        let d = bVector * cosi - c * sini
        let m1 = a * sinF - d * cosF
        let m0 = -(a * cosF + d * sinF)
        return LMMatrix3(r0: m0, r1: m1, r2: m2)
    }

    /// Moon-fixed position to Basic Reference at GET `timeCentiseconds`.
    public static func rpToR(_ moonFixed: LMVector3D, timeCentiseconds: Double) -> LMVector3D {
        let matrix = moonMatrix(timeCentiseconds: timeCentiseconds)
        let librated = moonFixed + Luminary99CoordinatePadLoad.librationRadians.cross(moonFixed)
        return matrix.timesTranspose(librated)
    }

    /// Inverse of `rpToR` (`R-TO-RP`).
    public static func rToRP(_ reference: LMVector3D, timeCentiseconds: Double) -> LMVector3D {
        let matrix = moonMatrix(timeCentiseconds: timeCentiseconds)
        let librationReference = matrix.timesTranspose(Luminary99CoordinatePadLoad.librationRadians)
        return matrix.times(reference - librationReference.cross(reference))
    }

    /// Moon-relative velocity in moon-fixed axes to Basic Reference.
    ///
    /// Rotates `V + ω × RP` with the same `Mᵀ` as position. `ω` is `OMEGMOON`
    /// along moon-fixed +Z. 504LM is treated as constant, so libration rate
    /// is omitted.
    public static func moonRelativeVelocityToReference(
        velocityMetersPerCentisecond: LMVector3D,
        moonFixedPosition: LMVector3D,
        timeCentiseconds: Double
    ) -> LMVector3D {
        let omega = LMVector3D(z: moonRateRadiansPerCentisecond)
        let inertialMoonFixed = velocityMetersPerCentisecond + omega.cross(moonFixedPosition)
        return moonMatrix(timeCentiseconds: timeCentiseconds).timesTranspose(inertialMoonFixed)
    }

    /// Inverse of `moonRelativeVelocityToReference`.
    public static func referenceVelocityToMoonRelative(
        inertialMetersPerCentisecond: LMVector3D,
        moonFixedPosition: LMVector3D,
        timeCentiseconds: Double
    ) -> LMVector3D {
        let inertialMoonFixed = moonMatrix(timeCentiseconds: timeCentiseconds).times(inertialMetersPerCentisecond)
        let omega = LMVector3D(z: moonRateRadiansPerCentisecond)
        return inertialMoonFixed - omega.cross(moonFixedPosition)
    }

    /// `NEWANGLE`: `X = frac(X0 + XDOT*(T + TEPHEM))` revolutions B0.
    public static func newAngle(x0: Double, xDot: Double, timeCentiseconds: Double) -> Double {
        let total = x0 + xDot * (timeCentiseconds + Luminary99CoordinatePadLoad.tephemCentiseconds)
        return total - floor(total)
    }

    private static func sincos(revolutions: Double) -> (sin: Double, cos: Double) {
        let radians = revolutions * 2.0 * .pi
        return (sin(radians), cos(radians))
    }
}

/// 3×3 matrix with rows matching AGC `MMATRIX` (`M0`, `M1`, `M2`).
public struct LMMatrix3: Equatable, Sendable {
    public let r0: LMVector3D
    public let r1: LMVector3D
    public let r2: LMVector3D

    public init(r0: LMVector3D, r1: LMVector3D, r2: LMVector3D) {
        self.r0 = r0
        self.r1 = r1
        self.r2 = r2
    }

    /// `M * v`.
    public func times(_ vector: LMVector3D) -> LMVector3D {
        LMVector3D(x: r0.dot(vector), y: r1.dot(vector), z: r2.dot(vector))
    }

    /// `Mᵀ * v`, the `VXM MMATRIX` / `VSL1` path in `RP-TO-R`.
    public func timesTranspose(_ vector: LMVector3D) -> LMVector3D {
        r0 * vector.x + r1 * vector.y + r2 * vector.z
    }

    public func row(_ index: Int) -> LMVector3D {
        switch index {
        case 0: return r0
        case 1: return r1
        default: return r2
        }
    }

    public func entry(row: Int, column: Int) -> Double {
        let vector = self.row(row)
        switch column {
        case 0: return vector.x
        case 1: return vector.y
        default: return vector.z
        }
    }
}
