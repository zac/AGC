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
    /// FLAGWRD5. SNUFFBIT (bit 13) inhibits Q,R RCS during a DPS burn (V65).
    public static let flagwrd5 = 0o101
    /// FLAGWRD7. IDLEFLAG (DVMON inhibit) lives here.
    public static let flagwrd7 = 0o103
    /// FLAGWRD13 / DAPBOOLS. USEQRJTS (bit 14) chooses GTS vs Q,R RCS.
    public static let dapbools = 0o111
    /// Unswitched IMODES30. Bit 9 set means IMU operating.
    public static let imodes30 = 0o1302
    /// Unswitched IMODES33. Bit 6 set disables DAP AUTO/HOLD (IMUZERO / coarse).
    public static let imodes33 = 0o1303
    /// E6,1421. DAP body rates at PI/4 rad/s. OMEGAQ = OMEGAP+1.
    public static let omegap = 0o3021
    public static let omegaq = 0o3022
    /// E6,1501. NEGUQ; ALLOWGTS = NEGUQ+1.
    public static let neguq = 0o3101
    public static let allowGts = 0o3102
    /// E6,1507. Q-jerk magnitude at PI/2^7 rad/s³. QACCDOT = ACCDOTQ+1 (signed).
    public static let accDotQ = 0o3107
    public static let qAccDot = 0o3110
    /// E6,1527. Descent engine pivot-to-CG at 8 ft.
    public static let pivotToCG = 0o3127
    /// E6,1530. 1JACC; 1JACCQ = 1JACC+1 at PI/4 rad/s².
    public static let oneJetAcc = 0o3130
    public static let oneJetAccQ = 0o3131
    /// E6,1537. Q-axis offset acceleration, DP at PI/2 rad/s².
    public static let aosQ = 0o3137
    /// E6,1635. FINDCDUW / KALCMANU desired CDUs (PI radians, two's complement).
    public static let cduxd = 0o3235
    /// E6,1643. FINDCDUW desired body rates at PI/4 rad/s. OMEGAQD = OMEGAPD+1.
    public static let omegaPD = 0o3243
    public static let omegaQD = 0o3244
    /// E6,1653. FINDCDUW thrust command (SM), half-unit after NORMUNIT.
    public static let unfc2 = 0o3253
    /// E6,1661. FINDCDUW window command (SM).
    public static let unwc2 = 0o3261
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
    /// E5,1520. LR altitude reasonableness (DELQFIX), meters B24.
    public static let delqfix = 0o2520
    public static let lralpha = 0o2522
    public static let lrbeta1 = 0o2523
    public static let lralpha2 = 0o2524
    public static let lrbeta2 = 0o2525
    public static let lrvmax = 0o2526
    public static let lrvf = 0o2527
    public static let lrwvz = 0o2530
    public static let lrwvy = 0o2531
    public static let lrwvx = 0o2532
    public static let lrwvfz = 0o2533
    public static let lrwvfy = 0o2534
    public static let lrwvfx = 0o2535
    public static let lrwvff = 0o2536
    /// E5,1537. Apollo 11 P66 rate-of-descent step, 1 ft/s (B-7).
    public static let rodScale = 0o2537
    /// E5,1540. Apollo 11 P66 ROD response time, 1.5 seconds (B9 DP).
    public static let tauRod = 0o2540
    /// E5,1542. Apollo 11 P66 DPS lag divided by TAUROD (B0 DP).
    public static let lagOverTau = 0o2542
    /// E5,1544. Apollo 11 minimum P66 thrust, 980 lbf (B12 DP).
    public static let minForce = 0o2544
    /// E5,1546. Apollo 11 maximum P66 thrust, 6300 lbf (B12 DP).
    public static let maxForce = 0o2546
    /// E7,1420. SERVICER bypasses every altitude update when H > LRHMAX.
    public static let lrhmax = 0o3420
    public static let lrwh = 0o3421
    public static let zoomtime = 0o3422
    public static let tendbrak = 0o3423
    public static let tendappr = 0o3424
    public static let delttfap = 0o3425
    public static let leadtime = 0o3426
    /// E7,1427. HIGATCHK: TTF/8 + RPCRTIME; NASA 62 s, same octal as TENDBRAK.
    public static let rpcrtime = 0o3427
    /// E7,1430. HIGATCHK angle gate. NASA −1 (77777) trips POS2 at P64 start.
    public static let rpcrtqsw = 0o3430
    /// E7,1560 PIPTIME1. IGNALG copies TAT here before DDUM.
    public static let pipTime1 = 0o3560
    /// E7,1626 VGU.
    public static let vgu = 0o3626
    /// E7,1634 LAND.
    public static let land = 0o3634
    /// E7,1642 TTF/8.
    public static let ttf8 = 0o3642
    /// E7,1644. P65/P66 desired vertical rate, updated by RODCOMP.
    public static let vdgVert = 0o3644
    /// E7,1746. ROD switch accumulator consumed by P66 RODCOMP.
    public static let rodCount = 0o3746
    /// Unswitched FLAGWRD11 / LRSTAT. READLR bit 6, NOLRREAD bit 10, LRBYPASS bit 15.
    public static let flagwrd11 = 0o107
    /// Unswitched FLAGWRD12 / RADMODES. LRPOSBIT is bit 6, ALTSCBIT is bit 9.
    public static let flagwrd12 = 0o110
    /// Unswitched PHASE2. READACCS skips R10/LRHTASK while this is nonzero.
    public static let phase2 = 0o755
    /// E7,1534. SERVICER HCALC, meters B24.
    public static let hcalc = 0o3534
    /// E7,1654. LRH HMEAS, DP 1.079 ft/bit. Below ~17 kft the count lives in +1.
    public static let hmeas = 0o3654
    /// E7,1674. Consecutive-good altitude samples remaining.
    public static let stilbadh = 0o3674
    /// E7,1441 TIG.
    public static let tig = 0o3441
    /// E7,1520. SERVICER `R`. MUNRVG keeps this in SM at B24 while MUNFLAG is set.
    public static let servicerR = 0o3520
    /// E7,1526. SERVICER `V`. MUNRVG keeps this in SM at B7 m/cs.
    public static let servicerV = 0o3526
    /// E7,1646 NIGNLOOP.
    public static let nignLoop = 0o3646
    /// Unswitched 01351. IGNALG = −1, BRAKQUAD = 0, APPRQUAD = 1, VERTICAL = 2.
    public static let wchPhase = 0o1351
    /// E5,1636 RGU.
    public static let rgu = 0o2636
    /// E3,1452. PIPA bias / scale-factor pair, then Y/Z. Perfect IMU is 0.
    public static let pbiasx = 0o1452
    public static let pipascfx = 0o1453
    public static let pbiasz = 0o1456
    public static let pipascfz = 0o1457
    /// Unswitched 01075. 1/PIPA Δt. Leave 0 with GCOMPSW negative.
    public static let pipadt = 0o1075
    /// E3,1477. CCS negative skips 1/PIPA / NBDONLY. Do not use -0 (077777);
    /// that takes the 1/PIPA path.
    public static let gcompsw = 0o1477
}

/// Flag decimal indices from Luminary 099 `FLAGWORD_ASSIGNMENTS.agc`.
public enum Luminary099Flag {
    public static let moonflag = 3
    public static let lunaflag = 48
    public static let refsmflg = 47
    /// FLAGWRD2 bit 11. Set by DVMON when ABDELV exceeds DVTHRUSH.
    public static let steersw = 34
    /// FLAGWRD5 bit 13. V65 SNUFFBIT: inhibit Q,R RCS during a DPS burn so GTS
    /// owns pitch/roll. Without it, RCS and GTS stack after ZOOM and tumble.
    public static let snuffer = 77
    public static let lmoonflg = 124
    /// FLAGWRD11 bit 8. V57 sets this to permit LR state-vector updates.
    public static let landingRadarUpdates = 172

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
    /// `MUM` in SI, `(m/cs)² → (m/s)²`.
    public static var lunarMuMetersCubedPerSecondSquared: Double {
        lunarMuMetersCubedPerCentisecondSquared * 10_000.0
    }
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
/// RN/VN are the tabletop pre-ignition lead state at live GET (same place as
/// the vehicle). The state is coasted backward from the sourced Apollo 11 PDI
/// condition so Average-G and TTF see the real range, not the RIGN epoch
/// `lookahead` seconds downstream. Tagging RIGN at `TDEC1` made `LEMPREC`
/// dt = 0 and IGNALG converge, but then TENDBRAK fired ~4 nmi out still
/// hypersonic. `TIG = TDEC1 − ZOOMTIME` stays far enough ahead that MIDTOAV1
/// and BURNBABY LONGCALL keep a positive dt. VN is inertial so
/// `|CG(V − WM×R)| = VIGN` with GUIDINIT’s half-unit `WM`. The tabletop
/// vehicle is that same runtime-lead state in site ENU. Altitude and H-dot are
/// spherical (`|R| − |RLS|`, `V · UNIT(R)`).
public enum LMAGCNavState {
    /// Body specific force in frozen SM for MUNRVG. ENU coincides with SM only
    /// at the REFSMMAT epoch; later GET must go through RP-TO-R and REFSMMAT.
    /// `site` is the origin of the attitude's local axes; nil preserves Apollo 11.
    /// Diagnostic / comparison helper — not the simulation PIPA hot path.
    public static func specificForceSM(
        body: LMVector3D,
        attitude: LMQuaternion,
        refsmmat: LMMatrix3,
        timeCentiseconds: Double,
        site: LMLunarLandingSite? = nil
    ) -> LMVector3D {
        let enu = attitude.rotated(body)
        let (north, east, up) = moonFixedSiteBasis(site: site)
        let moon = north * enu.x + east * enu.y + up * enu.z
        let basic = LuminaryMoonOrientation.moonMatrix(timeCentiseconds: timeCentiseconds)
            .timesTranspose(moon)
        return refsmmat.times(basic)
    }

    /// Frozen-REFSMMAT position (m) and inertial velocity (m/s) of the plant.
    /// Same conversion Average-G uses: live `RP-TO-R` / `V + ω×RP`, then `MXV REFSMMAT`.
    public static func stableMemberKinematics(
        from vehicle: LMVehicleStateSnapshot,
        refsmmat: LMMatrix3,
        timeCentiseconds: Double
    ) -> (positionMeters: LMVector3D, velocityMetersPerSecond: LMVector3D) {
        let moon = moonCenteredPositionMeters(from: vehicle)
        let position = refsmmat.times(
            LuminaryMoonOrientation.rpToR(moon, timeCentiseconds: timeCentiseconds)
        )
        let velocity = refsmmat.times(
            LuminaryMoonOrientation.moonRelativeVelocityToReference(
                velocityMetersPerCentisecond: velocityMetersPerCentisecond(from: vehicle),
                moonFixedPosition: moon,
                timeCentiseconds: timeCentiseconds
            )
        ) * 100.0
        return (position, velocity)
    }

    /// PIPA specific force: plant inertial ΔV/Δt minus two-body gravity in SM.
    /// Do not feed this to the PIPA counters: gravity residuals leak into PIPAX
    /// and FINDCDUW leaves braking.
    public static func nongravitationalAccelerationSM(
        previousVelocityMetersPerSecond: LMVector3D,
        positionMeters: LMVector3D,
        velocityMetersPerSecond: LMVector3D,
        deltaTime: Double
    ) -> LMVector3D {
        guard deltaTime > 0 else { return .zero }
        let radiusSquared = positionMeters.dot(positionMeters)
        let gravity = radiusSquared > 0
            ? positionMeters * (
                -Luminary099NavScale.lunarMuMetersCubedPerSecondSquared
                    / (radiusSquared * sqrt(radiusSquared))
            )
            : .zero
        return (velocityMetersPerSecond - previousVelocityMetersPerSecond) * (1.0 / deltaTime)
            - gravity
    }

    public static func moonCenteredPositionMeters(from vehicle: LMVehicleStateSnapshot) -> LMVector3D {
        let (north, east, up) = moonFixedSiteBasis(site: vehicle.landingSite)
        return landingSiteMeters(site: vehicle.landingSite)
            + north * vehicle.positionMeters.x
            + east * vehicle.positionMeters.y
            + up * vehicle.positionMeters.z
    }

    public static func landingSiteMeters(site: LMLunarLandingSite? = nil) -> LMVector3D {
        site?.positionMeters ?? Luminary99CoordinatePadLoad.landingSiteMeters
    }

    public static func velocityMetersPerCentisecond(from vehicle: LMVehicleStateSnapshot) -> LMVector3D {
        let (north, east, up) = moonFixedSiteBasis(site: vehicle.landingSite)
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
    public static func refsmmat(timeCentiseconds: Double, site: LMLunarLandingSite? = nil) -> LMMatrix3 {
        let xsm = LuminaryMoonOrientation.rpToR(
            landingSiteMeters(site: site),
            timeCentiseconds: timeCentiseconds
        ).normalized()
        let eastBasic = LuminaryMoonOrientation.moonMatrix(timeCentiseconds: timeCentiseconds)
            .timesTranspose(moonFixedSiteBasis(site: site).east)
        let zsm = (eastBasic - xsm * eastBasic.dot(xsm)).normalized()
        let ysm = zsm.cross(xsm).normalized()
        return LMMatrix3(r0: xsm, r1: ysm, r2: zsm)
    }

    /// IGNALG `LAND`: `RP-TO-R(RLS, TLAND)` with `TLAND` from live GET plus GUIDDURN and the IGNALG look-ahead.
    public static func landBasic(pipTimeCentiseconds: Double, site: LMLunarLandingSite? = nil) -> LMVector3D {
        LuminaryMoonOrientation.rpToR(
            landingSiteMeters(site: site),
            timeCentiseconds: Luminary99LandingPadLoad.tlandCentiseconds(fromClock: pipTimeCentiseconds)
        )
    }

    /// RIGN-epoch position in Basic: `LAND + (RIGNX, 0, RIGNZ)` in landing SM.
    public static func rignPositionMeters(pipTimeCentiseconds: Double, site: LMLunarLandingSite? = nil) -> LMVector3D {
        let matrix = refsmmat(timeCentiseconds: pipTimeCentiseconds, site: site)
        let rsm = matrix.times(landBasic(pipTimeCentiseconds: pipTimeCentiseconds, site: site)) + LMVector3D(
            x: Luminary99LandingPadLoad.rignXMeters,
            y: 0,
            z: Luminary99LandingPadLoad.rignZMeters
        )
        return matrix.timesTranspose(rsm)
    }

    /// Inertial velocity at the RIGN epoch so IGNALG `|VGU| = VIGN`.
    public static func rignVelocityMetersPerCentisecond(pipTimeCentiseconds: Double, site: LMLunarLandingSite? = nil) -> LMVector3D {
        let matrix = refsmmat(timeCentiseconds: pipTimeCentiseconds, site: site)
        let rsm = matrix.times(rignPositionMeters(pipTimeCentiseconds: pipTimeCentiseconds, site: site))
        return matrix.timesTranspose(inertialVelocitySM(rsm: rsm, timeCentiseconds: pipTimeCentiseconds, site: site))
    }

    /// State at the start of the runtime lead, backward from the sourced PDI
    /// condition. PDI itself is ZOOMTIME before the RIGN end-of-zoom target.
    public static func pdiPositionMeters(pipTimeCentiseconds: Double, site: LMLunarLandingSite? = nil) -> LMVector3D {
        pdiState(pipTimeCentiseconds: pipTimeCentiseconds, site: site).position
    }

    /// Inertial velocity matching `pdiPositionMeters` at the runtime lead.
    public static func pdiVelocityMetersPerCentisecond(pipTimeCentiseconds: Double, site: LMLunarLandingSite? = nil) -> LMVector3D {
        pdiState(pipTimeCentiseconds: pipTimeCentiseconds, site: site).velocity
    }

    /// Tabletop runtime lead: moon-fixed Kepler state before the sourced PDI
    /// condition, in site north/east/up. RN/VN in `erasableWords` are that
    /// same Basic-Reference state at live GET.
    public static func vehicleState(
        timeCentiseconds: Double,
        attitude: LMQuaternion,
        massKilograms: Double,
        site: LMLunarLandingSite? = nil
    ) -> LMVehicleStateSnapshot {
        let rMoon = LuminaryMoonOrientation.rToRP(
            pdiPositionMeters(pipTimeCentiseconds: timeCentiseconds, site: site),
            timeCentiseconds: timeCentiseconds
        )
        let vMoon = LuminaryMoonOrientation.referenceVelocityToMoonRelative(
            inertialMetersPerCentisecond: pdiVelocityMetersPerCentisecond(
                pipTimeCentiseconds: timeCentiseconds, site: site
            ),
            moonFixedPosition: rMoon,
            timeCentiseconds: timeCentiseconds
        ) * 100.0
        let (north, east, up) = moonFixedSiteBasis(site: site)
        let delta = rMoon - landingSiteMeters(site: site)
        return LMVehicleStateSnapshot(
            positionMeters: LMVector3D(
                x: delta.dot(north),
                y: delta.dot(east),
                z: delta.dot(up)
            ),
            velocityMetersPerSecond: LMVector3D(
                x: vMoon.dot(north),
                y: vMoon.dot(east),
                z: vMoon.dot(up)
            ),
            attitude: attitude,
            massKilograms: massKilograms, landingSite: site
        )
    }

    /// Selenographic east is polar × radial. Tranquility is near the equator,
    /// so that cross product is well defined.
    public static func moonFixedSiteBasis(site: LMLunarLandingSite? = nil) -> (north: LMVector3D, east: LMVector3D, up: LMVector3D) {
        if let site { return site.basis }
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
        let site = vehicle.landingSite
        let timeCentiseconds = AGCDoublePrecision(high: time2, low: time1).decoded(scale: 28)
        let tet = AGCDoublePrecision.encode(value: timeCentiseconds, scale: 28)
        // Preserve the historical Apollo overlay byte-for-byte. A custom
        // scenario encodes the actual plant state: the sourced lunar rotation
        // matrix is quantized, so rToRP/rpToR are not exact numerical inverses.
        // Recomputing PDI here displaced the encoded custom RN by up to 0.6 m.
        let position = site == nil
            ? pdiPositionMeters(pipTimeCentiseconds: timeCentiseconds)
            : basicReferencePositionMeters(from: vehicle, timeCentiseconds: timeCentiseconds)
        let velocity = site == nil
            ? pdiVelocityMetersPerCentisecond(pipTimeCentiseconds: timeCentiseconds)
            : basicReferenceVelocityMetersPerCentisecond(from: vehicle, timeCentiseconds: timeCentiseconds)
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
        words.append(contentsOf: refsmmatWords(timeCentiseconds: timeCentiseconds, site: site))
        words.append(contentsOf: vectorWords(ecadr: Luminary099Erasable.rls, meters: landingSiteMeters(site: site)))
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
        words.append(contentsOf: cduWords(attitude: vehicle.attitude))
        words.append(contentsOf: perfectIMUCompensationWords())
        return words
    }

    /// Skip 1/PIPA and gyro NBD. The plant PIPAs have no scale-factor error or
    /// bias; running 1/PIPA with GCOMPSW=+0 still DAS’s DELV against whatever
    /// is in E3 after idle boot.
    private static func perfectIMUCompensationWords() -> [AGCErasableWord] {
        var words: [AGCErasableWord] = []
        for ecadr in Luminary099Erasable.pbiasx...Luminary099Erasable.gcompsw {
            words.append(AGCErasableWord(ecadr: ecadr, value: 0))
        }
        words.append(AGCErasableWord(ecadr: Luminary099Erasable.pipadt, value: 0))
        words.append(AGCErasableWord(ecadr: Luminary099Erasable.gcompsw, value: 0o77776))
        return words
    }

    /// Seed IMU CDUs and CDUD to the tabletop 95° PDI attitude. Catch-up pulses
    /// only run after the first sample, so leaving CDUX/Y/Z at 0 after boot
    /// makes DAP see a 95° IMU error that never closes. NASA P/Q/R are sim
    /// Z/X/Y, so the PDI rotation about sim X is CDUY, not CDUX.
    private static func cduWords(attitude: LMQuaternion) -> [AGCErasableWord] {
        let counts = LMIMUGimbalMap.cduCounts(from: attitude)
        return [
            AGCErasableWord(ecadr: Register.regCDUX.rawValue, value: counts.x),
            AGCErasableWord(ecadr: Register.regCDUY.rawValue, value: counts.y),
            AGCErasableWord(ecadr: Register.regCDUZ.rawValue, value: counts.z),
            AGCErasableWord(ecadr: Luminary099Erasable.cduxd, value: counts.x),
            AGCErasableWord(ecadr: Luminary099Erasable.cduxd + 1, value: counts.y),
            AGCErasableWord(ecadr: Luminary099Erasable.cduxd + 2, value: counts.z)
        ]
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

    /// Moon-relative VIGN in SM (along `UNIT(R)` plus horizontal toward the site),
    /// plus GUIDINIT `WM × R` (`UNITZ` and `REFSMMAT` are both half-units).
    private static func inertialVelocitySM(
        rsm: LMVector3D,
        timeCentiseconds: Double,
        moonRelativeSpeedMetersPerCentisecond: Double = Luminary99LandingPadLoad.vignMetersPerCentisecond,
        radialRateMetersPerCentisecond: Double = Luminary99LandingPadLoad.pdiAltitudeRateMetersPerCentisecond,
        site: LMLunarLandingSite? = nil
    ) -> LMVector3D {
        let rdot = radialRateMetersPerCentisecond
        let radial = rsm.normalized() * rdot
        var horizontal = rsm.cross(LMVector3D(y: 1)).normalized()
        if horizontal.z < 0 {
            horizontal = horizontal * -1.0
        }
        let horizontalSpeed = sqrt(max(
            0,
            moonRelativeSpeedMetersPerCentisecond * moonRelativeSpeedMetersPerCentisecond - rdot * rdot
        ))
        let moonRelative = radial + horizontal * horizontalSpeed
        let polarSM = refsmmat(timeCentiseconds: timeCentiseconds, site: site).times(
            LuminaryMoonOrientation.rpToR(LMVector3D(z: 1), timeCentiseconds: timeCentiseconds)
        )
        let wm = polarSM * (
            LuminaryMoonOrientation.moonRateRadiansPerCentisecond
                * Luminary099NavScale.guidinitMoonRateHalfUnits
        )
        return moonRelative + wm.cross(rsm)
    }

    private static func pdiState(pipTimeCentiseconds: Double, site: LMLunarLandingSite? = nil) -> (position: LMVector3D, velocity: LMVector3D) {
        let provisionalPDI = keplerCoast(
            position: rignPositionMeters(pipTimeCentiseconds: pipTimeCentiseconds, site: site),
            velocity: rignVelocityMetersPerCentisecond(pipTimeCentiseconds: pipTimeCentiseconds, site: site),
            deltaCentiseconds: -Luminary99LandingPadLoad.zoomTimeCentiseconds,
            steps: max(1, Int((Luminary99LandingPadLoad.zoomTimeCentiseconds / 100.0).rounded()))
        )
        let pdiRadius = landingSiteMeters(site: site).magnitude + Luminary99LandingPadLoad.pdiAltitudeMeters
        let pdiPosition = provisionalPDI.position.normalized() * pdiRadius
        let refsmmat = refsmmat(timeCentiseconds: pipTimeCentiseconds, site: site)
        let pdiVelocitySM = inertialVelocitySM(
            rsm: refsmmat.times(pdiPosition),
            timeCentiseconds: pipTimeCentiseconds,
            moonRelativeSpeedMetersPerCentisecond: Luminary99LandingPadLoad.pdiSpeedMetersPerCentisecond,
            radialRateMetersPerCentisecond: Luminary99LandingPadLoad.pdiAltitudeRateMetersPerCentisecond, site: site
        )
        let pdiVelocity = refsmmat.timesTranspose(pdiVelocitySM)
        return keplerCoast(
            position: pdiPosition,
            velocity: pdiVelocity,
            deltaCentiseconds: -Luminary99LandingPadLoad.preIgnitionCentiseconds,
            steps: max(1, Int((Luminary99LandingPadLoad.preIgnitionCentiseconds / 100.0).rounded()))
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

    private static func refsmmatWords(timeCentiseconds: Double, site: LMLunarLandingSite? = nil) -> [AGCErasableWord] {
        let matrix = refsmmat(timeCentiseconds: timeCentiseconds, site: site)
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
