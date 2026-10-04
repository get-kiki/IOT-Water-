// =====================================================================
// 🧩 ai_reply.dart — แยกคำตอบดิบของ AI (Gemini) ออกเป็นส่วน ๆ
//
//    หน้าจอ AI (ai_page.dart) ขอให้ Gemini ตอบ 3 บล็อกตามลำดับตายตัว:
//      [สรุป]       → บทวิเคราะห์พฤติกรรมการใช้น้ำ (2-3 ประโยค)
//      [คาดการณ์]   → แนวโน้มระดับน้ำ 5 วันข้างหน้า (ตารางวัน + เวลาที่จะหมด)
//      [คำแนะนำ]    → ข้อประหยัดน้ำ (สูงสุด 3 ข้อ)
//
//    ไฟล์นี้เป็น "ฟังก์ชันล้วน" ไม่พึ่ง Flutter / Firebase เลย
//    → เขียนเทสต์ได้โดยไม่ต้องมีเน็ตหรือ Firebase (แพตเทิร์นเดียวกับ
//      water_tips.dart / ai_policy.dart)
//
//    เกณฑ์ระดับความเสี่ยงชุดเดียวกับ notification_service.dart:
//      ≤ 25% = critical / ≤ 50% = warning / > 50% = info
// =====================================================================

/// 📋 หัวข้อที่ใช้แบ่งส่วนคำตอบของ AI (ต้องตรงกับ prompt ใน ai_page.dart)
const String kSummaryHeader = '[สรุป]';
const String kForecastHeader = '[คาดการณ์]';
const String kTipsHeader = '[คำแนะนำ]';

/// 📈 จำนวนวันที่คาดการณ์ในหนึ่งคำตอบ
const int kForecastDays = 5;

/// 🔴🟡🔵 ระดับความเสี่ยงที่ AI ส่งกลับมาได้ (ใช้คู่กับ notification.dart)
const Set<String> kForecastLevels = <String>{'critical', 'warning', 'info'};

/// 📈 หนึ่งวันในคำตอบคาดการณ์
class ForecastDay {
  final int day; // 1..5
  final double percent; // 0-100
  final String level; // critical|warning|info
  final String note; // เหตุผลสั้น ๆ (ว่างได้สำหรับวันที่คำนวณเอง)

  const ForecastDay({
    required this.day,
    required this.percent,
    required this.level,
    required this.note,
  });
}

/// 🔮 ผลคาดการณ์ทั้ง 5 วัน + เวลาที่คาดว่าน้ำจะหมด
class AiForecast {
  final List<ForecastDay> days;
  final int? emptyDay; // วันที่น้ำจะหมด (1..5) หรือ null
  final String? emptyClock; // เวลาที่คาดว่าน้ำจะหมดในวันนั้น (HH:MM) หรือ null

  const AiForecast({
    required this.days,
    this.emptyDay,
    this.emptyClock,
  });

  bool get isEmptyDay => emptyDay == null;
}

// =====================================================================
// 🧩 แยก "บทสรุป" / "คำแนะนำ"
// =====================================================================

/// 📖 บทสรุป = ข้อความตั้งแต่ต้น ถึงบล็อกถัดไป ([คาดการณ์] หรือ [คำแนะนำ])
///    ตัดหัว [สรุป] ทิ้ง และตัดบล็อกคาดการณ์ออกเพื่อไม่ให้ปนเข้ามาในสรุป
String narrativeOf(String raw) {
  final int cut = _firstHeaderIndex(
    raw,
    const <String>[kForecastHeader, kTipsHeader],
  );
  final String head = cut >= 0 ? raw.substring(0, cut) : raw;
  return head.replaceAll(kSummaryHeader, '').trim();
}

/// 📋 คำแนะนำ = ข้อความหลัง [คำแนะนำ] (สูงสุด 3 ข้อ)
List<String> tipsOf(String raw) {
  final int cut = raw.indexOf(kTipsHeader);
  if (cut < 0) return const <String>[];
  final String body = raw.substring(cut + kTipsHeader.length);
  final List<String> tips = <String>[];
  for (final String line in body.split('\n')) {
    // ตัดหัวข้อย่อย (- * • 1. 1)) ออกให้เหลือแต่เนื้อความ
    final String cleaned = line
        .replaceFirst(RegExp(r'^[\s\-\*•\d\.\)]+'), '')
        .trim();
    if (cleaned.isEmpty) continue;
    tips.add(cleaned);
    if (tips.length == 3) break;
  }
  return tips;
}

int _firstHeaderIndex(String raw, List<String> headers) {
  int best = -1;
  for (final String header in headers) {
    final int index = raw.indexOf(header);
    if (index >= 0 && (best < 0 || index < best)) best = index;
  }
  return best;
}

// =====================================================================
// 🔮 แยก "คาดการณ์"
// =====================================================================

/// 📦 คืนเนื้อความของบล็อก [คาดการณ์] (ระหว่าง [คาดการณ์] กับ [คำแนะนำ])
///    คืน null ถ้าไม่มีบล็อกนี้ในคำตอบ
String? forecastBlockOf(String raw) {
  final int start = raw.indexOf(kForecastHeader);
  if (start < 0) return null;
  final int bodyStart = start + kForecastHeader.length;
  final int end = raw.indexOf(kTipsHeader, bodyStart);
  final String body = end >= 0
      ? raw.substring(bodyStart, end)
      : raw.substring(bodyStart);
  return body.trim();
}

/// 🔮 แปลงคำตอบดิบ (ทั้งข้อความ) เป็นผลคาดการณ์
///    คืน null ถ้าไม่มีบล็อก หรือข้อมูลไม่ผ่านการตรวจ (→ ใช้สูตรระบบแทน)
AiForecast? forecastFromReply(String raw, {required double currentPercent}) {
  final String? block = forecastBlockOf(raw);
  if (block == null || block.isEmpty) return null;
  return forecastFromBlock(block, currentPercent: currentPercent);
}

/// 🔮 แปลง "เนื้อความของบล็อกคาดการณ์" (ที่เก็บไว้ใน ai_state) เป็นผลคาดการณ์
AiForecast? forecastFromBlock(String block, {required double currentPercent}) {
  final List<ForecastDay> days = <ForecastDay>[];
  int? emptyDay;
  String? emptyClock;

  for (final String rawLine in block.split('\n')) {
    final String line = rawLine.trim();
    if (line.isEmpty) continue;

    // บรรทัดบอกเวลาที่น้ำจะหมด: หมด|<วัน 1-5 หรือ ->|<HH:MM>
    if (line.startsWith('หมด|')) {
      final List<String> parts = line.split('|');
      if (parts.length >= 3) {
        final String dayToken = parts[1].trim();
        final String clock = parts[2].trim();
        if (dayToken != '-' && dayToken.isNotEmpty) {
          final int? parsed = int.tryParse(dayToken);
          if (parsed != null && parsed >= 1 && parsed <= kForecastDays) {
            emptyDay = parsed;
          }
        }
        if (_isClock(clock)) emptyClock = clock;
      }
      continue;
    }

    final ForecastDay? day = _parseDayLine(line);
    if (day != null) days.add(day);
  }

  if (days.isEmpty) return null;

  days.sort((ForecastDay a, ForecastDay b) => a.day.compareTo(b.day));

  // --- ตรวจความถูกต้อง (ไม่ผ่าน = คืน null → ใช้สูตรระบบ) ---
  // 1) ต้องเริ่มที่วัน 1 และเรียงต่อเนื่องกันไม่ข้ามวัน (วัน 1,2,3,...)
  for (int i = 0; i < days.length; i++) {
    if (days[i].day != i + 1) return null;
  }

  // 2) วัน 1 ต้องใกล้เปอร์เซ็นต์ปัจจุบัน (ต่างไม่เกิน 15) — กัน AI เดาเพี้ยน
  if ((days.first.percent - currentPercent).abs() > 15) return null;

  // 3) เปอร์เซ็นต์ต้องไม่เพิ่มขึ้นในแต่ละวัน (ยอม tolerance จากการปัดเศษ)
  for (int i = 1; i < days.length; i++) {
    if (days[i].percent > days[i - 1].percent + 0.001) return null;
  }

  return AiForecast(days: days, emptyDay: emptyDay, emptyClock: emptyClock);
}

ForecastDay? _parseDayLine(String line) {
  final List<String> parts = line.split('|');
  if (parts.length < 5) return null;
  final String token = parts[0].trim();
  if (token != 'วัน' && token != 'day') return null;
  final int? day = int.tryParse(parts[1].trim());
  if (day == null || day < 1 || day > kForecastDays) return null;
  final double? percent = double.tryParse(parts[2].trim());
  if (percent == null || percent < 0 || percent > 100) return null;
  final String level = parts[3].trim().toLowerCase();
  if (!kForecastLevels.contains(level)) return null;
  final String note = parts.sublist(4).join('|').trim();
  if (note.isEmpty) return null;
  return ForecastDay(day: day, percent: percent, level: level, note: note);
}

bool _isClock(String value) {
  if (!RegExp(r'^\d{1,2}:\d{2}$').hasMatch(value)) return false;
  final int h = int.parse(value.split(':')[0]);
  final int m = int.parse(value.split(':')[1]);
  return h >= 0 && h <= 23 && m >= 0 && m <= 59;
}

// =====================================================================
// 🧮 สูตรระบบ (fallback) + ป้ายวันที่ + ระดับความเสี่ยง
// =====================================================================

/// 🧮 คำนวณเปอร์เซ็นต์คาดการณ์แบบเส้นตรง (สูตรระบบเดิม) 5 วัน
///    ใช้เป็น fallback เมื่อ AI ไม่ตอบ / ตอบไม่ครบ / ตอบไม่ถูกต้อง
List<double> localForecastPercents({
  required double currentPercent,
  required double averageDailyLiters,
  required double capacity,
}) {
  final double dropPerDay = (averageDailyLiters > 0 && capacity > 0)
      ? (averageDailyLiters / capacity) * 100.0
      : 0.0;
  return List<double>.generate(
    kForecastDays,
    (int i) => (currentPercent - dropPerDay * i).clamp(0.0, 100.0),
  );
}

/// 🧮 สร้างผลคาดการณ์ 5 วันที่ "ยึดค่าเฉลี่ยการใช้น้ำ" ล้วน ๆ (สูตรระบบ)
///    • เปอร์เซ็นต์มาจาก [localForecastPercents] (averageDailyLiters ÷ capacity × 100)
///      → ไม่ใช้ตัวเลขเปอร์เซ็นต์ที่ AI เดาเอง เพื่อให้กราฟ / จำนวนวันคงเหลือ /
///        การ์ดค่าเฉลี่ย เล่าเรื่องตรงกันทั้งหมด
///    • ระดับความเสี่ยงคิดจากเปอร์เซ็นต์เอง (ไม่ใช้ level ของ AI)
///    • [notes] = เหตุผลสั้น ๆ ของ AI แยกตามเลขวัน (ใช้เป็นข้อความ "แนวโน้ม" เท่านั้น)
///    ฟังก์ชันล้วน ไม่พึ่ง Flutter → เทสต์ได้
List<ForecastDay> averageDrivenForecast({
  required double currentPercent,
  required double averageDailyLiters,
  required double capacity,
  Map<int, String> notes = const <int, String>{},
}) {
  final List<double> percents = localForecastPercents(
    currentPercent: currentPercent,
    averageDailyLiters: averageDailyLiters,
    capacity: capacity,
  );
  return List<ForecastDay>.generate(
    kForecastDays,
    (int i) => ForecastDay(
      day: i + 1,
      percent: percents[i],
      level: levelForPercent(percents[i]),
      note: notes[i + 1] ?? '',
    ),
  );
}

/// 🎨 ระดับความเสี่ยงที่ใช้แสดง — อิง AI แต่ "ยกระดับได้ ห้ามลดระดับ"
///    (กันกรณี AI บอก info ทั้งที่เปอร์เซ็นต์ต่ำมาก → ระบบบังคับสูงกว่า)
String resolveForecastLevel(double percent, String aiLevel) {
  if (percent <= 25) return 'critical';
  if (percent <= 50) {
    return aiLevel == 'critical' ? 'critical' : 'warning';
  }
  return aiLevel;
}

/// 🎨 ระดับความเสี่ยงตามเกณฑ์เปอร์เซ็นต์ล้วน (ใช้กับวันที่คำนวณเอง)
String levelForPercent(double percent) {
  if (percent <= 25) return 'critical';
  if (percent <= 50) return 'warning';
  return 'info';
}

const List<String> _thaiWeekdayShort = <String>[
  '', // 0 (ไม่ใช้)
  'จ.', // 1 = จันทร์
  'อ.', // 2 = อังคาร
  'พ.', // 3 = พุธ
  'พฤ.', // 4 = พฤหัส
  'ศ.', // 5 = ศุกร์
  'ส.', // 6 = เสาร์
  'อา.', // 7 = อาทิตย์
];

/// 📅 ป้ายวันที่ 5 วันข้างหน้า (วันนี้ / พรุ่งนี้ / ชื่อวัน + d/M)
List<String> forecastDateLabels(DateTime now) {
  final List<String> labels = <String>[];
  for (int i = 0; i < kForecastDays; i++) {
    final DateTime date = now.add(Duration(days: i));
    final String weekday = _thaiWeekdayShort[date.weekday];
    if (i == 0) {
      labels.add('วันนี้ ${date.day}/${date.month}');
    } else if (i == 1) {
      labels.add('พรุ่งนี้ ${date.day}/${date.month}');
    } else {
      labels.add('$weekday ${date.day}/${date.month}');
    }
  }
  return labels;
}

/// 📅 ตารางวันที่ 5 วัน ส่งให้ AI อ้างอิงวันจริงในคำตอบ (ไม่ต้องให้ AI คิดวันที่เอง)
String forecastDateContext(DateTime now) {
  final List<String> labels = forecastDateLabels(now);
  final StringBuffer buffer = StringBuffer()
    ..writeln('วันที่ของกราฟคาดการณ์ (วัน 1 = วันนี้):');
  for (int i = 0; i < labels.length; i++) {
    buffer.writeln('  วัน ${i + 1} = ${labels[i]}');
  }
  return buffer.toString();
}



