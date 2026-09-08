# Arbitrary lunar landing-site frames

`LMLunarLandingSite` is an immutable Mean Earth / polar-axis latitude, longitude
and radial datum. A vehicle's optional `landingSite` follows it through PDI
initialization, spherical dynamics, navigation conversion, LR geometry and
recording/checkpoint serialization. Nil retains the original Apollo 11 NASA
pad load and old JSON compatibility.

`LMPoweredDescentScenario.lunarSite` retargets the modeled Apollo PDI conditions.
It is not a reconstruction of a mission at that location. It has a distinct
scenario ID and no Apollo P64/P65 checkpoint starts. Restoring a checkpoint with
a different site fails before mutating the AGC or vehicle.

Custom RN/VN pad words encode the actual initial plant state. Recomputing PDI
through the quantized lunar orientation matrix introduced a second round-trip
error. B27 double precision has 0.5 m steps, so the maximum three-dimensional
rounding error is sqrt(3) × 0.25 m. Tested RLS and RN maxima are 0.308361 m and
0.364937 m. Pole bases remain finite at both exact poles.

Validation on 2026-09-04:

- `/tmp/AGC-Lunar-Anchor-v6.log`: 86 tests across site, LR and scenario/dynamics
  suites pass in the working checkout, including its pre-existing gear work.
- `/tmp/AGC-Lunar-Anchor-Commit-Validation.log`: all five site tests pass in
  248.704 s from an isolated export of the staged tree. This excludes the
  pre-existing gear and pad-load changes. The custom 8.35°, 30.83° descent at
  radius 1,735,000 m progresses through P63/P64/P65 and reaches `softLanding`
  at simulation time 825.570374 s.

The full descent test uses spherical contact. It does not validate a rendered
terrain touchdown, a new cockpit location, actual spacecraft mission targeting,
or a physical Vision Pro experience. LM's rendered-contact integration has its
own acceptance record in `Docs/Stage2GlobalTerrainValidation.md`.

Replay validation on 2026-09-05:

- Interpolated replay samples retain their landing site. Previously these
  samples silently used Apollo 11, producing Moon-centered position errors
  of about 2,400 km in the polar regression. Samples from different site
  frames hold the earlier vehicle state until the next recorded timestamp;
  local coordinates from different origins are never blended.
- `/tmp/AGC-Site-Fixes/replay-before.log` reproduces the failures.
  `/tmp/AGC-Site-Fixes/replay-after.log` and `replay-isolated.log` pass all
  three replay tests, including the existing legacy recording test. The
  isolated export excludes the owner's uncommitted gear and panel edits.
- The regression checks serialized recordings, intermediate and endpoint
  samples, both directions of a legacy/custom site change, and Moon-centered
  continuity within 1e-8 m. Recording schema and stored samples are unchanged.

IMU diagnostic validation on 2026-09-05:

- Frozen-member force and diagnostic CDU conversion now accept the vehicle's
  site. Previously they always used Apollo 11's north/east/up basis, even when
  supplied a custom site's REFSMMAT. The diagnostic sensor-feedback path
  carries the same site through to CDU counters. Nil remains the legacy map;
  the production PIPA/CDU loop is unchanged.
- `/tmp/AGC-Site-Fixes/imu-before.log` reproduces force-vector errors up to
  3.5707651 m/s². After the fix, comparison against an independently converted
  inertial velocity difference has a maximum error of 4.998e-15 m/s² across
  four sites, including both poles, at the reference epoch and 1,200 seconds
  later. Epoch CDU agreement is within two counts. `imu-after.log` passes
  both new regressions and three existing Apollo IMU tests.
- `/tmp/AGC-Site-Fixes/combined-isolated.log`: 91 tests across site, radar,
  scenario/dynamics, replay, and IMU suites pass in 784.588 seconds. This
  clean export excludes the owner's uncommitted changes. Apollo automatic
  and P66 soft-contact regressions pass. Custom P63/P64/P65 still reaches
  spherical soft contact at 825.5703742983371 simulation seconds.

These fixes do not close the production inertial-IMU mapping caveat or the
rendered-terrain cockpit landing acceptance gate.
