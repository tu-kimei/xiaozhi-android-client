#!/usr/bin/env bash
#
# Vòng lặp dev nhanh: chạy app ở chế độ DEBUG + hot reload.
#
# Thay vì `flutter build apk --release` rồi `adb install` mỗi lần sửa,
# script này build/install MỘT lần, sau đó mỗi thay đổi chỉ cần nhấn:
#     r  -> hot reload   (~1 giây, giữ nguyên state)
#     R  -> hot restart  (khởi động lại app, nhanh hơn build lại)
#     q  -> thoát
#
# Dùng:
#     ./scripts/dev.sh            # tự chọn thiết bị android đang online đầu tiên
#     ./scripts/dev.sh <device>   # chỉ định thiết bị (adb devices)
#
# Kích hoạt từ terminal khác (hoặc từ Claude) mà không cần gõ phím:
#     kill -USR1 "$(cat /tmp/xiaozhi-flutter.pid)"   # hot reload
#     kill -USR2 "$(cat /tmp/xiaozhi-flutter.pid)"   # hot restart
#
# Lưu ý: sửa code Kotlin/Android, AndroidManifest hoặc pubspec.yaml thì
# hot reload không áp dụng được -> thoát (q) và chạy lại script.
#
set -euo pipefail

# shellcheck disable=SC1091
source "$HOME/sdk/env.sh"

DEVICE="${1:-}"
if [[ -z "$DEVICE" ]]; then
  DEVICE="$(adb devices | awk 'NR > 1 && $2 == "device" {print $1; exit}')"
fi

if [[ -z "$DEVICE" ]]; then
  echo "Không tìm thấy thiết bị/emulator nào đang online." >&2
  adb devices >&2
  exit 1
fi

echo "==> Flutter debug trên: $DEVICE"
echo "    r = hot reload | R = hot restart | q = thoát"
echo

PID_FILE=/tmp/xiaozhi-flutter.pid
exec flutter run -d "$DEVICE" --debug --pid-file "$PID_FILE"
