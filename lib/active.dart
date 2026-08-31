import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

// 📦 Firebase schema ที่หน้านี้คาดหวัง:
// water_system/activities/{pushId}: {
//   type: 'laundry' | 'dishes' | 'shower' | 'plants',
//   liters: <number>,
//   timestamp: <number>, // milliseconds since epoch
// }

class _ActivityType {
  final String id;
  final String label;
  final IconData icon;
  final double defaultLiters;
  final Color color;

  const _ActivityType({
    required this.id,
    required this.label,
    required this.icon,
    required this.defaultLiters,
    required this.color,
  });
}

const List<_ActivityType> _activityTypes = [
  _ActivityType(
    id: 'laundry',
    label: 'ซักผ้า',
    icon: Icons.local_laundry_service,
    defaultLiters: 80,
    color: Colors.indigo,
  ),
  _ActivityType(
    id: 'dishes',
    label: 'ล้างจาน',
    icon: Icons.kitchen,
    defaultLiters: 20,
    color: Colors.teal,
  ),
  _ActivityType(
    id: 'shower',
    label: 'อาบน้ำ',
    icon: Icons.bathtub,
    defaultLiters: 30,
    color: Colors.blue,
  ),
  _ActivityType(
    id: 'plants',
    label: 'รดน้ำต้นไม้',
    icon: Icons.local_florist,
    defaultLiters: 10,
    color: Colors.green,
  ),
];

_ActivityType _typeById(String id) {
  return _activityTypes.firstWhere(
    (t) => t.id == id,
    orElse: () => _activityTypes.first,
  );
}

class _ActivityLog {
  final String id;
  final String typeId;
  final double liters;
  final int timestamp;

  _ActivityLog({
    required this.id,
    required this.typeId,
    required this.liters,
    required this.timestamp,
  });
}

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  final DatabaseReference _activitiesRef = FirebaseDatabase.instance.ref(
    'water_system/activities',
  );
  StreamSubscription<DatabaseEvent>? _subscription;

  bool _isLoading = true;
  List<_ActivityLog> _logs = [];

  @override
  void initState() {
    super.initState();
    _subscription = _activitiesRef.onValue.listen(
      (event) {
        if (!mounted) return;

        final rootValue = event.snapshot.value;
        final List<_ActivityLog> parsed = [];

        if (rootValue != null) {
          try {
            final rootData = Map<dynamic, dynamic>.from(rootValue as Map);
            rootData.forEach((key, value) {
              final entry = Map<dynamic, dynamic>.from(value as Map);
              final rawLiters = entry['liters'];
              final rawTimestamp = entry['timestamp'];
              parsed.add(
                _ActivityLog(
                  id: key.toString(),
                  typeId: (entry['type'] ?? '').toString(),
                  liters: rawLiters is num ? rawLiters.toDouble() : 0,
                  timestamp: rawTimestamp is num ? rawTimestamp.toInt() : 0,
                ),
              );
            });
          } catch (e) {
            debugPrint('Error parsing Firebase activities data: $e');
          }
        }

        parsed.sort((a, b) => b.timestamp.compareTo(a.timestamp));

        setState(() {
          _logs = parsed;
          _isLoading = false;
        });
      },
      onError: (error) {
        debugPrint('Firebase activities stream error: $error');
        if (mounted) setState(() => _isLoading = false);
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  bool _isToday(int millis) {
    if (millis == 0) return false;
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  double get _todayTotal {
    return _logs
        .where((log) => _isToday(log.timestamp))
        .fold(0.0, (sum, log) => sum + log.liters);
  }

  Future<void> _openAddActivitySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddActivitySheet(activitiesRef: _activitiesRef),
    );
  }

  String _formatTime(int millis) {
    if (millis == 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    if (_isToday(millis)) return 'วันนี้ $hh:$mm น.';
    return '${date.day}/${date.month}/${date.year} $hh:$mm น.';
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
              _buildSummaryCard(),
              const SizedBox(height: 16),
              _buildAddButton(),
              const SizedBox(height: 20),
              const Text(
                'กิจกรรมล่าสุด',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              if (_logs.isEmpty)
                _buildEmptyState()
              else
                ..._logs.map(_buildActivityCard),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blue.shade400, Colors.blue.shade700],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.bolt, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ใช้น้ำจากกิจกรรมวันนี้',
                style: TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
              const SizedBox(height: 2),
              Text(
                '${_todayTotal.toStringAsFixed(1)} ลิตร',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        onPressed: _openAddActivitySheet,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text(
          'เพิ่มกิจกรรม',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 50),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.event_note, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'ยังไม่มีกิจกรรม กดปุ่ม "เพิ่มกิจกรรม" เพื่อเริ่มบันทึก',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityCard(_ActivityLog log) {
    final type = _typeById(log.typeId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.08),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: type.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(type.icon, color: type.color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(log.timestamp),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${log.liters.toStringAsFixed(0)} ลิตร',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: type.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------
// 📝 Bottom sheet สำหรับเลือกประเภทกิจกรรม + ระบุปริมาณน้ำที่ใช้ แล้วบันทึกขึ้น Firebase
// -----------------------------------------------------------------
class _AddActivitySheet extends StatefulWidget {
  final DatabaseReference activitiesRef;

  const _AddActivitySheet({required this.activitiesRef});

  @override
  State<_AddActivitySheet> createState() => _AddActivitySheetState();
}

class _AddActivitySheetState extends State<_AddActivitySheet> {
  int _selectedIndex = 0;
  late final TextEditingController _litersController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _litersController = TextEditingController(
      text: _activityTypes[_selectedIndex].defaultLiters.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _litersController.dispose();
    super.dispose();
  }

  void _selectType(int index) {
    setState(() {
      _selectedIndex = index;
      _litersController.text = _activityTypes[index].defaultLiters
          .toStringAsFixed(0);
    });
  }

  Future<void> _save() async {
    final liters = double.tryParse(_litersController.text.trim());
    if (liters == null || liters <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณากรอกปริมาณน้ำเป็นตัวเลขที่ถูกต้อง'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await widget.activitiesRef.push().set({
        'type': _activityTypes[_selectedIndex].id,
        'liters': liters,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Error saving activity: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกไม่สำเร็จ กรุณาลองใหม่')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'เพิ่มกิจกรรม',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: List.generate(_activityTypes.length, (index) {
                final type = _activityTypes[index];
                final isSelected = _selectedIndex == index;
                return GestureDetector(
                  onTap: () => _selectType(index),
                  child: Container(
                    width: 78,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? type.color.withOpacity(0.12)
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? type.color : Colors.grey.shade200,
                        width: isSelected ? 1.6 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(type.icon, color: type.color, size: 24),
                        const SizedBox(height: 6),
                        Text(
                          type.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? type.color
                                : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _litersController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'ปริมาณน้ำที่ใช้ (ลิตร)',
                prefixIcon: const Icon(Icons.opacity, size: 20),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'บันทึกกิจกรรม',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
