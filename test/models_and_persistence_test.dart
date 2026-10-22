import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drivesafe/models/call_record.dart';
import 'package:drivesafe/models/call_rule.dart';
import 'package:drivesafe/models/driving_state.dart';
import 'package:drivesafe/services/preference_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DrivingState Model Tests', () {
    test('DrivingState display names and screening active flags', () {
      expect(DrivingState.normal.displayName, 'Idle');
      expect(DrivingState.normal.isScreeningActive, isFalse);

      expect(DrivingState.drivingActive.displayName, 'Driving Active');
      expect(DrivingState.drivingActive.isScreeningActive, isTrue);

      expect(DrivingState.passenger.displayName, 'Passenger Mode');
      expect(DrivingState.passenger.isScreeningActive, isFalse);
    });
  });

  group('CallRules Model Tests', () {
    test('CallAction label conversions', () {
      expect(CallAction.silence.label, 'Silence');
      expect(CallAction.reject.label, 'Reject');
      expect(CallAction.allow.label, 'Allow');
      expect(CallAction.askMe.label, 'Silence');

      expect(CallActionX.fromLabel('Silence'), CallAction.silence);
      expect(CallActionX.fromLabel('Reject'), CallAction.reject);
      expect(CallActionX.fromLabel('Allow'), CallAction.allow);
      expect(CallActionX.fromLabel('Ask me'), CallAction.silence);
    });
  });

  group('CallRecord Model Tests', () {
    test('JSON serialization and deserialization roundtrip', () {
      final now = DateTime.now();
      final record = CallRecord(
        id: 'test-1',
        callerNumber: '+1 (555) 019-99',
        callerName: 'Mom',
        category: 'Saved Contact',
        actionTaken: 'Allowed',
        timestamp: now,
        note: 'Urgent call',
      );

      final json = record.toJson();
      final parsed = CallRecord.fromJson(json);

      expect(parsed.id, record.id);
      expect(parsed.callerNumber, record.callerNumber);
      expect(parsed.callerName, record.callerName);
      expect(parsed.category, record.category);
      expect(parsed.actionTaken, record.actionTaken);
      expect(parsed.note, record.note);
    });
  });

  group('PreferenceService Tests', () {
    test('Saves and loads CallRules', () async {
      final service = PreferenceService.instance;
      const customConfig = CallRulesConfig(
        spamAction: CallAction.reject,
        contactAction: CallAction.allow,
        unknownAction: CallAction.silence,
      );

      await service.saveCallRules(customConfig);
      final loaded = await service.loadCallRules();

      expect(loaded.spamAction, CallAction.reject);
      expect(loaded.contactAction, CallAction.allow);
      expect(loaded.unknownAction, CallAction.silence);
    });

    test('Saves and loads Settings', () async {
      final service = PreferenceService.instance;
      await service.saveSetting('passengerMode', true);
      await service.saveSetting('manualPause', true);

      final settings = await service.loadSettings();
      expect(settings['passengerMode'], isTrue);
      expect(settings['manualPause'], isTrue);
      expect(settings['unknownCallAlerts'], isTrue); // default
    });

    test('Adds and clears Call Records in history', () async {
      final service = PreferenceService.instance;
      final record = CallRecord(
        id: '123',
        callerNumber: '+15551234',
        callerName: 'Spam Robo',
        category: 'Spam',
        actionTaken: 'Rejected',
        timestamp: DateTime.now(),
      );

      await service.addCallRecord(record);
      var history = await service.loadCallHistory();
      expect(history.length, 1);
      expect(history.first.callerNumber, '+15551234');

      await service.clearCallHistory();
      history = await service.loadCallHistory();
      expect(history, isEmpty);
    });
  });
}
