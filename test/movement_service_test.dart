import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drivesafe/models/driving_state.dart';
import 'package:drivesafe/services/movement_service.dart';
import 'package:drivesafe/services/preference_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('MovementService State Machine Tests', () {
    test('Simulated high speed activates DrivingState.drivingActive', () async {
      final service = MovementService.instance;
      service.setSimulatedSpeed(45.0);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(service.currentStatus.state, DrivingState.drivingActive);
      expect(service.currentStatus.speedKmh, 45.0);
      expect(service.currentStatus.isSimulated, isTrue);
    });

    test('Passenger mode overrides speed and forces DrivingState.passenger', () async {
      final service = MovementService.instance;
      await PreferenceService.instance.saveSetting('passengerMode', true);

      service.setSimulatedSpeed(60.0);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(service.currentStatus.state, DrivingState.passenger);
    });

    test('Manual pause overrides speed and forces DrivingState.paused', () async {
      final service = MovementService.instance;
      await PreferenceService.instance.saveSetting('passengerMode', false);
      await PreferenceService.instance.saveSetting('manualPause', true);

      service.setSimulatedSpeed(50.0);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(service.currentStatus.state, DrivingState.paused);
    });

    test('Stationary speed returns DrivingState.normal when starting from idle', () async {
      final service = MovementService.instance;
      await PreferenceService.instance.saveSetting('passengerMode', false);
      await PreferenceService.instance.saveSetting('manualPause', false);

      service.setSimulatedSpeed(0.0);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(service.currentStatus.state, DrivingState.normal);
      expect(service.currentStatus.speedKmh, 0.0);
    });
  });
}
