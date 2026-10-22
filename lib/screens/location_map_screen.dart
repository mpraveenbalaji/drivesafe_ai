import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/call_screening_service.dart';
import '../services/movement_service.dart';

class LocationMapScreen extends StatefulWidget {
  const LocationMapScreen({super.key});

  @override
  State<LocationMapScreen> createState() => _LocationMapScreenState();
}

class _LocationMapScreenState extends State<LocationMapScreen>
    with SingleTickerProviderStateMixin {
  Position? _currentPosition;
  bool _isLoading = true;
  String _statusText = 'Acquiring GPS fix...';
  StreamSubscription<MovementStatus>? _sub;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fetchCurrentLocation();

    // Also listen to movement service stream
    _sub = MovementService.instance.statusStream.listen((status) {
      if (mounted && status.latitude != null && status.longitude != null) {
        setState(() {
          _currentPosition = Position(
            longitude: status.longitude!,
            latitude: status.latitude!,
            timestamp: DateTime.now(),
            accuracy: status.accuracy,
            altitude: status.altitude ?? 0.0,
            altitudeAccuracy: 0.0,
            heading: 0.0,
            headingAccuracy: 0.0,
            speed: status.speedKmh / 3.6,
            speedAccuracy: 0.0,
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() {
      _isLoading = true;
      _statusText = 'Requesting GPS position...';
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _statusText = 'Location services disabled on device.';
          });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _statusText = 'Location permission denied.';
            });
          }
          return;
        }
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      if (mounted) {
        setState(() {
          _currentPosition = pos;
          _isLoading = false;
          _statusText = 'GPS fix locked';
        });
      }
    } catch (e) {
      // If direct request times out, check if MovementService has a position
      final mv = MovementService.instance.currentStatus;
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (mv.latitude != null && mv.longitude != null) {
            _currentPosition = Position(
              longitude: mv.longitude!,
              latitude: mv.latitude!,
              timestamp: DateTime.now(),
              accuracy: mv.accuracy,
              altitude: mv.altitude ?? 0.0,
              altitudeAccuracy: 0.0,
              heading: 0.0,
              headingAccuracy: 0.0,
              speed: mv.speedKmh / 3.6,
              speedAccuracy: 0.0,
            );
            _statusText = 'Using last active GPS position';
          } else {
            _statusText = 'GPS reading standby (No fix yet)';
          }
        });
      }
    }
  }

  void _openGoogleMaps() {
    final lat = _currentPosition?.latitude ??
        MovementService.instance.currentStatus.latitude ??
        12.9716;
    final lng = _currentPosition?.longitude ??
        MovementService.instance.currentStatus.longitude ??
        77.5946;

    CallScreeningManager.instance.openMap(latitude: lat, longitude: lng);
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF176B52);
    final status = MovementService.instance.currentStatus;

    final lat = _currentPosition?.latitude ?? status.latitude;
    final lng = _currentPosition?.longitude ?? status.longitude;
    final alt = _currentPosition?.altitude ?? status.altitude ?? 0.0;
    final acc = _currentPosition?.accuracy ?? status.accuracy;
    final speedKmh = _currentPosition != null
        ? (_currentPosition!.speed * 3.6)
        : status.speedKmh;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        title: const Text(
          'Live GPS Location & Map',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Location',
            onPressed: _fetchCurrentLocation,
          ),
        ],
      ),
      body: _isLoading && lat == null
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: green),
                  SizedBox(height: 16),
                  Text(
                    'Locking GPS Satellite Coordinates...',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Interactive Map Canvas Card
                Container(
                  height: 250,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5ECE8),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: green.withValues(alpha: 0.2)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Stack(
                      children: [
                        // Stylized Map Grid / Background
                        CustomPaint(
                          size: const Size(double.infinity, 250),
                          painter: MapStylizedPainter(),
                        ),

                        // Center User Location Marker
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ScaleTransition(
                                scale: _pulseAnimation,
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: green.withValues(alpha: 0.25),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      color: green,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.my_location,
                                      color: Colors.white,
                                      size: 26,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  lat != null
                                      ? '${lat.toStringAsFixed(4)}°, ${lng!.toStringAsFixed(4)}°'
                                      : 'Locating...',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Top Badges Overlay
                        Positioned(
                          top: 14,
                          left: 14,
                          right: 14,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.satellite_alt,
                                      size: 14,
                                      color: green,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'GPS TRACKED',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: green,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  acc > 0
                                      ? 'Accuracy: ±${acc.toStringAsFixed(0)}m'
                                      : 'Acquiring',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Button: Open in Google Maps
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                  onPressed: _openGoogleMaps,
                  icon: const Icon(Icons.map_outlined, size: 22),
                  label: const Text(
                    'Open in Google Maps',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),

                const SizedBox(height: 20),

                const Text(
                  'GPS Sensor Coordinates',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                // Coordinates Grid
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        icon: Icons.explore_outlined,
                        label: 'Latitude',
                        value: lat != null
                            ? '${lat.toStringAsFixed(6)}°'
                            : 'Waiting...',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MetricCard(
                        icon: Icons.navigation_outlined,
                        label: 'Longitude',
                        value: lng != null
                            ? '${lng.toStringAsFixed(6)}°'
                            : 'Waiting...',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        icon: Icons.speed,
                        label: 'Calculated Speed',
                        value: '${speedKmh.toStringAsFixed(1)} km/h',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MetricCard(
                        icon: Icons.terrain_outlined,
                        label: 'Altitude',
                        value: alt != 0.0 ? '${alt.toStringAsFixed(1)} m' : 'N/A',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Status info box
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 20, color: Colors.black54),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _statusText,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: const Color(0xFF176B52)),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws an aesthetic stylized road grid on the canvas
class MapStylizedPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFFEAF1EC);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke;

    final secondaryRoadPaint = Paint()
      ..color = const Color(0xFFF7FAF8)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    // Draw stylized roads
    canvas.drawLine(
      Offset(0, size.height * 0.45),
      Offset(size.width, size.height * 0.55),
      roadPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.5, 0),
      Offset(size.width * 0.5, size.height),
      roadPaint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.2),
      Offset(size.width, size.height * 0.25),
      secondaryRoadPaint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.8),
      Offset(size.width, size.height * 0.75),
      secondaryRoadPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.25, 0),
      Offset(size.width * 0.25, size.height),
      secondaryRoadPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.75, 0),
      Offset(size.width * 0.75, size.height),
      secondaryRoadPaint,
    );

    // Park / Green area
    final parkPaint = Paint()..color = const Color(0xFFD4E7DC);
    final parkPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width * 0.08, size.height * 0.55, 60, 40),
          const Radius.circular(8),
        ),
      );
    canvas.drawPath(parkPath, parkPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
