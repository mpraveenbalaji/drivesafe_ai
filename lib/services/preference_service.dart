import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/call_record.dart';
import '../models/call_rule.dart';
import 'call_screening_service.dart';

class PreferenceService {
  static const _keySpamAction = 'rule_spam_action';
  static const _keyContactAction = 'rule_contact_action';
  static const _keyUnknownAction = 'rule_unknown_action';

  static const _keyPassengerMode = 'setting_passenger_mode';
  static const _keyUnknownAlerts = 'setting_unknown_alerts';
  static const _keyManualPause = 'setting_manual_pause';

  static const _keyCallHistory = 'call_history_records';

  PreferenceService._();
  static final PreferenceService instance = PreferenceService._();

  Future<CallRulesConfig> loadCallRules() async {
    final prefs = await SharedPreferences.getInstance();
    final spam = prefs.getString(_keySpamAction) ?? CallAction.silence.label;
    final contact = prefs.getString(_keyContactAction) ?? CallAction.allow.label;
    final unknown = prefs.getString(_keyUnknownAction) ?? CallAction.silence.label;

    return CallRulesConfig(
      spamAction: CallActionX.fromLabel(spam),
      contactAction: CallActionX.fromLabel(contact),
      unknownAction: CallActionX.fromLabel(unknown),
    );
  }

  Future<void> saveCallRules(CallRulesConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySpamAction, config.spamAction.label);
    await prefs.setString(_keyContactAction, config.contactAction.label);
    await prefs.setString(_keyUnknownAction, config.unknownAction.label);
  }

  Future<Map<String, bool>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'passengerMode': prefs.getBool(_keyPassengerMode) ?? false,
      'unknownCallAlerts': prefs.getBool(_keyUnknownAlerts) ?? true,
      'manualPause': prefs.getBool(_keyManualPause) ?? false,
    };
  }

  Future<void> saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    switch (key) {
      case 'passengerMode':
        await prefs.setBool(_keyPassengerMode, value);
        break;
      case 'unknownCallAlerts':
        await prefs.setBool(_keyUnknownAlerts, value);
        break;
      case 'manualPause':
        await prefs.setBool(_keyManualPause, value);
        break;
    }
  }

  Future<List<CallRecord>> loadCallHistory() async {
    // 1. Direct Native Query (bypasses all Dart isolate SharedPreferences caching)
    try {
      final nativeJson = await CallScreeningManager.instance.getNativeCallHistory();
      if (nativeJson != null && nativeJson.trim().isNotEmpty && nativeJson != '[]') {
        final decoded = jsonDecode(nativeJson);
        if (decoded is List && decoded.isNotEmpty) {
          final List<CallRecord> records = [];
          for (final item in decoded) {
            try {
              if (item is String) {
                records.add(CallRecord.fromJson(jsonDecode(item) as Map<String, dynamic>));
              } else if (item is Map) {
                records.add(CallRecord.fromJson(Map<String, dynamic>.from(item)));
              }
            } catch (_) {}
          }
          if (records.isNotEmpty) return records;
        }
      }
    } catch (_) {}

    // 2. Primary fallback: Force reload of SharedPreferences from disk
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    // Read JSON String (written by Kotlin CallHelper or Dart)
    final jsonString = prefs.getString(_keyCallHistory);
    if (jsonString != null && jsonString.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(jsonString);
        if (decoded is List) {
          final List<CallRecord> records = [];
          for (final item in decoded) {
            try {
              if (item is String) {
                records.add(CallRecord.fromJson(jsonDecode(item) as Map<String, dynamic>));
              } else if (item is Map) {
                records.add(CallRecord.fromJson(Map<String, dynamic>.from(item)));
              }
            } catch (_) {}
          }
          return records;
        }
      } catch (_) {}
    }

    // 3. String list fallback
    try {
      final rawList = prefs.getStringList(_keyCallHistory);
      if (rawList != null && rawList.isNotEmpty) {
        return rawList
            .map((item) => CallRecord.fromJson(jsonDecode(item) as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    return [];
  }

  Future<void> addCallRecord(CallRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await loadCallHistory();
    history.insert(0, record);

    // Save as standard JSON string readable by both native Android & Flutter
    final jsonArray = history.map((r) => r.toJson()).toList();
    await prefs.setString(_keyCallHistory, jsonEncode(jsonArray));
  }

  Future<void> deleteCallRecord(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await loadCallHistory();
    history.removeWhere((r) => r.id == id);

    final jsonArray = history.map((r) => r.toJson()).toList();
    await prefs.setString(_keyCallHistory, jsonEncode(jsonArray));
  }

  Future<void> clearCallHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCallHistory);
  }
}
