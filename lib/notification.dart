import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'notification_service.dart'; // purgeOlderThan() ใช้ลบแจ้งเตือนที่อายุเกิน 7 วัน

// =====================================================================
// 🎨 ตัวช่วยเรื่องสี / ไอคอน / ป้ายชื่อ ของ "ระดับความรุนแรง"
//
//    รวมไว้ที่เดียว แล้วให้ทั้งหน้าแจ้งเตือน (ไฟล์นี้) และ watertank.dart
//    เรียกใช้ร่วมกัน จะได้ไม่ต้องเขียน switch ซ้ำสองที่แล้วค่อยๆ ไม่ตรงกัน
// =====================================================================
Color notificationColorFor(String type) {
  switch (type) {
    case 'critical':
      return const Color(0xFFEB5757); // 🔴 วิกฤต
    case 'warning':
      return const Color(0xFFF2A93B); // 🟡 ควรระวัง
    default:
      return const Color(0xFF27AE60); // 🟢 ปกติ / ข่าวดี
  }
}

IconData notificationIconFor(String type) {
  switch (type) {
    case 'critical':
      return Icons.error_rounded;
    case 'warning':
      return Icons.warning_amber_rounded;
    default:
      return Icons.water_drop_outlined;
  }
}

/// 🏷️ ป้ายชื่อระดับความรุนแรงเป็นภาษาไทย
String notificationLabelFor(String type) {
  switch (type) {
    case 'critical':
      return 'วิกฤต';
    case 'warning':
      return 'ควรระวัง';
    default:
      return 'ปกติ';
  }
}

/// 🕒 เวลาบนการ์ดแจ้งเตือน
///    วันนี้ → "HH:mm น." / วันอื่น → "d/M HH:mm น."
String formatClockTime(int millis) {
  if (millis <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  final String hh = date.hour.toString().padLeft(2, '0');
  final String mm = date.minute.toString().padLeft(2, '0');
  final bool sameDay =
      date.year == now.year && date.month == now.month && date.day == now.day;
  return sameDay ? '$hh:$mm น.' : '${date.day}/${date.month} $hh:$mm น.';
}

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

/// 🔎 ตัวกรองบนแถบ chip ด้านบน
enum _NotiFilter { all, critical, warning, normal }

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
  Timer? _purgeTimer;

  bool _isLoading = true;
  List<_NotificationItem> _notifications = [];
  _NotiFilter _filter = _NotiFilter.all;

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

    // 🗑️ ลบการแจ้งเตือนที่อายุเกิน 7 วันทันที แล้วตรวจซ้ำทุกชั่วโมง
    _purgeOldNotifications();
    _purgeTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => _purgeOldNotifications(),
    );
  }

  @override
  void dispose() {
    _notiSubscription?.cancel();
    _purgeTimer?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // 🔎 ตัวกรอง
  // ------------------------------------------------------------------
  bool _matchFilter(_NotificationItem item, _NotiFilter filter) {
    switch (filter) {
      case _NotiFilter.all:
        return true;
      case _NotiFilter.critical:
        return item.type == 'critical';
      case _NotiFilter.warning:
        return item.type == 'warning';
      case _NotiFilter.normal:
        return item.type != 'critical' && item.type != 'warning';
    }
  }

  // ------------------------------------------------------------------
  // ✍️ อ่านแล้ว / อ่านทั้งหมด
  // ------------------------------------------------------------------
  Future<void> _markAsRead(_NotificationItem item) async {
    if (item.isRead) return;
    try {
      await _notiRef.child(item.id).update({'is_read': true});
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  Future<void> _markAllRead() async {
    final List<_NotificationItem> unread = _notifications
        .where((n) => !n.isRead)
        .toList();
    if (unread.isEmpty) return;
    try {
      // อัปเดตทีเดียวหลายรายการ (multi-path update) ประหยัดการเขียน Firebase
      final Map<String, Object?> updates = <String, Object?>{};
      for (final item in unread) {
        updates['${item.id}/is_read'] = true;
      }
      await _notiRef.update(updates);
      _showSnack('อ่านการแจ้งเตือนทั้งหมดแล้ว ✓');
    } catch (e) {
      debugPrint('Error marking all notifications as read: $e');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------
  // 🗑️ ลบการแจ้งเตือนที่อายุเกิน 7 วันทิ้งโดยอัตโนมัติ
  // ------------------------------------------------------------------
  void _purgeOldNotifications() {
    NotificationService.purgeOlderThan(const Duration(days: 7));
  }

  // ------------------------------------------------------------------
  // 🗑️ ถามยืนยันก่อนลบ (กันปัดพลาดแล้วข้อมูลหาย)
  // ------------------------------------------------------------------
  Future<bool> _confirmDeleteNotification(_NotificationItem item) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบการแจ้งเตือนนี้?'),
        content: Text(
          '${item.title}\n${item.message}',
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ลบ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteNotification(_NotificationItem item) async {
    try {
      await _notiRef.child(item.id).remove();
    } catch (e) {
      debugPrint('Error deleting notification ${item.id}: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ลบไม่สำเร็จ กรุณาลองใหม่')),
        );
      }
    }
  }

  // ==================================================================
  // 🎨 ส่วนแสดงผล
  // ==================================================================
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final int unread = _notifications.where((n) => !n.isRead).length;
    final List<_NotificationItem> visible = _notifications
        .where((n) => _matchFilter(n, _filter))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildHeroBanner(unread),
              const SizedBox(height: 16),
              _buildFilterChips(),
              const SizedBox(height: 16),
              _buildSectionHeader(unread),
              const SizedBox(height: 10),
              if (visible.isEmpty)
                _buildEmptyState()
              else
                ...visible.map(_buildNotificationCard),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 💙 แบนเนอร์ด้านบน: จำนวนที่ยังไม่อ่าน + ไอคอนกระดิ่ง
  // ------------------------------------------------------------------
  Widget _buildHeroBanner(int unread) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5CA9FF), Color(0xFF2F80ED)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2F80ED).withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'การแจ้งเตือนทั้งหมด',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      '$unread',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 5),
                      child: Text(
                        'รายการที่ยังไม่อ่าน',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 🔖 แถบกรอง: ทั้งหมด / วิกฤต / ควรระวัง / ปกติ
  // ------------------------------------------------------------------
  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _buildChip('ทั้งหมด', _NotiFilter.all),
          const SizedBox(width: 8),
          _buildChip('วิกฤต', _NotiFilter.critical),
          const SizedBox(width: 8),
          _buildChip('ควรระวัง', _NotiFilter.warning),
          const SizedBox(width: 8),
          _buildChip('ปกติ', _NotiFilter.normal),
        ],
      ),
    );
  }

  Widget _buildChip(String label, _NotiFilter filter) {
    final bool selected = _filter == filter;
    return GestureDetector(
      onTap: () => setState(() => _filter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2F80ED) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? const Color(0xFF2F80ED) : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 🏷️ หัวข้อ "รายการแจ้งเตือน" + ปุ่มอ่านทั้งหมด
  // ------------------------------------------------------------------
  Widget _buildSectionHeader(int unread) {
    return Row(
      children: <Widget>[
        const Text(
          'รายการแจ้งเตือน',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: unread > 0 ? _markAllRead : null,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF2F80ED),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(Icons.done_all_rounded, size: 16),
          label: const Text(
            'อ่านทั้งหมด',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // 🗂️ การ์ดแจ้งเตือน 1 รายการ
  // ------------------------------------------------------------------
  Widget _buildNotificationCard(_NotificationItem item) {
    final Color color = notificationColorFor(item.type);
    final bool unread = !item.isRead;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: ValueKey(item.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) => _confirmDeleteNotification(item),
        onDismissed: (_) => _deleteNotification(item),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.red.shade400,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _markAsRead(item),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: unread ? const Color(0xFFF4F9FF) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: unread ? const Color(0xFFCFE3FB) : Colors.grey.shade200,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.08),
                  spreadRadius: 1,
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    notificationIconFor(item.type),
                    color: color,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              item.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formatClockTime(item.timestamp),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: <Widget>[
                          _buildTag(notificationLabelFor(item.type), color),
                          if (unread)
                            _buildTag('ยังไม่อ่าน', const Color(0xFF2F80ED)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.message,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade700,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  /// 🏷️ ป้ายเล็กๆ ระบุระดับความรุนแรง / สถานะอ่าน
  Widget _buildTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.notifications_off_outlined,
            size: 40,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            _filter == _NotiFilter.all
                ? 'ยังไม่มีการแจ้งเตือน'
                : 'ไม่มีรายการในหมวดนี้',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}
