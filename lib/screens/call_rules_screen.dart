import 'package:flutter/material.dart';
import '../models/call_rule.dart';
import '../models/vehicle_type.dart';
import '../services/movement_service.dart';
import '../services/preference_service.dart';

class CallRulesScreen extends StatefulWidget {
  const CallRulesScreen({super.key});

  @override
  State<CallRulesScreen> createState() => _CallRulesScreenState();
}

class _CallRulesScreenState extends State<CallRulesScreen> {
  bool _isLoading = true;
  String spamAction = 'Silence';
  String contactAction = 'Allow';
  String unknownAction = 'Silence';

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    final rules = await PreferenceService.instance.loadCallRules();
    setState(() {
      spamAction = rules.spamAction.label;
      contactAction = rules.contactAction.label;
      unknownAction = rules.unknownAction.label;
      if (unknownAction == 'Ask me') {
        unknownAction = 'Silence';
      }
      _isLoading = false;
    });
    if (rules.unknownAction == CallAction.askMe) {
      _saveRules();
    }
  }

  Future<void> _saveRules() async {
    final config = CallRulesConfig(
      spamAction: CallActionX.fromLabel(spamAction),
      contactAction: CallActionX.fromLabel(contactAction),
      unknownAction: CallActionX.fromLabel(unknownAction),
    );
    await PreferenceService.instance.saveCallRules(config);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Call rules saved successfully'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Widget ruleCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF176B52).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: const Color(0xFF176B52), size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: value,
              decoration: InputDecoration(
                labelText: 'Preferred Action',
                filled: true,
                fillColor: const Color(0xFFF9FAF9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.15)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              items: options
                  .map(
                    (option) => DropdownMenuItem(
                      value: option,
                      child: Text(option),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Call Rules', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Driving State & Quick Test Banner
                StreamBuilder<MovementStatus>(
                  stream: MovementService.instance.statusStream,
                  initialData: MovementService.instance.currentStatus,
                  builder: (context, snapshot) {
                    final status = snapshot.data ?? MovementService.instance.currentStatus;
                    final isDriving = status.speedKmh >= 15.0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDriving ? const Color(0xFFE7F2ED) : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDriving ? const Color(0xFF176B52).withValues(alpha: 0.3) : const Color(0xFFFDE68A),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isDriving ? Icons.navigation : Icons.pause_circle_outline,
                            color: isDriving ? const Color(0xFF176B52) : const Color(0xFFD97706),
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isDriving
                                      ? '🚗 DRIVING ACTIVE (${status.speedKmh.toStringAsFixed(1)} km/h)'
                                      : '🛑 STOPPED / AT REST (${status.speedKmh.toStringAsFixed(1)} km/h)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isDriving ? const Color(0xFF0F4736) : const Color(0xFF92400E),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isDriving
                                      ? 'Rules enforced • Incoming calls will be screened'
                                      : 'Speed < 15 km/h • Calls ring freely without screening',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDriving ? const Color(0xFF176B52) : const Color(0xFFB45309),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              backgroundColor: isDriving ? Colors.red.withValues(alpha: 0.15) : const Color(0xFF176B52).withValues(alpha: 0.15),
                              foregroundColor: isDriving ? Colors.red : const Color(0xFF176B52),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () {
                              if (isDriving) {
                                MovementService.instance.setSimulatedSpeed(0.0, VehicleType.stationary);
                              } else {
                                MovementService.instance.setSimulatedSpeed(35.0, VehicleType.twoWheeler);
                              }
                            },
                            child: Text(
                              isDriving ? 'Stop' : 'Test Drive',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const Text(
                  'Choose how DriveSafe AI should handle different callers while driving.',
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 14),
                ruleCard(
                  icon: Icons.report_gmailerrorred_outlined,
                  title: 'Spam Calls',
                  subtitle: 'Numbers identified as suspected telemarketers or spam',
                  value: spamAction,
                  options: const ['Allow', 'Silence', 'Reject'],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => spamAction = value);
                      _saveRules();
                    }
                  },
                ),
                ruleCard(
                  icon: Icons.contacts_outlined,
                  title: 'Saved Contacts',
                  subtitle: 'People saved in your address book',
                  value: contactAction,
                  options: const ['Allow', 'Silence', 'Reject'],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => contactAction = value);
                      _saveRules();
                    }
                  },
                ),
                ruleCard(
                  icon: Icons.phone_callback_outlined,
                  title: 'Unknown Callers',
                  subtitle: 'Numbers not present in your contact list',
                  value: unknownAction,
                  options: const ['Allow', 'Silence', 'Reject'],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => unknownAction = value);
                      _saveRules();
                    }
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7F2ED),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined, color: Color(0xFF176B52), size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Safety Guarantee: Emergency calls (e.g. 911, 112) will NEVER be '
                          'intercepted, silenced, or rejected under any rule.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF0F4736),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
