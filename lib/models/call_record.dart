class CallRecord {
  final String id;
  final String callerNumber;
  final String? callerName;
  final String category; // 'Spam', 'Saved Contact', 'Unknown'
  final String actionTaken; // 'Silenced', 'Rejected', 'Allowed'
  final DateTime timestamp;
  final String? note;

  const CallRecord({
    required this.id,
    required this.callerNumber,
    this.callerName,
    required this.category,
    required this.actionTaken,
    required this.timestamp,
    this.note,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'callerNumber': callerNumber,
    'callerName': callerName,
    'category': category,
    'actionTaken': actionTaken,
    'timestamp': timestamp.toIso8601String(),
    'note': note,
  };

  factory CallRecord.fromJson(Map<String, dynamic> json) => CallRecord(
    id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
    callerNumber: json['callerNumber']?.toString() ?? '',
    callerName: json['callerName']?.toString(),
    category: json['category']?.toString() ?? 'Unknown',
    actionTaken: json['actionTaken']?.toString() ?? 'Allowed',
    timestamp: json['timestampMs'] != null
        ? DateTime.fromMillisecondsSinceEpoch((json['timestampMs'] as num).toInt()).toLocal()
        : (json['timestamp'] != null
            ? (DateTime.tryParse(json['timestamp'].toString())?.toLocal() ?? DateTime.now())
            : DateTime.now()),
    note: json['note']?.toString(),
  );
}
