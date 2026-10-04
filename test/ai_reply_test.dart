import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/ai_reply.dart';

// =====================================================================
// 🧪 เทสต์การแยกคำตอบดิบของ AI (ai_reply.dart)
//    (ฟังก์ชันล้วน → รันได้ทันทีโดยไม่ต้องมีเน็ต/Firebase)
//
//    flutter test test/ai_reply_test.dart
// =====================================================================
void main() {
  group('narrativeOf / tipsOf', () {
    test('แยกบทสรุปและคำแนะนำได้จากคำตอบ 3 บล็อก', () {
      const String raw =
          '[สรุป]\nน้ำเหลือ 60% ใช้ได้อีก 3 วัน\n'
          '[คาดการณ์]\nวัน|1|60|info|ปกติ\n'
          '[คำแนะนำ]\n- ปิดก๊อก\n- ตรวจท่อ\n';
      expect(narrativeOf(raw), 'น้ำเหลือ 60% ใช้ได้อีก 3 วัน');
      expect(tipsOf(raw), <String>['ปิดก๊อก', 'ตรวจท่อ']);
    });

    test('บทสรุปต้องไม่ดูดบล็อกคาดการณ์เข้ามาปน', () {
      const String raw =
          '[สรุป]\nสรุปย่อหน้าเดียว\n'
          '[คาดการณ์]\nวัน|1|60|info|ปกติ\nหมด|4|14:30\n'
          '[คำแนะนำ]\n- ปิดก๊อก\n';
      expect(narrativeOf(raw), 'สรุปย่อหน้าเดียว');
    });

    test('ไม่มีหัว [คำแนะนำ] → tips ว่าง', () {
      expect(tipsOf('[สรุป]\nแค่สรุป'), isEmpty);
    });
  });

  group('forecastFromReply', () {
    test('parse ครบ 5 วัน + เวลาหมด ได้ผลลัพธ์ถูกต้อง', () {
      const String raw =
          '[คาดการณ์]\n'
          'วัน|1|79|info|ยังใช้น้ำได้ตามปกติ\n'
          'วัน|2|58|warning|เริ่มต่ำ\n'
          'วัน|3|37|warning|ควรระวัง\n'
          'วัน|4|16|critical|วิกฤต\n'
          'วัน|5|0|critical|คาดว่าไม่เหลือ\n'
          'หมด|4|14:30\n'
          '[คำแนะนำ]\n- ปิดก๊อก\n';
      final AiForecast? f = forecastFromReply(raw, currentPercent: 82);
      expect(f, isNotNull);
      expect(f!.days.length, 5);
      expect(f.days.first.day, 1);
      expect(f.days.first.percent, 79);
      expect(f.days.first.level, 'info');
      expect(f.days.first.note, 'ยังใช้น้ำได้ตามปกติ');
      expect(f.emptyDay, 4);
      expect(f.emptyClock, '14:30');
    });

    test('วัน 1 ห่างจากปัจจุบันเกิน 15 → คืน null', () {
      const String raw = '[คาดการณ์]\nวัน|1|10|critical|x\n';
      expect(forecastFromReply(raw, currentPercent: 82), isNull);
    });

    test('เปอร์เซ็นต์เพิ่มขึ้น → คืน null', () {
      const String raw = '[คาดการณ์]\nวัน|1|50|warning|x\nวัน|2|60|warning|x\n';
      expect(forecastFromReply(raw, currentPercent: 52), isNull);
    });

    test('ค่าร้อยละหลุดช่วง 0-100 → คืน null', () {
      const String raw = '[คาดการณ์]\nวัน|1|120|info|x\n';
      expect(forecastFromReply(raw, currentPercent: 50), isNull);
    });

    test('ข้ามวัน (1,3) → คืน null', () {
      const String raw = '[คาดการณ์]\nวัน|1|50|warning|x\nวัน|3|30|warning|x\n';
      expect(forecastFromReply(raw, currentPercent: 52), isNull);
    });

    test('ไม่มีบล็อก [คาดการณ์] → คืน null', () {
      expect(forecastFromReply('[สรุป]\nเท่านั้น', currentPercent: 50), isNull);
    });

    test('หมด|-|- → emptyDay/emptyClock เป็น null', () {
      const String raw =
          '[คาดการณ์]\nวัน|1|70|info|x\nวัน|2|60|info|x\nหมด|-|-\n';
      final AiForecast? f = forecastFromReply(raw, currentPercent: 72);
      expect(f, isNotNull);
      expect(f!.emptyDay, isNull);
      expect(f.emptyClock, isNull);
    });
  });

  group('forecastFromBlock', () {
    test('parse เนื้อความที่บันทึกไว้ (ไม่มีหัว [คาดการณ์]) ได้', () {
      const String block = 'วัน|1|70|info|x\nวัน|2|60|info|x\nหมด|-|-\n';
      final AiForecast? f = forecastFromBlock(block, currentPercent: 72);
      expect(f, isNotNull);
      expect(f!.days.length, 2);
    });
  });

  group('localForecastPercents / resolveForecastLevel / forecastDateLabels', () {
    test('สูตรระบบลดเชิงเส้น 5 วัน', () {
      final List<double> v = localForecastPercents(
        currentPercent: 80,
        averageDailyLiters: 20,
        capacity: 100,
      );
      expect(v.length, 5);
      expect(v[0], closeTo(80, 0.001));
      expect(v[1], closeTo(60, 0.001));
      expect(v[4], closeTo(0, 0.001));
    });

    test('ยกระดับได้ ห้ามลดระดับ', () {
      expect(resolveForecastLevel(20, 'info'), 'critical');
      expect(resolveForecastLevel(40, 'info'), 'warning');
      expect(resolveForecastLevel(40, 'critical'), 'critical');
      expect(resolveForecastLevel(70, 'info'), 'info');
      expect(resolveForecastLevel(70, 'critical'), 'critical');
    });

    test('ป้ายวันที่ 5 วันถูกต้อง (วันนี้/พรุ่งนี้/ชื่อวัน)', () {
      final DateTime tue = DateTime(2026, 10, 6); // อังคาร
      final List<String> labels = forecastDateLabels(tue);
      expect(labels[0], 'วันนี้ 6/10');
      expect(labels[1], 'พรุ่งนี้ 7/10');
      expect(labels[2], 'พฤ. 8/10');
      expect(labels[3], 'ศ. 9/10');
      expect(labels[4], 'ส. 10/10');
    });
  });

  group('averageDrivenForecast — ยึดค่าเฉลี่ยการใช้น้ำ', () {
    test('เปอร์เซ็นต์คิดจากค่าเฉลี่ยล้วน (ไม่ใช้ค่าที่ AI เดา)', () {
      // ถัง 1500 ล. ค่าเฉลี่ย 1.88 ล./วัน → ลดวันละ 1.88/1500*100 ≈ 0.125%
      final List<ForecastDay> days = averageDrivenForecast(
        currentPercent: 99,
        averageDailyLiters: 1.88,
        capacity: 1500,
        notes: const <int, String>{1: 'ใช้น้ำตามปกติ'},
      );
      expect(days.length, 5);
      expect(days[0].percent, closeTo(99.0, 0.001));
      expect(days[4].percent, closeTo(99.0 - (1.88 / 1500 * 100) * 4, 0.001));
      // ยืนยันว่าเกือบนิ่งจริง (ไม่ใช่กราฟดิ่งแบบเดิม)
      expect(days[4].percent, greaterThan(98.4));
    });

    test('ระดับความเสี่ยงคิดจากเปอร์เซ็นต์เอง ไม่ใช้ level ที่ส่งมา', () {
      // ลด 30%/วัน → 100, 70, 40, 10, 0
      final List<ForecastDay> days = averageDrivenForecast(
        currentPercent: 100,
        averageDailyLiters: 30,
        capacity: 100,
      );
      expect(days[0].percent, closeTo(100, 0.001));
      expect(days[0].level, 'info');
      expect(days[2].percent, closeTo(40, 0.001));
      expect(days[2].level, 'warning');
      expect(days[3].level, 'critical');
    });

    test('แนบเหตุผลสั้นของ AI ตามวัน และวันอื่นเป็นค่าว่าง', () {
      final List<ForecastDay> days = averageDrivenForecast(
        currentPercent: 60,
        averageDailyLiters: 10,
        capacity: 100,
        notes: const <int, String>{2: 'เริ่มต่ำ'},
      );
      expect(days[1].note, 'เริ่มต่ำ');
      expect(days[0].note, isEmpty);
      expect(days[4].note, isEmpty);
    });

    test('ไม่มีการใช้น้ำ (ค่าเฉลี่ย 0) → กราฟนิ่งที่เปอร์เซ็นต์ปัจจุบัน', () {
      final List<ForecastDay> days = averageDrivenForecast(
        currentPercent: 55,
        averageDailyLiters: 0,
        capacity: 100,
      );
      for (final ForecastDay d in days) {
        expect(d.percent, closeTo(55, 0.001));
      }
    });

    test('ค่าเฉลี่ยสูงจนหมดถัง → ไม่ติดลบ (clamp 0)', () {
      final List<ForecastDay> days = averageDrivenForecast(
        currentPercent: 90,
        averageDailyLiters: 100,
        capacity: 100,
      );
      for (final ForecastDay d in days) {
        expect(d.percent, greaterThanOrEqualTo(0));
      }
      expect(days.last.percent, closeTo(0, 0.001));
    });
  });
}
