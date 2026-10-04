import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/water_tips.dart';

// =====================================================================
// 🧪 เทสต์ตรรกะล้วนของการ์ด "คำแนะนำประหยัดน้ำ" (lib/water_tips.dart)
//    การ์ดนี้ "แสดงตลอด" และเปลี่ยน 1 ประโยคตามสถานะระดับน้ำ
//    🎯 เหลือ 2 แบบข้อความตามเกณฑ์ 70% (70–100% ปกติ / 0–69% ให้ประหยัด)
//    ไม่ต้องต่อ Firebase จึงรันได้ทันที
//
//    flutter test test/water_tips_test.dart
// =====================================================================
void main() {
  WaterTipInput input({
    bool hasData = true,
    double percent = 80,
    double currentLiters = 400,
    double flowRate = 0,
    double? estimatedDaysRemaining,
  }) {
    return WaterTipInput(
      hasData: hasData,
      percent: percent,
      currentLiters: currentLiters,
      flowRate: flowRate,
      estimatedDaysRemaining: estimatedDaysRemaining,
    );
  }

  group('buildWaterTips — แสดงตลอดทุกช่วงระดับน้ำ', () {
    test('ทุกช่วงระดับน้ำ → แสดงการ์ด (ไม่ซ่อน)', () {
      for (final double p in <double>[10, 25, 40, 50, 60, 75, 90, 100]) {
        final r = buildWaterTips(input(percent: p, flowRate: 2));
        expect(r.shouldShow, isTrue, reason: 'ระดับน้ำ $p% ต้องแสดงการ์ด');
      }
    });

    test('แสดงเพียง 1 ประโยคต่อการ์ด (ตาม kMaxTips)', () {
      final r = buildWaterTips(input(percent: 10, flowRate: 2));
      expect(r.tips.length, kMaxTips);
      expect(r.tips.single.text, isNotEmpty);
    });

    test('ไม่มีข้อมูลจากเซ็นเซอร์ → ซ่อนการ์ด', () {
      final r = buildWaterTips(input(hasData: false, percent: 10));
      expect(r.shouldShow, isFalse);
      expect(r.tips, isEmpty);
    });
  });

  group('buildWaterTips — เหลือ 2 แบบข้อความตามเกณฑ์ 70%', () {
    test('69.9% → ยังไม่ถึงเกณฑ์ → "กรุณาใช้น้ำแบบประหยัด"', () {
      final r = buildWaterTips(input(percent: 69.9, currentLiters: 1048));
      expect(r.tips.single.text, contains('1048 ลิตร'));
      expect(r.tips.single.text, contains('69.9%'));
      expect(r.tips.single.text, contains('กรุณาใช้น้ำแบบประหยัด'));
    });

    test('ขอบเขต 70% → เริ่ม "ใช้น้ำได้ตามปกติ"', () {
      final r = buildWaterTips(input(percent: 70, flowRate: 2));
      expect(r.tips.single.text, contains('ใช้น้ำได้ตามปกติ'));
      expect(r.tips.single.text, isNot(contains('ประหยัด')));
      expect(r.trigger, WaterTipTrigger.normal);
      expect(r.tips.single.level, WaterTipLevel.info);
    });

    test('70–100% → ใช้น้ำได้ตามปกติ (ไม่พูดถึงการประหยัด)', () {
      for (final double p in <double>[70, 75.1, 80, 99, 100]) {
        final r = buildWaterTips(input(percent: p, currentLiters: 1485));
        expect(r.tips.single.text, contains('ใช้น้ำได้ตามปกติ'));
        expect(r.tips.single.text, isNot(contains('ประหยัด')));
        expect(r.tips.single.level, WaterTipLevel.info);
      }
    });

    test('0–69% → "กรุณาใช้น้ำแบบประหยัด" ทุกช่วง', () {
      for (final double p in <double>[1, 12, 25.1, 40, 50.1, 69]) {
        final r = buildWaterTips(input(percent: p, currentLiters: 100));
        expect(r.tips.single.text, contains('กรุณาใช้น้ำแบบประหยัด'));
        expect(r.tips.single.text, isNot(contains('ตามปกติ')));
      }
    });

    test('รูปแบบประโยค: "น้ำในถังเหลือ <pct>% (<ลิตร> ลิตร) ใช้ได้อีก ~<วัน> วัน — <คำแนะนำ>"', () {
      final r = buildWaterTips(
        input(percent: 99, currentLiters: 1485, estimatedDaysRemaining: 789),
      );
      expect(
        r.tips.single.text,
        'น้ำในถังเหลือ 99% (1485 ลิตร) ใช้ได้อีก ~789 วัน — ใช้น้ำได้ตามปกติ',
      );
    });

    test('สี/ไอคอนยังแยกระดับน้ำ (≤ 25% วิกฤต / < 70% ควรระวัง / ≥ 70% ปกติ)', () {
      expect(
        buildWaterTips(input(percent: 25, flowRate: 2)).trigger,
        WaterTipTrigger.criticalLevel,
      );
      expect(
        buildWaterTips(input(percent: 25, flowRate: 2)).tips.single.level,
        WaterTipLevel.critical,
      );
      expect(
        buildWaterTips(input(percent: 25.1, flowRate: 2)).trigger,
        WaterTipTrigger.lowLevel,
      );
      expect(
        buildWaterTips(input(percent: 40, flowRate: 2)).tips.single.level,
        WaterTipLevel.warning,
      );
      expect(
        buildWaterTips(input(percent: 69, flowRate: 2)).tips.single.level,
        WaterTipLevel.warning,
      );
      expect(
        buildWaterTips(input(percent: 70, flowRate: 2)).tips.single.level,
        WaterTipLevel.info,
      );
    });
  });

  group('buildWaterTips — ตัดคำเตือนเฉพาะกรณีออกแล้ว', () {
    test('อัตราการไหลไม่มีผลกับข้อความ (ไม่มีคำว่า ปั๊ม / รอยรั่ว แล้ว)', () {
      for (final double f in <double>[0, 0.01, 3, 35]) {
        final r = buildWaterTips(input(percent: 20, flowRate: f));
        expect(r.tips.single.text, contains('กรุณาใช้น้ำแบบประหยัด'));
        expect(r.tips.single.text, isNot(contains('ปั๊ม')));
        expect(r.tips.single.text, isNot(contains('รอยรั่ว')));

        final r2 = buildWaterTips(input(percent: 80, flowRate: f));
        expect(r2.tips.single.text, contains('ใช้น้ำได้ตามปกติ'));
        expect(r2.trigger, WaterTipTrigger.normal);
      }
    });
  });

  group('buildWaterTips — ข้อความที่แสดง', () {
    test('มีข้อมูลเวลาที่เหลือ → ต่อท้ายเป็นวัน', () {
      final r = buildWaterTips(
        input(percent: 80, currentLiters: 400, estimatedDaysRemaining: 2.5),
      );
      expect(r.tips.single.text, contains('ใช้ได้อีก ~2.5 วัน'));
    });

    test('เหลือน้ำ < 1 วัน → แสดงหน่วยชั่วโมง', () {
      final r = buildWaterTips(
        input(percent: 20, currentLiters: 60, estimatedDaysRemaining: 0.4),
      );
      expect(r.tips.single.text, contains('ชั่วโมง'));
    });

    test('ไม่มีข้อมูลเวลาที่เหลือ → ไม่มีคำว่า "ใช้ได้อีก"', () {
      final r = buildWaterTips(
        input(percent: 80, estimatedDaysRemaining: null),
      );
      expect(r.tips.single.text, isNot(contains('ใช้ได้อีก')));
    });

    test('ทุกช่วงมีป้ายอ้างอิง (reason) ไม่ว่าง', () {
      for (final double p in <double>[10, 40, 60, 90]) {
        final r = buildWaterTips(input(percent: p, flowRate: 2));
        expect(r.tips.single.reason, isNotEmpty);
      }
    });
  });
}
