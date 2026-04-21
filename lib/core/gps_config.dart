/// GPS ↔ Local coordinate conversion for campus buildings.
///
/// Each building has a GPS anchor (the building's local origin mapped to
/// a known latitude/longitude and compass bearing). This allows us to
/// convert between the graph's Cartesian coordinates (meters) and GPS
/// coordinates for display on flutter_map.

import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'models.dart';

// ─────────────────────────────────────────────────────────────
// GPS ANCHOR
// ─────────────────────────────────────────────────────────────

/// Maps a building's local (0,0,0) origin to a real-world GPS position.
class GpsAnchor {
  /// GPS latitude of the building's local origin.
  final double latitude;

  /// GPS longitude of the building's local origin.
  final double longitude;

  /// Compass bearing (degrees from North, clockwise) of the building's
  /// positive X-axis. For most buildings this is approximately East (90°).
  final double bearingDeg;

  const GpsAnchor({
    required this.latitude,
    required this.longitude,
    this.bearingDeg = 90.0,
  });

  LatLng get origin => LatLng(latitude, longitude);
}

// ─────────────────────────────────────────────────────────────
// CAMPUS ANCHORS (VIT Pune — placeholder coordinates)
// ─────────────────────────────────────────────────────────────

/// GPS anchor for each building.
///
/// **Update these with real surveyed coordinates!**
/// Buildings are placed ~80m apart matching the campus_data.dart offsets.
const Map<String, GpsAnchor> campusGpsAnchors = {
  'cs': GpsAnchor(
    latitude: 18.4529,
    longitude: 73.8674,
    bearingDeg: 90.0,
  ),
  'aiml': GpsAnchor(
    latitude: 18.4529,
    longitude: 73.86815, // ~80m east
    bearingDeg: 90.0,
  ),
  'aids': GpsAnchor(
    latitude: 18.45218, // ~80m south
    longitude: 73.8674,
    bearingDeg: 90.0,
  ),
  'ai': GpsAnchor(
    latitude: 18.45218,
    longitude: 73.86815,
    bearingDeg: 90.0,
  ),
};

/// Fallback anchor if building is unknown.
const _defaultAnchor = GpsAnchor(
  latitude: 18.4529,
  longitude: 73.8674,
);

// ─────────────────────────────────────────────────────────────
// CONVERSION UTILITIES
// ─────────────────────────────────────────────────────────────

/// Meters per degree of latitude (roughly constant).
const double _metersPerDegLat = 111320.0;

/// Meters per degree of longitude at a given latitude.
double _metersPerDegLng(double latDeg) {
  return 111320.0 * cos(latDeg * pi / 180.0);
}

/// Convert a graph-local [Position3D] to a GPS [LatLng].
///
/// The local coordinate system uses:
/// - X → East (positive = building's bearing direction)
/// - Z → North (positive = perpendicular left of bearing)
/// - Y → Up (ignored for GPS)
///
/// We apply a 2D rotation by the building's bearing angle, then offset
/// from the anchor's GPS origin.
LatLng localToLatLng(Position3D pos, String building) {
  final anchor = campusGpsAnchors[building] ?? _defaultAnchor;
  final bearingRad = anchor.bearingDeg * pi / 180.0;

  // Rotate local (x, z) by bearing to get (east, north) offsets in meters
  final eastMeters = pos.x * cos(bearingRad) - pos.z * sin(bearingRad);
  final northMeters = pos.x * sin(bearingRad) + pos.z * cos(bearingRad);

  // Convert meter offsets to lat/lng deltas
  final dLat = northMeters / _metersPerDegLat;
  final dLng = eastMeters / _metersPerDegLng(anchor.latitude);

  return LatLng(anchor.latitude + dLat, anchor.longitude + dLng);
}

/// Convert a GPS [LatLng] to a graph-local [Position3D].
///
/// Inverse of [localToLatLng]. Returns position on the ground floor (y=0).
Position3D latLngToLocal(LatLng gps, String building) {
  final anchor = campusGpsAnchors[building] ?? _defaultAnchor;
  final bearingRad = anchor.bearingDeg * pi / 180.0;

  // GPS deltas to meter offsets
  final dLat = gps.latitude - anchor.latitude;
  final dLng = gps.longitude - anchor.longitude;
  final northMeters = dLat * _metersPerDegLat;
  final eastMeters = dLng * _metersPerDegLng(anchor.latitude);

  // Inverse rotation to get local (x, z)
  final x = eastMeters * cos(bearingRad) + northMeters * sin(bearingRad);
  final z = -eastMeters * sin(bearingRad) + northMeters * cos(bearingRad);

  return Position3D(x: x, y: 0, z: z);
}

/// Calculate compass bearing (degrees) from [from] to [to].
///
/// Returns value in [0, 360) where 0 = North, 90 = East, etc.
double calcBearing(LatLng from, LatLng to) {
  final dLat = (to.latitude - from.latitude) * pi / 180.0;
  final dLng = (to.longitude - from.longitude) * pi / 180.0;
  final lat1 = from.latitude * pi / 180.0;
  final lat2 = to.latitude * pi / 180.0;

  final y = sin(dLng) * cos(lat2);
  final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
  final bearing = atan2(y, x) * 180.0 / pi;
  return (bearing + 360.0) % 360.0;
}

/// Calculate Haversine distance in meters between two GPS points.
double calcDistance(LatLng from, LatLng to) {
  const R = 6371000.0; // Earth radius in meters
  final dLat = (to.latitude - from.latitude) * pi / 180.0;
  final dLng = (to.longitude - from.longitude) * pi / 180.0;
  final lat1 = from.latitude * pi / 180.0;
  final lat2 = to.latitude * pi / 180.0;

  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return R * c;
}

/// Get cardinal direction string from bearing degrees.
String bearingToCardinal(double bearing) {
  const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  final index = ((bearing + 22.5) % 360 / 45).floor();
  return directions[index % 8];
}

/// Format distance for display (auto-switch between m and km).
String formatDistance(double meters) {
  if (meters < 1000) {
    return '${meters.toStringAsFixed(0)} m';
  }
  return '${(meters / 1000).toStringAsFixed(1)} km';
}
