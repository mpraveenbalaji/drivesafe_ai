import 'dart:async';
import '../models/driving_state.dart';
import '../models/vehicle_type.dart';
import 'ai_vehicle_classifier.dart';

/// Represents current movement and driving evaluation status.
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

/// Stub implementation of MovementService.
/// Core proprietary GPS tracking, Doppler filtering, and Kalman smoothing algorithms removed.
class MovementService {
  MovementService._();
  static final MovementService instance = MovementService._();

  final _statusController = StreamController<MovementStatus>.broadcast();
  Stream<MovementStatus> get statusStream => _statusController.stream;

  MovementStatus _currentStatus = MovementStatus.idle();
  MovementStatus get currentStatus => _currentStatus;

  bool _isListening = false;
  bool get isListening => _isListening;

  bool _isSimulatedMode = false;
  bool get isSimulatedMode => _isSimulatedMode;

  static const double drivingSpeedThresholdKmh = 15.0;

  /// Initializes integration with native sensor engine.
  void initNativeMotionIntegration() {
    // TODO: Connect native accelerometer and step sensor streams here.
  }

  /// Handles incoming motion events from native Android sensors.
  void handleNativeMotionUpdate(Map<String, dynamic> data) {
    // TODO: Process hardware motion updates here.
  }

  /// Starts listening to device GPS position stream.
  Future<bool> startTracking() async {
    // TODO: Implement GPS permissions, stream subscription, and location filtering here.
    _isListening = true;
    _isSimulatedMode = false;

    _emitStatus(
      speed: 0.0,
      state: DrivingState.normal,
      accuracy: 5.0,
      isSim: false,
      message: 'GPS tracking active (Stub mode) • Ready',
      motionLabel: 'GPS Active',
    );
    return true;
  }

  /// Stops tracking GPS.
  Future<void> stopTracking() async {
    // TODO: Cancel GPS stream subscriptions and release wake locks here.
    _isListening = false;
    _emitStatus(
      speed: 0.0,
      state: DrivingState.normal,
      accuracy: 0.0,
      isSim: false,
      message: 'GPS tracking stopped',
      motionLabel: 'Stopped',
    );
  }

  /// Sets simulated speed for UI testing.
  void setSimulatedSpeed(double speedKmh, [VehicleType? vehicleType]) {
    _isSimulatedMode = true;
    final bool isDriving = speedKmh >= drivingSpeedThresholdKmh;

    final assessment = AiVehicleClassifier.instance.classify(
      currentSpeedKmh: speedKmh,
      isPassengerMode: false,
      isManualPause: false,
    );

    _emitStatus(
      speed: speedKmh,
      state: isDriving ? DrivingState.drivingActive : DrivingState.normal,
      accuracy: 5.0,
      isSim: true,
      message: isDriving
          ? 'Driving Active (${speedKmh.toStringAsFixed(1)} km/h) • Rules enforced'
          : 'Speed: ${speedKmh.toStringAsFixed(1)} km/h • Calls ring normally',
      motionLabel: isDriving ? 'Driving (Simulated)' : 'Idle / Low Speed',
      assessment: assessment,
    );
  }

  /// Resets everything to 0.0 km/h and Idle.
  Future<void> resetToIdle() async {
    _isSimulatedMode = false;
    _emitStatus(
      speed: 0.0,
      state: DrivingState.normal,
      accuracy: 0.0,
      isSim: false,
      message: 'Stationary / Stopped in traffic • Calls ring normally',
      motionLabel: 'Idle / Stopped in Traffic',
    );
  }

  void _emitStatus({
    required double speed,
    required DrivingState state,
    required double accuracy,
    bool isSim = false,
    required String message,
    required String motionLabel,
    AiDrivingAssessment? assessment,
  }) {
    _currentStatus = MovementStatus(
      speedKmh: speed,
      state: state,
      accuracy: accuracy,
      latitude: null,
      longitude: null,
      altitude: null,
      isSimulated: isSim,
      message: message,
      motionLabel: motionLabel,
      timestamp: DateTime.now(),
      assessment: assessment ?? AiDrivingAssessment.idle(),
    );
    _statusController.add(_currentStatus);
  }

  void dispose() {
    stopTracking();
    _statusController.close();
  }
}
