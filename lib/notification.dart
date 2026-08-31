import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

// 📦 Firebase schema ที่หน้านี้คาดหวัง:
// water_system/notifications/{pushId}: {
//   title: <string>,
//   message: <string>,
//   type: 'critical' | 'warning' | 'info',   // กำหนดสี/ไอคอนของการ์ด
//   timestamp: <number>,                      // milliseconds since epoch
//   is_read: <bool>,
// }
class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationItem {
  final String id;
  final String title;
  final String message;
  final String type;
  final int timestamp;
  final bool isRead;

  _NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
    required this.isRead,
  });
}

class _NotificationPageState extends State<NotificationPage> {
  final DatabaseReference _notiRef = FirebaseDatabase.instance.ref(
    'water_system/notifications',
  );
  StreamSubscription<DatabaseEvent>? _notiSubscription;

  bool _isLoading = true;
  List<_NotificationItem> _notifications = [];

  @override
  void initState() {
    super.initState();
    _notiSubscription = _notiRef.onValue.listen(
      (event) {
        if (!mounted) return;

        final rootValue = event.snapshot.value;
        final List<_NotificationItem> parsed = [];

        if (rootValue != null) {
          try {
            final rootData = Map<dynamic, dynamic>.from(rootValue as Map);
            rootData.forEach((key, value) {
              final entry = Map<dynamic, dynamic>.from(value as Map);
              final rawTimestamp = entry['timestamp'];
              parsed.add(
                _NotificationItem(
                  id: key.toString(),
                  title: (entry['title'] ?? 'แจ้งเตือน').toString(),
                  message: (entry['message'] ?? '').toString(),
                  type: (entry['type'] ?? 'info').toString(),
                  timestamp: rawTimestamp is num ? rawTimestamp.toInt() : 0,
                  isRead: entry['is_read'] == true,
                ),
              );
            });
          } catch (e) {
            debugPrint('Error parsing Firebase notifications data: $e');
          }
        }

        parsed.sort((a, b) => b.timestamp.compareTo(a.timestamp));

        setState(() {
          _notifications = parsed;
          _isLoading = false;
        });
      },
      onError: (error) {
        debugPrint('Firebase notifications stream error: $error');
        if (mounted) setState(() => _isLoading = false);
      },
    );
  }

  @override
  void dispose() {
    _notiSubscription?.cancel();
    super.dispose();
  }

  Future<void> _markAsRead(_NotificationItem item) async {
    if (item.isRead) return;
    try {
      await _notiRef.child(item.id).update({'is_read': true});
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'critical':
        return Icons.error;
      case 'warning':
        return Icons.warning_amber_rounded;
      default:
        return Icons.info;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'critical':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  String _formatTimestamp(int millis) {
    if (millis == 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'เมื่อสักครู่';
    if (diff.inMinutes < 60) return '${diff.inMinutes} นาทีที่แล้ว';
    if (diff.inHours < 24) return '${diff.inHours} ชั่วโมงที่แล้ว';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              if (_notifications.isEmpty)
                _buildEmptyState()
              else
                ..._notifications.map(_buildNotificationCard),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final unreadCount = _notifications.where((n) => !n.isRead).length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'การแจ้งเตือนทั้งหมด',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.black87,
          ),
        ),
        if (unreadCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(
              'ยังไม่ได้อ่าน $unreadCount',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade400,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 40,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            'ยังไม่มีการแจ้งเตือน',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(_NotificationItem item) {
    final color = _colorForType(item.type);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _markAsRead(item),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: item.isRead ? Colors.white : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: item.isRead
                  ? Colors.grey.shade200
                  : Colors.blue.shade100,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.08),
                spreadRadius: 1,
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_iconForType(item.type), color: color, size: 20),
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
                            item.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (!item.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.blue,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.message,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatTimestamp(item.timestamp),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
