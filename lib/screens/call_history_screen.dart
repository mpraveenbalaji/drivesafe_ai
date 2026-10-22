import 'package:flutter/material.dart';
import '../models/call_record.dart';
import '../services/preference_service.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  bool _isLoading = true;
  List<CallRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await PreferenceService.instance.loadCallHistory();
    if (mounted) {
      setState(() {
        _records = history;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteSingleRecord(String id) async {
    await PreferenceService.instance.deleteCallRecord(id);
    await _loadHistory();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Call log deleted'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _clearHistory() async {
    await PreferenceService.instance.clearCallHistory();
    await _loadHistory();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All call screening history cleared'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour == 0 ? 12 : (local.hour > 12 ? local.hour - 12 : local.hour);
    final minute = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final monthStr = months[local.month - 1];
    return '${local.day} $monthStr ${local.year}, $hour:$minute $ampm';
  }

  IconData _iconForAction(String action) {
    final lower = action.toLowerCase();
    if (lower.contains('silence') || lower.contains('silenced')) {
      return Icons.volume_off_outlined;
    } else if (lower.contains('reject') || lower.contains('rejected')) {
      return Icons.phone_disabled_outlined;
    }
    return Icons.phone_in_talk_outlined;
  }

  Color _colorForAction(String action) {
    final lower = action.toLowerCase();
    if (lower.contains('silence') || lower.contains('silenced')) {
      return const Color(0xFFD97706);
    } else if (lower.contains('reject') || lower.contains('rejected')) {
      return const Color(0xFFDC2626);
    }
    return const Color(0xFF16A34A);
  }

  String _cleanActionLabel(String action) {
    final lower = action.toLowerCase();
    if (lower.contains('silenced')) return 'Silenced';
    if (lower.contains('rejected')) return 'Rejected';
    if (lower.contains('allowed')) return 'Allowed';
    return action;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Call History', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF176B52)),
            tooltip: 'Refresh History',
            onPressed: () async {
              setState(() => _isLoading = true);
              await _loadHistory();
            },
          ),
          if (_records.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
              tooltip: 'Clear All History',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear All Call History?'),
                    content: const Text('This will delete all logged call screening records. This cannot be undone.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Delete All'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _clearHistory();
                }
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadHistory,
              child: _records.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.history_toggle_off_outlined,
                              size: 64,
                              color: Colors.black.withValues(alpha: 0.25),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No call screening events yet',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Calls screened during driving mode will be automatically recorded here with date, time, caller type, and actions taken.\n\nTip: Pull down or tap 🔄 to refresh.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SafeArea(
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: bottomInset + 30),
                        itemCount: _records.length,
                        itemBuilder: (context, index) {
                      final item = _records[index];
                      final actionColor = _colorForAction(item.actionTaken);
                      final displayAction = _cleanActionLabel(item.actionTaken);

                      return Card(
                        elevation: 0,
                        color: Colors.white,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: actionColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _iconForAction(item.actionTaken),
                                  color: actionColor,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.callerName ?? item.callerNumber,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: actionColor.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            displayAction,
                                            style: TextStyle(
                                              color: actionColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${item.callerNumber} • ${item.category}',
                                      style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.schedule, size: 12, color: Colors.black45),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatDateTime(item.timestamp),
                                          style: const TextStyle(color: Colors.black54, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                    if (item.note != null && item.note!.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        item.note!,
                                        style: TextStyle(color: Colors.grey[600], fontSize: 11, fontStyle: FontStyle.italic),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.black38),
                                tooltip: 'Delete this record',
                                onPressed: () => _deleteSingleRecord(item.id),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ),
    );
  }
}
