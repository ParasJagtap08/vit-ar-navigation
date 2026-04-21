import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'gps_config.dart';
import 'gps_service.dart';

// ─────────────────────────────────────────────
// CAMPUS CONSTANTS
// ─────────────────────────────────────────────

/// Campus center — VIT Pune
const LatLng campusCenter = LatLng(18.4637, 73.8682);

/// Campus main entrance GPS — Google Maps navigates here
const LatLng campusEntrance = LatLng(18.4637, 73.8682);

/// ≤ 200m = on campus, > 200m = off campus
const double campusProximityThreshold = 200.0;

// ─────────────────────────────────────────────
// PROXIMITY RESULT
// ─────────────────────────────────────────────

enum ProximityStatus { nearCampus, farFromCampus, locationUnavailable }

class ProximityResult {
  final ProximityStatus status;
  final double? distanceMeters;
  final LatLng? userPosition;
  final String message;

  const ProximityResult({
    required this.status,
    this.distanceMeters,
    this.userPosition,
    required this.message,
  });
}

// ─────────────────────────────────────────────
// CORE PROXIMITY CHECK
// ─────────────────────────────────────────────

Future<ProximityResult> checkCampusProximity() async {
  try {
    final gps = GpsService.instance;
    if (!gps.isInitialized) await gps.initialize();

    if (!gps.isAvailable) {
      return const ProximityResult(
        status: ProximityStatus.locationUnavailable,
        message: 'Location services are disabled. Please enable GPS.',
      );
    }

    final userPos = await gps.getCurrentPosition();
    if (userPos == null) {
      return const ProximityResult(
        status: ProximityStatus.locationUnavailable,
        message: 'Could not get your location. Please try again.',
      );
    }

    final distance = calcDistance(userPos, campusCenter);

    if (distance <= campusProximityThreshold) {
      return ProximityResult(
        status: ProximityStatus.nearCampus,
        distanceMeters: distance,
        userPosition: userPos,
        message: '📍 You are inside campus (${formatDistance(distance)} away). '
            'Starting AR navigation...',
      );
    } else {
      return ProximityResult(
        status: ProximityStatus.farFromCampus,
        distanceMeters: distance,
        userPosition: userPos,
        message: '🗺️ You are ${formatDistance(distance)} from campus. '
            'Opening Google Maps to VIT entrance...',
      );
    }
  } catch (e) {
    return ProximityResult(
      status: ProximityStatus.locationUnavailable,
      message: 'Location error: $e',
    );
  }
}

// ─────────────────────────────────────────────
// ✅ GOOGLE MAPS LAUNCHER
// ─────────────────────────────────────────────

Future<void> openGoogleMaps() async {
  final googleMapsUrl = Uri.parse(
    "https://www.google.com/maps/dir/?api=1"
    "&destination=${campusEntrance.latitude},${campusEntrance.longitude}"
    "&travelmode=driving",
  );

  try {
    final launched = await launchUrl(
      googleMapsUrl,
      mode: LaunchMode.externalApplication,
    );

    if (!launched) {
      throw Exception("Could not launch external maps");
    }
  } catch (e) {
    // Fallback to geo URI
    final geoUrl = Uri.parse(
      "geo:${campusEntrance.latitude},${campusEntrance.longitude}"
      "?q=${campusEntrance.latitude},${campusEntrance.longitude}(VIT Pune)",
    );

    try {
      await launchUrl(geoUrl);
    } catch (e2) {
      debugPrint("❌ Maps launch failed: $e2");
    }
  }
}

// ─────────────────────────────────────────────
// ✅ ALL-IN-ONE UI FUNCTION
// ─────────────────────────────────────────────

/// Checks proximity and navigates accordingly:
/// - NEAR → calls [onNearCampus]
/// - FAR  → shows dialog + opens Google Maps
/// - ERROR → shows snackbar
Future<void> checkUserDistanceAndNavigate({
  required BuildContext context,
  required VoidCallback onNearCampus,
}) async {
  // Show loading
  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (_) => Center(
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF121830),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF00BCD4).withOpacity(0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 50,
              height: 50,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation(
                      const Color(0xFF00BCD4).withOpacity(0.6),
                    ),
                  ),
                  const Icon(Icons.my_location_rounded,
                      color: Color(0xFF00E5FF), size: 24),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Checking Location...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Determining distance from campus',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
                fontWeight: FontWeight.w400,
                decoration: TextDecoration.none,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );

  // Perform check with 6-second max timeout (never hang forever)
  ProximityResult result;
  try {
    result = await checkCampusProximity().timeout(
      const Duration(seconds: 6),
      onTimeout: () => const ProximityResult(
        status: ProximityStatus.nearCampus,
        message: '⏱️ Location check timed out. Proceeding with campus navigation...',
      ),
    );
  } catch (e) {
    result = const ProximityResult(
      status: ProximityStatus.nearCampus,
      message: '⏱️ Could not check location. Proceeding...',
    );
  }

  // Dismiss loading
  if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
  }
  if (!context.mounted) return;

  switch (result.status) {
    case ProximityStatus.nearCampus:
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(result.message)),
            ],
          ),
          backgroundColor: const Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
      onNearCampus();

    case ProximityStatus.farFromCampus:
      final shouldOpen = await showDialog<bool>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: const Color(0xFF121830),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFA726).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.directions_car_rounded,
                      color: Color(0xFFFFA726), size: 32),
                ),
                const SizedBox(height: 16),
                const Text(
                  'You are outside campus',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00BCD4).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF00BCD4).withOpacity(0.2)),
                  ),
                  child: Text(
                    '${formatDistance(result.distanceMeters ?? 0)} from campus',
                    style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'You need to reach VIT Pune campus first.\nOpen Google Maps for directions?',
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Color(0xFF2A2A4A)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(ctx, true),
                        icon: const Icon(Icons.map_rounded, color: Colors.white, size: 18),
                        label: const Text('Open Maps', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00BCD4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      if (shouldOpen == true) await openGoogleMaps();

    case ProximityStatus.locationUnavailable:
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.location_off_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(result.message)),
            ],
          ),
          backgroundColor: const Color(0xFFE65100),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'SETTINGS',
            textColor: Colors.white,
            onPressed: () => Geolocator.openLocationSettings(),
          ),
        ),
      );
  }
}