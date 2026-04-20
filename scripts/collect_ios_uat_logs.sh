#!/usr/bin/env bash
set -euo pipefail

# One-command helper for non-technical iOS UAT log capture.
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Khong tim thay Flutter trong PATH."
  echo "Vui long mo Terminal trong may Mac da cai Flutter, roi chay lai script."
  exit 1
fi

if ! command -v zip >/dev/null 2>&1; then
  echo "Khong tim thay lenh zip tren may Mac."
  exit 1
fi

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="UAT_LOGS/$TIMESTAMP"
FULL_LOG="$OUT_DIR/ios_uat_full.log"
FILTERED_LOG="$OUT_DIR/ios_uat_filtered.log"
ZIP_FILE="$OUT_DIR/ios_uat_logs.zip"

mkdir -p "$OUT_DIR"

echo "============================================="
echo "Buoc 1: Cam iPhone vao Mac, mo khoa may, bam Trust neu duoc hoi."
echo "Buoc 2: Dong Android phone neu dang cam cung luc."
echo "Buoc 3: Chon DEVICE ID cua iPhone ben duoi."
echo "============================================="
echo

flutter devices
echo
read -r -p "Nhap DEVICE ID iPhone: " DEVICE_ID

if [[ -z "$DEVICE_ID" ]]; then
  echo "Ban chua nhap DEVICE ID."
  exit 1
fi

echo
echo "Dang ghi log vao: $FULL_LOG"
echo "Hay mo app tren iPhone va test day du 14 buoc UAT."
echo "Khi xong, quay lai cua so nay va bam Ctrl+C."
echo

set +e
flutter logs -d "$DEVICE_ID" 2>&1 | tee "$FULL_LOG"
FLUTTER_EXIT=${PIPESTATUS[0]}
set -e

grep -Eai "appcheck|app check|firebase_app_check|storage|firebase_storage|permission|denied|403|token|sync|repair|firestore|failed-precondition|unauthorized|exception" "$FULL_LOG" > "$FILTERED_LOG" || true

(
  cd "$OUT_DIR"
  zip -q "ios_uat_logs.zip" "ios_uat_full.log" "ios_uat_filtered.log"
)

echo
echo "Da tao xong: $ZIP_FILE"
echo "Vui long gui file zip nay cho Copilot de tiep tuc fix va chot UAT iOS."

if [[ $FLUTTER_EXIT -ne 0 ]]; then
  echo "Luu y: flutter logs ket thuc voi ma loi $FLUTTER_EXIT."
  echo "Neu file log da tao, ban van co the gui de phan tich."
fi
