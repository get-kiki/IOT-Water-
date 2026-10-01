import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

// 📦 Firebase schema ที่หน้านี้คาดหวัง:
// water_system/history/{yyyy-MM-dd}: {
//   used_liters: <number>,                         // ยอดรวมของทั้งวัน
//   hourly/{HH}: { used_liters: <number> },         // ยอดของแต่ละชั่วโมง (00-23)
// }
//
// 🚀 แต่ละ tab ดึงข้อมูลเฉพาะช่วงที่ต้องใช้จริงเท่านั้น (ไม่โหลดทั้ง history ทั้งก้อน)
// เพื่อประหยัดแบนด์วิดท์ Firebase เมื่อข้อมูลสะสมไปเรื่อยๆ หลายเดือน/ปี:
//   - "วัน"   -> อ่านแค่ node ของวันนี้/hourly (24 ค่า)
//   - "เดือน" -> query เฉพาะช่วงวันที่ของเดือนนี้ (orderByKey + startAt/endAt)
//   - "ปี"    -> query เฉพาะช่วงวันที่ของปีนี้ แล้วรวมเป็นรายเดือนฝั่ง client
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryPage> {
  // ตัวแปรสำหรับเก็บสถานะการเลือก Tab (วัน / เดือน / ปี)
  String _selectedPeriod = 'วัน';

  // key: '00'..'23' -> ปริมาณน้ำที่ใช้ไปของชั่วโมงนั้น (วันนี้)
  Map<String, double> _hourlyToday = {};
  // key: 'yyyy-MM-dd' -> ปริมาณน้ำที่ใช้ไปของวันนั้น (เดือนนี้)
  Map<String, double> _dailyThisMonth = {};
  // key: 'yyyy-MM-dd' -> ปริมาณน้ำที่ใช้ไปของวันนั้น (ทั้งปีนี้ ไว้รวมเป็นรายเดือน)
  Map<String, double> _dailyThisYear = {};

  bool _hourlyLoaded = false;
  bool _monthlyLoaded = false;
  bool _yearlyLoaded = false;
  bool get _isLoading => !(_hourlyLoaded && _monthlyLoaded && _yearlyLoaded);

  late final DatabaseReference _hourlyRef;
  late final Query _monthQuery;
  late final Query _yearQuery;

  StreamSubscription<DatabaseEvent>? _hourlySub;
  StreamSubscription<DatabaseEvent>? _monthSub;
  StreamSubscription<DatabaseEvent>? _yearSub;

  static const List<String> _thaiMonths = [
    'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
    'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
  ];

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    final todayKey = '${now.year}-${_pad2(now.month)}-${_pad2(now.day)}';
    final monthStartKey = '${now.year}-${_pad2(now.month)}-01';
    final monthEndKey = '${now.year}-${_pad2(now.month)}-31';
    final yearStartKey = '${now.year}-01-01';
    final yearEndKey = '${now.year}-12-31';

    _hourlyRef = FirebaseDatabase.instance.ref(
      'water_system/history/$todayKey/hourly',
    );
    _monthQuery = FirebaseDatabase.instance
        .ref('water_system/history')
        .orderByKey()
        .startAt(monthStartKey)
        .endAt(monthEndKey);
    _yearQuery = FirebaseDatabase.instance
        .ref('water_system/history')
        .orderByKey()
        .startAt(yearStartKey)
        .endAt(yearEndKey);

    _hourlySub = _hourlyRef.onValue.listen(
      (event) {
        if (!mounted) return;
        final parsed = <String, double>{};
        final rootValue = event.snapshot.value;
        if (rootValue != null) {
          try {
            final rootData = Map<dynamic, dynamic>.from(rootValue as Map);
            rootData.forEach((key, value) {
              final entry = Map<dynamic, dynamic>.from(value as Map);
              parsed[key.toString()] = (entry['used_liters'] ?? 0).toDouble();
            });
          } catch (e) {
            debugPrint('Error parsing Firebase hourly data: $e');
          }
        }
        setState(() {
          _hourlyToday = parsed;
          _hourlyLoaded = true;
        });
      },
      onError: (error) {
        debugPrint('Firebase hourly stream error: $error');
        if (mounted) setState(() => _hourlyLoaded = true);
      },
    );

    _monthSub = _monthQuery.onValue.listen(
      (event) => _handleDailyEvent(event, (parsed) {
        _dailyThisMonth = parsed;
        _monthlyLoaded = true;
      }),
      onError: (error) {
        debugPrint('Firebase month stream error: $error');
        if (mounted) setState(() => _monthlyLoaded = true);
      },
    );

    _yearSub = _yearQuery.onValue.listen(
      (event) => _handleDailyEvent(event, (parsed) {
        _dailyThisYear = parsed;
        _yearlyLoaded = true;
      }),
      onError: (error) {
        debugPrint('Firebase year stream error: $error');
        if (mounted) setState(() => _yearlyLoaded = true);
      },
    );
  }

  // 🔁 ใช้ร่วมกันระหว่าง query เดือน/ปี เพราะ parsing เหมือนกันทุกอย่าง
  // ต่างกันแค่ map ปลายทางที่จะเก็บผลลัพธ์
  void _handleDailyEvent(
    DatabaseEvent event,
    void Function(Map<String, double> parsed) assignTo,
  ) {
    if (!mounted) return;
    final parsed = <String, double>{};
    final rootValue = event.snapshot.value;
    if (rootValue != null) {
      try {
        final rootData = Map<dynamic, dynamic>.from(rootValue as Map);
        rootData.forEach((key, value) {
          final entry = Map<dynamic, dynamic>.from(value as Map);
          parsed[key.toString()] = (entry['used_liters'] ?? 0).toDouble();
        });
      } catch (e) {
        debugPrint('Error parsing Firebase daily data: $e');
      }
    }
    setState(() => assignTo(parsed));
  }

  @override
  void dispose() {
    _hourlySub?.cancel();
    _monthSub?.cancel();
    _yearSub?.cancel();
    super.dispose();
  }

  // -----------------------------------------------------------------
  // 🧮 สร้างรายการข้อมูลตาม tab ที่เลือกอยู่ เรียงจากเก่า -> ใหม่
  //   วัน   -> ครบ 24 ชั่วโมงของวันนี้ (เติม 0 ให้ชั่วโมงที่ยังไม่มีข้อมูล)
  //   เดือน -> รายวันของเดือนนี้
  //   ปี    -> รายเดือนของปีนี้ (รวมจากยอดรายวันทั้งปี)
  // -----------------------------------------------------------------
  List<MapEntry<String, double>> _buildAggregatedEntries() {
    switch (_selectedPeriod) {
      case 'ปี':
        final totals = <String, double>{};
        for (final e in _dailyThisYear.entries) {
          final monthKey = e.key.substring(0, 7); // 'yyyy-MM'
          totals[monthKey] = (totals[monthKey] ?? 0) + e.value;
        }
        final sortedKeys = totals.keys.toList()..sort();
        return sortedKeys
            .map((k) => MapEntry(_formatMonthLabel(k), totals[k]!))
            .toList();
      case 'เดือน':
        final entries = _dailyThisMonth.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        return entries
            .map((e) => MapEntry(e.key.split('-').last, e.value))
            .toList();
      case 'วัน':
      default:
        return List.generate(24, (h) {
          final key = _pad2(h);
          return MapEntry('$key:00', _hourlyToday[key] ?? 0.0);
        });
    }
  }

  String _formatMonthLabel(String yearMonth) {
    final parts = yearMonth.split('-');
    final month = int.parse(parts[1]);
    return '${_thaiMonths[month - 1]} ${parts[0]}';
  }

  String get _averageUnitLabel {
    switch (_selectedPeriod) {
      case 'วัน':
        return 'ชั่วโมง';
      case 'เดือน':
        return 'วัน';
      case 'ปี':
        return 'เดือน';
      default:
        return '';
    }
  }

  String get _chartTitle {
    switch (_selectedPeriod) {
      case 'วัน':
        return 'การใช้น้ำวันนี้ (รายชั่วโมง)';
      case 'เดือน':
        return 'การใช้น้ำเดือนนี้ (รายวัน)';
      case 'ปี':
        return 'การใช้น้ำปีนี้ (รายเดือน)';
      default:
        return '';
    }
  }

  String get _detailSectionTitle {
    switch (_selectedPeriod) {
      case 'วัน':
        return 'รายละเอียดรายชั่วโมง (วันนี้)';
      case 'เดือน':
        return 'รายละเอียดรายวัน (เดือนนี้)';
      case 'ปี':
        return 'รายละเอียดรายเดือน (ปีนี้)';
      default:
        return '';
    }
  }

  double get _totalForPeriod {
    return _buildAggregatedEntries().fold(0.0, (sum, e) => sum + e.value);
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
            title: 'เฉลี่ยต่อ$_averageUnitLabel',
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
    final hasData = entries.any((e) => e.value > 0);

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
            _chartTitle,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
          Expanded(
            child: !hasData
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
    List<MapEntry<String, double>> entries = _buildAggregatedEntries();
    if (_selectedPeriod == 'วัน') {
      // ตัดชั่วโมงในอนาคตของวันนี้ทิ้ง (ยังไม่เกิดขึ้นจริง ไม่มีความหมายในลิสต์)
      final currentHour = DateTime.now().hour;
      entries = entries.sublist(0, currentHour + 1);
    }
    entries = entries.reversed.toList(); // ใหม่ -> เก่า
    final recent = entries.length > 12 ? entries.sublist(0, 12) : entries;

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
          Text(
            _detailSectionTitle,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          if (recent.every((e) => e.value == 0))
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
                      recent[index].key,
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
