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
    /// MASS+2. SERVICER `|DELV|` at 2(-14) cm/s; DVMON compares this to DVTHRUSH.
    public static let abdelv = 0o1246
    /// PGUIDE+2. P63 loads DPSTHRSH (36 cm/s, ~600 lbf).
    public static let dvthrush = 0o1251
    /// DVTHRUSH+1. P63IGN writes display 2CADR; P63ZOOM writes LUNLAND.
    public static let avegExit = 0o1252
    /// FLAGWRD2. STEERSW (bit 11) is set when DVMON sees enough thrust to steer.
    public static let flagwrd2 = 0o76
    /// Unswitched DELV vector (PIPASR).
    public static let delv = 0o324
    /// FLAGWRD7. IDLEFLAG (DVMON inhibit) lives here.
    public static let flagwrd7 = 0o103
    /// E7,1515. DVMON low-thrust pass counter.
    public static let dvcntr = 0o3515
    public static let lemMass = 0o1331
    public static let csmMass = 0o1332
    /// E3,1554. BURNBABY `CSMPREC` when MUNFLAG is set.
    public static let rRectCSM = 0o1554
    public static let vRectCSM = 0o1562
    public static let tetCSM = 0o1570
    public static let rCVCSM = 0o1606
    public static let vCVCSM = 0o1614
    public static let rRectLEM = 0o1626
    public static let vRectLEM = 0o1634
    public static let tetLEM = 0o1642
    /// Conic state. LEMPREC/PTOALEM copies this; equals RRECT/VRECT when TCLEM = 0.
    public static let rCVLEM = 0o1660
    public static let vCVLEM = 0o1666
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
    /// E7,1560 PIPTIME1. IGNALG copies TAT here before DDUM.
    public static let pipTime1 = 0o3560
    /// E7,1626 VGU.
    public static let vgu = 0o3626
    /// E7,1634 LAND.
    public static let land = 0o3634
    /// E7,1642 TTF/8.
    public static let ttf8 = 0o3642
    /// E7,1441 TIG.
    public static let tig = 0o3441
    /// E7,1646 NIGNLOOP.
    public static let nignLoop = 0o3646
    /// Unswitched 01351. IGNALG = −1, BRAKQUAD = 0, APPRQUAD = 1, VERTICAL = 2.
    public static let wchPhase = 0o1351
    /// E5,1636 RGU.
    public static let rgu = 0o2636
}

/// Flag decimal indices from Luminary 099 `FLAGWORD_ASSIGNMENTS.agc`.
public enum Luminary099Flag {
    public static let moonflag = 3
    public static let lunaflag = 48
    public static let refsmflg = 47
    /// FLAGWRD2 bit 11. Set by DVMON when ABDELV exceeds DVTHRUSH.
    public static let steersw = 34
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
    /// Luminary `MUM 2DEC* 4.9027780 E8 B-30*`, m³/cs².
    public static let lunarMuMetersCubedPerCentisecondSquared = 4.9027780e8
    /// GUIDINIT: `UNITZ` and `REFSMMAT` are both half-units, so `WM = 0.25 ω polar`.
    public static let guidinitMoonRateHalfUnits = refsmmatHalfUnit * refsmmatHalfUnit
}

/// Builds a Luminary-loadable nav state from LMCore vehicle kinematics.
///
/// RLS is the NASA Luminary 99 moon-fixed landing site. REFSMMAT is Luminary
/// `P52LS` / `LSORIENT` with modeled east as the approach azimuth (no CSM
/// state vector): X along RLS, Z horizontal east, Y = Z × X.
///
/// IGNALG’s first `TDEC1` is `GET + ZOOMTIME` plus the MIDTOAV TIG lead.
/// RIGN is the G-frame state at that epoch (`LAND + (RIGNX, 0, RIGNZ)` in SM).
/// RN/VN are that RIGN state tagged at `TDEC1` so `LEMPREC` has dt = 0 and
/// `|DDUM|` can fall under 8 cs without a tiny `INTEGRVS` (that WAITLIST-aborts
/// 01204). `TIG = TDEC1 − ZOOMTIME` is then far enough ahead that MIDTOAV1’s
/// `TIG − D29.9SEC` still exceeds `GET + TIMEDELT` after IGNALG/R60 (01703 if
/// not) and BURNBABY’s TIG-35 `LONGCALL` has a positive dt. VN is inertial so
/// `|CG(V − WM×R)| = VIGN` with GUIDINIT’s half-unit `WM`. The tabletop vehicle
/// is still that TIG-minus-lead state (two-body coast with Luminary `MUM`).
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

    public static func basicReferencePositionMeters(
        from vehicle: LMVehicleStateSnapshot,
        timeCentiseconds: Double
    ) -> LMVector3D {
        LuminaryMoonOrientation.rpToR(
            moonCenteredPositionMeters(from: vehicle),
            timeCentiseconds: timeCentiseconds
        )
    }

    public static func basicReferenceVelocityMetersPerCentisecond(
        from vehicle: LMVehicleStateSnapshot,
        timeCentiseconds: Double
    ) -> LMVector3D {
        LuminaryMoonOrientation.moonRelativeVelocityToReference(
            velocityMetersPerCentisecond: velocityMetersPerCentisecond(from: vehicle),
            moonFixedPosition: moonCenteredPositionMeters(from: vehicle),
            timeCentiseconds: timeCentiseconds
        )
    }

    /// Rows are Basic-Reference components of the landing-site SM axes.
    ///
    /// `XSM = UNIT(RLS)`, `ZSM` = horizontal modeled east, `YSM = ZSM × XSM`.
    /// Luminary `MXV REFSMMAT` then takes Basic Reference to SM.
    public static func refsmmat(timeCentiseconds: Double) -> LMMatrix3 {
        let xsm = LuminaryMoonOrientation.rpToR(
            landingSiteMeters(),
            timeCentiseconds: timeCentiseconds
        ).normalized()
        let eastBasic = LuminaryMoonOrientation.moonMatrix(timeCentiseconds: timeCentiseconds)
            .timesTranspose(moonFixedSiteBasis().east)
        let zsm = (eastBasic - xsm * eastBasic.dot(xsm)).normalized()
        let ysm = zsm.cross(xsm).normalized()
        return LMMatrix3(r0: xsm, r1: ysm, r2: zsm)
    }

    /// IGNALG `LAND`: `RP-TO-R(RLS, TLAND)` with `TLAND` from live GET plus GUIDDURN and the IGNALG look-ahead.
    public static func landBasic(pipTimeCentiseconds: Double) -> LMVector3D {
        LuminaryMoonOrientation.rpToR(
            landingSiteMeters(),
            timeCentiseconds: Luminary99LandingPadLoad.tlandCentiseconds(fromClock: pipTimeCentiseconds)
        )
    }

    /// RIGN-epoch position in Basic: `LAND + (RIGNX, 0, RIGNZ)` in landing SM.
    public static func rignPositionMeters(pipTimeCentiseconds: Double) -> LMVector3D {
        let matrix = refsmmat(timeCentiseconds: pipTimeCentiseconds)
        let rsm = matrix.times(landBasic(pipTimeCentiseconds: pipTimeCentiseconds)) + LMVector3D(
            x: Luminary99LandingPadLoad.rignXMeters,
            y: 0,
            z: Luminary99LandingPadLoad.rignZMeters
        )
        return matrix.timesTranspose(rsm)
    }

    /// Inertial velocity at the RIGN epoch so IGNALG `|VGU| = VIGN`.
    public static func rignVelocityMetersPerCentisecond(pipTimeCentiseconds: Double) -> LMVector3D {
        let matrix = refsmmat(timeCentiseconds: pipTimeCentiseconds)
        let rsm = matrix.times(rignPositionMeters(pipTimeCentiseconds: pipTimeCentiseconds))
        return matrix.timesTranspose(inertialVelocitySM(rsm: rsm, timeCentiseconds: pipTimeCentiseconds))
    }

    /// TIG/PDI position: two-body coast backward the IGNALG look-ahead from RIGN.
    public static func pdiPositionMeters(pipTimeCentiseconds: Double) -> LMVector3D {
        pdiState(pipTimeCentiseconds: pipTimeCentiseconds).position
    }

    /// TIG/PDI inertial velocity matching `pdiPositionMeters`.
    public static func pdiVelocityMetersPerCentisecond(pipTimeCentiseconds: Double) -> LMVector3D {
        pdiState(pipTimeCentiseconds: pipTimeCentiseconds).velocity
    }

    public static func vehicleState(
        timeCentiseconds: Double,
        attitude: LMQuaternion,
        massKilograms: Double
    ) -> LMVehicleStateSnapshot {
        let (north, east, up) = moonFixedSiteBasis()
        let rBasic = pdiPositionMeters(pipTimeCentiseconds: timeCentiseconds)
        let vBasic = pdiVelocityMetersPerCentisecond(pipTimeCentiseconds: timeCentiseconds)
        let rMoon = LuminaryMoonOrientation.rToRP(rBasic, timeCentiseconds: timeCentiseconds)
        let offset = rMoon - landingSiteMeters()
        let inertialMoon = LuminaryMoonOrientation.moonMatrix(timeCentiseconds: timeCentiseconds).times(vBasic)
        let moonRelative = inertialMoon
            - LMVector3D(z: LuminaryMoonOrientation.moonRateRadiansPerCentisecond).cross(rMoon)
        return LMVehicleStateSnapshot(
            positionMeters: LMVector3D(
                x: offset.dot(north),
                y: offset.dot(east),
                z: rMoon.magnitude - landingSiteMeters().magnitude
            ),
            velocityMetersPerSecond: LMVector3D(
                x: moonRelative.dot(north) * 100,
                y: moonRelative.dot(east) * 100,
                z: moonRelative.dot(up) * 100
            ),
            attitude: attitude,
            massKilograms: massKilograms
        )
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
        let timeCentiseconds = AGCDoublePrecision(high: time2, low: time1).decoded(scale: 28)
        let tetCentiseconds = timeCentiseconds + Luminary99LandingPadLoad.ignalgLookaheadCentiseconds
        let tet = AGCDoublePrecision.encode(value: tetCentiseconds, scale: 28)
        let position = rignPositionMeters(pipTimeCentiseconds: timeCentiseconds)
        let velocity = rignVelocityMetersPerCentisecond(pipTimeCentiseconds: timeCentiseconds)
        var words: [AGCErasableWord] = []
        words.append(contentsOf: vectorWords(ecadr: Luminary099Erasable.rn, meters: position))
        words.append(contentsOf: vectorWords(ecadr: Luminary099Erasable.vn, metersPerCentisecond: velocity))
        words.append(AGCErasableWord(ecadr: Luminary099Erasable.pipTime, value: tet.high))
        words.append(AGCErasableWord(ecadr: Luminary099Erasable.pipTime + 1, value: tet.low))
        words.append(contentsOf: vectorWords(ecadr: Luminary099Erasable.rRectLEM, meters: position))
        words.append(contentsOf: vectorWords(ecadr: Luminary099Erasable.vRectLEM, metersPerCentisecond: velocity))
        words.append(AGCErasableWord(ecadr: Luminary099Erasable.tetLEM, value: tet.high))
        words.append(AGCErasableWord(ecadr: Luminary099Erasable.tetLEM + 1, value: tet.low))
        words.append(contentsOf: vectorWords(ecadr: Luminary099Erasable.rCVLEM, meters: position))
        words.append(contentsOf: vectorWords(ecadr: Luminary099Erasable.vCVLEM, metersPerCentisecond: velocity))
        // P63 sets MUNFLAG; BURNBABY then CSMPREC’s this vector to TIG−29.9.
        // NASA landing overlay has no CSM pad, so the LEM lunar-SOI state is
        // reused (a zero CSM origin overflows 00430 / MIDTOAV 01703).
        words.append(contentsOf: vectorWords(ecadr: Luminary099Erasable.rRectCSM, meters: position))
        words.append(contentsOf: vectorWords(ecadr: Luminary099Erasable.vRectCSM, metersPerCentisecond: velocity))
        words.append(AGCErasableWord(ecadr: Luminary099Erasable.tetCSM, value: tet.high))
        words.append(AGCErasableWord(ecadr: Luminary099Erasable.tetCSM + 1, value: tet.low))
        words.append(contentsOf: vectorWords(ecadr: Luminary099Erasable.rCVCSM, meters: position))
        words.append(contentsOf: vectorWords(ecadr: Luminary099Erasable.vCVCSM, metersPerCentisecond: velocity))
        words.append(contentsOf: refsmmatWords(timeCentiseconds: timeCentiseconds))
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
            Luminary099Flag.refsmflg,
            Luminary099Flag.lmoonflg
        ].map { index in
            (Luminary099Flag.ecadr(decimalIndex: index), Luminary099Flag.bit(decimalIndex: index))
        }
    }

    /// Moon-relative VIGN in SM (local-vertical rate plus horizontal toward the site),
    /// plus GUIDINIT `WM × R` (`UNITZ` and `REFSMMAT` are both half-units).
    private static func inertialVelocitySM(rsm: LMVector3D, timeCentiseconds: Double) -> LMVector3D {
        let vign = Luminary99LandingPadLoad.vignMetersPerCentisecond
        let rdot = Luminary99LandingPadLoad.pdiAltitudeRateMetersPerCentisecond
        let radial = rsm.normalized() * rdot
        var horizontal = rsm.cross(LMVector3D(y: 1)).normalized()
        if horizontal.z < 0 {
            horizontal = horizontal * -1.0
        }
        let horizontalSpeed = sqrt(max(0, vign * vign - rdot * rdot))
        let moonRelative = radial + horizontal * horizontalSpeed
        let polarSM = refsmmat(timeCentiseconds: timeCentiseconds).times(
            LuminaryMoonOrientation.rpToR(LMVector3D(z: 1), timeCentiseconds: timeCentiseconds)
        )
        let wm = polarSM * (
            LuminaryMoonOrientation.moonRateRadiansPerCentisecond
                * Luminary099NavScale.guidinitMoonRateHalfUnits
        )
        return moonRelative + wm.cross(rsm)
    }

    private static func pdiState(pipTimeCentiseconds: Double) -> (position: LMVector3D, velocity: LMVector3D) {
        keplerCoast(
            position: rignPositionMeters(pipTimeCentiseconds: pipTimeCentiseconds),
            velocity: rignVelocityMetersPerCentisecond(pipTimeCentiseconds: pipTimeCentiseconds),
            deltaCentiseconds: -Luminary99LandingPadLoad.ignalgLookaheadCentiseconds,
            steps: max(1, Int((Luminary99LandingPadLoad.ignalgLookaheadCentiseconds / 100.0).rounded()))
        )
    }

    /// Two-body coast in Basic Reference using Luminary `MUM`.
    private static func keplerCoast(
        position: LMVector3D,
        velocity: LMVector3D,
        deltaCentiseconds: Double,
        steps: Int = 26
    ) -> (position: LMVector3D, velocity: LMVector3D) {
        let mu = Luminary099NavScale.lunarMuMetersCubedPerCentisecondSquared
        let step = deltaCentiseconds / Double(steps)
        var r = position
        var v = velocity
        for _ in 0..<steps {
            func accel(_ pos: LMVector3D) -> LMVector3D {
                let r2 = pos.dot(pos)
                let r3 = r2 * sqrt(r2)
                return pos * (-mu / r3)
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
        return (r, v)
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

    private static func refsmmatWords(timeCentiseconds: Double) -> [AGCErasableWord] {
        let matrix = refsmmat(timeCentiseconds: timeCentiseconds)
        var words: [AGCErasableWord] = []
        for row in 0..<3 {
            for column in 0..<3 {
                let cosine = matrix.entry(row: row, column: column)
                let dp = AGCDoublePrecision.encode(
                    value: cosine * Luminary099NavScale.refsmmatHalfUnit,
                    scale: 0
                )
                let address = Luminary099Erasable.refsmmat + (row * 3 + column) * 2
                words.append(AGCErasableWord(ecadr: address, value: dp.high))
                words.append(AGCErasableWord(ecadr: address + 1, value: dp.low))
            }
        }
        return words
    }
}
