import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drivesafe/models/driving_state.dart';
import 'package:drivesafe/services/movement_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('MovementService Stub Tests', () {
    test('Simulated speed >= 15 km/h engages drivingActive state', () async {
      final service = MovementService.instance;
      service.setSimulatedSpeed(45.0);
      await Future.delayed(const Duration(milliseconds: 20));

      expect(service.currentStatus.state, DrivingState.drivingActive);
      expect(service.currentStatus.speedKmh, 45.0);
      expect(service.currentStatus.isSimulated, isTrue);
    });

    test('Simulated speed < 15 km/h remains in normal state', () async {
      final service = MovementService.instance;
      service.setSimulatedSpeed(5.0);
      await Future.delayed(const Duration(milliseconds: 20));

      expect(service.currentStatus.state, DrivingState.normal);
      expect(service.currentStatus.speedKmh, 5.0);
    });

    test('ResetToIdle resets state to normal and 0.0 km/h', () async {
      final service = MovementService.instance;
      await service.resetToIdle();

      expect(service.currentStatus.state, DrivingState.normal);
      expect(service.currentStatus.speedKmh, 0.0);
      expect(service.currentStatus.isSimulated, isFalse);
    });
  });
}
