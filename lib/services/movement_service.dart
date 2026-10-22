import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/driving_state.dart';
import '../models/vehicle_type.dart';
import 'ai_vehicle_classifier.dart';
import 'call_screening_service.dart';
import 'preference_service.dart';

class MovementStatus {
  final double speedKmh;
  final DrivingState state;
  final double accuracy;
  final double? latitude;
  final double? longitude;
  final double? altitude;
  final bool isSimulated;
  final String message;
  final String motionLabel;
  final DateTime timestamp;
  final AiDrivingAssessment assessment;

  const MovementStatus({
    required this.speedKmh,
    required this.state,
    required this.accuracy,
    this.latitude,
    this.longitude,
    this.altitude,
    required this.isSimulated,
    required this.message,
    required this.motionLabel,
    required this.timestamp,
    required this.assessment,
  });

  factory MovementStatus.idle() => MovementStatus(
        speedKmh: 0.0,
        state: DrivingState.normal,
        accuracy: 0.0,
        latitude: null,
        longitude: null,
        altitude: null,
        isSimulated: false,
        message: 'Stationary / Stopped in traffic • Calls ring normally',
        motionLabel: 'Idle / Stopped in Traffic',
        timestamp: DateTime.now(),
        assessment: AiDrivingAssessment.idle(),
      );

  bool get isDriving => state == DrivingState.drivingActive;
}

class MovementService {
  MovementService._();
  static final MovementService instance = MovementService._();

  StreamSubscription<Position>? _positionSubscription;
  final _statusController = StreamController<MovementStatus>.broadcast();
  Stream<MovementStatus> get statusStream => _statusController.stream;

  MovementStatus _currentStatus = MovementStatus.idle();
  MovementStatus get currentStatus => _currentStatus;

  bool _isListening = false;
  bool get isListening => _isListening;

  // Speed threshold for active driving
  static const double drivingSpeedThresholdKmh = 15.0;

  bool _isSimulatedMode = false;
  bool get isSimulatedMode => _isSimulatedMode;

  double? _lastLatitude;
  double? _lastLongitude;
  double? _lastAltitude;

  Position? _anchorPosition;
  DateTime? _anchorTime;
  DateTime? _lastFixTime;
  Timer? _periodicFixTimer;

  /// Initializes integration with Android native motion and sensor engine.
  void initNativeMotionIntegration() {
    CallScreeningManager.instance.initMotionChannel(handleNativeMotionUpdate);
  }

  /// Handles incoming motion events from Android native Accelerometer, Step Detector & LocationManager.
  void handleNativeMotionUpdate(Map<String, dynamic> data) {
    if (_isSimulatedMode) return;
    final double speed = (data['speedKmh'] as num?)?.toDouble() ?? 0.0;
    final String motionLabel = data['motionLabel']?.toString() ?? 'Idle / Stopped in Traffic';
    final String motionType = data['motionType']?.toString() ?? 'IDLE';

    // If native sensor update reports IDLE or 0 speed, do NOT clobber GPS ground speed if GPS currently reports driving speed
    if (speed <= 0.0 && _currentStatus.speedKmh >= drivingSpeedThresholdKmh) {
      return;
    }

    // Only process native motion updates if there is meaningful motion (e.g., walking, jogging)
    // or if the device is not currently tracking an active GPS driving session
    if (motionType == 'WALKING' || motionType == 'RUNNING' || speed > 0.0) {
      _processSpeedUpdate(
        speed,
        accuracy: 5.0,
        isSim: false,
        forcedLabel: motionLabel,
        forcedMotionType: motionType,
      );
    }
  }

  /// Starts listening to real device GPS position stream and native motion engine.
  Future<bool> startTracking() async {
    _isSimulatedMode = false;
    _anchorPosition = null;
    _anchorTime = null;
    _lastFixTime = null;
    AiVehicleClassifier.instance.setSimulatedVehicleOverride(null);

    // Start hardware native sensor & location engine
    await CallScreeningManager.instance.startNativeMotionTracking();

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _updateStatus(
        speed: 0,
        state: DrivingState.uncertain,
        accuracy: 0,
        message: 'Location service disabled on device',
        motionLabel: 'GPS Disabled',
        assessment: AiDrivingAssessment.idle(),
      );
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _updateStatus(
          speed: 0,
          state: DrivingState.uncertain,
          accuracy: 0,
          message: 'Location permission denied by user',
          motionLabel: 'Permission Denied',
          assessment: AiDrivingAssessment.idle(),
        );
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _updateStatus(
        speed: 0,
        state: DrivingState.uncertain,
        accuracy: 0,
        message: 'Location permissions permanently denied in settings',
        motionLabel: 'Permission Blocked',
        assessment: AiDrivingAssessment.idle(),
      );
      return false;
    }

    await stopTracking();

    // High accuracy settings with 1-second interval and foreground notification config for Android
    late final LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'DriveSafe AI Active',
          notificationText: 'Monitoring speed & driving safety',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );
    }

    _isListening = true;

    // Immediately fetch initial fix so the app gets current location & speed without waiting
    try {
      final initialPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 4),
        ),
      );
      _handlePositionUpdate(initialPos);
    } catch (_) {}

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      _handlePositionUpdate,
      onError: (error) {
        _updateStatus(
          speed: 0,
          state: DrivingState.uncertain,
          accuracy: 0,
          message: 'GPS Error: $error',
          motionLabel: 'GPS Error',
          assessment: AiDrivingAssessment.idle(),
        );
      },
    );

    _startPeriodicFixTimer();

    return true;
  }


  /// Stops tracking GPS.
  Future<void> stopTracking() async {
    _isListening = false;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _periodicFixTimer?.cancel();
    _periodicFixTimer = null;
    _anchorPosition = null;
    _anchorTime = null;
    _lastFixTime = null;
    await CallScreeningManager.instance.stopNativeMotionTracking();
  }

  void _startPeriodicFixTimer() {
    _periodicFixTimer?.cancel();
    _periodicFixTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!_isListening || _isSimulatedMode) return;
      final now = DateTime.now();
      // If no GPS fix arrived via stream for more than 3 seconds while active, poll explicitly
      if (_lastFixTime == null || now.difference(_lastFixTime!).inSeconds >= 3) {
        try {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              timeLimit: Duration(seconds: 2),
            ),
          );
          _handlePositionUpdate(pos);
        } catch (_) {}
      }
    });
  }

  /// Sets simulated speed for desk testing.
  void setSimulatedSpeed(double speedKmh, [VehicleType? vehicleType]) {
    _isSimulatedMode = true;
    AiVehicleClassifier.instance.setSimulatedVehicleOverride(vehicleType);
    _processSpeedUpdate(speedKmh, accuracy: 5.0, isSim: true);
  }

  /// Resets everything to 0.0 km/h and Idle (used by Pull-to-Refresh).
  Future<void> resetToIdle() async {
    _isSimulatedMode = false;
    _anchorPosition = null;
    _anchorTime = null;
    _lastFixTime = null;
    AiVehicleClassifier.instance.setSimulatedVehicleOverride(null);
    _updateStatus(
      speed: 0.0,
      state: DrivingState.normal,
      accuracy: 0.0,
      isSim: false,
      message: 'Stationary / Stopped in traffic • Calls ring normally',
      motionLabel: 'Idle / Stopped in Traffic',
      assessment: AiDrivingAssessment.idle(),
    );
    await CallScreeningManager.instance.syncDrivingState(false);
    await CallScreeningManager.instance.restoreRinger();
  }

  void _handlePositionUpdate(Position position) {
    if (_isSimulatedMode) return;

    _lastLatitude = position.latitude;
    _lastLongitude = position.longitude;
    _lastAltitude = position.altitude;
    final now = DateTime.now();
    _lastFixTime = now;

    // 1. Hardware Doppler ground speed from device GPS (m/s -> km/h)
    double speedKmh = (position.speed > 0.2) ? (position.speed * 3.6) : 0.0;

    // 2. Robust Sliding Accumulating Anchor delta calculation:
    // Accumulates displacement over a window (>= 1.0s or >= 2.0m) before calculating speed
    // This allows walking (0.8 - 1.2 m/s) and real vehicle driving to register accurately
    // even on chipsets where position.speed is reported as 0.0 by Android vendor HAL
    if (_anchorPosition == null || _anchorTime == null) {
      _anchorPosition = position;
      _anchorTime = now;
    } else {
      final elapsedSec = now.difference(_anchorTime!).inMilliseconds / 1000.0;
      final distMeters = Geolocator.distanceBetween(
        _anchorPosition!.latitude,
        _anchorPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      if (elapsedSec >= 1.0 || distMeters >= 2.0) {
        if (elapsedSec > 0.3) {
          final deltaSpeed = (distMeters / elapsedSec) * 3.6;
          if (distMeters >= 1.5 && (speedKmh < 1.0 || deltaSpeed > speedKmh) && deltaSpeed < 180.0) {
            speedKmh = deltaSpeed;
          }
        }
        _anchorPosition = position;
        _anchorTime = now;
      }
    }

    // Stationary clamp: speed below 1.0 km/h is treated as stationary/idle
    if (speedKmh < 1.0) {
      speedKmh = 0.0;
    }

    _processSpeedUpdate(speedKmh, accuracy: position.accuracy, isSim: false);
  }

  Future<void> _processSpeedUpdate(
    double speedKmh, {
    required double accuracy,
    required bool isSim,
    String? forcedLabel,
    String? forcedMotionType,
  }) async {
    final settings = await PreferenceService.instance.loadSettings();
    final isPassenger = settings['passengerMode'] ?? false;
    final isPaused = settings['manualPause'] ?? false;

    final assessment = AiVehicleClassifier.instance.classify(
      currentSpeedKmh: speedKmh,
      isPassengerMode: isPassenger,
      isManualPause: isPaused,
    );

    // 1. Passenger Mode override
    if (isPassenger) {
      _updateStatus(
        speed: speedKmh,
        state: DrivingState.passenger,
        accuracy: accuracy,
        isSim: isSim,
        message: 'Passenger Mode active • Calls ring normally',
        motionLabel: 'Passenger Mode',
        assessment: assessment,
      );
      await CallScreeningManager.instance.syncDrivingState(false);
      await CallScreeningManager.instance.restoreRinger();
      return;
    }

    // 2. Manual Pause override
    if (isPaused) {
      _updateStatus(
        speed: speedKmh,
        state: DrivingState.paused,
        accuracy: accuracy,
        isSim: isSim,
        message: 'Manual Pause active • Detection suspended',
        motionLabel: 'Detection Paused',
        assessment: assessment,
      );
      await CallScreeningManager.instance.syncDrivingState(false);
      await CallScreeningManager.instance.restoreRinger();
      return;
    }

    // 3. Weak signal (real GPS only without native sensor override)
    if (!isSim && forcedLabel == null && accuracy > 55.0) {
      _updateStatus(
        speed: speedKmh,
        state: DrivingState.uncertain,
        accuracy: accuracy,
        isSim: isSim,
        message: 'Weak GPS signal (±${accuracy.toStringAsFixed(0)}m) • Standing by',
        motionLabel: 'Weak GPS Signal',
        assessment: assessment,
      );
      return;
    }

    // 4. Exact Speed and Motion logic:
    // Speed >= 15.0 km/h => Driving Active => Enforce call screening
    // Speed < 15.0 km/h (walking, running, or stopped in traffic) => Not Driving => Calls ring freely, phone control restored
    if (speedKmh >= drivingSpeedThresholdKmh) {
      _updateStatus(
        speed: speedKmh,
        state: DrivingState.drivingActive,
        accuracy: accuracy,
        isSim: isSim,
        message: 'Driving Active (${speedKmh.toStringAsFixed(1)} km/h) • Screening rules enforced',
        motionLabel: forcedLabel ?? 'Driving (In Motion)',
        assessment: assessment,
      );
      await CallScreeningManager.instance.syncDrivingState(true);
    } else {
      String label = forcedLabel ??
          (speedKmh >= 6.0
              ? 'Running / Jogging'
              : (speedKmh >= 1.0 ? 'Walking' : 'Stopped in Traffic / Idle'));
      String msg;
      if (label.contains('Running') || label.contains('Jogging')) {
        msg = 'Running pace (${speedKmh.toStringAsFixed(1)} km/h) • Calls ring normally';
      } else if (label.contains('Walking')) {
        msg = 'Walking pace (${speedKmh.toStringAsFixed(1)} km/h) • Calls ring normally';
      } else {
        label = 'Stopped in Traffic / Idle';
        msg = 'Vehicle stopped in traffic / Idle • Calls ring normally';
      }

      _updateStatus(
        speed: speedKmh,
        state: DrivingState.normal,
        accuracy: accuracy,
        isSim: isSim,
        message: msg,
        motionLabel: label,
        assessment: assessment,
      );
      await CallScreeningManager.instance.syncDrivingState(false);
      await CallScreeningManager.instance.restoreRinger();
    }
  }

  void _updateStatus({
    required double speed,
    required DrivingState state,
    required double accuracy,
    bool isSim = false,
    required String message,
    required String motionLabel,
    required AiDrivingAssessment assessment,
  }) {
    _currentStatus = MovementStatus(
      speedKmh: speed,
      state: state,
      accuracy: accuracy,
      latitude: _lastLatitude,
      longitude: _lastLongitude,
      altitude: _lastAltitude,
      isSimulated: isSim,
      message: message,
      motionLabel: motionLabel,
      timestamp: DateTime.now(),
      assessment: assessment,
    );
    _statusController.add(_currentStatus);
  }

  void dispose() {
    stopTracking();
    _statusController.close();
  }
}
