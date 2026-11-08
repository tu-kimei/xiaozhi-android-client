# Kế hoạch triển khai tiếp — Visbot làm bạn & gia sư cho bé

Ba việc, mỗi việc một file, viết để một agent khác có thể nhận và làm luôn.

| # | Việc | File | Phụ thuộc |
|---|------|------|-----------|
| 1 | Điều khiển robot bằng lời nói + cử chỉ tự động | [2026-11-08-voice-robot-control.md](2026-11-08-voice-robot-control.md) | — (xây nền MCP dùng chung) |
| 2 | Màn hình khuôn mặt cảm xúc | [2026-11-08-emotion-face.md](2026-11-08-emotion-face.md) | Có thể làm song song với 1 |
| 3 | Gia sư tiếng Anh: giáo trình + kiến trúc nội dung | _(đang trao đổi, sẽ bổ sung)_ | Cần MCP của việc 1; dùng mặt cười của việc 2 |

Thứ tự đề xuất: **1 (phần MCP) → 2 song song → 3**.

## Bối cảnh chung (đã kiểm chứng trên robot, 2026-11)

- App Flutter `com.lhht.ai_assistant`, nhánh `vietnamese-and-robot-control`. Robot UBTech Visbot, Android 8.1 (API 27), CPU armeabi-v7a, màn hình 308×240.
- Hội thoại giọng nói qua server chính thức xiaozhi.me: MQTT + UDP, listen mode `auto` (server VAD). ASR, LLM, TTS đều chạy trên server. Code: `lib/services/xiaozhi_service.dart`, `xiaozhi_mqtt_manager.dart`, `xiaozhi_udp_channel.dart`, `lib/utils/audio_util.dart`.
- Hello của app đã khai báo `"features": {"mcp": true}` nhưng **app chưa xử lý tin nhắn `type: "mcp"`**. Việc 1 sẽ làm phần này.
- Server gửi kèm cảm xúc ở mỗi câu trả lời: `{"type":"llm","text":"😊","emotion":"happy"}`. Hiện app chỉ log là "未知类型消息".
- Điều khiển robot đã chạy được qua `RobotService` (Dart) → `RobotChannel.kt` → `RosaClient.kt` (binder ROSA, không dùng SDK). Hiện có:
  - đầu `head` từ -23° đến 25°;
  - bánh xe `move` (đi thẳng, hoặc quay tại chỗ theo `turnSpeed`/`turnAngle`, có `durationMs`);
  - `stop`.
  Màn hình thử: `lib/screens/robot_control_screen.dart`.
- App tham khảo **Lily** (`com.sensornotes.xiaozhi`, cài sẵn trên robot) đã được dịch ngược. Bản dịch ngược ở thư mục scratchpad của phiên trước; có thể dịch lại từ APK trên robot bằng `adb shell pm path com.sensornotes.xiaozhi`. Phát hiện chính nằm trong từng file kế hoạch.
- Tài nguyên có sẵn trên robot, trong `/system/media/visbot/`:
  - `emotion/`: hoạt hình mặt dạng SVGA. Gồm `shuohua/speak_*` (khi đang nói) và `bushuohua/silent_*` (khi im lặng), khoảng 40 cảm xúc, mỗi cảm xúc 1–4 biến thể.
  - `dance/`, `dance2/`, `motion/`: file `.orch` (điệu nhảy, động tác).
  - `children_song/`, `interact_story/`: bài hát, truyện.
  - Đây là tài nguyên của UBTech: chỉ **đọc tại chỗ trên robot**, không đóng gói lại vào APK.

## Lưu ý vận hành cho agent triển khai

- Kết nối USB tới robot (usbip trên WSL2) hay rớt. Không cài APK debug 94MB bằng `flutter run` được; phải:
  1. `flutter build apk --debug --target-platform android-arm`;
  2. chạy `scripts/install_chunked.sh`: đẩy file theo từng mảnh 4MB rồi `pm install`.
- Sửa Dart: dùng `flutter attach` + hot reload. Sửa Kotlin: phải cài lại APK.
- Đọc memory `project-visbot-audio-quirks` trước khi động vào phần âm thanh.
- Theo `CLAUDE.md`: chạy GitNexus `impact` trước khi sửa symbol, và `detect_changes` trước khi commit.
- Người dùng cuối là **bé 5 tuổi**, nói tiếng Việt. An toàn và dễ dùng quan trọng hơn tính năng.
