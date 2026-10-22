import '../models/vehicle_type.dart';

class AiDrivingAssessment {
  final VehicleType vehicleType;
  final double confidence; // 0.0 to 1.0 (e.g. 0.94 = 94%)
  final bool isDriving;
  final String reasoning;
  final double speedKmh;
  final double accelerationMps2;

  const AiDrivingAssessment({
    required this.vehicleType,
    required this.confidence,
    required this.isDriving,
    required this.reasoning,
    required this.speedKmh,
    required this.accelerationMps2,
  });

  factory AiDrivingAssessment.idle() => const AiDrivingAssessment(
        vehicleType: VehicleType.stationary,
        confidence: 1.0,
        isDriving: false,
        reasoning: 'Device is at rest (0.0 km/h) • Idle mode',
        speedKmh: 0.0,
        accelerationMps2: 0.0,
      );
}

class AiVehicleClassifier {
  AiVehicleClassifier._();
  static final AiVehicleClassifier instance = AiVehicleClassifier._();

  VehicleType? _simulatedVehicleOverride;
  double _previousSpeedMs = 0.0;
  DateTime _lastTimestamp = DateTime.now();

  void setSimulatedVehicleOverride(VehicleType? type) {
    _simulatedVehicleOverride = type;
  }

  AiDrivingAssessment classify({
    required double currentSpeedKmh,
    required bool isPassengerMode,
    required bool isManualPause,
  }) {
    final now = DateTime.now();
    final elapsedSec = now.difference(_lastTimestamp).inMilliseconds / 1000.0;
    _lastTimestamp = now;

    final currentSpeedMs = currentSpeedKmh / 3.6;
    double acceleration = 0.0;
    if (elapsedSec > 0.1 && elapsedSec < 5.0) {
      acceleration = (currentSpeedMs - _previousSpeedMs) / elapsedSec;
    }
    _previousSpeedMs = currentSpeedMs;

    // 1. High-priority user context overrides
    if (isManualPause) {
      return AiDrivingAssessment(
        vehicleType: VehicleType.unknown,
        confidence: 1.0,
        isDriving: false,
        reasoning: 'Manual pause active • AI detection suspended',
        speedKmh: currentSpeedKmh,
        accelerationMps2: acceleration,
      );
    }

    if (isPassengerMode) {
      final detectedType = _simulatedVehicleOverride ??
          (currentSpeedKmh > 20.0 ? VehicleType.car : VehicleType.stationary);
      return AiDrivingAssessment(
        vehicleType: detectedType,
        confidence: 0.95,
        isDriving: false,
        reasoning: 'Passenger mode active • User is passenger • Calls ring freely',
        speedKmh: currentSpeedKmh,
        accelerationMps2: acceleration,
      );
    }

    // 2. Simulated preset vehicle override if chosen by tester
    if (_simulatedVehicleOverride != null) {
      final overrideType = _simulatedVehicleOverride!;
      final isVehicleDriving = overrideType.isMotorizedVehicle && currentSpeedKmh >= 15.0;
      return AiDrivingAssessment(
        vehicleType: overrideType,
        confidence: 0.98,
        isDriving: isVehicleDriving,
        reasoning: 'Simulated preset: ${overrideType.displayName} (${currentSpeedKmh.toStringAsFixed(1)} km/h)',
        speedKmh: currentSpeedKmh,
        accelerationMps2: acceleration,
      );
    }

    // 3. Core Benchmarks:
    // (a) Idle: 0 - 2 km/h
    if (currentSpeedKmh < 2.0) {
      return AiDrivingAssessment(
        vehicleType: VehicleType.stationary,
        confidence: 0.98,
        isDriving: false,
        reasoning: 'Stationary (0.0 km/h) • Device at rest',
        speedKmh: currentSpeedKmh,
        accelerationMps2: acceleration,
      );
    }

    // (b) Walking: 2 - 7 km/h
    if (currentSpeedKmh < 7.0) {
      return AiDrivingAssessment(
        vehicleType: VehicleType.walking,
        confidence: 0.94,
        isDriving: false,
        reasoning: 'Walking pace (${currentSpeedKmh.toStringAsFixed(1)} km/h) • Non-driving',
        speedKmh: currentSpeedKmh,
        accelerationMps2: acceleration,
      );
    }

    // (c) Running: 7 - 15 km/h
    if (currentSpeedKmh < 15.0) {
      return AiDrivingAssessment(
        vehicleType: VehicleType.running,
        confidence: 0.90,
        isDriving: false,
        reasoning: 'Running pace (${currentSpeedKmh.toStringAsFixed(1)} km/h) • Non-driving',
        speedKmh: currentSpeedKmh,
        accelerationMps2: acceleration,
      );
    }

    // (d) Bike / Two-Wheeler: 15 - 55 km/h
    if (currentSpeedKmh <= 55.0) {
      return AiDrivingAssessment(
        vehicleType: VehicleType.twoWheeler,
        confidence: 0.92,
        isDriving: true,
        reasoning: 'Two-Wheeler / Bike speed (${currentSpeedKmh.toStringAsFixed(1)} km/h) • Driving mode engaged',
        speedKmh: currentSpeedKmh,
        accelerationMps2: acceleration,
      );
    }

    // (e) Car: > 55 km/h
    return AiDrivingAssessment(
      vehicleType: VehicleType.car,
      confidence: 0.96,
      isDriving: true,
      reasoning: 'Car cruising speed (${currentSpeedKmh.toStringAsFixed(1)} km/h) • Driving mode engaged',
      speedKmh: currentSpeedKmh,
      accelerationMps2: acceleration,
    );
  }
}
