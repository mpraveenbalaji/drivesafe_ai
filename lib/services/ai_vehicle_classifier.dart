import '../models/vehicle_type.dart';

/// Assessment result model for vehicle classification.
class AiDrivingAssessment {
  final VehicleType vehicleType;
  final double confidence;
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
        reasoning: 'Idle mode • Waiting for movement',
        speedKmh: 0.0,
        accelerationMps2: 0.0,
      );
}

/// Stub implementation of AI Vehicle Classifier.
/// Core proprietary classification algorithms removed.
class AiVehicleClassifier {
  AiVehicleClassifier._();
  static final AiVehicleClassifier instance = AiVehicleClassifier._();

  VehicleType? _simulatedVehicleOverride;

  void setSimulatedVehicleOverride(VehicleType? type) {
    _simulatedVehicleOverride = type;
  }

  /// Classifies current motion into vehicle type and driving state.
  AiDrivingAssessment classify({
    required double currentSpeedKmh,
    required bool isPassengerMode,
    required bool isManualPause,
  }) {
    // TODO: Implement your custom vehicle classification and ML model inference here.
    // This is a stub placeholder for open collaboration.

    if (isManualPause || isPassengerMode) {
      return AiDrivingAssessment(
        vehicleType: _simulatedVehicleOverride ?? VehicleType.stationary,
        confidence: 0.0,
        isDriving: false,
        reasoning: isManualPause ? 'Manual pause enabled' : 'Passenger mode enabled',
        speedKmh: currentSpeedKmh,
        accelerationMps2: 0.0,
      );
    }

    final bool isDrivingMock = currentSpeedKmh >= 15.0;
    return AiDrivingAssessment(
      vehicleType: _simulatedVehicleOverride ??
          (isDrivingMock ? VehicleType.car : VehicleType.stationary),
      confidence: 0.5,
      isDriving: isDrivingMock,
      reasoning: 'Stub classifier: Speed = ${currentSpeedKmh.toStringAsFixed(1)} km/h',
      speedKmh: currentSpeedKmh,
      accelerationMps2: 0.0,
    );
  }
}
