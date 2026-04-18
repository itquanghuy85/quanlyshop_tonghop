#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must be run on macOS."
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[1/6] flutter clean"
flutter clean

echo "[2/6] flutter pub get"
flutter pub get

echo "[3/6] Reset iOS Pods state"
cd ios
pod deintegrate || true
rm -rf Pods Podfile.lock .symlinks

echo "[4/6] pod install"
pod install

echo "[5/6] Back to project root"
cd "$ROOT_DIR"

echo "[6/6] Done. Next: flutter run -d <ios-device-id>"
#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must be run on macOS."
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[1/6] flutter clean"
flutter clean

echo "[2/6] flutter pub get"
flutter pub get

echo "[3/6] Reset iOS Pods state"
cd ios
pod deintegrate || true
rm -rf Pods Podfile.lock .symlinks

echo "[4/6] pod install"
pod install

echo "[5/6] Back to project root"
cd "$ROOT_DIR"

echo "[6/6] Done. Next: flutter run -d <ios-device-id>"
#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must be run on macOS."
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[1/6] flutter clean"
flutter clean

echo "[2/6] flutter pub get"
flutter pub get

echo "[3/6] Reset iOS Pods state"
cd ios
pod deintegrate || true
rm -rf Pods Podfile.lock .symlinks

echo "[4/6] pod install"
pod install

echo "[5/6] Back to project root"
cd "$ROOT_DIR"

echo "[6/6] Done. Next: flutter run -d <ios-device-id>"
