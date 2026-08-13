import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

// 🚀 เชื่อมโยงไปที่ไฟล์ watertank.dart ของคุณ
import 'watertank.dart';

void main() async {
  // บังคับให้จัดการทำงานแบบ Async และผูกระบบกับ Firebase ก่อนเปิดแอป
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
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
  void _fillControllerFromTemplate(String sizeTemplate) {
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
      });

      _showSnackBar('ดึงค่าเข้าช่องกรอกแล้ว กรุณากดปุ่มบันทึกเพื่อยืนยัน');
    } catch (e) {
      _showSnackBar('ไม่สามารถดึงข้อมูลขนาดได้: $e');
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
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
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
      appBar: AppBar(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: _tankSizes.length,
                    itemBuilder: (context, index) {
                      final size = _tankSizes[index];

                      String mainText = size;
                      String popularText = '';

                      if (size.contains(' (นิยมที่สุด)')) {
                        mainText = size.replaceAll(' (นิยมที่สุด)', '');
                        popularText = ' (นิยมที่สุด)';
                      } else if (size.contains(' (นิยม)')) {
                        mainText = size.replaceAll(' (นิยม)', '');
                        popularText = ' (นิยม)';
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: InkWell(
                          onTap: () => _fillControllerFromTemplate(size),
                          borderRadius: BorderRadius.circular(12.0),
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12.0),
                              border: Border.all(
                                color: Colors.blue.shade200,
                                width: 1.5,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: RichText(
                              textAlign: TextAlign.center,
                              text: TextSpan(
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                                children: [
                                  TextSpan(text: mainText),
                                  if (popularText.isNotEmpty)
                                    TextSpan(
                                      text: popularText,
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 13,
                                        fontWeight: FontWeight.normal,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),

                // =========================================================
                // ส่วนที่ 3: ช่องกรอกข้อมูล (รับค่าอัตโนมัติจากการกดลิสต์ หรือพิมพ์เองก็ได้)
                // =========================================================
                const Text(
                  'ระบุขนาดแทงค์น้ำ (กว้าง * สูง และ ความจุ):',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // ช่องกรอก ความกว้าง
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: TextField(
                          controller: _widthController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'กว้าง (ซม.)',
                            labelStyle: const TextStyle(fontSize: 12),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // ช่องกรอก ความสูง
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: TextField(
                          controller: _heightController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'สูง (ซม.)',
                            labelStyle: const TextStyle(fontSize: 12),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // ช่องกรอก ปริมาตรลิตร
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: TextField(
                          controller: _literController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'ความจุ (ลิตร)',
                            labelStyle: const TextStyle(fontSize: 12),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // ปุ่มบันทึกข้อมูลและนำทางไปหน้า watertank.dart
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
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
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
