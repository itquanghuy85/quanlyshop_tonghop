# iOS Build Guide for macOS 14.8 + Xcode 16.2

## Prerequisites
- macOS 14.8 (Sonoma) or later
- Xcode 16.2 (from App Store)
- Flutter SDK (3.38.5+ recommended)
- CocoaPods (`sudo gem install cocoapods`)

## First-time Setup

### 1. Clone and prepare
```bash
git clone <repository>
cd quanlyshop
flutter pub get
```

### 2. Install iOS dependencies
```bash
cd ios
pod deintegrate  # Clean old pods
rm -rf Pods Podfile.lock
pod install --repo-update
cd ..
```

### 3. Open in Xcode (optional, for signing setup)
```bash
open ios/Runner.xcworkspace
```

In Xcode:
- Select "Runner" project in Navigator
- Go to "Signing & Capabilities" tab
- Select your Team for signing
- Ensure Bundle Identifier is `com.huluca.shopmanager`

## Build Commands

### Debug Build (Simulator)
```bash
flutter build ios --simulator --debug
```

### Debug Build (Device)
```bash
flutter build ios --debug
# or
flutter run -d <device_id>
```

### Release Build
```bash
flutter build ios --release
```

### Archive for App Store
```bash
flutter build ipa --release --export-method app-store
```

## Troubleshooting

### 1. CocoaPods Issues
```bash
cd ios
pod deintegrate
rm -rf Pods Podfile.lock ~/.cocoapods/repos/trunk
pod repo update
pod install --verbose
```

### 2. Signing Issues
- Open `ios/Runner.xcworkspace` in Xcode
- In Build Settings, ensure `CODE_SIGNING_ALLOWED = YES` for Release
- Select your development team
- For CI/CD, use `--export-options-plist` with proper provisioning

### 3. Module Map Errors
If you see "module map file not found":
```bash
cd ios
pod deintegrate
rm -rf Pods
flutter clean
flutter pub get
pod install --repo-update
```

### 4. Privacy Manifest Warnings
PrivacyInfo.xcprivacy is already included. If you see warnings about missing privacy manifests from dependencies, they need to be updated by their maintainers.

### 5. Xcode 16.2 Specific
- `ENABLE_USER_SCRIPT_SANDBOXING = NO` is already set in Podfile
- `DT_TOOLCHAIN_DIR` → `TOOLCHAIN_DIR` fix is automatic
- Resource bundle signing is disabled for pods

## Configuration Files

### Podfile Highlights
- Platform: iOS 14.0+
- User Script Sandboxing: Disabled
- Code Signing for Pods: Disabled
- Swift Version: 5.0

### Build Settings
- IPHONEOS_DEPLOYMENT_TARGET: 14.0
- SWIFT_VERSION: 5.0
- ENABLE_USER_SCRIPT_SANDBOXING: NO

## Firebase Setup
Ensure `GoogleService-Info.plist` is in `ios/Runner/`:
- Download from Firebase Console
- Add to Xcode project (Runner target)
- Verify bundle ID matches Firebase config

## Notes
- Privacy Manifest (PrivacyInfo.xcprivacy) is included for App Store compliance
- Minimum iOS version is 14.0 for best Xcode 16.2 compatibility
- Bluetooth, Camera, Location permissions are declared in Info.plist

## Quick Commands Reference
```bash
# Full clean rebuild
flutter clean && flutter pub get && cd ios && pod install && cd .. && flutter build ios

# Run on connected device
flutter run -d <device_id>

# List available devices
flutter devices

# Check for issues
flutter doctor -v
```
