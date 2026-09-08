# First-contact orientation diagnostics

`LMSurfaceContactSnapshot.tiltRadians` is the angle between the vehicle thrust
axis and the first loaded footpad's surface normal. It is not terrain slope.
The optional `surfaceNormal` now preserves that exact normal in site ENU
(north, east, up), taken at the same contact substep as the recorded velocities
and tilt. The normal is the existing finite difference over a footpad diameter;
this change does not alter contact forces or landing classification.

`acos(surfaceNormal.z)` gives pad-scale slope relative to the original site
up axis. For a slope relative to the local lunar radial direction, consumers
must also account for the landing-site radius and the position at contact.
Do not substitute a later settled attitude or a lighting normal for this value.

Older recordings decode with a nil normal; the diagnostic is unavailable,
not zero. Sphere-only snapshots retain nil unless their producer supplies it.
New gear contacts retain their normal through Codable round trips.

Validation, 2026-09-05: 16 `LMLandingGearTests` pass with
`swift test --filter LMLandingGearTests`. The new tilted-plane case separates
a 12-degree slope from a roughly 7-degree contact tilt and retains the crash
classification. The legacy JSON test verifies missing-normal compatibility.
This is host test evidence; LM also builds the updated library for visionOS
Simulator. No physical-device acceptance is inferred.
