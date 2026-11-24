# Thiết kế camera vision một-shot an toàn cho Visbot

Đây là đặc tả thiết kế, **chưa phải triển khai**. Quyết định trung tâm là xây dựng một luồng “nhìn một lần rồi trả lời” có parent gate, chỉ chạy khi app đang foreground/visible, chụp đúng một ảnh tĩnh, gửi qua biên vision được kiểm soát, rồi xóa artifact tạm. Probe ADB trên đúng Visbot đã xác nhận Android Camera Service nhìn thấy một camera sau, nhưng camera chưa được app này mở/chụp thử. HAL hiện công bố API1 và báo `API2 not directly supported`; vì vậy implementation phải **API1-first trên Visbot**, giữ Camera2 như adapter tùy chọn cho thiết bị khác. UVC/vendor SDK chỉ là nhánh điều tra. Vision chỉ tạo câu trả lời hội thoại, luôn trả `canMove=false`, và tuyệt đối không gọi các tool chuyển động hiện có.

Trong tài liệu này, nhãn **[FACT]** là sự kiện đã xác nhận từ repository hoặc nguồn dẫn trực tiếp; **[SOURCED]** là kết quả nghiên cứu có URL; **[PROPOSED]** là giá trị mặc định/kiến trúc đề xuất, cần đo hoặc được product/privacy owner phê duyệt trước khi ship.

## status/decision summary

**Trạng thái:** design-only; file này là thay đổi duy nhất được phép trong phạm vi yêu cầu. Chưa thêm permission, plugin, MethodChannel, MCP tool hay native camera code.

**Các quyết định bắt buộc:**

| Quyết định | Nội dung | Phân loại |
|---|---|---|
| Camera availability | [MEASURED] Camera Service thấy 1 normal device (`id 0`), facing back, orientation 90°, device đang closed/no client; chưa có capture test từ app này | [MEASURED], chưa phải capture-ready |
| MVP | Parent-enabled, snapshot-on-demand, một JPEG cho một request, foreground-only | [PROPOSED] |
| Backend | Trên Visbot: Camera API1 native trước vì HAL báo `API2 not directly supported`; Camera2 adapter chỉ probe tùy chọn; UVC/vendor path không nằm trong MVP | [MEASURED] + [PROPOSED] |
| Flutter boundary | Dart nhận metadata và opaque reference, không nhận base64/live stream | [PROPOSED] |
| MCP | Thêm `self.vision.capture` dạng one-shot bounded observation; schema strict; rate limit; không có side effect robot | [PROPOSED] |
| Dify | Production dùng server-side relay; direct mobile Dify chỉ là prototype-only vì API key hiện nằm trong app | [PROPOSED] + [FACT]/[SOURCED] |
| Motion | Vision không được gọi `self.robot.move`, `self.robot.head` hoặc bất kỳ actuator tool nào; kết quả luôn `canMove=false` | [PROPOSED safety invariant] |
| Retention | Raw frame không lưu lâu dài; file cache/private/no-backup, xóa sau upload/inference, timeout, cancel hoặc shutdown | [PROPOSED], phù hợp hướng dẫn Android |

CameraX/Flutter `camera` không phải đường mặc định trên Visbot vì HAL thực tế báo Camera2 không được hỗ trợ trực tiếp; chỉ xem xét sau khi probe chứng minh plugin có thể đi qua API1 shim và CPU/latency chấp nhận được. Android ghi nhận Camera2 và CameraX hỗ trợ API 21+, nhưng Camera2 phụ thuộc cấu hình thiết bị; Camera API1 đã deprecated từ API 21 và vẫn hữu ích cho thiết bị OEM kiểu legacy ([Android Camera2](https://developer.android.com/media/camera/camera2), [Android Camera](https://developer.android.com/reference/android/hardware/Camera)).

## goals

Mục tiêu của MVP là cung cấp một hành động có thể giải thích với trẻ: trẻ hoặc UI yêu cầu “nhìn”, robot báo trước “Con sẽ chụp một ảnh để trả lời”, camera hoạt động visibly, ảnh được chụp một lần, câu hỏi và ảnh đi qua pipeline được kiểm soát, rồi robot trả lời ngắn gọn với trạng thái không chắc chắn khi cần.

Thiết kế phải có capability probe và chẩn đoán đủ để phân biệt: không có camera, camera bị vendor process chiếm, permission bị từ chối, Camera2 không configure được, API1 hoạt động, hay chỉ có UVC/vendor-private path. Native layer phải quản lý permission, lifecycle, thread, orientation, JPEG validity, temp-file lifecycle và timeout; Flutter chỉ orchestration/UX.

Thiết kế cũng phải giữ pipeline bounded: một request in-flight, một JPEG, kích thước/pixel/byte ceiling, deadline, cancellation, cleanup trong mọi nhánh. MCP registry hiện đã validate các schema cơ bản, vì vậy tool mới phải tận dụng và bổ sung validation/rate-limit ở handler thay vì coi JSON schema là biên an toàn duy nhất ([MCP Tools](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)).

## non-goals

MVP không bao gồm video liên tục, preview stream cho MCP, periodic/background observation, wake-word-only capture, camera khi app background, camera tự động, gallery ảnh cloud, profile trẻ từ ảnh, face recognition/embedding/identity matching, emotion/gaze/age/gender/race/health inference, safety-critical detection, collision avoidance, navigation, obstacle avoidance, hay dùng một câu trả lời model làm bằng chứng rằng người/toy/cầu thang/đường đi an toàn.

MVP không cho phép vision trực tiếp gọi motion tools, thay đổi tốc độ/góc bánh xe, điều khiển đầu robot, hoặc suy ra “được phép di chuyển”. Local ML Kit nếu được bổ sung sau này chỉ xử lý tín hiệu hẹp dạng structured event; ML Kit object detection tối đa năm object và không phải scene-understanding tổng quát ([ML Kit object detection](https://developers.google.com/ml-kit/vision/object-detection/android)).

MVP không giải quyết thay cho tư vấn pháp lý về COPPA, parental consent, data controller/processor, cross-border transfer, DPA, retention/training/subprocessor của provider. Dịch vụ hướng tới trẻ dưới 13 tuổi phải được privacy/legal review ([FTC COPPA](https://www.ftc.gov/legal-library/browse/rules/childrens-online-privacy-protection-rule-coppa)).

## current-state evidence

| Quan sát | Bằng chứng | Hệ quả thiết kế |
|---|---|---|
| Android target | [FACT] App chạy cho Visbot Android 8.1/API 27; build có `minSdk = 24` và arm-only `armeabi-v7a` filter trong `android/app/build.gradle.kts` | Không giả định API 28 external-camera path; kiểm tra ARMv7, HAL và thermal thực tế |
| Camera | [FACT] Không có camera implementation trong repository; `AndroidManifest.xml` hiện chưa khai báo `android.permission.CAMERA` | Chưa được capture; sau design phải thêm permission/native registration trong implementation task |
| Ảnh hiện có | [FACT] `lib/screens/chat_screen.dart` dùng `image_picker` và có đường upload ảnh | Tái sử dụng semantics upload nếu phù hợp, nhưng không đẩy camera byte qua Dart nếu không cần |
| Dify | [FACT] `DifyService.sendMessage` nhận `fileIds`; request dùng `files[]` với `type=image`, `transfer_method=local_file`, `upload_file_id` | Adapter vision có thể nối vào upload-file path; cần tách credential/retention trước production |
| Rủi ro Dify | [FACT] Dịch vụ hiện log prefix API key, device user ID, file IDs và lưu conversation map trong SharedPreferences | Không dùng implementation hiện tại làm privacy boundary cho ảnh trẻ; direct mobile path chỉ prototype-only |
| MCP | [FACT] Registry ở `lib/services/mcp/mcp_server.dart`, đăng ký `McpTool`, validate required/type/enum/min/max/unknown keys; result hiện text-only | Tool mới phải phát text an toàn và reference qua trusted adapter; cập nhật contract khi implementation |
| Robot tools | [FACT] `lib/services/mcp/robot_tools.dart` đăng ký `self.robot.stop`, `self.robot.head`, `self.robot.move` | Vision handler không import/gọi motion; stop vẫn độc lập và luôn ưu tiên |

### Kết quả probe ADB trên Visbot — 2026-11-13

Các kết quả dưới đây là `[MEASURED]` bằng ADB read-only trên serial `0123456789ABCDEF`, chưa phải kết quả capture của app:

| Hạng mục | Kết quả | Ý nghĩa |
|---|---|---|
| Android | Android 8.1.0, API 27; `mt8167`; ABI `armeabi-v7a` | Khớp bối cảnh deploy; không có ABI 64-bit |
| Camera feature | `android.hardware.camera`, `.camera.any`, `.camera.autofocus`, `.camera.front` | PackageManager khai báo camera/autofocus/front capability; chưa chứng minh app mở được |
| Camera service | 1 camera device, 1 normal device, ID `0`, facing `Back`, orientation `90`, no flash | Có một camera sau được camera service quản lý |
| Camera HAL/API | `Camera HAL device@1.0/internal/0`; `API1 info`; `API2 not directly supported` | Visbot phải ưu tiên Camera API1; không giả định Camera2 native |
| Ảnh | JPEG: `320x240` đến `1600x1200`; hiện tại camera service dump ghi picture-size `1600x1200` | Có thể chọn 640x480 hoặc 1280x720/960 làm benchmark; phải capture-test |
| Preview | YUV420 variants; preview sizes đến `1600x1200`; FPS range gồm 15/24/30 | Có đường preview API1 để thỏa điều kiện `takePicture()` |
| Camera ownership | `Device 0 is closed, no client instance`; active clients `[]`; error traces `0` | Tại thời điểm probe không bị app khác giữ; cần test lại trong runtime |
| USB/UVC | Có USB host feature nhưng `USB Port State: <no ports>`; không có `/dev/video*` hoặc `/dev/media*` | Chưa có bằng chứng camera UVC; USB hiện là ADB peripheral mode |
| App hiện tại | Trước probe: `com.lhht.ai_assistant` chưa có CAMERA permission/grant. Sau khi thêm manifest và xin runtime permission: `CAMERA: allow` (AppOps ghi nhận `duration=+22s`) | App này **đã** được cấp quyền và mở được camera; Lily `com.sensornotes.xiaozhi` chỉ là manh mối tham khảo, không được tự động phụ thuộc |

### Kết quả capture thật trong app trên Visbot — 2026-11-14

Diagnostic probe native (`android/app/src/main/kotlin/com/lhht/ai_assistant/vision/CameraProbe.kt`) chạy qua intent extra `camera_probe`, chỉ giữ ảnh trong `cacheDir` và xóa ngay sau khi đọc metadata. **Không upload, không gọi Dify/MCP, không điều khiển robot.**

Luồng đã chạy được: `Camera.open(0)` → set parameters → `setPreviewCallbackWithBuffer` (3 buffer NV21) → `startPreview` → `takePicture(null, null, jpegCallback)` → đọc JPEG → `delete()` → `release()`.

| Đo đạc `[MEASURED]` | Kết quả |
|---|---|
| Mở camera + preview | Thành công, `mtkcam-dev1 [CameraDevice1Base::open] Add new cameraId 0`, `startPreview status(0)` |
| Preview frame đầu | ~590–1040 ms sau `startPreview` |
| Preview FPS thực tế | **~3.6–5.9 fps** ở 640x480 (thấp hơn FPS range HAL khai báo 15/24/30) |
| **Capture đầu tiên sau khi mở camera (cold)** | **~8.0 s và ~8.5 s** trong hai lần chạy độc lập |
| Capture thứ hai trở đi (warm session) | **~1.1–1.3 s** |
| Ảnh 320x240 | 1.08 s, ~76–84 KB, `sof=320x240` |
| Ảnh 640x480 rotation 0 | 1.32 s (warm), ~122 KB, `sof=640x480`, `exif=1` |
| Ảnh 640x480 rotation 90 | 1.10 s (warm), ~122 KB, `sof=480x640` (HAL xoay pixel, không chỉ EXIF) |
| Ảnh 1280x720 | 1.10–1.32 s, ~185 KB, `sof=1280x720` |
| Quyền sở hữu camera | CameraService ghi `CONNECT/DISCONNECT device 0 client for package com.lhht.ai_assistant (PID …)`; sau khi release `Active Camera Clients: []` |
| App khác | Lily `com.sensornotes.xiaozhi` không chạy trong lúc đo; `com.ubtech.visbot` (system) chạy nhưng không giữ camera |
| Tài nguyên | RAM tổng ~1 GB (`ram.low`), `MemAvailable` ~471 MB; không đọc được thermal zone bằng shell thường |

**Kết luận từ capture test:**

1. **Rotation không phải nguyên nhân chậm.** Lần chụp đầu tiên chậm ~8 s bất kể rotation/size; các lần sau ~1.1 s. Đây là cold-start penalty của sensor/ISP/3A trên MTK legacy HAL.
2. `setRotation(90)` làm HAL xoay **pixel thật** (JPEG thành 480x640 portrait) chứ không chỉ ghi EXIF. Vì vậy orientation phải được quyết định theo hướng ảnh mong muốn, không dựa vào EXIF.
3. Preview **bắt buộc phải consume frame** (`setPreviewCallbackWithBuffer` hoặc `updateTexImage`). Dùng `SurfaceTexture` không có consumer làm buffer queue đầy, HAL kẹt ở `StateCapture` và `takePicture()` không bao giờ trả callback.
4. **Device quirk:** SELinux `mtk_hal_camera` bị deny đọc `/dev/devmap` (`avc: denied { read } for name="devmap"`), HAL log `[powerOn] /dev/devmap kernel open fail, errno(13)` nhưng preview/capture vẫn hoạt động. Đây là hành vi cố định của firmware; không được "sửa" bằng cách nới SELinux.

**Chưa đo được:** nhiệt độ CPU/GPU (không có quyền đọc thermal zone), CPU time chính xác của pipeline, hành vi khi Lily/vendor app đang giữ camera, chất lượng ảnh trong điều kiện thiếu sáng, và privacy LED/shutter vật lý.

Repository evidence: [`chat_screen.dart`](https://github.com/tu-kimei/xiaozhi-android-client/blob/feat/visbot-next-phase/lib/screens/chat_screen.dart), [`dify_service.dart`](https://github.com/tu-kimei/xiaozhi-android-client/blob/feat/visbot-next-phase/lib/services/dify_service.dart), [`mcp_server.dart`](https://github.com/tu-kimei/xiaozhi-android-client/blob/feat/visbot-next-phase/lib/services/mcp/mcp_server.dart), [`robot_tools.dart`](https://github.com/tu-kimei/xiaozhi-android-client/blob/feat/visbot-next-phase/lib/services/mcp/robot_tools.dart), [`build.gradle.kts`](https://github.com/tu-kimei/xiaozhi-android-client/blob/feat/visbot-next-phase/android/app/build.gradle.kts).

Related UBTECH Cruzr material advertises RGB/depth hardware and an Android/ROS environment, while an SDK guide shows an API1/NV21 preview callback; đây chỉ là evidence từ platform liên quan, **không phải bằng chứng Visbot có cùng camera hoặc app access** ([Cruzr presentation](https://www.generationrobots.com/media/cruzr-robot-presentation.pdf), [Cruzr SDK guide](https://usermanual.wiki/Document/Cruzr20SDK20Integration20Guide.577788025.pdf)). AOSP external USB camera path cần provider/HAL/kernel/SELinux integration và Java Camera2 `EXTERNAL` hardware level được tài liệu hóa từ API 28; API 27 không được giả định hỗ trợ đường này ([AOSP external USB cameras](https://source.android.com/docs/core/camera/external-usb-cameras)).

## assumptions and unknowns

**Giả định [PROPOSED]** là app có thể foreground một Flutter Activity khi người dùng yêu cầu; parent có thể bật/tắt camera questions; một opaque reference có thể được trusted local adapter resolve; server relay có thể xác thực robot bằng credential không nhúng Dify secret; provider có thể cấu hình retention tối thiểu. Nếu một giả định không đúng, phải chuyển sang failure/unsupported, không tự nới quyền.

**Chưa biết [UNKNOWN]**: hướng ảnh đúng cho mắt người/mô hình (rotation 0 landscape hay 90 portrait) vì chưa ai xem ảnh thật, autofocus/low-light thực tế, hành vi khi Lily hoặc vendor app đang giữ camera, privacy LED/shutter vật lý, CPU time/thermal chính xác, cache capacity, network, Dify host/provider retention và deletion SLA. Camera ID/facing/API1 path, permission grant, cold/warm latency và JPEG size đã được đo; UVC chưa có evidence. Không nguồn công khai nào trong research notes xác minh các điểm còn lại trên đúng Visbot ([hardware research](https://github.com/tu-kimei/xiaozhi-android-client/blob/feat/visbot-next-phase/research_notes/Visbot%20camera%20vision%20design/hardware-camera-stack.md)).

Mọi con số dưới đây như **60 giây reference TTL, 10 giây cooldown, 1920×1080 maximum, 1–2 MB target** đều là [PROPOSED safety defaults], không phải guarantee. Riêng latency đã đo trên Visbot: **~8 s cho lần chụp đầu tiên sau khi mở camera, ~1.1–1.3 s cho các lần sau**. Vì vậy deadline 5 giây ban đầu bị **bác bỏ**.

### Quyết định: bounded pre-warm (2026-11-14)

Để câu hỏi bằng camera không mất ~8 s mỗi lần, camera được **pre-warm có giới hạn**, không phải mở vĩnh viễn:

| Thuộc tính | Giá trị [PROPOSED] | Lý do |
|---|---|---|
| Thời điểm mở | Khi parent bật "Câu hỏi bằng camera" và app đang foreground | Không mở khi trẻ chưa hỏi gì và không có parent watching |
| Thời lượng tối đa | **60 giây**, có countdown hiển thị | Giới hạn cửa sổ camera-active, tránh "luôn bật" |
| Không hoạt động | Tự đóng sau **30 giây** không có capture nào | Giảm thời gian camera mở |
| Lifecycle | Đóng ngay khi app background, screen off, parent tắt, hoặc hết TTL | Không capture/không giữ session ngoài foreground |
| Frame | Preview callback chỉ để nuôi pipeline 3A; **không lưu frame nào** | Pre-warm không tạo artifact |
| Capture | Vẫn một JPEG/request, single-flight, xóa ngay sau khi dùng | Không đổi privacy model |
| Indicator | Banner "Camera đang bật" + countdown trong suốt cửa sổ pre-warm | Trẻ và parent biết camera đang mở |
| Deadline sau pre-warm | **3 giây** end-to-end cho capture + xử lý ảnh | Warm path ~1.1–1.3 s |
| Deadline khi pre-warm chưa sẵn sàng | **12 giây**, UI nói "đang mở camera" | Cold path ~8 s + upload |
| Fallback | Nếu pre-warm fail, chuyển cold path một lần rồi mới báo lỗi | Không loop mở/đóng camera |

Pre-warm chỉ **mở camera và chạy preview**, không phân tích ảnh, không gửi gì lên mạng. Đây là đánh đổi có chủ đích: giảm latency đổi lấy cửa sổ camera-active ngắn, có giới hạn thời gian và có hiển thị rõ.

## user experience and consent

Parent bật “Câu hỏi bằng camera” trong Settings qua parent gate. UI giải thích: chụp một ảnh tĩnh, ảnh gửi tới service nào, retention/deletion ra sao, permission có thể từ chối, và camera không dùng để theo dõi liên tục. Tắt tính năng phải disable tool, hủy request đang chờ và xóa local artifacts.

Mỗi request cần một intent rõ ràng từ nút “Nhìn” hoặc utterance đã được xác định là yêu cầu nhìn; wake word đơn độc không đủ. Trước khi mở camera, UI/robot nói thông báo ngắn và hiển thị banner/camera-active indicator; nếu phần cứng không có LED/shutter thì phải nêu rõ limitation trong product review. Có nút Cancel. Không capture khi Activity inactive/backgrounded, khi robot đang dock/idle nếu chưa có policy riêng, hoặc khi parent đã disable.

Kết quả thành công dùng ngôn ngữ trẻ em, nêu uncertainty: “Mình nhìn thấy … nhưng không chắc” khi ảnh tối/mờ hoặc model confidence thấp. Permission denied, offline, timeout, busy hay unavailable chỉ dẫn đến voice/text fallback; không gây áp lực xin quyền lại. Vision response không được ra lệnh chuyển động.

## architecture diagram

```text
Child utterance / Look button
          │ explicit intent + parent gate + foreground check
          ▼
Flutter VisionCoordinator ───────────────► consent/banner/cancel/fallback UI
          │ MethodChannel: metadata + opaque reference (no JPEG bytes)
          ▼
Native SnapshotCameraService
   ┌──────┴───────────┐
   │ capability probe │── Camera1SnapshotCamera (Visbot primary)
   │                  └── Camera2SnapshotCamera (optional fallback/other devices)
   │                  └── UVC/vendor source (future, only after proof)
   ▼
Private cache/no-backup TempFileStore → VisionReferenceStore (TTL, single-use)
          │ trusted local upload adapter
          ▼
VisionUploadProvider
   ├── Production: authenticated server-side relay → Dify/provider
   └── Prototype only: existing direct mobile Dify upload/fileIds path
          ▼
PolicyGate → bounded answer + canMove=false
          │
          ├── Flutter conversation / Xiaozhi response
          └── self.vision.capture MCP text + opaque resource reference

Independent safety boundary: self.robot.stop/head/move
Vision path ──X──> motion controller / robot actuator
```

## components and responsibilities

| Component | Trách nhiệm | Không được làm |
|---|---|---|
| `VisionCoordinator` (Dart) | Xác nhận consent/foreground, tạo request ID, gọi channel, nối upload/answer, hiển thị state | Không giữ camera bytes, không tự bỏ qua native lifecycle, không gọi motion |
| `CameraSource` | Interface thống nhất `probe`, `capture`, `cancel`, `close`; trả metadata/reference/error; chọn API1 trước trên Visbot theo probe | Không upload cloud, không suy luận scene |
| `Camera2SnapshotCamera` | Enumerate characteristics, session + ImageReader JPEG, orientation, close tài nguyên | Không retry vô hạn |
| `Camera1SnapshotCamera` | API1 serialized open/configure/preview/takePicture/release, normalize JPEG orientation | Không concurrent calls; API1 không thread-safe ([Camera reference](https://developer.android.com/reference/android/hardware/Camera)) |
| `CapabilityProbe` | Ghi camera IDs, API1/API2 path, facing, sizes, open/configure result, quirk fingerprint | Không biến “enumerated” thành “capture-ready” |
| `TempFileStore`/`VisionReferenceStore` | Private cache/no-backup, opaque nonce, TTL, single-use, stale sweep, delete | Không log path hoặc expose arbitrary filesystem path |
| `VisionUploadProvider` | Upload đúng một file, timeout, provider response normalization, deletion hook | Không chứa Dify secret trong APK production |
| `VisionPolicyGate` | Child-safe prompt/answer, uncertainty, `canMove=false`, sensitive-output filtering | Không tuyên bố safety/identity/medical fact |
| `self.vision.capture` handler | Strict MCP validation, consent/foreground/rate limit, invoke one capture, safe result | Không import/use `robot_tools` motion APIs |
| relay | Device auth, Dify call, quotas, no raw-image retention by default, provider deletion/terms | Không coi Dify generic defaults sebagai deletion guarantee |

## camera capability probe

Probe là gate trước implementation và phải chạy trên đúng Visbot bằng diagnostic screen/APK. Probe ghi `apiLevel`, build fingerprint, ABI, permission/AppOps, `CameraManager.getCameraIdList()`, từng ID: lens facing, sensor orientation, `INFO_SUPPORTED_HARDWARE_LEVEL`, capabilities, JPEG/YUV sizes, FPS ranges, min frame duration, open result, session configure result, owner/conflict log. Không chỉ ghi “camera list non-empty”.

Probe theo thứ tự trên Visbot: (1) permission check; (2) enumerate Camera API1 candidate; (3) chọn camera ID `0`/back theo policy; (4) `open → parameters → preview surface → takePicture` với JPEG nhỏ; (5) close/release sạch; (6) chỉ thử Camera2 nếu thiết bị khác công bố API2; (7) nếu integrated path fail, chỉ ghi UVC/vendor evidence, không tự mở `/dev/video*`.

Success của probe phải có ảnh JPEG hợp lệ, kích thước, byte count, orientation đã hiểu, latency và backend. `cameraId` có thể enumerate nhưng bị vendor process chiếm; trạng thái đó là `camera_unavailable`/`camera_busy`, không phải capability success. Output probe không chứa ảnh; golden fixture có thể dùng trong instrumentation.

## CameraSource interface and Camera2/API1 fallback

Interface logic [PROPOSED]: `probe() -> CameraCapabilities`, `capture(CaptureRequest) -> SnapshotResult`, `cancel(requestId)`, `delete(reference)`, `close()`. `CaptureRequest` bounded bởi facing/cameraId, maxWidth/maxHeight, quality, deadline, purpose. `SnapshotResult` gồm opaque `reference`, MIME, width, height, rotation, bytes, backend, capturedAt, expiresAt.

Camera2 dùng `ImageFormat.JPEG`, ImageReader `maxImages=2`, một still request với `TEMPLATE_STILL_CAPTURE`, target surface đã configure. Acquire đúng một `Image`, copy bytes vào temp file, close image trong `finally`, sau đó đóng reader/session/device. Không giữ live preview cho MCP. Nếu size bị reject, chỉ retry một size nhỏ hơn trong native bound. `ImageReader` phải đóng image vì queue đầy sẽ làm producer stall ([ImageReader](https://developer.android.com/reference/android/media/ImageReader), [capture sessions](https://developer.android.com/training/camera2/capture-sessions-requests)).

Camera API1 chỉ dùng khi Camera2 metadata/session không dùng được, `LEGACY`/OEM behavior yêu cầu, hoặc probe chứng minh API1 path. Một event-thread serialized thực hiện open → parameters → preview surface → asynchronous `takePicture` → stop/release. `setDisplayOrientation` không đảm bảo JPEG byte ordering; phải normalize orientation riêng ([Camera#setDisplayOrientation](https://developer.android.com/reference/android/hardware/Camera)). Không loop Camera2/API1 qua lại.

Orientation phải dựa trên sensor orientation, lens facing và device rotation; orientation mơ hồ/contradictory trả `orientation_unknown`, không đoán 0° ([Camera2 preview orientation](https://developer.android.com/training/camera2/camera-preview)). Chọn size lớn nhất dưới pixel/byte ceiling đã đo, không dùng unbounded maximum. API1 và Camera2 cùng trả một contract để Flutter/MCP không biết backend nào chạy.

## Flutter MethodChannel contract

Channel đề xuất [PROPOSED] là `self.vision/camera`. Methods:

| Method | Input | Output/behavior |
|---|---|---|
| `getCapabilities` | none | metadata probe result, không ảnh |
| `captureSnapshot` | `cameraId?`, `facing?` (`back/front/external`), `maxWidth?`, `maxHeight?`, `quality?`, `timeoutMs?`, `purpose?` | metadata map + `vision://snapshot/<opaque>` |
| `deleteSnapshot` | opaque reference | idempotent delete |
| `cleanupStaleSnapshots` | none | count only |

Native clamp/reject unknown keys; max defaults/limits là proposed và phải cấu hình tập trung. Success map không base64:

```json
{"ok":true,"reference":"vision://snapshot/opaque-id","mimeType":"image/jpeg","width":1280,"height":720,"rotation":0,"bytes":183421,"backend":"camera2","capturedAtEpochMs":0,"expiresAtEpochMs":0}
```

`reference` chỉ resolve qua trusted local upload adapter, không phải arbitrary path. Stable `PlatformException.code`: `camera_permission_denied`, `camera_backgrounded`, `camera_unavailable`, `camera_busy`, `camera_timeout`, `camera_configuration`, `camera_capture`, `image_invalid`, `orientation_unknown`, `storage_full`, `cancelled`, `unsupported`, `reference_unavailable`. Details chỉ gồm backend/cameraId/retryable; không gồm API key, full path, stack trace. Flutter có thể reject sớm khi inactive nhưng native luôn re-check vì lifecycle có race. MethodChannel là async và chuẩn codec hỗ trợ map/list/primitive; handler platform main-thread dispatch và camera work phải bounded/offloaded phù hợp ([Flutter platform channels](https://docs.flutter.dev/platform-integration/platform-channels)).

## self.vision.capture MCP contract

Tool [PROPOSED] đăng ký qua MCP registry với tên `self.vision.capture`, description nêu rõ one-shot, user-requested, không monitor/loop/move/background capture. Schema strict:

```json
{"type":"object","properties":{"prompt":{"type":"string","maxLength":300},"camera":{"type":"string","enum":["default","front","back","external"]},"maxWidth":{"type":"integer","minimum":320,"maximum":1920},"maxHeight":{"type":"integer","minimum":240,"maximum":1080},"timeoutMs":{"type":"integer","minimum":500,"maximum":5000}},"required":["prompt"],"additionalProperties":false}
```

Handler phải kiểm tra parent-enabled, foreground/resumed, camera permission, one-in-flight mutex, cooldown (default proposed 10 giây), prompt length/content policy, dimensions, deadline, provider availability và cleanup. Một MCP invocation tạo tối đa một capture; retry nội bộ chỉ là một smaller-size retry camera đã bounded, không lộ retry loop ra MCP. MCP server hiện trả text-only, nên success text chứa metadata ngắn và opaque reference; chỉ thêm `resource_link` sau khi transport/local resolver chứng minh access control. Không mở rộng sang base64 để tiện vận chuyển.

Success text mẫu: `Đã chụp một ảnh JPEG 1280x720, backend camera2; reference hết hạn sau 60 giây.` Không nói “camera thấy” trước khi provider trả lời. Error là `isError=true`, mã ổn định trong text; không lộ filesystem, stack trace hay vendor internals. MCP spec cho phép text/image/resource link nhưng yêu cầu validation, access control, rate limit, timeout và human-in-the-loop ([MCP Tools](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)).

## vision upload/provider boundary

`VisionUploadProvider` nhận `VisionRequest(requestId, prompt, reference, pseudonymousSessionId)` và trả `VisionAnswer(answer, uncertainty, policyCode, canMove=false)`. Nó được phép resolve reference, resize/compress một lần, upload một file, gọi provider và xóa. Dify adapter có thể map file upload ID vào semantics `local_file` hiện có, nhưng conversation/device identifiers phải được thay bằng ephemeral pseudonymous request/session identity khi production boundary cho phép.

**Production:** app xác thực với server-side relay; relay giữ Dify secret, enforce per-device/child quota, request size, provider allowlist, no-training/no-retention settings khi có, response policy, deletion hook và audit metadata không ảnh. Dify tự khuyến nghị gọi API từ backend vì API key nhúng frontend/mobile có thể bị trích xuất ([Dify API FAQ](https://docs.dify.ai/en/getting-started/install-self-hosted/faq/api)). Phải thu thập điều khoản đúng host/model/provider; không suy ra deletion/training/retention từ generic Dify docs.

**Prototype-only:** direct mobile `DifyService` path có thể dùng để kiểm chứng end-to-end sau khi user chấp thuận rủi ro, nhưng phải gắn feature flag, quota, short-lived/revocable key nếu có, không ship child production. Trước production phải loại log API key prefix, device ID, file IDs và rà soát SharedPreferences/backup. Android app-specific cache/no-backup phù hợp hơn ordinary storage; Android Auto Backup cần exclude sensitive files ([Android Auto Backup](https://developer.android.com/identity/data/autobackup), [app-specific storage](https://developer.android.com/training/data-storage/app-specific)).

## lifecycle/concurrency/timeout/cleanup

Capture chỉ được bắt đầu khi Activity resumed/visible, permission granted, parent consent active và request có owner. App pause/inactive, process death, parent disable hoặc cancel đều abort capture/upload, release camera và delete artifact. Không dùng camera foreground service để lách background policy; API 27 không có căn cứ cho background exemption ([camera foreground service](https://developer.android.com/develop/background-work/services/fgs/service-types)).

Một mutex/single-flight reject concurrent request bằng `camera_busy`; không queue unbounded. Default proposed end-to-end deadline là **3 giây khi pre-warm đã sẵn sàng** và **12 giây khi phải cold-open**, với sub-deadline open/configure/capture và provider timeout rõ ràng. Reference proposed TTL 60 giây hoặc single-use sớm hơn. Startup stale sweep xóa prefix file quá TTL. `finally` phải đóng Image, ImageReader, session, device/API1 camera, stream/file handle; xóa partial/invalid JPEG. Cache write phải dùng random filename/private mode, không đưa path ra MCP/model.

Request state machine: `idle → checking → capturing → artifact_ready → uploading → inferring → answer|failed → cleanup → idle`. Mỗi transition có request ID; terminal state luôn cleanup. Sau timeout không retry tự động hoặc enqueue offline. Process death được xử lý bằng startup sweep; server-side upload deletion cần request ID/idempotency nếu provider hỗ trợ.

## privacy/child safety

Mỗi frame có trẻ/bystander được coi là sensitive personal information. Data minimization: một JPEG low-resolution, không audio/video recording, không face biometric, không persistent image history. Prompt gửi provider chỉ là câu hỏi cần thiết, không toàn bộ conversation. Parent có “Delete all vision data”: clear cache, reference/upload IDs, local conversation entries liên quan và gọi provider deletion API; nếu provider không xác nhận deletion thì không dùng cho child images.

Response policy cấm nhận dạng người lạ, private attributes, medical/emotion claims, dangerous instructions và certainty giả. Ảnh/prompt có thể chứa prompt injection; model output vẫn phải qua policy gate. Emergency stop hoạt động độc lập với vision/network; failure ở camera, MCP, policy, network hoặc sensor phải giữ robot đứng yên. Vision không bao giờ thay thế obstacle sensor/safety controller và không được biến “stairs/person/edge/road” thành motion permission.

Audit chỉ ghi request ID, timestamp, backend, camera ID đã redacted nếu cần, result code, dimensions, bytes, duration, consent/foreground booleans và provider status class. Không log raw bytes, thumbnail, full path, API key, child prompt nếu nhạy cảm, device identifier lâu dài, hay model chain-of-thought. Crash reports phải scrub temp paths/image IDs.

## failure matrix

| Điều kiện | Native/channel | MCP | Retry | Side effect/cleanup |
|---|---|---|---|---|
| Permission denied/permanently denied | `camera_permission_denied` | error, giải thích permission | Không auto retry | Không mở camera, không file |
| App background/inactive | `camera_backgrounded` | error foreground required | Chỉ sau foreground/user action | Hủy pending, xóa temp |
| Consent/parent disabled | `unsupported` hoặc `consent_required` | error | Không | Disable tool, cleanup |
| Schema/bounds/unknown key | `invalid_arguments` | error allowed bounds | Không | Không mở camera |
| Request đang chạy | `camera_busy` | error try later | Caller retry sau cooldown | Request owner giữ file |
| Không camera/camera bị vendor chiếm | `camera_unavailable`/`camera_busy` | error capability summary | Không blind retry | Close partial backend |
| Camera2 metadata/session fail | `camera_configuration` | error sau API1 fallback bounded | Fallback đúng một lần | Close device/session/reader |
| API1 open/takePicture fail | `camera_capture` | error safe text | Tối đa một controlled retry nếu còn deadline | `release`, delete |
| Deadline hết | `camera_timeout` | error, không reference | Không auto retry | Cancel, release, delete |
| JPEG thiếu/invalid/oversize | `image_invalid` | error | Có thể một smaller-size retry | Delete invalid |
| Orientation mơ hồ | `orientation_unknown` | error; không đoán | Không | Delete/quarantine TTL |
| Cache full/write fail | `storage_full` | error | Sau cleanup nếu user retry | Delete partial |
| Upload/provider unavailable | `reference_unavailable` | text-only metadata hoặc error theo policy | Không re-capture mặc định | Delete theo TTL |
| Offline/4xx/5xx | `provider_unavailable` | calm fallback | Không queue image | Delete, không motion |
| Cancel/process death | `cancelled` | error/no result | User invoke lại | finally + startup sweep |
| Model low confidence/sensitive output | `policy_rejected`/`uncertain` | safe uncertainty answer | Không capture lại tự động | Delete ảnh, `canMove=false` |

## observability without raw images

Mỗi request dùng `requestId` random không chứa child/device identity. Metrics tối thiểu: probe result/backend, camera ID class, permission outcome, foreground outcome, open/configure/capture/upload/inference latency buckets, JPEG dimensions/bytes, timeout/busy/error counts, cleanup success, stale-file count, provider status class, policy reject count. Logs structured và redact prompt/path/API key/file ID; correlation với relay dùng request ID ngắn hạn.

Diagnostic export cho parent/developer chỉ cho metadata và capability fingerprint, không preview/thumbnail mặc định. Nếu cần debug ảnh, phải là explicit lab-only build/consent, TTL cực ngắn, không cloud log và không child production. Alert khi cleanup fail, timeout tăng, provider deletion fail hoặc camera ownership conflict lặp lại.

## acceptance criteria

1. Trên robot không có camera hoặc camera chưa probe thành công, UI/MCP trả unsupported/unavailable và **không** tuyên bố đã nhìn thấy; không có capture loop.
2. Khi probe thành công, cả Camera2 và API1 adapter (nếu hardware hỗ trợ) trả cùng `SnapshotResult`; orientation/size/byte count được kiểm chứng bằng fixture và artifact luôn đóng/xóa đúng.
3. Permission prompt xuất hiện chỉ sau user intent; denial giữ voice/text app hoạt động; background/inactive bị từ chối.
4. Parent gate, visible indicator, announcement, cancel và delete-all-data hoạt động; tắt consent hủy request và xóa cache.
5. Concurrent invocation bị `camera_busy`; timeout/cancel/process death không để camera session/file/upload queue sống sót; stale sweep dọn được file.
6. `self.vision.capture` strict-validates schema, rate-limits, one-shot, không trả base64/path, không gọi bất kỳ motion tool nào; `canMove=false` trong mọi success answer.
7. Vision answer không thể trigger `self.robot.move/head`; `self.robot.stop` vẫn độc lập và hoạt động khi vision/provider lỗi.
8. Production adapter không chứa Dify secret trong APK, có relay auth, quota, provider terms, deletion contract và redacted audit; direct mobile path chỉ được test dưới prototype flag.
9. Tests bao phủ permission deny, no camera, vendor busy, malformed metadata, rotations, low-light/blur, low storage, offline, 4xx/5xx, duplicate request, cancellation, process kill và prompt injection trong ảnh.
10. Chưa có acceptance nào được đánh dấu pass chỉ vì camera related-UBTECH hoặc Android API tồn tại; phải có log probe trên đúng Visbot.

## staged implementation plan

**Stage 0 — decision/probe only.** Đã **hoàn thành** trên đúng Visbot: app được cấp `CAMERA`, mở được camera ID 0 qua API1, preview có frame, `takePicture()` trả JPEG hợp lệ, camera được release sạch. Kết quả: cold capture ~8 s, warm ~1.1–1.3 s, preview ~4–6 fps, JPEG 640x480 ~122 KB, 1280x720 ~185 KB. Việc còn lại của Stage 0 là chốt hướng ảnh (rotation 0 hay 90) bằng cách xem một ảnh thật, và kiểm tra hành vi khi app vendor đang giữ camera. Diagnostic probe hiện nằm ở `vision/CameraProbe.kt` sau extra `camera_probe` và sẽ bị gỡ hoặc chuyển thành test gate ở Stage 1.

**Stage 1 — native bounded snapshot.** Thêm permission/lifecycle wiring, `CameraSource`, Camera2 adapter, API1 fallback, TempFileStore/ReferenceStore, error codes và unit/instrumentation tests. Chưa cloud, chưa motion, chưa background service. Chạy trên API 27/armeabi-v7a và test cache/rotation/process death.

**Stage 2 — Flutter UX boundary.** Thêm MethodChannel wrapper, typed errors, parent gate, announcement/banner/indicator/cancel, `VisionCoordinator`, lifecycle observer và voice/text fallback. Dart không nhận byte arrays. Gate bằng probe success.

**Stage 3 — MCP contract.** Đăng ký `self.vision.capture`, strict schema, consent/foreground/rate-limit/single-flight, safe text/reference. Integration test chứng minh tool listing/call không reach `robot_tools` motion handlers.

**Stage 4 — provider prototype.** Chỉ khi Stage 1–3 ổn, nối một upload provider; direct mobile Dify là prototype-only, test key exposure/log/backups và short TTL. Không dùng child production.

**Stage 5 — production relay/privacy gate.** Xây relay authenticated, Dify secret server-side, quotas, no-training/retention/deletion evidence, policy gate, data-processing review, parent delete path, observability và release threat model. Chỉ ship sau legal/privacy sign-off.

**Stage 6 — hậu MVP có gate riêng.** Local single-image coarse detector chỉ sau benchmark ARMv7. Periodic/cloud continuous hoặc vision-assisted motion cần battery/thermal/false-positive study, explicit session controls và independent robotics safety review; không tự động mở rộng từ MVP.

## device test checklist

| Nhóm | Kiểm tra bắt buộc | Bằng chứng cần lưu |
|---|---|---|
| Identity | Android 8.1/API 27, build fingerprint, ABI armeabi-v7a, target SDK | redacted diagnostic record |
| Camera enumeration | IDs, facing, orientation, hardware level, capabilities, JPEG/YUV sizes/FPS | JSON metadata, không ảnh |
| Access/ownership | permission grant/deny/permanent deny, vendor app đang dùng camera, concurrent open | error code + sanitized logcat |
| Backends | Camera2 open/configure/capture; API1 fallback; no infinite loop | backend/result/duration |
| Image | JPEG validity, dimensions/bytes ceiling, rotation 0/90/180/270, low-light/blur | golden fixture hash/metadata |
| Lifecycle | pause/resume, Activity destroy, app background, process kill, screen off | cleanup/stale sweep proof |
| Concurrency | duplicate MCP ID, two captures, cancel during open/capture/upload | state transition + no orphan file |
| Storage | full/low cache, partial write, stale TTL | file count/cleanup metrics |
| Network/provider | offline, timeout, 4xx/5xx, relay auth failure, deletion failure | status class, no raw payload |
| UX/consent | parent gate, announcement, indicator, cancel, denial fallback, delete-all | screen/robot behavior checklist |
| Safety | vision answer and prompt injection cannot call move/head; stop works independently | MCP audit + motion controller test |
| Privacy | no bytes/path/key/prompt leakage in logs, crash, SharedPreferences, backup | redaction scan and backup review |
| Performance | capture/upload/inference latency, CPU, memory, thermal, battery on ARMv7 | percentile metrics and go/no-go |

## open decisions

1. ~~Visbot có camera tích hợp app-accessible nào, camera ID nào, và vendor process có ownership độc quyền không?~~ **Đã trả lời phần chính (2026-11-14):** có 1 camera sau ID `0`, app mở/chụp được qua API1, không vendor process nào giữ camera lúc đo. Còn lại: hành vi khi Lily hoặc `com.ubtech.videolive` đang chạy.
2. Có privacy LED/shutter hoặc chỉ có indicator UI/voice? Nếu không có, product có chấp nhận thông báo phần mềm là đủ không?
3. Parent gate và consent model nào đáp ứng jurisdiction, COPPA/age-appropriate design và deployment tại nhà/trường?
4. Relay production đặt ở đâu, device authentication/rotation thế nào, Dify host/model/provider cụ thể là gì, và deletion/training/logging terms đã ký chưa?
5. Reference TTL, cooldown, pixel/byte ceiling chính thức là bao nhiêu? (Latency đã đo: cold ~8 s, warm ~1.1–1.3 s; pre-warm 60 s đã được chọn làm hướng.)
6. Có cần expose `resource_link` trong MCP transport hiện tại, hay chỉ trusted local resolver với text reference?
7. Có cần chọn front/back/external khi UI chưa biết semantics camera, hay chỉ cho `default` đến khi probe có stable mapping?
8. Nếu Camera2 và API1 đều fail, UBTECH có SDK/vendor service được phê duyệt không? UVC có hardware/OTG/kernel/SELinux/ARMv7 evidence không?
9. Provider answer policy và parent-visible audit/delete UX do team nào sở hữu; ai phê duyệt `policy_rejected`, uncertainty và sensitive-topic behavior?
10. Có safety-rated motion controller/obstacle sensors độc lập để giữ invariant “vision không điều khiển chuyển động” khi các phase sau được đề xuất không?

**Điều kiện đóng design:** chỉ sau khi các câu hỏi về camera availability, consent, provider retention/deletion, relay ownership và safety boundary có owner + bằng chứng mới chuyển tài liệu này thành implementation tasks bằng gitnexus-plan. Until then, trạng thái chính thức của Visbot camera là **unknown/unprobed**, không phải available.
