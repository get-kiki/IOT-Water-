// ค่า config สำหรับ Firebase (ดึงจาก android/app/google-services.json)
// หมายเหตุ: web.appId ยังเป็นค่า placeholder (โปรเจคยังไม่ได้ลงทะเบียน Web app
// ใน Firebase Console) — ถ้าต้องการค่า appId ที่ถูกต้อง 100% ให้รัน
// `flutterfire configure` หลัง login Firebase แล้วมันจะ generate ไฟล์นี้ให้ใหม่
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    return android;
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCHCshsmhRVuGdvO3a2JKUhGRkctcaK3Ag',
    appId: '1:774815603608:web:73456953ce4a750c73a9ed',
    messagingSenderId: '774815603608',
    projectId: 'water-tank-iot-8c113',
    authDomain: 'water-tank-iot-8c113.firebaseapp.com',
    databaseURL:
        'https://water-tank-iot-8c113-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'water-tank-iot-8c113.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCHCshsmhRVuGdvO3a2JKUhGRkctcaK3Ag',
    appId: '1:774815603608:android:73456953ce4a750c73a9ed',
    messagingSenderId: '774815603608',
    projectId: 'water-tank-iot-8c113',
    databaseURL:
        'https://water-tank-iot-8c113-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'water-tank-iot-8c113.firebasestorage.app',
  );
}
