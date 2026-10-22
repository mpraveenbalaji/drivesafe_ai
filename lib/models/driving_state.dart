/// Represents the current travel and driver state of the user.
enum DrivingState {
  /// Stationary, walking, or at rest.
  normal,

  /// Movement or acceleration detected; evaluating if vehicle travel is sustained.
  vehicleCandidate,

  /// Driving confirmed. Active call handling policies are applied.
  drivingActive,

  /// Signal is weak, sensors are intermittent, or state is ambiguous.
  uncertain,

  /// User flagged themselves as a passenger; driver suppression rules are bypassed.
  passenger,

  /// Manually paused by the user for a temporary session.
  paused,
}

extension DrivingStateX on DrivingState {
  String get displayName {
    switch (this) {
      case DrivingState.normal:
        return 'Idle';
      case DrivingState.vehicleCandidate:
        return 'Detecting Movement';
      case DrivingState.drivingActive:
        return 'Driving Active';
      case DrivingState.uncertain:
        return 'Uncertain State';
      case DrivingState.passenger:
        return 'Passenger Mode';
      case DrivingState.paused:
        return 'Paused';
    }
  }

  bool get isScreeningActive => this == DrivingState.drivingActive;
}
