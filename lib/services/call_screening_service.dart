import 'package:flutter/services.dart';

class CallScreeningManager {
  static const MethodChannel _channel = MethodChannel('drivesafe_ai/call_screening');

  CallScreeningManager._();
  static final CallScreeningManager instance = CallScreeningManager._();

  void initMotionChannel(Function(Map<String, dynamic>) onMotionUpdate) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onNativeMotionUpdate') {
        if (call.arguments is Map) {
          final data = Map<String, dynamic>.from(call.arguments as Map);
          onMotionUpdate(data);
        }
      }
    });
  }

  Future<void> startNativeMotionTracking() async {
    try {
      await _channel.invokeMethod('startNativeMotionTracking');
    } catch (_) {}
  }

  Future<void> stopNativeMotionTracking() async {
    try {
      await _channel.invokeMethod('stopNativeMotionTracking');
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> getNativeMotionStatus() async {
    try {
      final res = await _channel.invokeMethod<Map>('getNativeMotionStatus');
      if (res != null) {
        return Map<String, dynamic>.from(res);
      }
    } catch (_) {}
    return null;
  }

  /// Checks if the Android system has granted ROLE_CALL_SCREENING to this app.
  Future<bool> isRoleGranted() async {
    try {
      final bool? granted = await _channel.invokeMethod<bool>('isRoleGranted');
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Requests the user to set DriveSafe AI as their Call Screening app.
  Future<bool> requestRole() async {
    try {
      final bool? granted = await _channel.invokeMethod<bool>('requestRole');
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Synchronizes whether driving mode is currently active to native Android SharedPreferences.
  Future<void> syncDrivingState(bool isActive) async {
    try {
      await _channel.invokeMethod('syncDrivingState', {'isActive': isActive});
    } catch (_) {}
  }

  /// Restores device ringer mode to normal and un-mutes ringer stream.
  Future<void> restoreRinger() async {
    try {
      await _channel.invokeMethod('restoreRinger');
    } catch (_) {}
  }

  /// Fetches real contacts from device contacts database.
  Future<List<Map<String, String>>> getDeviceContacts() async {
    try {
      final List<dynamic>? list = await _channel.invokeMethod('getDeviceContacts');
      if (list == null) return [];
      return list.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return {
          'name': map['name']?.toString() ?? 'Contact',
          'number': map['number']?.toString() ?? '',
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Opens Google Maps with coordinates.
  Future<void> openMap({required double latitude, required double longitude}) async {
    try {
      await _channel.invokeMethod('openMap', {'lat': latitude, 'lng': longitude});
    } catch (_) {}
  }

  /// Checks if contacts, phone, and call log permissions are granted.
  Future<bool> areNativePermissionsGranted() async {
    try {
      final bool? granted = await _channel.invokeMethod<bool>('areNativePermissionsGranted');
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Fetches raw JSON history directly from native Android SharedPreferences.
  Future<String?> getNativeCallHistory() async {
    try {
      final String? history = await _channel.invokeMethod<String>('getCallHistory');
      return history;
    } catch (_) {
      return null;
    }
  }

  /// Requests all necessary phone, contact, and call log permissions directly.
  Future<void> requestNativePermissions() async {
    try {
      await _channel.invokeMethod('requestNativePermissions');
    } catch (_) {}
  }
}
