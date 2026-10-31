// ค่า config สำหรับ Firebase (ดึงจาก android/app/google-services.json)
// ค่าทั้งหมดเป็นของจริงจากโปรเจค water-tank-iot-e8d2e แล้ว (Android จาก
// google-services.json / Web จาก Web app ที่ลงทะเบียนใน Firebase Console)
// ถ้าย้ายโปรเจคอีกครั้ง ให้รัน `flutterfire configure` หลัง `firebase login`
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    return android;
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCZaOU9oISEjUrgW4EtLp8DjTCgEpKly_g',
    appId: '1:1098039764195:web:fcce6de7517d13709251d6',
    messagingSenderId: '1098039764195',
    projectId: 'water-tank-iot-e8d2e',
    authDomain: 'water-tank-iot-e8d2e.firebaseapp.com',
    databaseURL:
        'https://water-tank-iot-e8d2e-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'water-tank-iot-e8d2e.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCZaOU9oISEjUrgW4EtLp8DjTCgEpKly_g',
    appId: '1:1098039764195:android:7e126ac0dfd9f31a9251d6',
    messagingSenderId: '1098039764195',
    projectId: 'water-tank-iot-e8d2e',
    databaseURL:
        'https://water-tank-iot-e8d2e-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'water-tank-iot-e8d2e.firebasestorage.app',
  );
}
