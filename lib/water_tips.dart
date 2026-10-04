// =====================================================================
// 💧 ระบบผู้เชี่ยวชาญตามเกณฑ์ (Rule-based) สำหรับการ์ด "คำแนะนำประหยัดน้ำ"
//
//    การ์ดนี้ "แสดงตลอด" และเปลี่ยนคำแนะนำตามสถานะระดับน้ำ (การ์ดละ 1 ประโยค)
//    🎯 เหลือเพียง 2 แบบข้อความ โดยยึดเกณฑ์ 70%:
//      70–100%    = "ใช้น้ำได้ตามปกติ"            🟢 info
//      0–69.9%    = "กรุณาใช้น้ำแบบประหยัด"       🟡 warning / 🔴 critical
//    หมายเหตุ: คำเตือนเฉพาะกรณี (น้ำไม่ไหล → ตรวจปั๊ม/วาล์ว,
//    อัตราการไหล ≥ 30 ลิตร/นาที → เตือนรอยรั่ว) ถูกตัดออกตามที่ตกลงกันแล้ว
//    (การแจ้งเตือนระดับน้ำ/การไหลยังมีอยู่ที่ notification_service.dart)
//
//    สี/ไอคอนของการ์ดยังแยกระดับน้ำให้เห็นชัด (เกณฑ์เดียวกับ notification_service.dart):
//      ≤ 25%      = ระดับน้ำต่ำมาก (วิกฤต)   🔴 critical
//      < 70%      = ระดับน้ำต่ำ (ควรระวัง)    🟡 warning
//      ≥ 70%      = ระดับน้ำปกติ             🟢 info
//
//    ไฟล์นี้เป็น "ฟังก์ชันล้วน" ไม่พึ่ง Flutter / Firebase เลย
//    → เขียนเทสต์ได้โดยไม่ต้องมีเน็ตหรือ Firebase (แพตเทิร์นเดียวกับ ai_policy.dart)
// =====================================================================

/// 🔴 เกณฑ์ระดับน้ำต่ำมาก (ใช้กำหนดสี/ไอคอนของการ์ดเท่านั้น ไม่ได้กำหนดข้อความ)
const double kTipsCriticalPercent = 25.0;

/// 🎯 เกณฑ์คำแนะนำ: ต่ำกว่านี้ = "กรุณาใช้น้ำแบบประหยัด" / ตั้งแต่ค่านี้ขึ้นไป = "ใช้น้ำได้ตามปกติ"
const double kTipsSaveBelowPercent = 70.0;

/// จำนวนคำแนะนำสูงสุดต่อการ์ด
/// การ์ดนี้ออกแบบให้แสดง "1 ประโยค" ที่ตรงกับสถานะที่สุด
/// (ถ้าต้องการโชว์หลายข้อ เปลี่ยนเป็น 2 หรือ 3 ได้เลย)
const int kMaxTips = 1;

/// 🔴🟡🔵 ระดับความรุนแรงของคำแนะนำ (ใช้คู่กับสีใน notification.dart)
enum WaterTipLevel { critical, warning, info }

extension WaterTipLevelKey on WaterTipLevel {
  /// ส่งต่อให้ notificationColorFor / notificationIconFor / notificationLabelFor
  String get typeKey => switch (this) {
    WaterTipLevel.critical => 'critical',
    WaterTipLevel.warning => 'warning',
    WaterTipLevel.info => 'info',
  };
}

/// 💡 คำแนะนำ 1 ประโยค — เนื้อความ + ระดับความรุนแรง + เกณฑ์อ้างอิง
class WaterTip {
  /// รูปแบบข้อความ: "หัวข้อ: รายละเอียด" หรือ "สถานการณ์ — สิ่งที่ควรทำ"
  /// (ถ้ามีเครื่องหมาย ":" หน้าสองจุดจะขึ้นตัวหนาให้อัตโนมัติที่ UI)
  final String text;

  final WaterTipLevel level;

  /// เกณฑ์อ้างอิง เช่น 'เกณฑ์ ≤ 25%' — เก็บไว้ใช้ทดสอบ/ตรวจสอบย้อนหลัง
  /// (ปัจจุบันไม่ได้แสดงบนการ์ดแล้ว)
  final String reason;

  const WaterTip({
    required this.text,
    required this.level,
    required this.reason,
  });
}

/// 🎯 เหตุผลที่ระบบเลือกคำแนะนำนี้ (ใช้กำหนดสี/ไอคอนของการ์ด)
enum WaterTipTrigger { criticalLevel, lowLevel, normal }

class WaterTipsResult {
  final WaterTipTrigger trigger;

  /// ว่าง = ยังไม่มีข้อมูลจากเซ็นเซอร์ (จึงไม่แสดงการ์ด)
  final List<WaterTip> tips;

  const WaterTipsResult(this.trigger, this.tips);

  bool get shouldShow => tips.isNotEmpty;

  static const WaterTipsResult hidden = WaterTipsResult(
    WaterTipTrigger.normal,
    <WaterTip>[],
  );
}

/// 📥 ข้อมูลที่ส่งเข้า (ดึงจาก WaterSnapshot เป็นพารามิเตอร์ล้วน → เทสต์ง่าย)
class WaterTipInput {
  final bool hasData;
  final double percent; // 0-100
  final double currentLiters;
  final double flowRate; // ลิตร/นาที (ยังส่งเข้ามาเพื่อความเข้ากันได้ แต่ข้อความ 2 แบบนี้ไม่ใช้แล้ว)
  final double? estimatedDaysRemaining;

  const WaterTipInput({
    required this.hasData,
    required this.percent,
    required this.currentLiters,
    required this.flowRate,
    required this.estimatedDaysRemaining,
  });
}

/// 🧮 สร้างคำแนะนำ 1 ประโยคตามสถานะระดับน้ำ (เหลือ 2 แบบตามเกณฑ์ [kTipsSaveBelowPercent])
///    • 70–100%  → "น้ำในถังเหลือ … ใช้ได้อีก ~… วัน — ใช้น้ำได้ตามปกติ"
///    • 0–69.9%  → "น้ำในถังเหลือ … ใช้ได้อีก ~… วัน — กรุณาใช้น้ำแบบประหยัด"
///    • ถ้า [WaterTipInput.estimatedDaysRemaining] เป็น null (ข้อมูลวันเต็มวัน
///      ไม่ครบเกณฑ์ใน water_context.dart) ส่วน "ใช้ได้อีก ~… วัน" จะถูกตัดออก
///      → ประโยคสั้นลงเหลือ "น้ำในถังเหลือ … — <คำแนะนำ>"
/// (ผลลัพธ์ว่าง = ยังไม่มีข้อมูลจากเซ็นเซอร์ → ไม่แสดงการ์ด)
WaterTipsResult buildWaterTips(WaterTipInput i) {
  if (!i.hasData) return WaterTipsResult.hidden;

  final String pct = _fmt(i.percent);
  final String liters = _fmt(i.currentLiters);
  final String remain = _remainingText(i);
  final String body = 'น้ำในถังเหลือ $pct% ($liters ลิตร)$remain';

  // 🟢 70–100% → ใช้น้ำได้ตามปกติ
  if (i.percent >= kTipsSaveBelowPercent) {
    return _single(
      WaterTipTrigger.normal,
      '$body — ใช้น้ำได้ตามปกติ',
      WaterTipLevel.info,
      'เกณฑ์ ≥ ${_fmt(kTipsSaveBelowPercent)}%',
    );
  }

  // 🔴🟡 0–69% → กรุณาใช้น้ำแบบประหยัด (สี/ไอคอนยังบันทึกตามระดับน้ำให้เห็นชัด)
  return _single(
    _triggerFor(i.percent),
    '$body — กรุณาใช้น้ำแบบประหยัด',
    _levelFor(i.percent),
    'เกณฑ์ < ${_fmt(kTipsSaveBelowPercent)}%',
  );
}

/// 🎯 ระดับของทริกเกอร์ตามช่วงน้ำ (ใช้กำหนดสี/ไอคอนของการ์ด)
WaterTipTrigger _triggerFor(double percent) {
  if (percent <= kTipsCriticalPercent) return WaterTipTrigger.criticalLevel;
  return WaterTipTrigger.lowLevel;
}

/// 🔴🟡 ระดับความรุนแรงตามช่วงน้ำ (ต่ำกว่าเกณฑ์ประหยัด = เริ่มเตือนเป็นสีส้ม)
WaterTipLevel _levelFor(double percent) {
  if (percent <= kTipsCriticalPercent) return WaterTipLevel.critical;
  return WaterTipLevel.warning;
}

/// 🧩 รวมผลลัพธ์เป็น "1 ประโยค" ให้ทุกเส้นทางออกแบบเดียวกัน
WaterTipsResult _single(
  WaterTipTrigger trigger,
  String text,
  WaterTipLevel level,
  String reason,
) {
  return WaterTipsResult(trigger, <WaterTip>[
    WaterTip(text: text, level: level, reason: reason),
  ]);
}

/// ⏳ ต่อท้ายว่า "ใช้ได้อีกกี่วัน/ชั่วโมง" ('' = ยังไม่มีข้อมูล)
String _remainingText(WaterTipInput i) {
  final double? days = i.estimatedDaysRemaining;
  if (days == null || days <= 0) return '';
  if (days < 1) return ' ใช้ได้อีก ~${_fmt(days * 24)} ชั่วโมง';
  return ' ใช้ได้อีก ~${_fmt(days)} วัน';
}

/// 🧾 จัดรูปแบบตัวเลข: ลงตัว → ไม่มีทศนิยม, ไม่ลงตัว → ทศนิยม 1 ตำแหน่ง
String _fmt(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(1);
}
