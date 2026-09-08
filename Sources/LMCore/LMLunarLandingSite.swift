import Foundation

/// Immutable Mean Earth / polar-axis origin for one simulation. Nil on a
/// vehicle means the original NASA Apollo 11 pad load, preserving old fixtures.
public struct LMLunarLandingSite: Equatable, Sendable, Codable {
    public let latitudeDegrees: Double
    public let longitudeDegrees: Double
    public let radiusMeters: Double

    public enum SiteError: Error { case invalidCoordinate, incompatibleCheckpoint }
    public init(latitudeDegrees: Double, longitudeDegrees: Double, radiusMeters: Double) throws {
        guard latitudeDegrees.isFinite, longitudeDegrees.isFinite, radiusMeters.isFinite,
              abs(latitudeDegrees) <= 90, abs(longitudeDegrees) <= 180, radiusMeters > 0 else {
            throw SiteError.invalidCoordinate
        }
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.radiusMeters = radiusMeters
    }
    private enum CodingKeys: String, CodingKey { case latitudeDegrees, longitudeDegrees, radiusMeters }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(latitudeDegrees: c.decode(Double.self, forKey: .latitudeDegrees),
                      longitudeDegrees: c.decode(Double.self, forKey: .longitudeDegrees),
                      radiusMeters: c.decode(Double.self, forKey: .radiusMeters))
    }
    public var basis: (north: LMVector3D, east: LMVector3D, up: LMVector3D) {
        let lat = latitudeDegrees * .pi / 180, lon = longitudeDegrees * .pi / 180
        return (.init(x: -sin(lat) * cos(lon), y: -sin(lat) * sin(lon), z: cos(lat)),
                .init(x: -sin(lon), y: cos(lon), z: 0),
                .init(x: cos(lat) * cos(lon), y: cos(lat) * sin(lon), z: sin(lat)))
    }
    public var positionMeters: LMVector3D { basis.up * radiusMeters }
}

extension LMPoweredDescentScenario {
    /// Retarget the modeled Apollo PDI conditions and Luminary pad construction
    /// to another ME origin. This is a simulation scenario, not a historical
    /// mission reconstruction. Apollo checkpoint fixtures cannot start it.
    public static func lunarSite(_ site: LMLunarLandingSite) -> Self {
        let foundation = Self.apollo11SourceBacked
        let state = LMAGCNavState.vehicleState(
            timeCentiseconds: Luminary99LandingPadLoad.pdiClockCentiseconds,
            attitude: foundation.initialState.attitude,
            massKilograms: foundation.initialState.massKilograms ?? 0, site: site)
        return .init(id: "lunar-site:\(site.latitudeDegrees):\(site.longitudeDegrees):\(site.radiusMeters)",
                     title: "Custom lunar powered descent", initialState: state,
                     configuration: foundation.configuration, checkpoints: [], sourceStatus: foundation.sourceStatus)
    }
}
