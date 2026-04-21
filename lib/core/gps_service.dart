/// GPS location service wrapper.
///
/// Abstracts the geolocator package and provides:
/// - Permission checking and requesting
/// - One-shot position fetch
/// - Continuous position stream for live tracking
/// - Graceful fallback when GPS is unavailable (emulator/web)

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Encapsulates all GPS/location operations.
class GpsService {
  GpsService._();
  static final GpsService instance = GpsService._();

  /// Whether the service has been initialized and permissions granted.
  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Whether GPS is available on this platform.
  bool _available = false;
  bool get isAvailable => _available;

  // ─────────────────────────────────────────────────────────
  // INITIALIZATION & PERMISSIONS
  // ─────────────────────────────────────────────────────────

  /// Check and request location permissions.
  ///
  /// Returns `true` if location services are enabled and permission granted.
  Future<bool> initialize() async {
    try {
      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('GpsService: Location services are disabled.');
        _available = false;
        _initialized = true;
        return false;
      }

      // Check permission
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('GpsService: Location permission denied.');
          _available = false;
          _initialized = true;
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('GpsService: Location permission permanently denied.');
        _available = false;
        _initialized = true;
        return false;
      }

      _available = true;
      _initialized = true;
      debugPrint('GpsService: Initialized successfully.');
      return true;
    } catch (e) {
      debugPrint('GpsService: Error during initialization: $e');
      _available = false;
      _initialized = true;
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────
  // POSITION QUERIES
  // ─────────────────────────────────────────────────────────

  /// Get the current GPS position as a [LatLng].
  ///
  /// Returns `null` if GPS is unavailable.
  Future<LatLng?> getCurrentPosition() async {
    if (!_available) return null;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      debugPrint('GpsService: Error getting position: $e');
      return null;
    }
  }

  /// Get a continuous stream of GPS positions.
  ///
  /// [distanceFilter] — minimum distance change (meters) to trigger an update.
  /// Default is 3m which works well for walking navigation.
  ///
  /// Each event is a [GpsPosition] containing LatLng, speed, heading, and accuracy.
  Stream<GpsPosition> getPositionStream({
    int distanceFilter = 3,
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) {
    if (!_available) {
      return const Stream.empty();
    }

    final settings = LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
    );

    return Geolocator.getPositionStream(locationSettings: settings).map(
      (position) => GpsPosition(
        latLng: LatLng(position.latitude, position.longitude),
        accuracy: position.accuracy,
        speed: position.speed,
        heading: position.heading,
        timestamp: position.timestamp,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // CALCULATIONS
  // ─────────────────────────────────────────────────────────

  /// Distance in meters between two GPS points (Haversine).
  double distanceBetween(LatLng from, LatLng to) {
    return Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
  }

  /// Bearing in degrees from [from] to [to].
  double bearingBetween(LatLng from, LatLng to) {
    return Geolocator.bearingBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// GPS POSITION MODEL
// ─────────────────────────────────────────────────────────────

/// A GPS position with metadata.
class GpsPosition {
  /// Latitude and longitude.
  final LatLng latLng;

  /// Horizontal accuracy in meters.
  final double accuracy;

  /// Speed in m/s (may be 0 if stationary).
  final double speed;

  /// Heading in degrees (0 = North, 90 = East). May be 0 if unavailable.
  final double heading;

  /// Timestamp of the position fix.
  final DateTime? timestamp;

  const GpsPosition({
    required this.latLng,
    this.accuracy = 0,
    this.speed = 0,
    this.heading = 0,
    this.timestamp,
  });

  @override
  String toString() =>
      'GpsPosition(${latLng.latitude.toStringAsFixed(6)}, '
      '${latLng.longitude.toStringAsFixed(6)}, '
      'acc=${accuracy.toStringAsFixed(1)}m)';
}
