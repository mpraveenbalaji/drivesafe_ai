# 🚗 DriveSafe

**DriveSafe** is an intelligent, distraction-free Android driving assistant built with **Flutter** and **Native Android Telecom & Motion Services**. It actively monitors vehicle movement using high-accuracy GPS speed tracking, determines when the user is operating a vehicle, and automatically manages incoming phone calls based on personalized screening rules to reduce distracted driving.

---

## ✨ Features

- 🏎️ **Speed-Based Driving Detection**: Automatically enters driving mode when vehicle speed exceeds $15\text{ km/h}$.
- 🛡️ **Intelligent Call Screening**: Enforces safety policies for:
  - **Saved Contacts**: Allow, Silence, or Reject
  - **Suspected Spam**: Automatically rejected or silenced
  - **Unknown Numbers**: Configurable screening actions
- 🛑 **Speed Inactivity Guard**: Automatically pauses active screening when stopped in traffic or at a stoplight for extended periods.
- 👤 **Passenger Mode & Manual Override**: Instantly disable call screening with a single tap when traveling as a passenger.
- 📋 **Call History Log**: Real-time record of all calls screened while driving, including timestamps and actions taken.
- 🧪 **Speed Simulator**: Built-in interactive test panel to simulate driving speeds and trigger state transitions without requiring physical road travel.

---

## 🏗️ Architecture & Project Structure

```text
drivesafe/
├── android/            # Native Kotlin Android implementation (Telecom & CallScreeningService)
│   └── app/src/main/kotlin/com/example/drivesafe_ai/
│       ├── MainActivity.kt               # MethodChannel bridge
│       ├── CallScreeningServiceImpl.kt   # Android Telecom CallScreeningService
│       ├── PhoneCallReceiver.kt          # Telephony broadcast receiver
│       └── NativeMotionEngine.kt         # Sensor-based motion evaluation
├── lib/
│   ├── main.dart                         # Flutter entry point & app theme
│   ├── models/                           # Data models (DrivingState, CallRule, CallRecord)
│   ├── screens/                          # UI Screens (Home, Settings, History)
│   ├── services/                         # MovementService, PreferenceService, CallScreeningService
│   └── widgets/                          # Reusable UI components
├── test/                                 # Unit & Widget test suite
└── pubspec.yaml                          # Flutter package definitions & dependencies
```

---

## 🚀 Getting Started

### Prerequisites
- **Flutter SDK**: `>=3.11.5`
- **Dart SDK**: Compatible with Flutter SDK
- **Android Studio** or **VS Code** with Flutter extensions
- **Android Device or Emulator**: Android 7.0 (API 24) or higher (Android 10+ recommended for complete CallScreeningService support)

### Installation & Run

1. **Clone the repository:**
   ```bash
   git clone https://github.com/mpraveenbalaji/drivesafe_ai.git
   cd drivesafe_ai
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run the test suite:**
   ```bash
   flutter test
   ```

4. **Launch the application:**
   ```bash
   flutter run
   ```

5. **Build APK:**
   ```bash
   flutter build apk --debug
   ```

---

## 🔒 Permissions Required

To function properly as a driving assistant and call screening manager, the app requires:
- `android.permission.ACCESS_FINE_LOCATION` (GPS speed tracking)
- `android.permission.ACCESS_COARSE_LOCATION`
- `android.permission.READ_PHONE_STATE`
- `android.permission.CALL_SCREENING_SERVICE`
- `android.permission.READ_CONTACTS`

---

## 👥 Collaboration & Contributing

1. Fork or clone this repository.
2. Create your feature branch (`git checkout -b feature/amazing-feature`).
3. Commit your changes (`git commit -m 'feat: add amazing feature'`).
4. Push to the branch (`git push origin feature/amazing-feature`).
5. Open a Pull Request.

---

## 📄 License
Developed for safe, distraction-free driving.
