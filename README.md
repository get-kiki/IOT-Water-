# IoT Water Level Monitor (Water Tank IoT)

แอปพลิเคชันตรวจสอบระดับน้ำและการไหลของน้ำผ่านอุปกรณ์ IoT
ประกอบด้วย **แอป Flutter** (มือถือ/Web) + **บอร์ด ESP32** + **Firebase Realtime Database**

## โครงสร้างโปรเจค

```
lib/
├── main.dart            # หน้าตั้งค่าขนาดถังน้ำ (เลือกขนาด/กำหนดเอง)
├── watertank.dart       # หน้าแสดงระดับน้ำแบบ realtime + แท็บหลัก
├── history.dart         # หน้าประวัติการใช้น้ำ (รายวัน/เดือน/ปี)
├── active.dart          # หน้าบันทึกกิจกรรมการใช้น้ำ
├── notification.dart    # หน้าการแจ้งเตือน
├── ai_page.dart         # (ยังว่าง - รอพัฒนาส่วน AI)
└── firebase_options.dart# ค่า config Firebase (Web/Android)

Code IOT device.txt      # โค้ด Arduino/ESP32 (วัดระดับน้ำด้วย ultrasonic + OLED)
android/                 # โปรเจค Android
web/                     # โปรเจค Web
```

## ข้อมูล Firebase (Realtime Database)

- Project: `water-tank-iot-8c113`
- Database URL: `https://water-tank-iot-8c113-default-rtdb.asia-southeast1.firebasedatabase.app`
- Schema หลักอยู่ใต้ `/water_system`:
  - `monitor/water_level_liters`, `monitor/flow_rate_min` ← ESP32 เขียน
  - `setting/tank_depth`, `setting/tank_capacity` ← แอปเขียน / ESP32 อ่าน
  - `history/{yyyy-MM-dd}/used_liters` ← ข้อมูลน้ำที่ใช้รายวัน
  - `activities/{id}` ← บันทึกกิจกรรม
  - `notifications/{id}` ← การแจ้งเตือน

---

## วิธีรันแอป Flutter

### สิ่งที่ต้องติดตั้ง (เตรียมไว้แล้วในเครื่องนี้)

| เครื่องมือ | ตำแหน่ง |
|---|---|
| Flutter SDK 3.47.2 | `C:\flutter` |
| Android SDK (cmdline-tools 12.0) | `C:\Android` |
| JDK 21 | `C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot` |
| AVD (emulator) | ชื่อ `flutter_emulator` (Pixel 7, Android API 36) |

> หมายเหตุ: ถ้ายังไม่เพิ่ม `C:\flutter\bin` ใน PATH ให้เรียก flutter ด้วย path เต็ม:
> `C:\flutter\bin\flutter.bat`

### 1) รันบน Chrome (Web) — เร็วสุด

```bat
cd C:\MyProject\IOT-WaterLevel-Mornitor
C:\flutter\bin\flutter.bat run -d chrome
```

หรือ build เป็น static แล้ว serve เอง:

```bat
cd C:\MyProject\IOT-WaterLevel-Mornitor
C:\flutter\bin\flutter.bat build web
python -m http.server 8080 --directory build\web
:: แล้วเปิด http://localhost:8080 ใน browser
```

### 2) รันบน Android Emulator

```bat
:: 1. เปิด emulator (ถ้ายังไม่เปิด)
C:\Android\emulator\emulator.exe -avd flutter_emulator

:: 2. รอให้ boot เสร็จ (เช็คด้วย)
C:\Android\platform-tools\adb.exe devices

:: 3. รันแอป
cd C:\MyProject\IOT-WaterLevel-Mornitor
C:\flutter\bin\flutter.bat run -d emulator-5554
```

> ถ้าเครื่องตั้ง PATH ไว้แล้ว ใช้ `flutter run` สั้น ๆ ได้เลย

### ตัวแปร environment ที่ใช้ (สำหรับการ build Android)

```bat
set JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot
set ANDROID_HOME=C:\Android
set ANDROID_SDK_ROOT=C:\Android
```

---

## หมายเหตุ / ข้อควรรู้

- **Firebase Web appId** ใน `lib/firebase_options.dart` ยังเป็นค่า placeholder —
  ถ้าต้องการค่า appId จริง ให้รัน `flutterfire configure` (หลัง `firebase login`)
  หรือลงทะเบียน Web app ใน Firebase Console
- **สิทธิ์ Realtime Database**: ถ้าแอปอ่าน/เขียนข้อมูลไม่ได้ (permission denied)
  ให้เปิด rule ใน Firebase Console เช่น `".read": true, ".write": true` (เฉพาะช่วงพัฒนา)
- **`test/widget_test.dart`** ยังเป็นเทสต์ counter เริ่มต้น → `flutter test` จะ fail (ไม่กระทบการรันแอป)

## ฝั่ง ESP32 (Arduino)

- เปิด `Code IOT device.txt` ใน Arduino IDE
- ต้องติดตั้งไลบรารี: `Adafruit GFX`, `Adafruit SSD1306`, `Firebase ESP32`
- แก้ค่า `WIFI_SSID`, `WIFI_PASSWORD`, `FIREBASE_HOST`, `FIREBASE_AUTH` ให้ตรงกับของจริง
- เลือกบอร์ด ESP32 แล้ว Upload

