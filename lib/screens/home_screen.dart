import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/call_rule.dart';
import '../models/driving_state.dart';
import '../models/vehicle_type.dart';
import '../services/call_screening_service.dart';
import '../services/movement_service.dart';
import '../services/preference_service.dart';
import 'call_history_screen.dart';
import 'call_rules_screen.dart';
import 'location_map_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<MovementStatus>? _movementSub;
  MovementStatus _movementStatus = MovementStatus.idle();
  CallRulesConfig _callRules = const CallRulesConfig();
  bool _passengerMode = false;
  int _historyCount = 0;
  bool _isCallScreeningGranted = true;
  bool _hasContactsPermission = true;
  bool _hasPhonePermission = true;

  @override
  void initState() {
    super.initState();
    _refreshState();
    _checkRuntimePermissions();
    MovementService.instance.initNativeMotionIntegration();
    _movementStatus = MovementService.instance.currentStatus;
    _movementSub = MovementService.instance.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _movementStatus = status;
        });
      }
    });

    // Automatically initiate natural GPS speed & motion tracking on launch
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final locStatus = await Permission.location.status;
      if (!locStatus.isGranted) {
        await Permission.location.request();
      }
      await MovementService.instance.startTracking();
    });
  }

  @override
  void dispose() {
    _movementSub?.cancel();
    super.dispose();
  }

  Future<void> _checkRuntimePermissions() async {
    final contacts = await Permission.contacts.status;
    final phone = await Permission.phone.status;
    final nativeGranted = await CallScreeningManager.instance.areNativePermissionsGranted();
    if (mounted) {
      setState(() {
        _hasContactsPermission = contacts.isGranted || nativeGranted;
        _hasPhonePermission = phone.isGranted || nativeGranted;
      });
    }
  }

  Future<void> _requestRuntimePermissions() async {
    await CallScreeningManager.instance.requestNativePermissions();
    await [
      Permission.contacts,
      Permission.phone,
      Permission.location,
    ].request();

    await _checkRuntimePermissions();

    if (mounted && _hasContactsPermission && _hasPhonePermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contacts, Phone & Location access granted! Saved contacts and real speed will now be tracked.'),
          backgroundColor: Color(0xFF15803D),
        ),
      );
    }
  }

  Future<void> _refreshState() async {
    final rules = await PreferenceService.instance.loadCallRules();
    final settings = await PreferenceService.instance.loadSettings();
    final history = await PreferenceService.instance.loadCallHistory();
    final roleGranted = await CallScreeningManager.instance.isRoleGranted();

    if (mounted) {
      setState(() {
        _callRules = rules;
        _passengerMode = settings['passengerMode'] ?? false;
        _historyCount = history.length;
        _isCallScreeningGranted = roleGranted;
      });
    }
  }

  /// Pull-to-refresh: resets simulated speed to 0 km/h, restores Idle mode, reloads state.
  Future<void> _handlePullToRefresh() async {
    await MovementService.instance.resetToIdle();
    await _refreshState();
    await _checkRuntimePermissions();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Refreshed: Current speed reset to 0.0 km/h • Idle mode restored'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _toggleGpsTracking() async {
    if (_passengerMode) return;

    if (MovementService.instance.isListening) {
      await MovementService.instance.stopTracking();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Auto GPS tracking stopped')),
        );
      }
    } else {
      final success = await MovementService.instance.startTracking();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Auto GPS tracking active • Listening for vehicle speed'
                  : 'Could not start GPS. Please check device location settings.',
            ),
          ),
        );
      }
    }
    setState(() {});
  }

  void _showSpeedSimulationModal() {
    if (_passengerMode) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            double currentSpeed = _movementStatus.speedKmh;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Simulate Mobility & Speed',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const Text(
                    'Set exact speed to test driving detection. Incoming calls on your phone will be screened according to your rules when speed >= 15 km/h.',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Speed: ${currentSpeed.toStringAsFixed(1)} km/h',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Slider(
                    value: currentSpeed.clamp(0.0, 100.0),
                    min: 0.0,
                    max: 100.0,
                    divisions: 20,
                    label: '${currentSpeed.round()} km/h',
                    activeColor: const Color(0xFF176B52),
                    onChanged: (val) {
                      MovementService.instance.setSimulatedSpeed(val);
                      setSheetState(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Speed & Motion Benchmarks:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '• < 15 km/h (Stopped / Walk / Run): Calls ring freely\n• >= 15 km/h: Driving active, calls screened',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.pause_circle_outline, size: 16),
                        label: const Text('🛑 Stopped in Traffic (0 km/h)'),
                        onPressed: () {
                          MovementService.instance.setSimulatedSpeed(0.0, VehicleType.stationary);
                          setSheetState(() {});
                        },
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.directions_walk, size: 16),
                        label: const Text('🚶 Walking (4 km/h)'),
                        onPressed: () {
                          MovementService.instance.setSimulatedSpeed(4.0, VehicleType.walking);
                          setSheetState(() {});
                        },
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.directions_run, size: 16),
                        label: const Text('🏃 Running (9 km/h)'),
                        onPressed: () {
                          MovementService.instance.setSimulatedSpeed(9.0, VehicleType.running);
                          setSheetState(() {});
                        },
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.two_wheeler, size: 16),
                        label: const Text('🏍️ Driving (35 km/h)'),
                        onPressed: () {
                          MovementService.instance.setSimulatedSpeed(35.0, VehicleType.twoWheeler);
                          setSheetState(() {});
                        },
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.directions_car, size: 16),
                        label: const Text('🚗 Cruising (60 km/h)'),
                        onPressed: () {
                          MovementService.instance.setSimulatedSpeed(60.0, VehicleType.car);
                          setSheetState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF176B52),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        MovementService.instance.resetToIdle();
                        setSheetState(() {});
                      },
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('Reset Speed to 0.0 km/h'),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF176B52);
    final state = _movementStatus.state;
    final isDriving = state == DrivingState.drivingActive && !_passengerMode;
    final isGpsTracking = MovementService.instance.isListening;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    Color cardColor = Colors.white;
    Color textColor = Colors.black87;

    if (_passengerMode) {
      cardColor = const Color(0xFFFFFBEB);
      textColor = const Color(0xFF92400E);
    } else if (isDriving) {
      cardColor = green;
      textColor = Colors.white;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/logo_circle.png',
                width: 34,
                height: 34,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'DriveSafe AI',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
              _refreshState();
            },
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: green,
          onRefresh: _handlePullToRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: bottomInset + 28),
            children: [
              const Text(
                'Drive smarter. Stay focused.',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Manage incoming calls while travelling.',
                style: TextStyle(color: Colors.black54, fontSize: 14),
              ),
              const SizedBox(height: 16),

              // Passenger Mode Context Banner
              if (_passengerMode) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Color(0xFFD97706), size: 22),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Passenger Mode Active: Driving controls are disabled. Speed is calculated, but call screening is bypassed so your calls ring normally.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF92400E),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Contacts & Phone Permission Alert Banner
              if (!_hasContactsPermission || !_hasPhonePermission) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.contact_phone_outlined, color: Color(0xFFDC2626), size: 22),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Contacts & Phone Access Required',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Color(0xFFB91C1C),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'To identify saved contacts (like "Amma") vs unknown callers and automatically silence or reject calls while driving, DriveSafe AI needs Contacts and Phone permissions.',
                        style: TextStyle(fontSize: 13, color: Color(0xFF7F1D1D)),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _requestRuntimePermissions,
                          icon: const Icon(Icons.verified_user_outlined, size: 18),
                          label: const Text('Grant Contacts & Phone Access'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Call Screening Permission Banner
              if (!_isCallScreeningGranted) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.phone_locked_outlined, color: Color(0xFF2563EB), size: 22),
                          SizedBox(width: 8),
                          Text(
                            'Enable Call Screening Role',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Color(0xFF1E40AF),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'To automatically silence or reject incoming calls at the OS level while driving, Android requires setting DriveSafe AI as your Call Screening app.',
                        style: TextStyle(fontSize: 13, color: Color(0xFF1E3A8A)),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () async {
                            final granted = await CallScreeningManager.instance.requestRole();
                            if (granted) {
                              _refreshState();
                            }
                          },
                          icon: const Icon(Icons.shield_outlined, size: 18),
                          label: const Text('Set as Call Screening App'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Main Driving Detection Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(24),
                  border: _passengerMode
                      ? Border.all(color: const Color(0xFFFDE68A), width: 1.5)
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Top Badges
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _passengerMode
                                ? const Color(0xFFFDE68A)
                                : isDriving
                                    ? Colors.white.withValues(alpha: 0.22)
                                    : Colors.black.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _passengerMode
                                ? 'PASSENGER MODE'
                                : (isDriving ? 'DRIVING ACTIVE' : 'STOPPED / NOT DRIVING'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _passengerMode
                                  ? const Color(0xFF92400E)
                                  : isDriving
                                      ? Colors.white
                                      : const Color(0xFF176B52),
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _passengerMode
                                    ? const Color(0xFFFEF3C7)
                                    : isDriving
                                        ? Colors.white.withValues(alpha: 0.25)
                                        : const Color(0xFFE0E7FF),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _passengerMode
                                    ? 'SCREENING OFF'
                                    : (isDriving ? '✓ SCREENING ACTIVE' : 'CALLS RING FREELY'),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _passengerMode
                                      ? const Color(0xFF92400E)
                                      : isDriving
                                          ? Colors.white
                                          : const Color(0xFF15803D),
                                ),
                              ),
                            ),
                            if (_movementStatus.isSimulated && !_passengerMode)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'SIMULATED',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Hero Icon
                    Icon(
                      _passengerMode
                          ? Icons.airline_seat_recline_normal
                          : (isDriving
                              ? Icons.navigation
                              : (_movementStatus.speedKmh >= 6.0
                                  ? Icons.directions_run
                                  : (_movementStatus.speedKmh >= 1.0
                                      ? Icons.directions_walk
                                      : Icons.pause_circle_outline))),
                      size: 56,
                      color: _passengerMode
                          ? const Color(0xFFD97706)
                          : (isDriving ? Colors.white : green),
                    ),
                    const SizedBox(height: 8),

                    Text(
                      _passengerMode
                          ? 'Passenger Mode Active'
                          : (isDriving
                              ? 'Driving Mode Active'
                              : (_movementStatus.speedKmh < 1.0
                                  ? 'Stopped in Traffic / Rest'
                                  : _movementStatus.motionLabel)),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Current Speed: ${_movementStatus.speedKmh.toStringAsFixed(1)} km/h',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _passengerMode
                            ? const Color(0xFF78350F)
                            : (isDriving ? Colors.white.withValues(alpha: 0.9) : Colors.black87),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Motion & Speed Info Box
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: _passengerMode
                            ? const Color(0xFFFDE68A).withValues(alpha: 0.4)
                            : (isDriving
                                ? Colors.black.withValues(alpha: 0.16)
                                : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 2,
                            children: [
                              Icon(
                                Icons.speed,
                                size: 14,
                                color: _passengerMode
                                    ? const Color(0xFFD97706)
                                    : (isDriving ? Colors.amber[200] : const Color(0xFFD97706)),
                              ),
                              Text(
                                _passengerMode
                                    ? 'Motion: Passenger • Speed Tracking Only'
                                    : 'Motion: ${_movementStatus.motionLabel}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _passengerMode
                                      ? const Color(0xFF92400E)
                                      : (isDriving ? Colors.white : Colors.black87),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _passengerMode
                                ? 'All screening options disabled. Calls ring freely.'
                                : _movementStatus.message,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: _passengerMode
                                  ? const Color(0xFF78350F)
                                  : (isDriving ? Colors.white70 : Colors.black54),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Controls: Auto GPS & Simulate
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: _passengerMode
                                  ? Colors.black12
                                  : (isDriving ? Colors.white : green),
                              foregroundColor: _passengerMode
                                  ? Colors.black38
                                  : (isDriving ? green : Colors.white),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _passengerMode ? null : _toggleGpsTracking,
                            icon: Icon(
                              isGpsTracking ? Icons.gps_fixed : Icons.gps_not_fixed,
                              size: 18,
                            ),
                            label: Text(
                              _passengerMode
                                  ? 'GPS Disabled'
                                  : (isGpsTracking ? 'Stop GPS' : 'Auto GPS'),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _passengerMode
                                  ? Colors.black38
                                  : (isDriving ? Colors.white : green),
                              side: BorderSide(
                                color: _passengerMode
                                    ? Colors.black12
                                    : (isDriving ? Colors.white70 : green.withValues(alpha: 0.35)),
                                width: 1.5,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _passengerMode ? null : _showSpeedSimulationModal,
                            icon: const Icon(Icons.tune, size: 18),
                            label: Text(
                              _passengerMode ? 'Simulate Off' : 'Simulate',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Live GPS Location & Map Box (Requirement 2)
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const LocationMapScreen()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: green.withValues(alpha: 0.15)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.location_on, color: green, size: 20),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Live GPS & Location Map',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                          const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.black45),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Mini Map Visual Banner
                      Container(
                        height: 90,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF1EC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CustomPaint(
                                size: const Size(double.infinity, 90),
                                painter: MapStylizedPainter(),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      color: green,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.my_location, color: Colors.white, size: 16),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.black87,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _movementStatus.latitude != null
                                          ? '${_movementStatus.latitude!.toStringAsFixed(4)}°, ${_movementStatus.longitude!.toStringAsFixed(4)}°'
                                          : 'Tap to view full map & location',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Tracked with live satellite GPS',
                            style: TextStyle(color: Colors.black54, fontSize: 12),
                          ),
                          Text(
                            'View Details →',
                            style: TextStyle(color: green, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
              const Text(
                'Call Management Rules',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              FeatureTile(
                icon: Icons.report_gmailerrorred_outlined,
                title: 'Spam Calls',
                subtitle: 'Action: ${_callRules.spamAction.label}',
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const CallRulesScreen()),
                  );
                  _refreshState();
                },
              ),
              FeatureTile(
                icon: Icons.contacts_outlined,
                title: 'Saved Contacts',
                subtitle: 'Action: ${_callRules.contactAction.label}',
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const CallRulesScreen()),
                  );
                  _refreshState();
                },
              ),
              FeatureTile(
                icon: Icons.phone_callback_outlined,
                title: 'Unknown Callers',
                subtitle: 'Action: ${_callRules.unknownAction.label}',
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const CallRulesScreen()),
                  );
                  _refreshState();
                },
              ),
              FeatureTile(
                icon: Icons.history,
                title: 'Call History',
                subtitle: _historyCount == 0
                    ? 'No screened call events recorded yet'
                    : '$_historyCount call event${_historyCount == 1 ? '' : 's'} recorded',
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const CallHistoryScreen()),
                  );
                  _refreshState();
                },
              ),

              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F2ED),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.verified_outlined, color: Color(0xFF176B52)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'DriveSafe AI Motion Engine: Calculates exact speed. Calls ring freely when stopped in traffic or walking (< 15 km/h). Screening rules activate during motion (>= 15 km/h).',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F2ED),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_outlined, color: Color(0xFF176B52)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Safety Guarantee: Emergency calls (e.g. 911, 112) will NEVER be intercepted, silenced, or rejected under any rule.',
                        style: TextStyle(fontSize: 13, color: Color(0xFF176B52), fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Center(
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'assets/logo_circle.png',
                          width: 72,
                          height: 72,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.shield, size: 72, color: Color(0xFF176B52)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'DriveSafe AI v1.0.0',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'AI-Powered Driving Detection & Call Screening',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }
}

class FeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const FeatureTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF176B52).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFF176B52)),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.black54, fontSize: 13),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.black45),
        onTap: onTap,
      ),
    );
  }
}
