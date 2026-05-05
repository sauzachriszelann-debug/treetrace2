# TreeTrace Mobile (Flutter)

Android/iOS app for the Panabo City Tree Inventory. Connects to the same FastAPI backend.

## Features
- Login with your TreeTrace account
- Dashboard with tree stats
- Tree list with search + health filter
- Tree detail with health history
- Add tree with AI species identification (auto-runs on photo)
- Interactive map with color-coded markers
- QR code scanner → instant tree profile

## Setup

### 1. Install Flutter
Download from https://flutter.dev/docs/get-started/install
Run `flutter doctor` to verify everything is installed.

### 2. Configure the backend URL
Open `lib/services/api_service.dart` and update `kBaseUrl`:

```dart
// Android emulator talking to your PC's localhost:
const String kBaseUrl = 'http://10.0.2.2:8000/api';

// Real Android device on the same WiFi as your PC:
const String kBaseUrl = 'http://192.168.1.xxx:8000/api';
// (find your PC's IP: run `ipconfig` on Windows, look for IPv4 Address)

// iOS simulator:
const String kBaseUrl = 'http://127.0.0.1:8000/api';
```

### 3. Install dependencies
```
flutter pub get
```

### 4. Make sure backend is running
```
cd backend
uvicorn app.main:app --reload
```

### 5. Run the app
```
# Android emulator (open Android Studio → AVD Manager → start an emulator first)
flutter run

# Specific device
flutter devices          # list connected devices
flutter run -d <device>
```

### 6. Build APK (to install on real phone)
```
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
# Send this file to your phone and install it
```

## Troubleshooting

**"Connection refused" on real device:**
- Make sure phone and PC are on the same WiFi
- Use your PC's local IP (not localhost) in kBaseUrl
- Check Windows Firewall allows port 8000

**Camera not working:**
- Accept the camera permission when the app asks
- On emulator: Extended Controls → Camera → use webcam

**"Flutter not found":**
- Add Flutter to your PATH after installing
- Restart your terminal
