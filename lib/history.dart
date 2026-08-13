import 'package:flutter/material.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryPage> {
  // ตัวแปรสำหรับเก็บสถานะการเลือก Tab (วัน / เดือน / ปี)
  String _selectedPeriod = 'วัน';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 204, 212, 219), // ใช้โทนสีพื้นหลังเดียวกันกับหน้าหลัก
      appBar: AppBar(
        title: const Text('ประวัติการใช้น้ำ'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
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
                  // TODO: เขียนฟังก์ชันดึงข้อมูลใหม่ตาม period ที่เลือกตรงนี้
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
            value: '124.5 ลิตร',
            icon: Icons.water_drop,
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildCardItem(
            title: 'เฉลี่ยต่อ$_selectedPeriod',
            value: '15.2 ลิตร',
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
          const Expanded(
            child: Center(
              child: Text(
                '📊 [ พื้นที่สำหรับใส่กราฟเช่น fl_chart ]',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------
  // 📋 4. รายการประวัติแบบละเอียด (History List)
  // -----------------------------------------------------------------
  Widget _buildHistoryList() {
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
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 5,
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
                    'วันที่ 26 ก.ค. 2026 - ช่วงที่ ${index + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: const Text(
                    'ใช้น้ำไป 12.5 ลิตร',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  trailing: const Text(
                    '15:30 น.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
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