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

exec flutter run -d "$DEVICE" --debug
