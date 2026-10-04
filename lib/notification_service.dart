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
// =====================================================================
const double kCriticalPercent = 25.0; // ≤ 25% = ระดับน้ำต่ำมาก (วิกฤต)
const double kWarningPercent = 50.0; // ≤ 50% = ระดับน้ำต่ำ (ควรระวัง)
const double kNormalPercent = 75.0; // ≤ 75% = ระดับน้ำ (เกินนี้ = ระดับน้ำปกติ)
const double kHighFlowLpm = 30.0; // เกินนี้ถือว่าไหลเร็วผิดปกติ (ใช้ในคำแนะนำของระบบ)
const Duration kAlertCooldown = Duration(minutes: 15); // กันแจ้งซ้ำถี่เกินไป

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
          final ts = levelEntry['timestamp'];
          if (ts is num) _lastEmitAt['level'] = ts.toInt();
        }
        final flowEntry = data['flow'];
        if (flowEntry is Map) {
          final v = flowEntry['value'];
          if (v is String) _lastFlow = v;
          final ts = flowEntry['timestamp'];
          if (ts is num) _lastEmitAt['flow'] = ts.toInt();
        }
      }
    } catch (e) {
      debugPrint('Error loading alert state: $e');
    }
    _stateLoaded = true;
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
      final bool firstTime = _lastZone < 0;
      _lastZone = zone;
      _saveStateValue('level', zone);

      if (!firstTime) {
        final alert = levelAlertFor(zone, snapshot);
        if (_canEmit('level')) {
          _emit('level', alert, stateValue: zone);
        }
      }
    }

    // (2) สถานะการไหลเปลี่ยน (ไม่ไหล ⇄ ไหล) → แจ้งเฉพาะ หยุดไหล / กลับมาไหล
    final String flow = flowStateOf(snapshot.flowRate);
    if (flow != _lastFlow) {
      final String previous = _lastFlow;
      final bool firstTime = previous == 'unknown';
      _lastFlow = flow;
      _saveStateValue('flow', flow);

      if (!firstTime) {
        final alert = flowAlertFor(flow, previous, snapshot);
        if (alert != null && _canEmit('flow')) {
          _emit('flow', alert, stateValue: flow);
        }
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
  static TankAlert? flowAlertFor(
    String newState,
    String previous,
    WaterSnapshot s,
  ) {
    if (newState == 'none') {
      return TankAlert(
        title: 'น้ำหยุดไหล',
        message: 'อัตราการไหลกลับมาเป็น 0 ลิตร/นาที',
        type: 'info',
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

  /// ⏳ กันแจ้งซ้ำถี่เกินไป
  bool _canEmit(String key) {
    final last = _lastEmitAt[key];
    if (last == null) return true;
    final diff = DateTime.now().millisecondsSinceEpoch - last;
    return diff >= kAlertCooldown.inMilliseconds;
  }

  /// 📤 ส่งการแจ้งเตือน (เขียน Firebase + บันทึกสถานะ + แจ้งหน้าจอ)
  void _emit(String key, TankAlert alert, {dynamic stateValue}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastEmitAt[key] = now;

    final payload = <String, dynamic>{'timestamp': now};
    if (stateValue != null) payload['value'] = stateValue;
    _stateRef
        .child(key)
        .set(payload)
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

