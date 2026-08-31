import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

// 📦 Firebase schema ที่หน้านี้คาดหวัง:
// water_system/history/{yyyy-MM-dd}: { used_liters: <number> }
// แต่ละ key คือยอดน้ำที่ใช้ไปทั้งหมดของวันนั้น (ฝั่งบอร์ดเซนเซอร์เป็นคนอัปเดตทับทุกครั้งที่น้ำไหล)
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryPage> {
  final DatabaseReference _historyRef = FirebaseDatabase.instance.ref(
    'water_system/history',
  );
  StreamSubscription<DatabaseEvent>? _historySubscription;

  // ตัวแปรสำหรับเก็บสถานะการเลือก Tab (วัน / เดือน / ปี)
  String _selectedPeriod = 'วัน';
  bool _isLoading = true;

  // key: 'yyyy-MM-dd' -> ปริมาณน้ำที่ใช้ไปของวันนั้น (ลิตร)
  Map<String, double> _dailyUsage = {};

  static const List<String> _thaiMonths = [
    'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
    'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
  ];

  @override
  void initState() {
    super.initState();
    _historySubscription = _historyRef.onValue.listen(
      (event) {
        if (!mounted) return;

        final rootValue = event.snapshot.value;
        final Map<String, double> parsed = {};

        if (rootValue != null) {
          try {
            final rootData = Map<dynamic, dynamic>.from(rootValue as Map);
            rootData.forEach((key, value) {
              final entry = Map<dynamic, dynamic>.from(value as Map);
              parsed[key.toString()] = (entry['used_liters'] ?? 0).toDouble();
            });
          } catch (e) {
            debugPrint('Error parsing Firebase history data: $e');
          }
        }

        setState(() {
          _dailyUsage = parsed;
          _isLoading = false;
        });
      },
      onError: (error) {
        debugPrint('Firebase history stream error: $error');
        if (mounted) setState(() => _isLoading = false);
      },
    );
  }

  @override
  void dispose() {
    _historySubscription?.cancel();
    super.dispose();
  }

  // -----------------------------------------------------------------
  // 🧮 รวมข้อมูลรายวันให้เป็นรายการตามช่วงเวลาที่เลือก (วัน / เดือน / ปี)
  // เรียงจากเก่าไปใหม่ ใช้ทั้งกราฟและการ์ดสรุป
  // -----------------------------------------------------------------
  List<MapEntry<String, double>> _buildAggregatedEntries() {
    if (_dailyUsage.isEmpty) return [];

    switch (_selectedPeriod) {
      case 'เดือน':
        return _aggregateBy((date) =>
            '${date.year}-${date.month.toString().padLeft(2, '0')}')
            .map((e) => MapEntry(_formatMonthLabel(e.key), e.value))
            .toList();
      case 'ปี':
        return _aggregateBy((date) => date.year.toString())
            .map((e) => MapEntry(e.key, e.value))
            .toList();
      case 'วัน':
      default:
        final entries = _dailyUsage.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        // แสดงแค่ 30 วันล่าสุด กันกราฟยาวเกินไปเมื่อมีข้อมูลสะสมมาก
        final recent = entries.length > 30
            ? entries.sublist(entries.length - 30)
            : entries;
        return recent
            .map((e) => MapEntry(_formatDayLabel(e.key), e.value))
            .toList();
    }
  }

  List<MapEntry<String, double>> _aggregateBy(
    String Function(DateTime date) keyOf,
  ) {
    final Map<String, double> totals = {};
    for (final e in _dailyUsage.entries) {
      final date = DateTime.tryParse(e.key);
      if (date == null) continue;
      final key = keyOf(date);
      totals[key] = (totals[key] ?? 0) + e.value;
    }
    final sortedKeys = totals.keys.toList()..sort();
    return sortedKeys.map((k) => MapEntry(k, totals[k]!)).toList();
  }

  String _formatDayLabel(String isoDate) {
    final date = DateTime.tryParse(isoDate);
    if (date == null) return isoDate;
    return '${date.day}/${date.month}';
  }

  String _formatMonthLabel(String yearMonth) {
    final parts = yearMonth.split('-');
    final month = int.parse(parts[1]);
    return '${_thaiMonths[month - 1]} ${parts[0]}';
  }

  double get _totalForPeriod {
    final entries = _buildAggregatedEntries();
    return entries.fold(0.0, (sum, e) => sum + e.value);
  }

  double get _averageForPeriod {
    final entries = _buildAggregatedEntries();
    if (entries.isEmpty) return 0;
    return _totalForPeriod / entries.length;
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
              // 1. ส่วนเลือกช่วงเวลา (Tab Switcher: วัน / เดือน / ปี)
              _buildPeriodSelector(),
              const SizedBox(height: 20),

              // 2. การ์ดสรุปยอดรวม (Summary Cards)
              _buildSummaryCards(),
              const SizedBox(height: 20),

              // 3. ส่วนแสดงกราฟหรือสถิติ (Dashboard Chart Area)
              _buildChartSection(),
              const SizedBox(height: 20),

              // 4. รายการประวัติแบบละเอียด (History List)
              _buildHistoryList(),
            ],
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------
  // 🔘 1. ส่วนสลับมุมมอง (วัน / เดือน / ปี)
  // -----------------------------------------------------------------
  Widget _buildPeriodSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: ['วัน', 'เดือน', 'ปี'].map((period) {
          bool isSelected = _selectedPeriod == period;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedPeriod = period;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Text(
                  period,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isSelected ? Colors.white : Colors.grey.shade700,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // -----------------------------------------------------------------
  // 📊 2. การ์ดสรุปข้อมูลรวม (Summary Cards)
  // -----------------------------------------------------------------
  Widget _buildSummaryCards() {
    return Row(
      children: [
        Expanded(
          child: _buildCardItem(
            title: 'ใช้น้ำรวม',
            value: '${_totalForPeriod.toStringAsFixed(1)} ลิตร',
            icon: Icons.water_drop,
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildCardItem(
            title: 'เฉลี่ยต่อ$_selectedPeriod',
            value: '${_averageForPeriod.toStringAsFixed(1)} ลิตร',
            icon: Icons.analytics,
            color: Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildCardItem({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------
  // 📈 3. ส่วนแสดงกราฟแดชบอร์ด (Chart Section)
  // -----------------------------------------------------------------
  Widget _buildChartSection() {
    final entries = _buildAggregatedEntries();

    return Container(
      height: 220,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'กราฟแสดงสถิติการใช้น้ำ (ราย$_selectedPeriod)',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? const Center(
                    child: Text(
                      'ยังไม่มีข้อมูลการใช้น้ำ\nรอเชื่อมต่อเซ็นเซอร์วัดการไหล',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  )
                : _buildBarChart(entries),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(List<MapEntry<String, double>> entries) {
    final maxValue = entries
        .map((e) => e.value)
        .fold<double>(0, (a, b) => a > b ? a : b);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: entries.map((entry) {
          final heightFactor = maxValue == 0
              ? 0.02
              : (entry.value / maxValue).clamp(0.02, 1.0);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  entry.value.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 32,
                  height: 100,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: heightFactor,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.shade300,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  entry.key,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // -----------------------------------------------------------------
  // 📋 4. รายการประวัติแบบละเอียด (History List)
  // -----------------------------------------------------------------
  Widget _buildHistoryList() {
    final entries = _dailyUsage.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key)); // ใหม่ -> เก่า
    final recent = entries.length > 10 ? entries.sublist(0, 10) : entries;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ประวัติการใช้งานล่าสุด',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          if (recent.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'ยังไม่มีข้อมูลการใช้น้ำ ระบบจะเริ่มบันทึกอัตโนมัติ\nเมื่อเชื่อมต่อเซ็นเซอร์วัดการไหลแล้ว',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recent.length,
              itemBuilder: (context, index) {
                final date = DateTime.tryParse(recent[index].key);
                final label = date == null
                    ? recent[index].key
                    : '${date.day} ${_thaiMonths[date.month - 1]} ${date.year}';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.water, color: Colors.blue),
                    ),
                    title: Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      'ใช้น้ำไป ${recent[index].value.toStringAsFixed(1)} ลิตร',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
