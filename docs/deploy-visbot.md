# Deploy app lên robot UBTech Visbot

Robot: adb serial `0123456789ABCDEF`, Android 8.1 (API 27), armeabi-v7a, màn hình 308×240.
Robot nối vào WSL2 qua **usbip** (usbipd-win). Đường USB này **rất hay rớt** khi truyền file lớn liên tục.

## Quy tắc

- **KHÔNG** dùng `adb install`, `flutter run`, `flutter install`, hay `adb push` cả APK một lần — đều đứt giữa chừng (thường sau ~10–50MB).
- **KHÔNG** bật `adb tcpip` / adb qua WiFi.
- Luôn cài bằng `scripts/install_chunked.sh`.

## 1. Build

```bash
export JAVA_HOME=/home/tukinga/sdk/jdk17
export PATH=/home/tukinga/sdk/flutter/bin:$PATH
flutter build apk --debug --target-platform android-arm   # chỉ armeabi-v7a, ~94MB
```

`flutter run --target-platform` không tồn tại; dùng `build apk` như trên.

## 2. Cài

```bash
scripts/install_chunked.sh                     # mặc định: build/app/outputs/flutter-apk/app-debug.apk
scripts/install_chunked.sh path/to/other.apk   # APK khác
```

Script:
1. Cắt APK thành mảnh 4MB.
2. Đẩy từng mảnh vào `/data/local/tmp/apkparts/` (mỗi mảnh thử lại tối đa 8 lần, tự `adb reconnect offline` giữa các lần).
3. Mảnh nào đã có trên robot và đúng kích thước thì bỏ qua → **chạy lại script là đẩy tiếp từ chỗ dừng**.
4. Ghép mảnh, so md5 với file gốc, khớp thì `pm install -r`, rồi dọn file tạm.

Báo `md5 mismatch` → chạy lại script.

## 3. Chạy app

```bash
adb shell am start -n com.lhht.ai_assistant/.MainActivity
adb shell am force-stop com.lhht.ai_assistant      # tắt app khi không test (tiết kiệm pin)
```

## 4. Khi adb mất thiết bị

`adb devices` trống hoặc `offline`:

```bash
"/mnt/c/Program Files/usbipd-win/usbipd.exe" attach --wsl --busid 1-5
adb reconnect offline
adb devices -l
```

## 5. Hot reload (chỉ sửa Dart)

```bash
flutter attach -d 0123456789ABCDEF     # chạy TRƯỚC
adb shell am start -n com.lhht.ai_assistant/.MainActivity   # rồi mới mở app
```

- Phải attach trước vì URL VM service trôi khỏi logcat (buffer nhỏ) rất nhanh.
- Attach lỗi "Stream has already been listened to" → force-stop app, attach lại, mở lại app.
- Sửa Kotlin / manifest / thêm plugin → phải build + cài lại (bước 1–2).

## 6. Cài đặt hệ thống đã chỉnh trên robot

- Đã khoá màn hình ngang (đầu robot gật làm cảm biến xoay màn hình lung tung):
  `settings put system accelerometer_rotation 0` và `settings put system user_rotation 0`.
  Bật lại tự xoay: `adb shell settings put system accelerometer_rotation 1`.

## Xem log

```bash
adb logcat -s flutter:V PcmStreamPlayer:V AndroidRuntime:E
```

Xem thêm các lưu ý âm thanh trên robot trong `docs/plans/README.md` (mục "Lưu ý vận hành").
