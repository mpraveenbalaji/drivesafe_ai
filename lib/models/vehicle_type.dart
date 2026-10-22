import 'package:flutter/material.dart';

enum VehicleType {
  stationary,
  walking,
  running,
  twoWheeler,
  car,
  unknown,
}

extension VehicleTypeX on VehicleType {
  String get displayName {
    switch (this) {
      case VehicleType.stationary:
        return 'Idle (No Motion)';
      case VehicleType.walking:
        return 'Walking (Pedestrian)';
      case VehicleType.running:
        return 'Running / Jogging';
      case VehicleType.twoWheeler:
        return 'Bike / Two-Wheeler';
      case VehicleType.car:
        return 'Car / Automobile';
      case VehicleType.unknown:
        return 'Analyzing Motion...';
    }
  }

  String get shortLabel {
    switch (this) {
      case VehicleType.twoWheeler:
        return '🏍️ BIKE';
      case VehicleType.car:
        return '🚗 CAR';
      case VehicleType.running:
        return '🏃 RUNNING';
      case VehicleType.walking:
        return '🚶 WALKING';
      case VehicleType.stationary:
        return '🛑 IDLE';
      case VehicleType.unknown:
        return '🔍 ANALYZING';
    }
  }

  IconData get icon {
    switch (this) {
      case VehicleType.twoWheeler:
        return Icons.two_wheeler;
      case VehicleType.car:
        return Icons.directions_car;
      case VehicleType.running:
        return Icons.directions_run;
      case VehicleType.walking:
        return Icons.directions_walk;
      case VehicleType.stationary:
        return Icons.pause_circle_outline;
      case VehicleType.unknown:
        return Icons.shield_outlined;
    }
  }

  bool get isMotorizedVehicle =>
      this == VehicleType.twoWheeler || this == VehicleType.car;
}
