# Việc 2 — Màn hình khuôn mặt cảm xúc (cười, mếu, khóc…)

## Mục tiêu

Trong lúc gọi thoại, màn hình robot hiện một **khuôn mặt hoạt hình**. Mặt đổi theo cảm xúc của câu robot đang nói (vui, buồn, ngạc nhiên, suy nghĩ…) và theo trạng thái hội thoại (đang nghe, đang nghĩ, đang nói, đang chờ). Bé nhìn vào thấy robot "có hồn", giống app Lily.

## Nguồn cảm xúc

Server Xiaozhi đã gửi cảm xúc trong mỗi lượt trả lời:

```json
{"type":"llm","text":"😊","emotion":"happy","session_id":"…"}
```

Bộ tên chuẩn của Xiaozhi, và cũng là 21 file Lily dùng:

> neutral, happy, laughing, funny, sad, angry, crying, loving, embarrassed, surprised, shocked, thinking, winking, cool, relaxed, delicious, kissy, confident, sleepy, silly, confused

Hiện `XiaozhiService` chưa xử lý `type: "llm"`; tin này rơi vào nhánh "未知类型消息". Ngoài ra đã có sẵn `voiceState` (waiting/listening/thinking/speaking) để biết trạng thái hội thoại.

## Lily làm thế nào (đã dịch ngược)

- Lấy `emotion` từ tin `llm`, chuyển chữ thường, rồi ghép đường dẫn `assets/emotions/<emotion>.gif`. Không có file khớp thì dùng `neutral.gif`.
- 21 file GIF động, mỗi file 0.2–1.2MB. Ngoài ra có chế độ avatar "girl" (file `.bin` tự định dạng) và Live2D trong WebView.
- **Không dùng** dịch vụ cảm xúc của robot (`EmotionManager`).
- **Không được chép GIF của Lily vào app**: đó là tài nguyên của bên thứ ba.

## Tài nguyên mặt có sẵn trên robot (lựa chọn tốt nhất)

`/system/media/visbot/emotion/` là bộ mặt chính hãng UBTech, dạng **SVGA** (hoạt hình vector):

- `shuohua/speak_<tên>_<n>.svga`: mặt **khi đang nói**.
- `bushuohua/silent_<tên>_<n>.svga`: mặt **khi im lặng**.
- Khoảng 40 cảm xúc: default, happy, enjoy, excited, funny, love, shy, pet, cry, cry2, frustrated, disappointed, helpless, surprised, scared, fear, curious, doubt, confidence, mad, anger, dissatisfied, bored, fatigue, lethargy, dizziness, leisurely, relax, expect, desire, alert, anxiety, tension, disgust, smelly, evil, cockfighting, uncomfortable, lookup, lookdown, lookleft, lookright, whistle (chỉ có bản silent).
- Mỗi thư mục có file `*_exp.config` (JSON từng dòng: ID, name, cờ song/chat) mô tả cách hệ thống dùng.
- Đọc file **tại chỗ trên robot** (`File('/system/media/visbot/emotion/...')`). Không đóng gói vào APK.

Ưu điểm: giống "khuôn mặt" quen thuộc của robot, đẹp, nhẹ, có sẵn cặp nói/im lặng.

## Thiết kế

### A. Tầng dữ liệu

- `XiaozhiService`:
  - thêm `case 'llm'` để cập nhật `ValueNotifier<String> emotion`;
  - reset về `neutral` khi xong lượt: sau `tts stop`, sau vài giây.
- `FaceController` (`lib/services/face_controller.dart`):
  - đầu vào: `emotion`, `voiceState`, và sự kiện từ Việc 1/3 (ví dụ bé trả lời đúng thì "khen");
  - đầu ra: `FaceState {emotion, speaking}`.
- Bảng ánh xạ cảm xúc Xiaozhi sang cảm xúc Visbot:

| Xiaozhi | Visbot (speak_/silent_) |
|---------|-------------------------|
| neutral | default |
| happy, relaxed | happy / enjoy |
| laughing, funny, silly | funny / excited |
| loving, kissy | love |
| winking, cool, confident | confidence |
| embarrassed | shy |
| sad | frustrated / disappointed |
| crying | cry |
| angry | mad / anger |
| surprised, shocked | surprised |
| thinking, confused | doubt / curious |
| sleepy | fatigue |
| delicious | desire |

- Trạng thái hội thoại:
  - đang nghe: `curious` hoặc `lookup`;
  - đang nghĩ (đã gửi câu, chờ server): `doubt`;
  - đang nói: dùng `speak_` của cảm xúc hiện tại;
  - chờ: `silent_default`, thỉnh thoảng `lookleft`/`lookright`/`whistle` cho sinh động.

### B. Hiển thị

- Gói Flutter phát SVGA: `svgaplayer_flutter` (pub.dev). Kiểm tra gói còn chạy với Flutter 3.29 và Android API 27. Nếu không chạy, phương án dự phòng: dùng `SVGAPlayer-Android` qua PlatformView, hoặc ROSA `EmotionManager.express(Uri)` (dịch vụ `"emotion"`, lệnh `/emotion/express`) để chính hệ thống robot vẽ mặt. Cần thử xem nó vẽ ở lớp nào.
- `FaceView` toàn màn hình, nền đen, đặt trong `voice_call_screen.dart`. Chạm vào thì hiện lại điều khiển cuộc gọi (nút kết thúc, trạng thái) vài giây.
- Chuyển cảnh: đổi cảm xúc khi animation đang chạy hết vòng, hoặc cross-fade, tránh giật.
- Nếu không đọc được `/system/media/visbot` (chạy trên điện thoại thường) thì dùng bộ mặt dự phòng tự vẽ bằng `CustomPainter`. Chỉ cần mắt và miệng đơn giản cho khoảng 6 cảm xúc.

### C. Cài đặt

- Bật/tắt mặt khi gọi.
- Chọn bộ mặt: Visbot hoặc đơn giản.
- (Tuỳ chọn) độ "biểu cảm": ít đổi hoặc đổi nhiều.

## Các bước

1. Bắt tin `llm` → `emotion` notifier, kèm test.
2. Thử `svgaplayer_flutter` với 1 file trên robot (đọc bằng `File`). Đo tốc độ khung hình trên CPU yếu của robot.
3. `FaceController` + bảng ánh xạ, kèm test đơn vị.
4. `FaceView` trong màn gọi, ẩn và hiện điều khiển.
5. Bộ mặt dự phòng `CustomPainter`.
6. Cài đặt.
7. Nối với cử chỉ tự động của Việc 1: cùng sự kiện cảm xúc.

## Tiêu chí nghiệm thu

- Robot kể chuyện vui → mặt cười, miệng chuyển động khi nói. Bé kể chuyện buồn → robot trả lời với mặt buồn hoặc mếu.
- Bé đang nói → mặt "lắng nghe". Chờ server → mặt "suy nghĩ".
- Không làm giật âm thanh. Theo dõi log `断粮` (phát bị đói dữ liệu) không tăng so với trước. CPU trong lúc gọi đủ cho cả giải mã Opus lẫn hoạt hình.
- Chạy trên điện thoại không phải Visbot vẫn có mặt (dự phòng), không crash.

## Rủi ro

- Hoạt hình SVGA trên CPU yếu có thể tranh CPU với luồng âm thanh. Phải đo; nếu cần thì giảm khung hình.
- Bản quyền: chỉ đọc file hệ thống có sẵn trên chính robot; không phân phối lại.
