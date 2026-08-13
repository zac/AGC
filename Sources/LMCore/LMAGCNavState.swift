import AGC
import Foundation

/// Luminary 099 ECADRs from the yaYUL listing of `ERASABLE_ASSIGNMENTS.agc`.
///
/// Unswitched locations equal their 12-bit CPU addresses. Switched E3/E4
/// locations use the full 11-bit ECADR (`EBANK << 8 | offset`).
public enum Luminary099Erasable {
    public static let state = 0o74
    public static let time2 = 0o24
    public static let time1 = 0o25
    public static let rn = 0o1220
    public static let vn = 0o1226
    public static let pipTime = 0o1234
    public static let mass = 0o1244
    public static let lemMass = 0o1331
    public static let csmMass = 0o1332
    public static let rRectLEM = 0o1626
    public static let vRectLEM = 0o1634
    public static let tetLEM = 0o1642
    public static let tephem = 0o1706
    public static let azo = 0o1711
    public static let negAyo = 0o1713
    public static let axo = 0o1715
    public static let refsmmat = 0o1733
    public static let lm504 = 0o2012
    /// E4,1422 with `SETLOC 2000` → ECADR 02022, not CPU address 01422 or 02222.
    public static let rls = 0o2022
    public static let tland = 0o2400
    public static let rbrfg = 0o2402
    public static let vbrfg = 0o2410
    public static let abrfg = 0o2416
    public static let vbrfgStar = 0o2424
    public static let abrfgStar = 0o2426
    public static let jbrfgStar = 0o2430
    public static let gainBrak = 0o2432
    public static let tcgfBrak = 0o2434
    public static let tcgiBrak = 0o2435
    public static let rapfg = 0o2436
    public static let vapfg = 0o2444
    public static let aapfg = 0o2452
    public static let vapfgStar = 0o2460
    public static let aapfgStar = 0o2462
    public static let japfgStar = 0o2464
    public static let gainAppr = 0o2466
    public static let tcgfAppr = 0o2470
    public static let tcgiAppr = 0o2471
    public static let vign = 0o2472
    public static let rignx = 0o2474
    public static let rignz = 0o2476
    public static let kignx = 0o2500
    public static let kigny = 0o2502
    public static let kignv = 0o2504
    public static let lowcrit = 0o2506
    public static let highcrit = 0o2507
    public static let v2fg = 0o2510
    public static let tauvert = 0o2516
    public static let zoomtime = 0o3422
    public static let tendbrak = 0o3423
    public static let tendappr = 0o3424
    public static let delttfap = 0o3425
    public static let leadtime = 0o3426
}

/// Flag decimal indices from Luminary 099 `FLAGWORD_ASSIGNMENTS.agc`.
public enum Luminary099Flag {
    public static let moonflag = 3
    public static let lunaflag = 48
    public static let lmoonflg = 124

    public static func ecadr(decimalIndex: Int) -> Int {
        Luminary099Erasable.state + decimalIndex / 15
    }

    public static func bit(decimalIndex: Int) -> Int {
        15 - (decimalIndex % 15)
    }
}

/// GSOP / Luminary scales for lunar-SOI state vectors.
public enum Luminary099NavScale {
    /// Moon equatorial radius, Luminary `504RM 2DEC 1738090 B-29`.
    public static let moonRadiusMeters = 1_738_090.0
    /// Lunar-SOI position: meters B27.
    public static let positionScale = 27
    /// Lunar-SOI velocity: meters/centisecond B5.
    public static let velocityScale = 5
    /// MASS / LEMMASS: kilograms B16.
    public static let massScale = 16
    /// REFSMMAT direction cosines stored as half-units (1.0 → 0.5).
    public static let refsmmatHalfUnit = 0.5
}

/// Builds a Luminary-loadable nav state from LMCore vehicle kinematics.
///
/// RLS is the NASA Luminary 99 moon-fixed landing site. The tabletop vehicle
/// is attached in a modeled local-vertical at that site: +Z along RLS,
/// +Y selenographic east (modeled downrange), +X north. Identity REFSMMAT
/// keeps SM aligned with that modeled frame. PDI still starts over the site
/// rather than ~260 nmi uprange. RN/VN stay moon-fixed; IGNALG’s `RP-TO-R`
/// rotates RLS into Basic Reference.
public enum LMAGCNavState {
    public static func moonCenteredPositionMeters(from vehicle: LMVehicleStateSnapshot) -> LMVector3D {
        let (north, east, up) = moonFixedSiteBasis()
        return Luminary99CoordinatePadLoad.landingSiteMeters
            + north * vehicle.positionMeters.x
            + east * vehicle.positionMeters.y
            + up * vehicle.positionMeters.z
    }

    public static func landingSiteMeters() -> LMVector3D {
        Luminary99CoordinatePadLoad.landingSiteMeters
    }

    public static func velocityMetersPerCentisecond(from vehicle: LMVehicleStateSnapshot) -> LMVector3D {
        let (north, east, up) = moonFixedSiteBasis()
        let velocity = vehicle.velocityMetersPerSecond
        return (north * velocity.x + east * velocity.y + up * velocity.z) / 100.0
    }

    /// Selenographic east is polar × radial. Tranquility is near the equator,
    /// so that cross product is well defined.
    public static func moonFixedSiteBasis() -> (north: LMVector3D, east: LMVector3D, up: LMVector3D) {
        let up = Luminary99CoordinatePadLoad.landingSiteMeters.normalized()
        let east = LMVector3D(z: 1).cross(up).normalized()
        let north = up.cross(east).normalized()
        return (north, east, up)
    }

    public static func erasableWords(
        vehicle: LMVehicleStateSnapshot,
        time2: Int,
        time1: Int
    ) -> [AGCErasableWord] {
        var words: [AGCErasableWord] = []
        words.append(contentsOf: vectorWords(ecadr: Luminary099Erasable.rn, meters: moonCenteredPositionMeters(from: vehicle)))
        words.append(contentsOf: vectorWords(ecadr: Luminary099Erasable.vn, metersPerCentisecond: velocityMetersPerCentisecond(from: vehicle)))
        words.append(AGCErasableWord(ecadr: Luminary099Erasable.pipTime, value: time2))
        words.append(AGCErasableWord(ecadr: Luminary099Erasable.pipTime + 1, value: time1))
        words.append(contentsOf: vectorWords(ecadr: Luminary099Erasable.rRectLEM, meters: moonCenteredPositionMeters(from: vehicle)))
        words.append(contentsOf: vectorWords(ecadr: Luminary099Erasable.vRectLEM, metersPerCentisecond: velocityMetersPerCentisecond(from: vehicle)))
        words.append(AGCErasableWord(ecadr: Luminary099Erasable.tetLEM, value: time2))
        words.append(AGCErasableWord(ecadr: Luminary099Erasable.tetLEM + 1, value: time1))
        words.append(contentsOf: identityRefsmmatWords())
        words.append(contentsOf: vectorWords(ecadr: Luminary099Erasable.rls, meters: landingSiteMeters()))
        if let mass = vehicle.massKilograms {
            let massDP = AGCDoublePrecision.encode(value: mass, scale: Luminary099NavScale.massScale)
            words.append(AGCErasableWord(ecadr: Luminary099Erasable.mass, value: massDP.high))
            words.append(AGCErasableWord(ecadr: Luminary099Erasable.mass + 1, value: massDP.low))
            words.append(AGCErasableWord(
                ecadr: Luminary099Erasable.lemMass,
                value: AGCSinglePrecision.encode(value: mass, scale: Luminary099NavScale.massScale).word
            ))
        }
        words.append(AGCErasableWord(ecadr: Luminary099Erasable.csmMass, value: 0))
        return words
    }

    public static func lunarSphereFlags() -> [(ecadr: Int, bit: Int)] {
        [
            Luminary099Flag.moonflag,
            Luminary099Flag.lunaflag,
            Luminary099Flag.lmoonflg
        ].map { index in
            (Luminary099Flag.ecadr(decimalIndex: index), Luminary099Flag.bit(decimalIndex: index))
        }
    }

    private static func vectorWords(ecadr: Int, meters: LMVector3D) -> [AGCErasableWord] {
        vectorWords(ecadr: ecadr, components: [meters.x, meters.y, meters.z], scale: Luminary099NavScale.positionScale)
    }

    private static func vectorWords(ecadr: Int, metersPerCentisecond: LMVector3D) -> [AGCErasableWord] {
        vectorWords(
            ecadr: ecadr,
            components: [metersPerCentisecond.x, metersPerCentisecond.y, metersPerCentisecond.z],
            scale: Luminary099NavScale.velocityScale
        )
    }

    private static func vectorWords(ecadr: Int, components: [Double], scale: Int) -> [AGCErasableWord] {
        var words: [AGCErasableWord] = []
        for (index, component) in components.enumerated() {
            let dp = AGCDoublePrecision.encode(value: component, scale: scale)
            let address = ecadr + index * 2
            words.append(AGCErasableWord(ecadr: address, value: dp.high))
            words.append(AGCErasableWord(ecadr: address + 1, value: dp.low))
        }
        return words
    }

    private static func identityRefsmmatWords() -> [AGCErasableWord] {
        let half = AGCDoublePrecision.encode(value: Luminary099NavScale.refsmmatHalfUnit, scale: 0)
        let zero = AGCDoublePrecision.encode(value: 0, scale: 0)
        var words: [AGCErasableWord] = []
        for row in 0..<3 {
            for column in 0..<3 {
                let dp = row == column ? half : zero
                let address = Luminary099Erasable.refsmmat + (row * 3 + column) * 2
                words.append(AGCErasableWord(ecadr: address, value: dp.high))
                words.append(AGCErasableWord(ecadr: address + 1, value: dp.low))
            }
        }
        return words
    }
}
