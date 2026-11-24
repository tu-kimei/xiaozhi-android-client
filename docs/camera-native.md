# Camera Visbot — trạng thái triển khai native

Nhánh triển khai: `feat/visbot-camera-vision`.

## Phạm vi hiện tại

Triển khai lõi Camera API1 và cầu nối metadata cho Flutter theo
`docs/plans/2026-11-14-gitnexus-plan-visbot-camera-vision-implementation.md`.
Chưa phải toàn bộ tính năng hỏi–đáp bằng ảnh.

- Camera `0`, ảnh JPEG landscape `640×480`, rotation `0` theo kết quả thử trên Visbot.
- Ba bộ đệm preview NV21 được tái sử dụng; không lưu frame preview.
- Consent native mặc định tắt, chỉ hoạt động khi Activity foreground và màn hình bật.
- Pre-warm tối đa 60 giây, idle 30 giây, không gia hạn giới hạn tuyệt đối bằng capture.
- Lần chụp đầu có ngân sách 12 giây; lần sau 3 giây. Preview có frame **không**
  chứng minh lần chụp đầu đã hết cold-start penalty. Không có ảnh làm nóng ngầm.
- JPEG riêng tư, reference mờ đục, TTL 60 giây; không đưa byte hoặc đường dẫn
  qua Dart/MCP. Không upload, không gọi Dify và không điều khiển robot.

## Channel

MethodChannel: `visbot/vision`.
EventChannel native: `visbot/vision/events`.
Adapter Dart: `lib/services/vision/vision_camera.dart`.

| Method | Đầu vào | Trách nhiệm |
|---|---|---|
| `getCapabilities` | Không | Metadata khả dụng, không mở camera |
| `setConsent` | `enabled` | Cho phép phiên native hoặc thu hồi và dọn ảnh |
| `startPrewarm` | Không | Yêu cầu rõ ràng từ phụ huynh, đã cấp CAMERA |
| `captureSnapshot` | `requestId` | Một ảnh/request, từ chối khi busy |
| `cancel` | `requestId` | Đóng phiên camera và dọn reference; hiện là hủy toàn phiên, không hủy chọn lọc |
| `deleteSnapshot` | `reference` | Xóa artifact theo reference |
| `cleanupStaleSnapshots` | Không | Dọn artifact hết hạn |
| `close` | Không | Đóng phiên, hủy request và xóa artifact |

Metadata capture: `reference`, `mimeType`, `width`, `height`, `bytes`, `rotation`,
`capturedAt`, `expiresAt`, `canMove=false`. Thời điểm metadata là epoch milliseconds;
giới hạn chạy camera dùng đồng hồ monotonic native. Reference chưa có public
resolver/upload API; không coi một token ngẫu nhiên là cơ chế upload hoàn chỉnh.

Events native biểu diễn trạng thái `closed`, `opening`, `warming`, `ready`,
`capturing`, `error` cùng thời điểm hết hạn nếu phù hợp. Phần UI cần đăng ký events,
hiển thị banner/countdown và thu hồi khi không còn màn hình người dùng tương ứng.

## Cổng phụ huynh cục bộ

Trong Cài đặt có màn “Camera phụ huynh — thử nghiệm cục bộ”. Không có PIN
mặc định; lần thiết lập đầu tin người đang cầm thiết bị và mở Cài đặt, không
phải xác thực phụ huynh từ tài khoản từ xa.

Native lưu salt và verifier trong file app-private/no-backup, dùng PBKDF2-SHA256
210.000 vòng và HMAC với khóa AndroidKeyStore. Giới hạn thử sai được lưu qua
restart; đổi PIN cần PIN hiện tại. PIN không được ghi log hoặc trả lại qua channel.
Chưa có quy trình quên PIN/khôi phục an toàn.

PIN đúng chỉ cho một xác nhận mở cửa sổ camera ngắn hạn; pause, screen-off,
close hoặc hết hạn thu hồi quyền. Opt-in lưu trong Settings không tự mở camera
và không thay thế kiểm tra native. Quyền CAMERA chỉ được hỏi sau thao tác rõ ràng.
Màn thử chỉ hiển thị metadata rồi xóa ảnh, không có xem ảnh/upload/AI.

Đã build được APK debug ARM; unit/widget test không chứng minh AndroidKeyStore,
hiệu năng KDF và HAL camera hoạt động đúng trên Visbot. Cần kiểm chứng trên thiết bị.

## Các cổng còn chưa đạt

1. Parent gate PIN mới là cổng cục bộ cho lab; chưa phải danh tính/tài khoản
   phụ huynh thương mại, chưa có reset PIN an toàn hoặc kiểm chứng Keystore trên robot.
2. Chưa nối Look UI dành cho bé, coordinator hội thoại hoặc MCP tool; không được tự bật camera
   từ request cloud hay wake word.
3. Chưa có relay đã xác thực, hợp đồng provider/retention và policy answer.
   Không thay thế bằng direct mobile Dify.
4. Chưa kiểm thử instrumentation bản native mới trên Visbot:
   timing, vòng preview sau capture, cancel trong callback, pause/screen-off,
   camera release, vendor busy, thermal và cleanup sau process death.
5. Chưa có nghiệm thu single-use resolver cho upload; store hiện chỉ tạo/xóa
   reference với TTL, không xuất byte cho consumer bên ngoài.

Không coi build/JVM test thành công là đã đạt cổng thiết bị, privacy hoặc production.
Watchdog có thể vô hiệu hóa request đúng hạn nhưng việc nhả phần cứng vẫn phải
đi qua luồng sở hữu camera. Nếu lời gọi HAL đồng bộ bị treo, không có bảo đảm
software có thể buộc cảm biến đóng đúng thời hạn; cần kiểm thử thiết bị và
không diễn giải deadline trả kết quả thành chứng nhận phần cứng đã tắt.
Không sửa motion, standby hoặc English Tutor để bật tính năng này.
Khi được phép kiểm thử trên robot, tuân thủ `docs/deploy-visbot.md` và chỉ cài
bằng `scripts/install_chunked.sh`; dùng khung cảnh thử nghiệm không có trẻ em.
