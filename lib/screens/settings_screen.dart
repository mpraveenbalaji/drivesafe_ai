import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/call_screening_service.dart';
import '../services/preference_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = true;
  bool passengerMode = false;
  bool _contactsGranted = false;
  bool _phoneGranted = false;
  bool _screeningRoleGranted = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await PreferenceService.instance.loadSettings();
    final contacts = await Permission.contacts.isGranted;
    final phone = await Permission.phone.isGranted;
    final role = await CallScreeningManager.instance.isRoleGranted();

    if (mounted) {
      setState(() {
        passengerMode = settings['passengerMode'] ?? false;
        _contactsGranted = contacts;
        _phoneGranted = phone;
        _screeningRoleGranted = role;
        _isLoading = false;
      });
    }
  }

  Future<void> _updatePassengerMode(bool value) async {
    setState(() => passengerMode = value);
    await PreferenceService.instance.saveSetting('passengerMode', value);
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF176B52);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: bottomInset + 24),
                children: [
                  // Passenger Mode Card
                  Card(
                    elevation: 0,
                    color: Colors.white,
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
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.airline_seat_recline_normal, color: Color(0xFFD97706), size: 24),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Passenger Mode',
                                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Switch(
                                value: passengerMode,
                                activeThumbColor: green,
                                onChanged: _updatePassengerMode,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Turn this ON when travelling as a passenger in a cab, bus, or car. '
                            'Your incoming calls will ring normally without being screened or silenced.',
                            style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),
                  const Text(
                    'App Permissions & Protection',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),

                  // Permissions Card
                  Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(
                            _contactsGranted ? Icons.check_circle : Icons.warning_amber_rounded,
                            color: _contactsGranted ? const Color(0xFF15803D) : Colors.red,
                          ),
                          title: const Text('Contacts Access', style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            _contactsGranted ? 'Granted • Saved contacts recognized' : 'Missing • Cannot identify saved contacts',
                            style: TextStyle(fontSize: 12, color: _contactsGranted ? Colors.black54 : Colors.red),
                          ),
                          trailing: !_contactsGranted
                              ? TextButton(
                                  onPressed: () async {
                                    await Permission.contacts.request();
                                    _loadSettings();
                                  },
                                  child: const Text('Grant'),
                                )
                              : null,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(
                            _phoneGranted ? Icons.check_circle : Icons.warning_amber_rounded,
                            color: _phoneGranted ? const Color(0xFF15803D) : Colors.red,
                          ),
                          title: const Text('Phone State Access', style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            _phoneGranted ? 'Granted • Call detection active' : 'Missing • Cannot detect incoming calls',
                            style: TextStyle(fontSize: 12, color: _phoneGranted ? Colors.black54 : Colors.red),
                          ),
                          trailing: !_phoneGranted
                              ? TextButton(
                                  onPressed: () async {
                                    await Permission.phone.request();
                                    _loadSettings();
                                  },
                                  child: const Text('Grant'),
                                )
                              : null,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(
                            _screeningRoleGranted ? Icons.check_circle : Icons.shield_outlined,
                            color: _screeningRoleGranted ? const Color(0xFF15803D) : const Color(0xFF2563EB),
                          ),
                          title: const Text('Call Screening Role', style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            _screeningRoleGranted ? 'Active • System telecom screening enabled' : 'Not set • Tap to set as screening app',
                            style: TextStyle(fontSize: 12, color: _screeningRoleGranted ? Colors.black54 : const Color(0xFF2563EB)),
                          ),
                          trailing: !_screeningRoleGranted
                              ? TextButton(
                                  onPressed: () async {
                                    await CallScreeningManager.instance.requestRole();
                                    _loadSettings();
                                  },
                                  child: const Text('Enable'),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  // About & Logo
                  Center(
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset(
                            'assets/logo_circle.png',
                            width: 64,
                            height: 64,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'DriveSafe AI v1.0.0',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'AI-Powered Driving Detection & Call Screening',
                          style: TextStyle(color: Colors.black45, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
