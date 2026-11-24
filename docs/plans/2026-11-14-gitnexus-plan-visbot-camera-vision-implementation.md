# Kế hoạch kỹ thuật GitNexus

> Nhiệm vụ: Triển khai theo giai đoạn chuyên sâu tính năng thị giác camera Visbot chụp một lần, có kiểm soát của phụ huynh.
> Bằng chứng đã được xác minh tại commit 7b1f48d94381de932ed8a33cbf6c9bb349e24010; chỉ mục GitNexus ở cùng HEAD, trình chạy CLI `node .gitnexus/run.cjs` 1.6.12 (danh tính bản phân phối được ghi trong chỉ mục); không cần làm mới. Probe chưa được theo dõi trong working tree không nằm trong chỉ mục; truy vấn PDG cho các điểm neo Dart/Kotlin trả về không có cạnh nào, **không phải bằng chứng rằng không có điều kiện bảo vệ**.
> Lược đồ nguồn gốc bằng chứng 2; global dirty digest `1471e425a8d921650c1accf0e9d6b94e0b1a40510983552a405a443dd2e11c2c`; manifest đường dẫn trích dẫn gồm 17 mục đã sắp xếp; loại trừ đường dẫn chính xác của kế hoạch được tạo. Mọi thay đổi dirty/chưa theo dõi hiện có đều có trước kế hoạch này và phải được giữ nguyên.

## 1. Mục tiêu

Cung cấp một yêu cầu hỏi qua camera rõ ràng, được phụ huynh cho phép, chỉ khi ứng dụng ở foreground → một JPEG → relay tin cậy → câu trả lời an toàn cho trẻ, luôn `canMove=false`; không tác động đến cơ cấu chấp hành do thị giác gây ra. Giai đoạn 1 cung cấp ảnh chụp nhanh native có giới hạn ngay cả khi chưa có cloud hoặc UI. Probe thiết bị Giai đoạn 0 đã hoàn tất; các cổng phê duyệt phát hành production và quyền riêng tư thì chưa.

## 2. Hành vi hiện tại

- [verified] `CameraProbe` là một **công cụ chẩn đoán chưa được theo dõi**, chỉ được gọi qua intent extras của `MainActivity`; nó mở API1 id 0, cấu hình ba bộ đệm callback NV21, tái sử dụng các frame, chờ một frame rồi gọi `takePicture`, cuối cùng dừng/giải phóng (`android/app/src/main/kotlin/com/lhht/ai_assistant/vision/CameraProbe.kt:33-69,76-170,257-265`; `MainActivity.kt:20-38,61-79`). Chế độ keep có thể giữ JPEG trong external files và ghi log đường dẫn đầy đủ: chỉ dùng trong phòng thử nghiệm, không phải mẫu hình production (`CameraProbe.kt:121-156`). `dispose()` tắt executor của nó nhưng không có giao thức hủy rõ ràng cho chủ sở hữu camera (`CameraProbe.kt:72-74`).
- [verified] Quyền CAMERA có trong manifest **đã dirty từ trước**; yêu cầu quyền lúc chạy hiện thuộc về probe (`android/app/src/main/AndroidManifest.xml:1-5`; `MainActivity.kt:31-53`). Thiết bị API 27 cùng hướng ảnh/độ trễ được đo trong bản đặc tả thiết kế chưa được theo dõi (`docs/plans/2026-11-12-visbot-camera-vision.md:54-98`); sau đó người dùng xác nhận rotation **0** ở 640×480 là hướng landscape đúng. Các dòng 3/108/300/345 của bản đặc tả cũ, vốn cho rằng chưa probe hoặc chưa chốt hướng, đã lỗi thời, không phải tiêu chí nghiệm thu.
- [verified] `ChatScreen._pickImage` hiện dùng image_picker, sao chép vào bộ nhớ documents, rồi tải lên trực tiếp qua `DifyService` (`lib/screens/chat_screen.dart:1550-1649`); không phù hợp cho thị giác tạm thời dành cho trẻ. `DifyService` gửi API key/định danh thiết bị, ghi log tiền tố key/file IDs và lưu ánh xạ hội thoại (`lib/services/dify_service.dart:34-103,158-265,449-515`).

## 3. Kiến trúc liên quan

- [verified] `MainActivity` hiện quản lý vòng đời robot, nguồn màn hình, âm thanh và probe chẩn đoán (`MainActivity.kt:13-70`), còn `WakeListeningService` hiện import `MainActivity` (GitNexus `impact(MainActivity, upstream, d=3)`, import trực tiếp). Dùng kênh thị giác native riêng; không thay đổi hành vi màn hình/âm thanh.
- [verified] `XiaozhiService._createMcpServer` đăng ký các công cụ standby và robot; `_handleMcp` ghi log payload yêu cầu/phản hồi (`lib/services/xiaozhi_service.dart:92-135`). `McpServer` kiểm tra trường bắt buộc/kiểu/enum/giới hạn số và khóa lạ nhưng **không kiểm tra maxLength của chuỗi**, bắt ngoại lệ handler thành `e.toString()` thô và chỉ trả về văn bản (`lib/services/mcp/mcp_server.dart:93-157`). Handler công cụ phải kiểm tra độ dài prompt, che thông tin lỗi và tránh ghi log prompt/reference của trẻ ở tầng truyền tải.
- [verified] `registerRobotTools` gọi trực tiếp motion stop/head/move (`lib/services/mcp/robot_tools.dart:5-82`). Riêng `RobotConversationMotion` có thể kích hoạt `motion.celebrate` từ trạng thái khuôn mặt/cảm xúc/giọng nói (`lib/services/robot_conversation_motion.dart:35-101`), vì vậy chỉ tránh gọi công cụ trực tiếp chưa đủ để bảo đảm an toàn chỉ trả lời.

## 4. Phát hiện từ GitNexus

- [graph] `context(MainActivity)` và `impact(MainActivity, upstream, maxDepth=3)` báo LOW, có import trực tiếp ở `WakeListeningService.kt`, không có quy trình nào được lập chỉ mục. **MainActivity dirty và CameraProbe chưa được theo dõi phải được đánh giá dựa trên mã nguồn**; đồ thị không thể mô tả các cạnh probe hiện tại.
- [graph] `context(McpServer)` / `impact(McpServer, upstream, maxDepth=3)` báo **CRITICAL**, 3 đối tượng phụ thuộc d=1 (`_createMcpServer`, `robot_tools.dart`, `xiaozhi_service.dart`), 38 symbol bị ảnh hưởng, 57 luồng bị ảnh hưởng. Tránh thay đổi ngữ nghĩa dispatch dùng chung; kiểm thử registry call/list, robot handlers và tích hợp Xiaozhi. `test/mcp_server_test.dart:43-161` xác minh hành vi hiện tại.
- [graph] `context(DifyService)` / `impact(DifyService, upstream, maxDepth=3)` báo LOW, các nơi import trực tiếp là `chat_screen.dart`, `settings_screen.dart`; đường tải lên trực tiếp hiện có không được trở thành ranh giới thị giác production.
- [graph] `context(RobotConversationMotion)` / `impact(RobotConversationMotion, upstream, maxDepth=3)` báo **CRITICAL**, trực tiếp liên quan `initState` và `voice_call_screen.dart`, 59 luồng bị ảnh hưởng; không refactor nó cho Giai đoạn 1. Phải chủ động giữ đầu ra thị giác ngoài đường cảm xúc/chuyển động tự động và kiểm thử bằng phần cứng giả.
- [graph limitation] `query` cho các khái niệm camera native/MCP/upload trả về những định nghĩa rộng và thứ hạng quy trình thường không liên quan; `detect_changes(scope=all)` tìm thấy bốn symbol được lập chỉ mục đã thay đổi trên ba file tracked nhưng **không tính đến CameraProbe/bản đặc tả chưa được theo dõi**, nên đây không phải khẳng định working tree sạch. Trạng thái dirty toàn repo được ghi trong nguồn gốc bằng chứng thay thế.

## 5. Phát hiện PDG ở cấp câu lệnh

- [graph limitation] `pdg_query(controls/flows, mcp_server.dart)` và `pdg_query(controls, MainActivity.kt)` không trả về kết quả; điểm neo symbol `_handle`/`_validate` cũng trả về không. Không được bịa các cạnh CDG/REACHING_DEF. Điều kiện bảo vệ trong nguồn tại `mcp_server.dart:93-120,129-157` và `MainActivity.kt:31-53` đã được xác minh, nhưng **suy ra từ nguồn, không phải bằng chứng PDG**. Service native chưa có trong đồ thị. Người triển khai chỉ nên lập lại chỉ mục bằng `node .gitnexus/run.cjs analyze --index-only --pdg` nếu có lớp PDG được hỗ trợ và hữu ích; bất kể vậy vẫn kiểm thử race/quyền.

## 6. Thay đổi đề xuất

1. [inferred] **Giai đoạn 1 native**, các file mới `Camera1SnapshotCamera`, `SnapshotCameraService`, `VisionReferenceStore`, và các lớp camera-channel tại `android/app/src/main/kotlin/com/lhht/ai_assistant/vision/`; tích hợp qua `MainActivity` đã xác minh bằng nguồn. Tuần tự hóa mọi thao tác API1 trên luồng chuyên trách sở hữu camera, đưa callback vào cùng state machine được kiểm soát; không làm việc camera trên luồng platform của Flutter. Chỉ prewarm sau tín hiệu phụ huynh bật rõ ràng, khi Activity resumed/hiển thị và màn hình bật, đã cấp quyền. Đặt giới hạn **tuyệt đối 60s tính từ lúc mở** theo đồng hồ monotonic (không gia hạn bởi lần chụp), **giới hạn idle 30s** (đóng sau khi không có lần chụp), sự kiện/đếm ngược hiển thị, đóng ngay khi pause/stop/destroy/tắt màn hình/phụ huynh tắt; dừng callback đang chờ bằng generation token của request, chỉ giải phóng đúng một lần. Không có background service.
2. [inferred] Triển khai API1 id 0/back trên Visbot, JPEG 640×480, `Parameters.setRotation(0)`, thương lượng kích thước được hỗ trợ, preview NV21 với **ba callback buffer có kích thước đúng**, `setPreviewCallbackWithBuffer`, liên tục đưa lại buffer nhận được vào hàng đợi khi preview đang chạy và từ chối chụp đến khi có frame thật. Tránh `SurfaceTexture` không có consumer (HAL thiết bị bị treo). Callback tuyệt đối không ghi/lưu/phân tích frame. Một `takePicture(null,null,jpegCallback)` cho mỗi yêu cầu; kiểm tra JPEG SOI/EOI/SOF, kích thước ảnh/giới hạn byte, giới hạn chất lượng/pixel và metadata reference. Chỉ giữ camera mở trong thời gian prewarm có giới hạn; sau khi `takePicture` dừng preview, khởi động lại preview/cài lại buffer và nhận lại một frame trước yêu cầu kế tiếp hoặc giải phóng. Khi timeout/hủy, vô hiệu hóa generation và **giải phóng camera trên luồng chủ sở hữu**; callback đến muộn không được công bố file. Không chặn luồng chủ sở hữu để chờ callback nếu việc dispatch callback cũng cần luồng này. Yêu cầu thứ hai trả về busy, không xếp hàng công việc vô hạn. Ngân sách chụp native cold **12s**, warm **3s** là các deadline mục tiêu đề xuất dựa trên đo đạc; mỗi loại phải có watchdog và deadline con. Suy luận qua mạng có deadline tách biệt, giới hạn rõ ràng; không tuyên bố 3s end-to-end gồm upload nếu chưa đo.
3. [inferred] `VisionReferenceStore` chỉ ghi JPEG hợp lệ vào thư mục app-private loại trừ backup/kiểm soát cache, tên/nonce ngẫu nhiên, TTL tối đa 60s, reference mờ đục dùng một lần, commit nguyên tử, giới hạn byte của file và một artifact/yêu cầu. Tuyệt đối không lộ đường dẫn hoặc byte cho Dart/MCP. Khi mọi lỗi/hủy/hết hạn/thu hồi/delete-all, xóa file dở dang và đã commit; quét file cũ lúc khởi động xử lý trường hợp process chết. Thiết kế bộ phân giải upload/stream **native** đáng tin cậy (hoặc ranh giới được xác thực tương đương) để reference mờ đục không thể dùng với đường dẫn filesystem Dart tùy ý; không đưa chế độ keep ở external-files vào. Ghi nhận lỗi dọn dẹp và đóng theo hướng an toàn.
4. [inferred] `MainActivity` chỉ thay thế luồng intent chẩn đoán sau khi lưu bằng chứng phòng thử nghiệm; chỉ hỏi quyền sau ý định Look rõ ràng của người dùng, không tự động prewarm trước đồng thuận; channel `getCapabilities`, `startPrewarm`, `captureSnapshot`, `cancel`, `deleteSnapshot`, `cleanupStaleSnapshots`, `close` trả về metadata/mã lỗi có giới hạn. Native kiểm tra lại cổng phụ huynh + foreground ở mọi thao tác, không chỉ ở Dart; không có byte/base64/đường dẫn thô. Giữ quyền trong manifest dirty hiện tại; rà soát chính sách backup. Adapter Camera2 là **tùy chọn sau khi API1 được chứng minh** và không bắt buộc để nghiệm thu Giai đoạn 1 trên Visbot. Nếu thêm cho thiết bị khác, dùng một đường ImageReader JPEG có giới hạn và luôn đóng mọi image/session/device; không lặp fallback. Giữ các channel khác không liên quan của MainActivity.
5. [inferred] **Giai đoạn 2**, adapter/coordinator channel có kiểu mới tại `lib/services/vision/`; cổng phụ huynh được lưu và mặc định từ chối, độc lập với tùy chọn bánh xe robot (`lib/services/robot_preferences.dart:27-51,52-95` là mẫu preference hiện có), thông báo đồng thuận/xóa trong Settings, UI Look tại `chat_screen.dart`/`voice_call_screen.dart` có thông báo, banner/đếm ngược hoạt động, hủy và phương án dự phòng khi offline/thiếu quyền. Cả foreground/lifecycle và trạng thái native đều phải chặn khi không hợp lệ. `_pickImage` hiện có vẫn riêng biệt và không được tái sử dụng cho thị giác. Chỉ wake word hoặc lời gọi MCP từ xa không được phép tự bật camera.
6. [inferred] **Giai đoạn 3**, `lib/services/mcp/vision_tools.dart` riêng, chỉ đăng ký trong `XiaozhiService._createMcpServer` đã xác minh bằng nguồn khi có khả năng đồng thuận/foreground/ý định rõ ràng. `self.vision.capture` kiểm tra nghiêm prompt ≤300, lựa chọn camera/giới hạn, cooldown (~10s đề xuất), single-flight; **`timeoutMs` 500–5000ms của MCP trong bản đặc tả cũ xung đột với cold native ~8s**: chỉ định nghĩa nó là giới hạn chờ của bên gọi với lần chụp đã prewarm, hoặc sửa schema/hợp đồng cho cold 12s trước khi công bố. Handler kiểm tra khóa lạ và độ dài chuỗi; trả mã lỗi an toàn thay vì ngoại lệ thô; chỉ văn bản/reference mờ đục cho đến khi có truyền tải resource được cho phép. Không import motion handlers vào công cụ thị giác.
7. [inferred] **Giai đoạn 4–5**, triển khai hợp đồng relay mobile→server tin cậy, được xác thực (repository/deployment server **chưa được xác minh ở đây**), một JPEG có giới hạn + prompt tối thiểu + request ID tạm thời, Dify secret ở server, quota/giới hạn kích thước, danh sách provider cho phép, điều khoản xóa/lưu giữ, audit đã che dữ liệu và đường xóa hiển thị cho người dùng. Production **không được** gọi trực tiếp `DifyService` trên mobile cho tính năng này; nguyên mẫu Giai đoạn 4, nếu được phê duyệt riêng, không đủ điều kiện production cho trẻ. Thêm policy lọc sự chắc chắn thiếu cơ sở về danh tính/y tế/an toàn và prompt injection, trả về tính không chắc chắn và `canMove=false` bất biến; chuyển câu trả lời đến đầu ra text/voice nhưng không đưa vào `replyText`/cảm xúc hay trigger cử chỉ tự động nếu chưa chứng minh sự cô lập. Stop luôn hoạt động độc lập. Phê duyệt pháp lý/quyền riêng tư là điều kiện chặn phát hành production.

## 7. Trình tự triển khai

1. **Đối chiếu bằng chứng/quyền sở hữu:** giữ nguyên công việc dirty; chỉ cập nhật các mâu thuẫn trong thiết kế như một thay đổi riêng của người triển khai sau khi phê duyệt. Chốt rotation 0 và thời gian cold/warm đã đo; xác định người phụ trách đồng thuận, relay, giới hạn byte cụ thể, nguồn gốc ý định và đồng hồ. Điều kiện hoàn thành: hợp đồng interface/lỗi được duyệt, không có mã thay đổi motion.
2. **Lõi native:** tách service camera production và kho reference riêng từ kiến thức chẩn đoán, triển khai vòng callback buffer preview API1, trạng thái tuần tự, TTL/idle/lifecycle/hủy khi mất quyền. Điều kiện hoàn thành: fixture instrumentation cục bộ không cần cloud; không có artifact tồn tại lâu dài. Chạy lại impact trước mỗi lần sửa symbol hiện có.
3. **Channel/tích hợp native:** nối `MainActivity`, lỗi/metadata có kiểu, quyền chỉ được xin khi có ý định, dọn dẹp/quét sau khi bị kill. Điều kiện hoàn thành: kiểm thử thiết bị API27/ARMv7 xác nhận rotation 0 và giải phóng; hoãn Camera2 trừ khi chấp nhận yêu cầu cho thiết bị không phải Visbot.
4. **Cổng/coordinator/UI Flutter:** cổng phụ huynh, banner 60s hiển thị, đếm ngược/hủy, ý định Look rõ ràng, vòng đời Activity; fallback văn bản. Điều kiện hoàn thành: kiểm thử fake-clock/widget bao phủ hai cổng độc lập và trường hợp từ chối.
5. **Công cụ MCP:** đăng ký cô lập, kiểm tra nghiêm trong handler, cooldown, lỗi an toàn, không chuyển động. Điều kiện hoàn thành: kiểm thử MCP list/call và stop/head/move với phần cứng giả đều đạt; xử lý xung đột schema timeout trước khi bật chụp cold.
6. **Relay/policy:** hoàn tất hợp đồng relay ngoài/auth/phê duyệt riêng tư, triển khai bộ phân giải upload tin cậy + endpoint server, xóa và quota, policy cho câu trả lời. Điều kiện hoàn thành: kiểm thử tích hợp offline/auth/4xx/5xx/timeout/delete và che dữ liệu; không có Dify secret trong APK/config thị giác.
7. **Cổng phát hành:** chạy trên thiết bị với sự cho phép của người dùng và rà soát mối đe dọa quyền riêng tư; kiểm tra hiệu năng/nhiệt/pin, xung đột quyền sở hữu camera và chỉ báo. Khi triển khai, đọc `docs/deploy-visbot.md`, build ARM APK và cài **chỉ** bằng `scripts/install_chunked.sh`; không thuộc lượt lập kế hoạch này. Giai đoạn 6 về ML cục bộ/chụp liên tục/chuyển động được hoãn rõ ràng.

## 8. Chiến lược kiểm thử

- Kiểm thử JVM native với camera/clock/storage có thể inject (kiểm thử mới trong `android/app/src/test/...` khi có harness): bị từ chối quyền/không có camera/vendor bận; chờ frame đầu; cả ba buffer được đưa lại vào hàng đợi; chụp trong deadline cold/warm; hủy lúc mở/preview/JPEG; callback muộn; yêu cầu trùng; idle 30s so với giới hạn tuyệt đối 60s; pause/stop/tắt màn hình/phụ huynh tắt; khởi động lại preview hoặc giải phóng; JPEG lỗi/quá lớn; dung lượng thấp; quét file cũ lúc khởi động và dùng một lần/TTL. Instrumentation Android trên Visbot API27 thật là thiết yếu cho HAL cũ và nhiệt; hiện chưa tìm thấy thư mục test Android.
- Kiểm thử Flutter: `test/vision_coordinator_test.dart` mới, kiểm thử widget Settings/UI, cập nhật `test/mcp_server_test.dart:43-161`, `test/robot_motion_controller_test.dart:10-63` với phần cứng giả: bị từ chối → không mở camera; yêu cầu hợp lệ, rõ ràng → một lần chụp; prompt lỗi/khóa thừa/quá kích thước → không chụp; đồng thời/busy/hủy → chỉ một lần dọn dẹp kết thúc; chỉ dẫn chèn trong hình ảnh → không move/head, stop vẫn hoạt động; câu trả lời thị giác không kích hoạt tự động ăn mừng qua `RobotConversationMotion`. Kiểm thử ID JSON-RPC trùng và reset session.
- Kiểm thử relay trong repository tương lai của nó: auth sai/quá kích thước/vượt quota/provider 4xx/5xx/timeout/retry/xóa thất bại và prompt injection trong phản hồi → câu trả lời/lỗi an toàn, audit có giới hạn đã che dữ liệu, không lưu dữ liệu thô. Kiểm thử thiết bị không dùng hình ảnh trẻ thật, có đồng thuận phòng thử nghiệm rõ ràng; xác minh byte/hình dạng và chỉ báo hiển thị cho phụ huynh. Chạy `flutter test ...`, `flutter analyze`; lệnh build ARM và triển khai theo chunk chỉ dành cho triển khai từ `docs/deploy-visbot.md:12-35` đã xác minh.

## 9. Phân tích rủi ro và tác động

- [graph] `McpServer` và `RobotConversationMotion` **CRITICAL**; các đối tượng phụ thuộc trực tiếp đã được bao phủ: MCP `_createMcpServer` trong `xiaozhi_service.dart`, nơi import `robot_tools.dart` và `xiaozhi_service.dart`; conversation motion trong `voice_call_screen.dart` và caller `initState` của nó. Giữ nguyên dispatch toàn cục và emotion/motion; kiểm thử tập trung mọi consumer trực tiếp và stop độc lập. Import trực tiếp của standby service vào `MainActivity` vẫn hoạt động. Các consumer trực tiếp của `DifyService` là `chat_screen.dart`/`settings_screen.dart` không đổi đối với luồng ảnh hiện có.
- [inferred] Giới hạn 60s và idle 30s phải dùng đồng hồ monotonic, generation/giải phóng an toàn trước race và callback vòng đời; tắt màn hình có thể xảy ra mà không có lifecycle Flutter. Preview HAL bị thiếu frame là nguy cơ đã được chứng minh, không phải tối ưu mang tính giả thuyết. Quyền camera có sẵn trong manifest dirty không đồng nghĩa với đồng thuận dùng trong production.
- [inferred] Chỉ reference mờ đục dùng một lần không bảo đảm bí mật; cần bộ phân giải đã xác thực và cô lập file cục bộ. Log payload MCP hiện tại và chuỗi lỗi handler thô sẽ lộ prompt/token nếu cắm thị giác vào một cách đơn giản. Hệ thống upstream có thể gọi robot motion độc lập; bảo đảm kết quả thị giác không đi vào đường đó; không tuyên bố robot bất động toàn cục.

## 10. Những file dự kiến thay đổi

| File | Symbol / phạm vi | Lý do |
|---|---|---|
| `android/app/src/main/kotlin/com/lhht/ai_assistant/vision/` các file production mới | camera, reference, channel mới | Service native Giai đoạn 1, preview API1 có buffer, vòng đời |
| `android/app/src/main/kotlin/com/lhht/ai_assistant/MainActivity.kt` | `MainActivity` | Nối channel/quyền và hủy độc lập; giữ công việc dirty |
| `android/app/src/main/AndroidManifest.xml` | rà soát CAMERA/backup | Quyền đã có trong thay đổi dirty; không có background camera service |
| `android/app/src/main/kotlin/com/lhht/ai_assistant/vision/CameraProbe.kt` | `CameraProbe` | Ngừng hoặc giới hạn chế độ keep chỉ dùng trong phòng thử nghiệm vào test sau khi lưu bằng chứng |
| `lib/services/vision/` các file mới | coordinator, channel, relay policy | Ranh giới metadata native và pipeline chỉ trả lời |
| `lib/screens/settings_screen.dart`, `lib/screens/chat_screen.dart`, `lib/screens/voice_call_screen.dart` | cổng / UI Look | Đồng thuận, chỉ báo và fallback |
| `lib/services/xiaozhi_service.dart`, `lib/services/mcp/vision_tools.dart` | `_createMcpServer`, handler mới | Đăng ký MCP cô lập |
| `test/` và `android/app/src/test/`, `android/app/src/androidTest/` | kiểm thử mới/cập nhật | An toàn, vòng đời, bằng chứng HAL |
| repository relay bên ngoài (chưa rõ) | endpoint, policy, xóa | Cô lập secret production; không bịa đường dẫn ở đây |

## 11. Ngữ cảnh triển khai có thể tái sử dụng

```json
{
  "implementation_context": {
    "task_summary": "Staged, parent-gated one-shot Visbot camera vision, native API1 first, trusted relay and answer-only safety.",
    "acceptance_criteria": [
      "single JPEG/request; private single-use TTL reference; rotation 0 on Visbot",
      "parent-enabled 60s maximum prewarm, 30s idle close, visible foreground only",
      "no raw image/path/secret to Dart or MCP; production relay and policy",
      "all vision outcomes canMove=false; stop independent and no move/head calls"
    ],
    "evidence_provenance": {
      "schema_version": 2,
      "head_commit": "7b1f48d94381de932ed8a33cbf6c9bb349e24010",
      "generated_plan_path": "docs/plans/2026-11-14-gitnexus-plan-visbot-camera-vision-implementation.md",
      "global_dirty_digest": {
        "algorithm": "sha256",
        "canonicalization": "gitnexus-evidence-provenance-v2 NUL-framed UTF-8 records",
        "value": "1471e425a8d921650c1accf0e9d6b94e0b1a40510983552a405a443dd2e11c2c"
      },
      "cited_path_manifest": [
        {
          "path": "android/app/build.gradle.kts",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:e8a8eb1051c44dcf508e1da125e3c227c76e174bebc7e6365a7f6d68d33cc3e2",
          "index_digest": "sha256:e8a8eb1051c44dcf508e1da125e3c227c76e174bebc7e6365a7f6d68d33cc3e2",
          "worktree_digest": "sha256:e8a8eb1051c44dcf508e1da125e3c227c76e174bebc7e6365a7f6d68d33cc3e2",
          "untracked_digest": "absent"
        },
        {
          "path": "android/app/src/main/AndroidManifest.xml",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "unstaged",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:6d106f2f82538cf462fa2f914a1d2b8d4d604e997572658b9c4e6436fd41f6a6",
          "index_digest": "sha256:6d106f2f82538cf462fa2f914a1d2b8d4d604e997572658b9c4e6436fd41f6a6",
          "worktree_digest": "sha256:8781f1291e4d7b367d95a4113cc8e68e5809603a0787fa9629b6178ca665578c",
          "untracked_digest": "absent"
        },
        {
          "path": "android/app/src/main/kotlin/com/lhht/ai_assistant/MainActivity.kt",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "unstaged",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:4def7d5deeee7ff45ef01dbf04cbce59ab8716de1370edb4934de9fb242cbf31",
          "index_digest": "sha256:4def7d5deeee7ff45ef01dbf04cbce59ab8716de1370edb4934de9fb242cbf31",
          "worktree_digest": "sha256:28b473993df7a51467f0c652d752fc490ac3da440476ee33f1cbd0c386b8a2ba",
          "untracked_digest": "absent"
        },
        {
          "path": "android/app/src/main/kotlin/com/lhht/ai_assistant/vision/CameraProbe.kt",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:44b43ca4793f014d6409b1e7bae1f63b97bd847cc9557192533f555c402434fd"
        },
        {
          "path": "docs/deploy-visbot.md",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:c9b93c656104b87e630835d096ce31a2d808b50e148ba626e1a13a616341b8d2"
        },
        {
          "path": "docs/plans/2026-11-12-visbot-camera-vision.md",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:3753cd8b77974fd1879f2fc3cfd1c8c84255bb9e4c80d6118c8d1eaf64659c79"
        },
        {
          "path": "lib/screens/chat_screen.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:987624fb1287903b33f83fcc99ce6cdf83b2c50aedd53ad59959acf23f4f1bce",
          "index_digest": "sha256:987624fb1287903b33f83fcc99ce6cdf83b2c50aedd53ad59959acf23f4f1bce",
          "worktree_digest": "sha256:987624fb1287903b33f83fcc99ce6cdf83b2c50aedd53ad59959acf23f4f1bce",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/screens/settings_screen.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:4944c544d21352ee26fdb29b6548928fde723e0659dbdb650872ea3b8d5e18e3",
          "index_digest": "sha256:4944c544d21352ee26fdb29b6548928fde723e0659dbdb650872ea3b8d5e18e3",
          "worktree_digest": "sha256:4944c544d21352ee26fdb29b6548928fde723e0659dbdb650872ea3b8d5e18e3",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/screens/voice_call_screen.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:d89dcc7b132b16aba46199b97cc04b68d436d01c29f90849101746be58af8130",
          "index_digest": "sha256:d89dcc7b132b16aba46199b97cc04b68d436d01c29f90849101746be58af8130",
          "worktree_digest": "sha256:d89dcc7b132b16aba46199b97cc04b68d436d01c29f90849101746be58af8130",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/services/dify_service.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:36687baf0feb6eada184aba25e60b1cb5f284513915b73e379686f870a7cb436",
          "index_digest": "sha256:36687baf0feb6eada184aba25e60b1cb5f284513915b73e379686f870a7cb436",
          "worktree_digest": "sha256:36687baf0feb6eada184aba25e60b1cb5f284513915b73e379686f870a7cb436",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/services/mcp/mcp_server.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:332aaf432c13c1423a1886f873e0e06b34fa6c263d9ac0ce97b1c3d961529f21",
          "index_digest": "sha256:332aaf432c13c1423a1886f873e0e06b34fa6c263d9ac0ce97b1c3d961529f21",
          "worktree_digest": "sha256:332aaf432c13c1423a1886f873e0e06b34fa6c263d9ac0ce97b1c3d961529f21",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/services/mcp/robot_tools.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:e45d89c8efb198368ba17858c0629eaec6e24a1fed5803671baaaf9296a78c2b",
          "index_digest": "sha256:e45d89c8efb198368ba17858c0629eaec6e24a1fed5803671baaaf9296a78c2b",
          "worktree_digest": "sha256:e45d89c8efb198368ba17858c0629eaec6e24a1fed5803671baaaf9296a78c2b",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/services/robot_conversation_motion.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:43e9489e2505802809e383bfc28c743e4a04c2d86fea44e88f17890bdec0c1c5",
          "index_digest": "sha256:43e9489e2505802809e383bfc28c743e4a04c2d86fea44e88f17890bdec0c1c5",
          "worktree_digest": "sha256:43e9489e2505802809e383bfc28c743e4a04c2d86fea44e88f17890bdec0c1c5",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/services/robot_preferences.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:97af606979f64248a95087d5568a935c7fd6f3bb58acc1fa33c1529537e888e6",
          "index_digest": "sha256:97af606979f64248a95087d5568a935c7fd6f3bb58acc1fa33c1529537e888e6",
          "worktree_digest": "sha256:97af606979f64248a95087d5568a935c7fd6f3bb58acc1fa33c1529537e888e6",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/services/xiaozhi_service.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:4f02fc852253c413f65681033e4b079ce53f1f3fb107e76b3e4abd219bdff988",
          "index_digest": "sha256:4f02fc852253c413f65681033e4b079ce53f1f3fb107e76b3e4abd219bdff988",
          "worktree_digest": "sha256:4f02fc852253c413f65681033e4b079ce53f1f3fb107e76b3e4abd219bdff988",
          "untracked_digest": "absent"
        },
        {
          "path": "test/mcp_server_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:e44ba2e79d0982dde099a5a5e94b203b54ed5ff2ca81e3d5b401e20707494d1b",
          "index_digest": "sha256:e44ba2e79d0982dde099a5a5e94b203b54ed5ff2ca81e3d5b401e20707494d1b",
          "worktree_digest": "sha256:e44ba2e79d0982dde099a5a5e94b203b54ed5ff2ca81e3d5b401e20707494d1b",
          "untracked_digest": "absent"
        },
        {
          "path": "test/robot_motion_controller_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:96c967b97614c504683604868399f6f85799f6d41ca0939299e670604ada5e1f",
          "index_digest": "sha256:96c967b97614c504683604868399f6f85799f6d41ca0939299e670604ada5e1f",
          "worktree_digest": "sha256:96c967b97614c504683604868399f6f85799f6d41ca0939299e670604ada5e1f",
          "untracked_digest": "absent"
        }
      ]
    },
    "primary_symbols": [
      {
        "symbol": "MainActivity",
        "file": "android/app/src/main/kotlin/com/lhht/ai_assistant/MainActivity.kt",
        "lines": "13-79",
        "role": "native registration, lifecycle and permission"
      },
      {
        "symbol": "CameraProbe",
        "file": "android/app/src/main/kotlin/com/lhht/ai_assistant/vision/CameraProbe.kt",
        "lines": "25-266",
        "role": "untracked Stage-0 evidence, not production service"
      },
      {
        "symbol": "McpServer",
        "file": "lib/services/mcp/mcp_server.dart",
        "lines": "29-170",
        "role": "registry and text-only result validation"
      },
      {
        "symbol": "DifyService",
        "file": "lib/services/dify_service.dart",
        "lines": "10-517",
        "role": "existing direct upload; exclude from child production"
      },
      {
        "symbol": "RobotConversationMotion",
        "file": "lib/services/robot_conversation_motion.dart",
        "lines": "10-110",
        "role": "independent automatic motion risk"
      }
    ],
    "related_symbols": [
      {
        "symbol": "XiaozhiService._createMcpServer",
        "relationship": "registers tools",
        "relevance": "vision registration only; avoid global dispatcher changes"
      },
      {
        "symbol": "registerRobotTools",
        "relationship": "registers stop/head/move",
        "relevance": "must not be called by vision"
      },
      {
        "symbol": "ChatScreen._pickImage",
        "relationship": "existing Dify image route",
        "relevance": "persistent image copy is unsuitable for one-shot child vision"
      },
      {
        "symbol": "RobotPreferences",
        "relationship": "shared preferences",
        "relevance": "new consent state must be independent and fail closed"
      }
    ],
    "execution_path": [
      "parent enables feature and starts explicit bounded foreground prewarm with visible countdown",
      "native rechecks permission/resumed/screen/consent and serializes Camera.open(0), three NV21 preview buffers, frame recycling",
      "one takePicture callback yields valid 640x480 rotation-0 JPEG and private single-use reference",
      "trusted local adapter resolves reference once for authenticated relay upload; deletes artifact on every terminal branch",
      "relay performs Dify/provider call and policy, returns bounded answer with canMove=false; UI/MCP displays answer without motion dispatch"
    ],
    "pdg_constraints": [],
    "architectural_patterns": [
      {
        "pattern": "native MethodChannel wiring in FlutterActivity",
        "example_location": "android/app/src/main/kotlin/com/lhht/ai_assistant/MainActivity.kt:20-29",
        "usage_guidance": "new camera channel separate from robot and screen channels"
      },
      {
        "pattern": "McpTool enabled callback and text result",
        "example_location": "lib/services/mcp/mcp_server.dart:5-25,93-120",
        "usage_guidance": "register separate vision handler; sanitize failures"
      },
      {
        "pattern": "robot stop independently registered",
        "example_location": "lib/services/mcp/robot_tools.dart:12-27",
        "usage_guidance": "never gate stop behind vision"
      }
    ],
    "files_to_modify": [
      {
        "file": "android/app/src/main/kotlin/com/lhht/ai_assistant/MainActivity.kt",
        "symbols": [
          "MainActivity"
        ],
        "intended_change": "replace diagnostic-only wiring with production native service/channel and lifecycle cancellation, preserving unrelated channels"
      },
      {
        "file": "android/app/src/main/kotlin/com/lhht/ai_assistant/vision/CameraProbe.kt",
        "symbols": [
          "CameraProbe"
        ],
        "intended_change": "retire lab-only keep mode after retaining test evidence; do not ship raw artifact log"
      },
      {
        "file": "android/app/src/main/AndroidManifest.xml",
        "symbols": [],
        "intended_change": "retain existing dirty CAMERA permission; review backup exclusions and no background camera service"
      },
      {
        "file": "lib/services/xiaozhi_service.dart",
        "symbols": [
          "XiaozhiService._createMcpServer"
        ],
        "intended_change": "register isolated vision tool with fail-closed gate"
      },
      {
        "file": "lib/screens/settings_screen.dart",
        "symbols": [],
        "intended_change": "parent gate and consent details"
      },
      {
        "file": "lib/screens/chat_screen.dart",
        "symbols": [
          "ChatScreen._pickImage"
        ],
        "intended_change": "add separate Look entry, do not reuse persistent Dify image flow"
      },
      {
        "file": "lib/screens/voice_call_screen.dart",
        "symbols": [],
        "intended_change": "visible indicator/cancel and explicit voice intent only"
      }
    ],
    "tests": [
      {
        "file": "test/mcp_server_test.dart",
        "scenarios": [
          "invalid/unknown/oversize prompt and dimensions → no capture",
          "disabled/paused consent → tool absent or rejected; duplicate ID executes once"
        ]
      },
      {
        "file": "test/robot_motion_controller_test.dart",
        "scenarios": [
          "vision answer/prompt injection → fake hardware records no head/move; stop still works"
        ]
      },
      {
        "file": "test/vision_coordinator_test.dart",
        "scenarios": [
          "cancel/pause/timeout/consent-off → native cancel + cleanup and fallback; fake clocks enforce bounds"
        ]
      },
      {
        "file": "android/app/src/androidTest/.../Camera1SnapshotTest.kt",
        "scenarios": [
          "on-device 3-buffer preview → 640x480 rotation-0 valid JPEG; cold/warm timings",
          "busy/denied/background/low-storage/kill/restart → closed camera and no orphan file"
        ]
      }
    ],
    "verification_commands": [
      "flutter test test/mcp_server_test.dart test/robot_motion_controller_test.dart test/vision_coordinator_test.dart (after new file exists)",
      "flutter analyze",
      "flutter build apk --debug --target-platform android-arm (implementation only; JAVA_HOME and PATH per docs/deploy-visbot.md)",
      "scripts/install_chunked.sh (implementation device test only; never adb install/flutter run)"
    ],
    "risks": [
      "McpServer impact CRITICAL: broad dispatch flows; avoid generic response changes",
      "RobotConversationMotion impact CRITICAL: face/reply routes can induce automatic movement",
      "cold takePicture ~8s: 5s schema cannot be native cold deadline",
      "DifyService leaks key prefix/device/file IDs; existing chat path stores permanent image"
    ],
    "assumptions": [
      "Check where relay source and deploy ownership live before integration; none was verified in this repo",
      "Recheck vendor camera ownership, privacy indicator hardware and provider terms on production device",
      "Confirm parent-auth model, TTL/byte limits and delete semantics with product/privacy owner"
    ],
    "open_questions": [
      "Choose relay endpoint/auth and provider retention/deletion SLA before child production",
      "Determine voice-intent provenance that cannot be forged by remote MCP invocation",
      "Does user intend all app conversation-motion automatic gestures disabled during vision answers? Default to no voice-state/emotion triggers and test"
    ],
    "avoid": [
      "Do not overwrite preexisting dirty/untracked files or treat CameraProbe as production-ready",
      "Do not use unconsumed SurfaceTexture; no background/continuous camera",
      "Do not send JPEG/base64/path/secret through Dart or MCP; never call motion/head from vision",
      "Do not use direct DifyService for child production",
      "Do not use adb install or flutter run on robot"
    ]
  }
}
```

## 12. Giả định và câu hỏi còn mở

- [assumed] Relay phía server và triển khai xác thực thiết bị đã tồn tại hoặc có thể được cung cấp ngoài repo này; xác định người phụ trách và xác minh auth/luân chuyển key, quota, SLA xóa/huấn luyện/lưu giữ trước khi bật dữ liệu trẻ em. Kế hoạch này chưa xác lập điều khoản của provider.
- [assumed] Cổng/xác thực phụ huynh và nguồn gốc phát ngôn rõ ràng có thể trở nên đáng tin cậy xuyên Flutter↔native↔MCP; thiết kế và kiểm thử chống vượt qua. Quyền đã được cấp cho probe, nhưng quyền được giữ lâu dài không bao giờ thay thế đồng thuận phụ huynh.
- [assumed] Prewarm tuyệt đối 60s, idle 30s, TTL reference 60s, cooldown 10s, giới hạn chất lượng/byte ở 640×480 và deadline native 12s/3s là mặc định đề xuất, chờ xác thực về sản phẩm/hiệu năng; timeout mạng tách biệt. Xác nhận LED/shutter vật lý, xung đột process vendor, ánh sáng yếu, nhiệt và CPU trên robot.
- [verified discrepancy] Nguồn `CameraProbe.kt:121-135` vẫn có chế độ keep; các dòng thiết kế 3/108/300/345 khẳng định chưa biết/probe chưa hoàn tất, trong khi lần chụp thiết bị thực và quyết định hướng ảnh đã thay thế chúng. Người triển khai không được âm thầm xóa công cụ chẩn đoán chưa được theo dõi của người dùng.
- [graph limitation] Truy vấn PDG không tạo cạnh ở cấp câu lệnh cho các hàm Dart/Kotlin này, và mã native chưa được theo dõi nằm ngoài chỉ mục. Làm mới chỉ mục sau khi thêm file production và xác minh impact bằng nguồn khi đó; không bịa cạnh. Bản phân phối analyzer chưa được build lại; không dùng công cụ đổi model trong phiên này (model con được cung cấp là `kimei/gpt-6-sol`).
- Hoãn rõ ràng: chụp liên tục/video, bộ nhận diện ML cục bộ, UVC/vendor SDK, chuyển động tự động do thị giác kích hoạt, Camera2 trên Visbot khi chưa có bằng chứng. Camera2 có thể thêm cho đích không phải Visbot được xác minh riêng.

## 13. Định nghĩa hoàn thành

1. Thiết bị: API27 ARMv7 id0 chụp **một** JPEG landscape 640×480 rotation-0 hợp lệ qua ba buffer NV21 tái sử dụng; hành vi cold/warm có giới hạn đã được đo mà không bị đói frame do SurfaceTexture; camera được giải phóng sau timeout/tắt/background/idle 30s/giới hạn cứng 60s.
2. Đồng thuận/UX: Look chỉ ở foreground có cổng phụ huynh, chỉ xin quyền sau ý định, đếm ngược/thông báo/hủy hiển thị và fallback nhẹ nhàng; tắt màn hình/background đóng ngay, không tự mở lại khi thiếu hành động rõ ràng của phụ huynh.
3. Dữ liệu: một JPEG riêng tư cho mỗi yêu cầu, không lưu frame preview, reference mờ đục dùng một lần, không có byte/đường dẫn trong Dart/MCP/log/backup; dọn dẹp mọi trường hợp kết thúc và quét khi khởi động lại, xác minh delete-all.
4. An toàn: `self.vision.capture` kiểm tra nghiêm/cooldown/single-flight; câu trả lời policy `canMove=false`; không có head/move hoặc cử chỉ hội thoại do thị giác kích hoạt khi gặp prompt injection; kiểm thử stop khẩn cấp độc lập.
5. Production: relay được xác thực giữ Dify secret; quota, yêu cầu có giới hạn, bằng chứng xóa/lưu giữ của provider, rà soát pháp lý/quyền riêng tư, audit che dữ liệu và người phụ trách phê duyệt phát hành. Tải lên trực tiếp từ mobile không được tính là hoàn thành.
6. Kiểm thử/analyze đều đạt cùng instrumentation trên thiết bị được phê duyệt; không mất công việc dirty/chưa theo dõi có từ trước. Sau khi triển khai và trước bất kỳ commit nào, chạy GitNexus `detect_changes(scope=all)` mà không chấp nhận partial/truncated là sạch.
