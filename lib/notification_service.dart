import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';

import 'water_context.dart';

// =====================================================================
// 🔔 เกณฑ์แจ้งเตือนอัตโนมัติ (ปรับได้ตามหน้างานจริง)
//
//    ระดับน้ำแบ่งเป็น 4 ช่วง (แจ้งตามระดับน้ำแบบเรียลไทม์):
//    ≤ 25%        = ระดับน้ำต่ำมาก (วิกฤต)   🔴 critical
//    25.1–50%     = ระดับน้ำต่ำ (ควรระวัง)     🟡 warning
//    50.1–75%     = ระดับน้ำ                   🟢 info
//    > 75%        = ระดับน้ำปกติ               🟢 info
//
//    การไหลแบ่งเป็น 2 สถานะ (แจ้งเฉพาะ หยุด / กลับมาไหล):
//    ≤ 0.01 ลิตร/นาที = ไม่ไหล → น้ำหยุดไหล
//    > 0.01 ลิตร/นาที = ไหลอยู่ → (ถ้าก่อนหน้าไม่ไหล) น้ำกลับมาไหล
//
//    🪣 ข้อยกเว้นสำคัญ "ถังเต็ม" (≥ kFullPercent):
//    พอน้ำเต็มถัง ลูกลอยจะปิดวาล์วเอง อัตราไหลเข้าจึงตกเป็น 0 เองตามกลไก
//    และจะเติมจิ๋ว ๆ สลับหยุดไปเรื่อย ๆ ทุกครั้งที่มีการใช้น้ำ
//    (0 → 0.13 → 0 วนไป) ถ้าแจ้งทุกครั้งจะกลายเป็นสแปมและสื่อผิดว่าระบบมีปัญหา
//    ทั้งที่จริงคือทำงานถูกต้อง → ตอนถังเต็มจึง "ไม่แจ้งเรื่องการไหลทั้ง 2 ทิศทาง"
//    เหลือแจ้งแค่ "ถังน้ำเต็มแล้ว" ครั้งเดียวตอนเพิ่งเต็ม
// =====================================================================
const double kCriticalPercent = 25.0; // ≤ 25% = ระดับน้ำต่ำมาก (วิกฤต)
const double kWarningPercent = 50.0; // ≤ 50% = ระดับน้ำต่ำ (ควรระวัง)
const double kNormalPercent = 75.0; // ≤ 75% = ระดับน้ำ (เกินนี้ = ระดับน้ำปกติ)
const double kHighFlowLpm = 30.0; // เกินนี้ถือว่าไหลเร็วผิดปกติ (ใช้ในคำแนะนำของระบบ)
/// ⏳ กันแจ้งซ้ำถี่เกินไป — นับ **แยกตาม "ราง + ระดับความรุนแรง"**
///
/// (`level:critical`, `level:warning`, `level:info`, `full:info`)
/// จึงไม่มีกรณีที่การแจ้ง `info` ไปบล็อกการแจ้ง `critical` ที่ตามมา
/// และการแจ้งที่ถูก cooldown กันไว้จะ **ไม่ถูกทิ้ง** — ระบบไม่ commit สถานะใหม่
/// แล้วลองแจ้งอีกครั้งในรอบถัดไปจนกว่าจะพ้น cooldown (ดู `_handleSnapshot`)
///
/// ⚠️ ราง `flow` **ไม่ใช้ cooldown** — ดู [kFlowCooldown]
const Duration kAlertCooldown = Duration(minutes: 15);

/// 💧 cooldown ของราง `flow` = **ศูนย์ (แจ้งทันที)**
///
/// น้ำไหล/หยุดไหลเป็นเหตุการณ์ที่ผู้ใช้ต้องการรู้ "ตอนนั้นเลย" การหน่วงไว้
/// 15 นาทีทำให้การแจ้งมาช้าหรือถูกยุบหายเมื่อการไหลเปลี่ยนสลับกันเร็ว
/// จึงตั้งเป็น 0 → ทุกครั้งที่สถานะการไหลเปลี่ยน (`none` ⇄ `flowing`) จะแจ้งทันที
///
/// ตัวกันสแปมของรางนี้ใช้ 2 อย่างแทน cooldown
///  1. แจ้งเฉพาะเมื่อ **สถานะเปลี่ยน** เท่านั้น (ไหลอยู่แล้วเร่ง/ลดความเร็วไม่แจ้ง)
///  2. guard ตอนถังเต็ม (≥ [kFullPercent]) ซึ่งเป็นต้นเหตุหลักของการแกว่งถี่
///     เพราะลูกลอยปิด-เปิดวาล์วเองเป็นจังหวะ
const Duration kFlowCooldown = Duration.zero;

/// 🪣 ตั้งแต่เปอร์เซ็นต์นี้ขึ้นไป = ถือว่า "ถังเต็ม"
///
/// ทำไมไม่ใช้ `== 100` เป๊ะ ๆ: ค่าจากเซ็นเซอร์ผ่านตัวกรองมาหลายชั้น
/// (มัธยฐาน 7 ค่า → EMA → ปัดทศนิยม 1 ตำแหน่งตอนส่งขึ้น Firebase)
/// บางจังหวะจึงอาจค้างอยู่ที่ 99.x แล้วการแจ้ง "เต็ม" จะไม่เกิดขึ้นเลย
/// ซึ่งแย่กว่าไม่มีฟีเจอร์นี้ เพราะผู้ใช้จะเข้าใจว่าระบบทำงานอยู่แต่จริง ๆ ไม่ใช่
const double kFullPercent = 99.0;

// =====================================================================
// ✍️ NotificationService — เขียนการแจ้งเตือนลง Firebase
//    โครงสร้างตรงกับที่ notification.dart อ่าน (title/message/type/timestamp/is_read)
// =====================================================================
class NotificationService {
  static final DatabaseReference _notiRef = FirebaseDatabase.instance.ref(
    'water_system/notifications',
  );

  /// ➕ เพิ่มการแจ้งเตือนใหม่ 1 รายการ
  /// [type] ใช้ได้ 3 ค่า ตามที่หน้าการแจ้งเตือนรองรับ: critical / warning / info
  static Future<void> push({
    required String title,
    required String message,
    String type = 'info',
  }) async {
    try {
      final newRef = _notiRef.push();
      await newRef.set(<String, dynamic>{
        'title': title,
        'message': message,
        'type': type,
        // ใช้เวลาจากเซิร์ฟเวอร์ กันนาฬิกาของมือถือ/ESP32 ไม่ตรงกัน
        'timestamp': ServerValue.timestamp,
        'is_read': false,
      });
    } catch (e) {
      debugPrint('Error pushing notification: $e');
    }
  }

  /// 🗑️ ลบการแจ้งเตือนที่ไม่ใช่วันนี้ทิ้ง กันปุ่มโตขึ้นเรื่อยๆ
  /// (เรียกได้จากหน้าแจ้งเตือนถ้าต้องการ)
  static Future<void> purgeOlderThan(Duration age) async {
    try {
      final snapshot = await _notiRef.once();
      final value = snapshot.snapshot.value;
      if (value is! Map) return;
      final cutoff = DateTime.now().subtract(age).millisecondsSinceEpoch;
      final data = Map<dynamic, dynamic>.from(value);
      for (final key in data.keys) {
        final entry = data[key];
        if (entry is! Map) continue;
        final ts = entry['timestamp'];
        if (ts is num && ts.toInt() > 0 && ts.toInt() < cutoff) {
          await _notiRef.child(key.toString()).remove();
        }
      }
    } catch (e) {
      debugPrint('Error purging notifications: $e');
    }
  }
}

/// 📩 รายการแจ้งเตือนที่เพิ่งถูกสร้างขึ้น (ส่งต่อให้หน้าจอโชว์ SnackBar)
class TankAlert {
  final String title;
  final String message;
  final String type; // critical / warning / info

  const TankAlert({
    required this.title,
    required this.message,
    required this.type,
  });
}

// =====================================================================
// 👀 TankAlertWatcher — เฝ้าดูสถานะถังน้ำ แล้วเขียนการแจ้งเตือนอัตโนมัติ
//
//    ทำงานร่วมกับ WaterContextWatcher (อ่าน Firebase)
//    → ตรวจเกณฑ์ (ระดับน้ำ 4 ช่วง + การไหล หยุด/กลับมาไหล)
//    → เขียนลง water_system/notifications ผ่าน NotificationService
//    → เรียก onAlert(...) ให้หน้าจอโชว์ SnackBar ได้ทันที
//
//    สถานะเดิมถูกเก็บไว้ที่ water_system/notification_state
//    เพื่อไม่ให้แจ้งซ้ำทุกครั้งที่เปิดแอปใหม่ (มี cooldown กันด้วย)
// =====================================================================
class TankAlertWatcher {
  TankAlertWatcher({required this.onAlert});

  /// เรียกทุกครั้งที่มีการแจ้งเตือนใหม่ถูกสร้าง
  final void Function(TankAlert alert) onAlert;

  final DatabaseReference _stateRef = FirebaseDatabase.instance.ref(
    'water_system/notification_state',
  );

  WaterContextWatcher? _watcher;
  bool _stateLoaded = false;
  bool _running = false;
  int _lastZone = -1; // -1 = ยังไม่รู้ช่วงระดับน้ำปัจจุบัน
  String _lastFlow = 'unknown';
  String _lastFull = 'unknown'; // 'full' / 'not_full' / 'unknown' (ยังไม่รู้)
  final Map<String, int> _lastEmitAt = <String, int>{};

  // ------------------------------------------------------------------
  // ▶️ เริ่ม / ⏹️ หยุด
  // ------------------------------------------------------------------
  Future<void> start() async {
    if (_running) return;
    _running = true;
    await _loadState();
    _watcher = WaterContextWatcher(onSnapshot: _handleSnapshot)..start();
  }

  void stop() {
    _running = false;
    _watcher?.stop();
    _watcher = null;
  }

  /// อ่านสถานะล่าสุดจาก Firebase (รอดแอปปิด-เปิดใหม่)
  Future<void> _loadState() async {
    try {
      final event = await _stateRef.once();
      final value = event.snapshot.value;
      if (value is Map) {
        final data = Map<dynamic, dynamic>.from(value);
        final levelEntry = data['level'];
        if (levelEntry is Map) {
          final v = levelEntry['value'];
          if (v is int) _lastZone = v;
          _readEmitAt('level', levelEntry);
        }
        final flowEntry = data['flow'];
        if (flowEntry is Map) {
          final v = flowEntry['value'];
          if (v is String) _lastFlow = v;
          _readEmitAt('flow', flowEntry);
        }
        final fullEntry = data['full'];
        if (fullEntry is Map) {
          final v = fullEntry['value'];
          if (v is String) _lastFull = v;
          _readEmitAt('full', fullEntry);
        }
      }
    } catch (e) {
      debugPrint('Error loading alert state: $e');
    }
    _stateLoaded = true;
  }

  /// 📥 อ่านเวลาแจ้งล่าสุด "แยกตามระดับความรุนแรง" จาก `{track}/emit_at/{type}`
  ///
  /// ของเก่า (ก่อนแยก cooldown ตามระดับ) เก็บเวลาไว้ที่ `{track}/timestamp`
  /// ก้อนเดียว ซึ่งไม่รู้ว่าเป็นของระดับไหน จึงไม่นำมาใช้เป็น cooldown ต่อ
  /// ผลที่เกิดคือหลังอัปเดตเวอร์ชันนี้ครั้งแรก การแจ้งรอบถัดไปจะไม่ติด cooldown
  /// (เกิดครั้งเดียว ไม่เป็นอันตราย) ส่วน `timestamp` ยังถูกเขียนต่อไว้ดูย้อนหลัง
  void _readEmitAt(String track, Map<dynamic, dynamic> entry) {
    final raw = entry['emit_at'];
    if (raw is! Map) return;
    for (final e in Map<dynamic, dynamic>.from(raw).entries) {
      final v = e.value;
      if (v is num) {
        _lastEmitAt[cooldownKeyOf(track, e.key.toString())] = v.toInt();
      }
    }
  }

  // ------------------------------------------------------------------
  // 🔍 ตรวจเกณฑ์การแจ้งเตือนทุกครั้งที่ข้อมูลจาก Firebase เปลี่ยน
  // ------------------------------------------------------------------
  void _handleSnapshot(WaterSnapshot snapshot) {
    if (!_stateLoaded || !snapshot.hasData) return;
    // ถ้ายังไม่รู้ความจุถัง คิดเป็นเปอร์เซ็นต์ไม่ได้ → ข้ามการแจ้งเตือนตามระดับ
    if (snapshot.capacity <= 0) return;

    // (1) ระดับน้ำเปลี่ยนช่วง (≤25 / ≤50 / ≤75 / >75) → แจ้งตามระดับแบบเรียลไทม์
    final int zone = levelZoneOf(snapshot.percent);
    if (zone != _lastZone) {
      if (_lastZone < 0) {
        // ครั้งแรก (ยังไม่เคยรู้โซน) → จำตำแหน่งไว้เงียบ ๆ ไม่แจ้ง
        _lastZone = zone;
        _saveStateValue('level', zone);
      } else {
        final alert = levelAlertFor(zone, snapshot);
        if (_canEmit('level', alert.type)) {
          _lastZone = zone;
          _emit('level', alert, stateValue: zone);
        }
        // ⏳ ถูก cooldown กัน → ตั้งใจ "ไม่" commit _lastZone เพื่อให้รอบถัดไป
        //    ลองใหม่ได้ ไม่ใช่ทิ้งการแจ้งนั้นหายถาวร (ดูหัวข้อ cooldown ที่หัวไฟล์)
      }
    }

    // (2) ถังน้ำเต็ม (≥ kFullPercent) → แจ้ง "ถังน้ำเต็มแล้ว" ครั้งเดียวตอนเพิ่งเต็ม
    //     ใช้ key แยกจาก 'level' เพื่อให้มี cooldown ของตัวเอง — กันกรณีเติมน้ำเร็ว
    //     แล้วการแจ้ง "เต็มแล้ว" ถูก cooldown ของการข้ามโซน 75% กลืนหายไป
    final String full = fullStateOf(snapshot.percent);
    if (full != _lastFull) {
      final alert = _lastFull == 'unknown'
          ? null // ครั้งแรก → จำเงียบ ๆ
          : fullAlertFor(full, snapshot);
      // alert == null = ไม่มีอะไรต้องแจ้ง (ครั้งแรก หรือ full → not_full) → commit ได้เลย
      if (alert == null) {
        _lastFull = full;
        _saveStateValue('full', full);
      } else if (_canEmit('full', alert.type)) {
        _lastFull = full;
        _emit('full', alert, stateValue: full);
      }
      // ถูก cooldown กัน → ไม่ commit เพื่อให้ "ถังน้ำเต็มแล้ว" ยังมีโอกาสแจ้งรอบถัดไป
    }

    // (3) สถานะการไหลเปลี่ยน (ไม่ไหล ⇄ ไหล) → แจ้งเฉพาะ หยุดไหล / กลับมาไหล
    //     ยกเว้นตอนถังเต็ม (จัดการใน flowAlertFor) — ดูเหตุผลที่หัวไฟล์
    final String flow = flowStateOf(snapshot.flowRate);
    if (flow != _lastFlow) {
      final String previous = _lastFlow;
      final alert = previous == 'unknown'
          ? null // ครั้งแรก → จำเงียบ ๆ
          : flowAlertFor(flow, previous, snapshot);
      // alert == null = ไม่มีอะไรต้องแจ้ง (ครั้งแรก / ถังเต็ม / เปลี่ยนความเร็ว) → commit เลย
      if (alert == null) {
        _lastFlow = flow;
        _saveStateValue('flow', flow);
      } else if (_canEmit('flow', alert.type)) {
        // ราง flow ไม่มี cooldown (kFlowCooldown = 0) → เงื่อนไขนี้เป็นจริงเสมอ
        // จึงแจ้งทันทีทุกครั้งที่สถานะการไหลเปลี่ยน ไม่มีการเลื่อนหรือยุบหาย
        _lastFlow = flow;
        _emit('flow', alert, stateValue: flow);
      }
    }
  }

  /// 📊 แบ่งระดับน้ำเป็นช่วง (zone) ตามจุดแจ้งเตือน 25% / 50% / 75%
  ///   0 = ≤25 (ต่ำมาก/วิกฤต), 1 = ≤50 (ต่ำ/ควรระวัง),
  ///   2 = ≤75 (ระดับน้ำ), 3 = >75 (ระดับน้ำปกติ)
  static int levelZoneOf(double percent) {
    if (percent <= kCriticalPercent) return 0;
    if (percent <= kWarningPercent) return 1;
    if (percent <= kNormalPercent) return 2;
    return 3;
  }

  /// 💧 สถานะการไหล (binary): 'none' = ไม่ไหล / 'flowing' = ไหลอยู่
  static String flowStateOf(double flowRate) {
    return flowRate <= 0.01 ? 'none' : 'flowing';
  }

  /// 🪣 สถานะความเต็มของถัง: 'full' = เต็ม (≥ [kFullPercent]) / 'not_full' = ยังไม่เต็ม
  static String fullStateOf(double percent) {
    return percent >= kFullPercent ? 'full' : 'not_full';
  }

  /// 🪣 ข้อความแจ้งเตือนเมื่อถังน้ำเต็ม
  ///    แจ้งเฉพาะตอน "เพิ่งเต็ม" (not_full → full) เท่านั้น
  ///    ส่วนตอนน้ำลดลงจากเต็ม (full → not_full) คือการใช้น้ำปกติ ไม่ต้องแจ้ง
  ///    (ระดับน้ำที่ลดลงมีการแจ้งตามโซน 75/50/25% ดูแลอยู่แล้ว)
  static TankAlert? fullAlertFor(String newState, WaterSnapshot s) {
    if (newState != 'full') return null;
    return TankAlert(
      title: 'ถังน้ำเต็มแล้ว',
      message:
          'ระดับน้ำ ${s.percent.toStringAsFixed(0)}% '
          '(${s.currentLiters.toStringAsFixed(0)} ลิตร) น้ำเต็มถังเรียบร้อย',
      type: 'info',
    );
  }

  /// 🔴🟡🟢 ข้อความแจ้งเตือนตามระดับน้ำ (เรียลไทม์ตามช่วงที่ระดับน้ำอยู่)
  static TankAlert levelAlertFor(int zone, WaterSnapshot s) {
    final String pct = s.percent.toStringAsFixed(0);
    final String liters = s.currentLiters.toStringAsFixed(0);

    switch (zone) {
      case 0:
        return TankAlert(
          title: 'ระดับน้ำต่ำมาก (วิกฤต)',
          message:
              'ระดับน้ำเหลือ $pct% ($liters ลิตร) '
              'กรุณาเติมน้ำเข้าถังโดยเร็วที่สุด',
          type: 'critical',
        );
      case 1:
        return TankAlert(
          title: 'ระดับน้ำต่ำ (ควรระวัง)',
          message: 'ระดับน้ำเหลือ $pct% ($liters ลิตร) ควรเตรียมเติมน้ำไว้ล่วงหน้า',
          type: 'warning',
        );
      case 2:
        return TankAlert(
          title: 'ระดับน้ำ',
          message: 'ระดับน้ำ $pct% ($liters ลิตร)',
          type: 'info',
        );
      default:
        return TankAlert(
          title: 'ระดับน้ำปกติ',
          message: 'ระดับน้ำ $pct% ($liters ลิตร)',
          type: 'info',
        );
    }
  }

  /// 💧 ข้อความแจ้งเตือนเมื่อสถานะการไหลเปลี่ยน (แค่ หยุด / กลับมาไหล)
  ///
  /// 🪣 ถังเต็มแล้ว (≥ [kFullPercent]) = เงียบทั้ง 2 ทิศทาง
  ///    เพราะลูกลอยจะปิด/เปิดวาล์วเองเป็นจังหวะทุกครั้งที่มีการใช้น้ำ
  ///    (ไหล 0 → 0.13 → 0 วนไปทั้งวัน) ไม่ใช่เหตุการณ์ที่ผู้ใช้ต้องทำอะไร
  ///    → ให้เหลือแจ้งแค่ "ถังน้ำเต็มแล้ว" จาก [fullAlertFor] ครั้งเดียว
  static TankAlert? flowAlertFor(
    String newState,
    String previous,
    WaterSnapshot s,
  ) {
    if (s.percent >= kFullPercent) return null;

    if (newState == 'none') {
      return TankAlert(
        title: 'น้ำหยุดไหล',
        message: 'อัตราการไหลกลับมาเป็น 0 ลิตร/นาที',
        // 🔴 critical: น้ำขาเข้าหยุดไหลโดยที่ถังยังไม่เต็ม อาจหมายถึงน้ำประปาหยุด
        //    ปั๊มไม่ทำงาน หรือวาล์วปิด — ผู้ใช้ควรเห็นเด่นชัดทันที
        //    (ตอนถังเต็มถูก guard บรรทัดแรกของฟังก์ชันนี้กรองออกไปแล้ว)
        type: 'critical',
      );
    }

    if (previous == 'none') {
      return TankAlert(
        title: 'น้ำกลับมาไหล',
        message: 'อัตราการไหล ${s.flowRate.toStringAsFixed(1)} ลิตร/นาที',
        type: 'info',
      );
    }

    // ไหลอยู่แล้วแล้วเปลี่ยนความเร็ว → ไม่ต้องแจ้ง (โจทย์ให้มีแค่ หยุดไหล/กลับมาไหล)
    return null;
  }

  /// 🔑 คีย์ cooldown = "ราง + ระดับความรุนแรง"
  ///
  /// ⚠️ จุดสำคัญของการแก้บั๊ก: เดิมใช้คีย์เป็นชื่อรางเฉย ๆ (`'level'`) cooldown
  /// จึงครอบทุกระดับความรุนแรงรวมกัน ทำให้การแจ้ง `info` (เช่น "ระดับน้ำปกติ")
  /// ไปบล็อกการแจ้ง `critical` ("ระดับน้ำต่ำมาก") ที่ตามมาภายใน 15 นาทีได้
  /// ตอนนี้แต่ละระดับมี cooldown ของตัวเอง → การแจ้งที่ไม่สำคัญไม่กินโควตา
  /// ของการแจ้งที่สำคัญอีก
  static String cooldownKeyOf(String track, String type) => '$track:$type';

  /// ⏳ cooldown ของแต่ละราง — ราง `flow` เป็น 0 (แจ้งทันที) ดู [kFlowCooldown]
  static Duration cooldownForTrack(String track) =>
      track == 'flow' ? kFlowCooldown : kAlertCooldown;

  /// ⏳ ครบ cooldown แล้วหรือยัง — ฟังก์ชันล้วน (เทสต์ได้ ไม่พึ่ง Firebase/นาฬิกาเครื่อง)
  ///
  /// [cooldown] เป็น [Duration.zero] → คืน true เสมอ (ลัดวงจรก่อนคำนวณเวลา
  /// เพื่อไม่ให้นาฬิกาเครื่องที่คลาดเคลื่อนทำให้ค่าติดลบแล้วบล็อกการแจ้งโดยไม่ควร)
  static bool canEmitNow({
    required Map<String, int> lastEmitAt,
    required String track,
    required String type,
    required int nowMs,
    Duration? cooldown,
  }) {
    final Duration window = cooldown ?? cooldownForTrack(track);
    if (window <= Duration.zero) return true;

    final int? last = lastEmitAt[cooldownKeyOf(track, type)];
    if (last == null) return true;
    return (nowMs - last) >= window.inMilliseconds;
  }

  /// ⏳ กันแจ้งซ้ำถี่เกินไป (แยก cooldown ตามระดับความรุนแรงของ [type])
  bool _canEmit(String track, String type) => canEmitNow(
        lastEmitAt: _lastEmitAt,
        track: track,
        type: type,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );

  /// 📤 ส่งการแจ้งเตือน (เขียน Firebase + บันทึกสถานะ + แจ้งหน้าจอ)
  void _emit(String key, TankAlert alert, {dynamic stateValue}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastEmitAt[cooldownKeyOf(key, alert.type)] = now;

    // ใช้ update ไม่ใช่ set — เพราะ set จะลบ emit_at ของระดับความรุนแรงอื่นทิ้ง
    final payload = <String, dynamic>{
      'timestamp': now, // เวลาแจ้งล่าสุดของรางนี้ (ไว้ดูย้อนหลัง)
      'emit_at/${alert.type}': now, // เวลาแจ้งล่าสุด "แยกตามระดับ" = ตัวคุม cooldown
    };
    if (stateValue != null) payload['value'] = stateValue;
    _stateRef
        .child(key)
        .update(payload)
        .catchError((e) => debugPrint('Error saving alert state: $e'));

    NotificationService.push(
      title: alert.title,
      message: alert.message,
      type: alert.type,
    );

    onAlert(alert);
  }

  /// 💾 บันทึกสถานะล่าสุดไว้ (ถึงแม้ cooldown จะกันการแจ้ง ก็ยังจำตำแหน่งไว้ได้)
  void _saveStateValue(String key, dynamic value) {
    _stateRef
        .child(key)
        .update(<String, dynamic>{'value': value})
        .catchError((e) => debugPrint('Error saving alert state: $e'));
  }
}

