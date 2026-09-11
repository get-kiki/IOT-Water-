import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

// 🚀 เชื่อมโยงไปที่ไฟล์ watertank.dart ของคุณ
import 'watertank.dart';
import 'firebase_options.dart';

void main() async {
  // บังคับให้จัดการทำงานแบบ Async และผูกระบบกับ Firebase ก่อนเปิดแอป
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Water Tank IoT',
      debugShowCheckedModeBanner: false, // ปิดแถบแบนเนอร์ Debug สีแดงมุมขวา
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'ขนาดแทงค์น้ำ'),
    );
  }
}

// 📦 ข้อมูลขนาดแทงค์ที่แยกส่วนไว้แล้ว ใช้แสดงผลบนการ์ดให้อ่านง่ายขึ้น
class _TankSizeInfo {
  final String dimensions; // เช่น "93 × 185 ซม."
  final String liters; // เช่น "1,000 ลิตร"
  final String? tag; // "นิยม" / "นิยมที่สุด" หรือ null

  _TankSizeInfo({required this.dimensions, required this.liters, this.tag});
}

_TankSizeInfo _parseTankSize(String raw) {
  String? tag;
  String base = raw;
  if (raw.contains(' (นิยมที่สุด)')) {
    tag = 'นิยมที่สุด';
    base = raw.replaceAll(' (นิยมที่สุด)', '');
  } else if (raw.contains(' (นิยม)')) {
    tag = 'นิยม';
    base = raw.replaceAll(' (นิยม)', '');
  }

  final parts = base.split(' ซม. ความจุ ');
  final dimensions = '${parts[0].replaceAll('*', ' × ')} ซม.';
  final liters = parts.length > 1 ? parts[1] : '';

  return _TankSizeInfo(dimensions: dimensions, liters: liters, tag: tag);
}

// 🛢️ ไอคอนรูปแทงค์น้ำขนาดเล็ก วาดเองจากกล่องซ้อนกัน (โครงถัง + ระดับน้ำ + ฝาถัง)
// ใช้รูปเดียวกันทุกรายการ ไม่ไล่ระดับตามความจุ
class _MiniTankIcon extends StatelessWidget {
  static const double _fillFactor = 0.6;
  final Color color;

  const _MiniTankIcon({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 24,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.bottomCenter,
        children: [
          // โครงถัง (ขอบ)
          Container(
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              border: Border.all(color: color, width: 1.4),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
                bottom: Radius.circular(2),
              ),
            ),
          ),
          // ระดับน้ำภายในถัง
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(3),
              bottom: Radius.circular(1),
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: _fillFactor,
                widthFactor: 1,
                child: Container(color: color),
              ),
            ),
          ),
          // ฝาถังด้านบน
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 2.2,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // อ้างอิงพิกัดใน Firebase Database
  // 🚀 ถ้า Realtime Database ของคุณอยู่ region อื่น (เช่น asia-southeast1)
  // ให้เปลี่ยนมาใช้ FirebaseDatabase.instanceFor(app: ..., databaseURL: ...) แทน
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref(
    'water_system',
  );

  // แยก Controller สำหรับรับค่าแต่ละส่วน
  final TextEditingController _widthController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _literController = TextEditingController();

  // 🚀 flag กันผู้ใช้กดปุ่มซ้ำระหว่างรอ Firebase ตอบกลับ
  bool _isSaving = false;

  // 🎯 ดัชนีของขนาดมาตรฐานที่ถูกเลือกอยู่ (ไว้ไฮไลต์การ์ด), null = ยังไม่เลือก/พิมพ์เอง
  int? _selectedTemplateIndex;

  // รายการขนาดแทงค์น้ำมาตรฐาน
  final List<String> _tankSizes = [
    '74*114 ซม. ความจุ 400 ลิตร',
    '73*141 ซม. ความจุ 500 ลิตร',
    '77*179 ซม. ความจุ 700 ลิตร (นิยม)',
    '93*185 ซม. ความจุ 1,000 ลิตร (นิยมที่สุด)',
    '108*199 ซม. ความจุ 1,500 ลิตร',
    '121*211 ซม. ความจุ 2,000 ลิตร',
    '143*224 ซม. ความจุ 3,000 ลิตร',
    '177*240 ซม. ความจุ 5,000 ลิตร',
  ];

  // ฟังก์ชันแยกตัวเลขจากข้อความปุ่มมาตรฐาน เพื่อเอาไปเติมในช่องกรอกข้อมูล
  void _fillControllerFromTemplate(int index, String sizeTemplate) {
    try {
      // 1. แยกส่วนกว้างสูง ออกจากส่วนลิตร ด้วยคำว่า " ซม."
      final parts = sizeTemplate.split(' ซม.');
      final dimensions = parts[0].split('*'); // แยกความกว้างกับความสูงด้วย '*'

      final String width = dimensions[0].trim();
      final String height = dimensions[1].trim();

      // 2. ดึงตัวเลขลิตร โดยตัดข้อความส่วนเกินออก
      final int startIdx = sizeTemplate.indexOf('ความจุ ') + 'ความจุ '.length;
      final int endIdx = sizeTemplate.indexOf(' ลิตร');
      final String liters = sizeTemplate
          .substring(startIdx, endIdx)
          .replaceAll(',', '')
          .trim();

      // 3. เอาค่าที่แกะได้ไปใส่ใน Controller ทั้ง 3 ช่อง
      setState(() {
        _widthController.text = width;
        _heightController.text = height;
        _literController.text = liters;
        _selectedTemplateIndex = index;
      });

      _showSnackBar('ดึงค่าเข้าช่องกรอกแล้ว กรุณากดปุ่มบันทึกเพื่อยืนยัน');
    } catch (e) {
      _showSnackBar('ไม่สามารถดึงข้อมูลขนาดได้: $e');
    }
  }

  // ⌨️ เมื่อผู้ใช้แก้ไขช่องกรอกเอง ให้เลิกไฮไลต์การ์ดที่เคยเลือกไว้ (ค่าจริงไม่ตรงกันแล้ว)
  void _onManualEdit() {
    if (_selectedTemplateIndex != null) {
      setState(() => _selectedTemplateIndex = null);
    }
  }

  // 🚀 ฟังก์ชันส่งค่าอัปเดตขึ้น Firebase แบบ "รอผลลัพธ์จริง" (await)
  // คืนค่า true ถ้าสำเร็จ, false ถ้าล้มเหลว (พร้อม log error ชัดเจน)
  Future<bool> _saveTankSettingsToFirebase({
    required double depth,
    required double capacity,
    required String rawString,
  }) async {
    try {
      await _dbRef.child('setting').update({
        'tank_depth': depth, // ส่งตัวเลขความสูงตรงๆ ให้บอร์ด ESP32 ไปคำนวณ
        'tank_capacity': capacity, // ส่งตัวเลขความจุตรงๆ ให้บอร์ด ESP32 ไปคำนวณ
        'tank_size': rawString, // เก็บสตริงเต็มไว้เช็คบนฐานข้อมูล
      });
      debugPrint('✅ Firebase Update Success: $rawString');
      return true;
    } catch (error) {
      // 🚀 ตรงนี้คือจุดสำคัญ ถ้าบันทึกไม่ผ่าน (เช่น permission denied,
      // databaseURL ผิด, ไม่มีเน็ต) จะเห็น error ชัดเจนใน console
      debugPrint('❌ Firebase Update Error: $error');
      return false;
    }
  }

  // 🛠️ ฟังก์ชันประมวลผลเมื่อกดปุ่มบันทึก (แก้ปัญหา Scudo Allocator + รอผล Firebase จริง)
  Future<void> _handleCustomSizeSubmit() async {
    if (_isSaving) return; // กันกดซ้ำ

    final width = _widthController.text.trim();
    final height = _heightController.text.trim();
    final liters = _literController.text.trim();

    // ตรวจสอบว่ากรอกครบทุกช่องไหม
    if (width.isEmpty || height.isEmpty || liters.isEmpty) {
      _showSnackBar('กรุณากรอกข้อมูลให้ครบทุกช่องก่อนบันทึก');
      return;
    }

    // แปลงสตริงให้กลายเป็นตัวเลข
    final double? parsedDepth = double.tryParse(height);
    final double? parsedCapacity = double.tryParse(liters);

    if (parsedDepth == null || parsedCapacity == null) {
      _showSnackBar('กรุณากรอกข้อมูลเป็นตัวเลขที่ถูกต้อง');
      return;
    }

    final formattedSize = '$width*$height ซม. ความจุ $liters ลิตร';

    // 🚀 ซ่อนคีย์บอร์ดแบบนุ่มนวลก่อนบันทึก
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() => _isSaving = true);

    // 🚀 รอผลลัพธ์จาก Firebase ก่อนตัดสินใจว่าจะไปหน้าถัดไปหรือไม่
    final success = await _saveTankSettingsToFirebase(
      depth: parsedDepth,
      capacity: parsedCapacity,
      rawString: formattedSize,
    );

    if (!mounted) return;

    setState(() => _isSaving = false);

    if (!success) {
      // 🚀 บันทึกไม่สำเร็จ แจ้งผู้ใช้ชัดเจน ไม่เปลี่ยนหน้า
      _showSnackBar(
        'บันทึกข้อมูลไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่',
      );
      return;
    }

    _showSnackBar('บันทึกข้อมูลสำเร็จ');

    // 🚀 ใช้ pushAndRemoveUntil เพื่อล้างหน้าเก่าทิ้งทันที เคลียร์ Memory Leak
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const WaterTankPage()),
      (Route<dynamic> route) =>
          false, // เคลียร์ทุกหน้าจอเก่าออกไปจากหน่วยความจำ
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    _literController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 209, 219, 226),
      appBar: AppBar(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.title),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 20),
                  ..._tankSizes.asMap().entries.map(
                        (e) => _buildSizeCard(e.key, e.value),
                      ),
                  const SizedBox(height: 8),
                  _buildOrDivider(),
                  const SizedBox(height: 16),
                  _buildCustomSizeCard(),
                  const SizedBox(height: 20),
                  _buildSaveButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------
  // 🏷️ ส่วนหัว: ไอคอนและคำอธิบายสั้นๆ
  // -----------------------------------------------------------------
  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.blue.shade300, Colors.blue.shade600],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.35),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.water_drop, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 12),
        const Text(
          'เลือกขนาดแทงค์น้ำ',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'แตะเลือกจากขนาดมาตรฐาน หรือกำหนดขนาดเองด้านล่าง',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  // -----------------------------------------------------------------
  // 🛢️ การ์ดขนาดแทงค์มาตรฐานแต่ละรายการ
  // -----------------------------------------------------------------
  Widget _buildSizeCard(int index, String size) {
    final info = _parseTankSize(size);
    final bool isSelected = _selectedTemplateIndex == index;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: InkWell(
        onTap: () => _fillControllerFromTemplate(index, size),
        borderRadius: BorderRadius.circular(14.0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(14.0),
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.grey.shade200,
              width: isSelected ? 1.8 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _MiniTankIcon(
                  color: isSelected ? Colors.white : Colors.blue,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          info.dimensions,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        if (info.tag != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Text(
                              info.tag!,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ความจุ ${info.liters}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isSelected ? Icons.check_circle : Icons.chevron_right,
                color: isSelected ? Colors.blue : Colors.grey.shade300,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------
  // ➖ เส้นแบ่ง "หรือกำหนดขนาดเอง"
  // -----------------------------------------------------------------
  Widget _buildOrDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade300)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'หรือกำหนดขนาดเอง',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey.shade300)),
      ],
    );
  }

  // -----------------------------------------------------------------
  // ✏️ การ์ดกรอกขนาดเอง (กว้าง / สูง / ความจุ)
  // -----------------------------------------------------------------
  Widget _buildCustomSizeCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18.0),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, color: Colors.blue.shade600, size: 18),
              const SizedBox(width: 8),
              const Text(
                'กำหนดขนาดเอง',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildSizeField(
                  controller: _widthController,
                  label: 'กว้าง (ซม.)',
                  icon: Icons.straighten,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSizeField(
                  controller: _heightController,
                  label: 'สูง (ซม.)',
                  icon: Icons.height,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSizeField(
                  controller: _literController,
                  label: 'ความจุ (ลิตร)',
                  icon: Icons.opacity,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSizeField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      onChanged: (_) => _onManualEdit(),
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 11.5),
        prefixIcon: Icon(icon, size: 18, color: Colors.blue.shade300),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.blue.shade400, width: 1.4),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------
  // 💾 ปุ่มบันทึกข้อมูลและนำทางไปหน้า watertank.dart
  // -----------------------------------------------------------------
  Widget _buildSaveButton() {
    return SizedBox(
      height: 54,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          elevation: 3,
          shadowColor: Colors.blue.withOpacity(0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
        ),
        // 🚀 ปิดปุ่มระหว่างกำลังบันทึก กันกดซ้ำ
        onPressed: _isSaving ? null : _handleCustomSizeSubmit,
        icon: _isSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.save),
        label: Text(
          _isSaving ? 'กำลังบันทึก...' : 'บันทึกข้อมูลขนาดแทงค์',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
    );
  }
}
