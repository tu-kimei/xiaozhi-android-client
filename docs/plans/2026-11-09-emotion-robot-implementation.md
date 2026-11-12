# Emotion-face và điều khiển robot — triển khai ngày 2026-11-09

Nhánh: `feat/visbot-next-phase`, từ `vietnamese-and-robot-control` sau PR #1 (`7a5c078`).

## Cách sử dụng

- **Cài đặt → Chung → Bộ mặt khi gọi**: chọn Đơn giản hoặc Visbot. Visbot đọc SVGA tại `/system/media/visbot/emotion/`; không có hoặc đọc lỗi thì tự dùng mặt đơn giản. Bộ mặt đơn giản vẫn là mặc định.
- Mặt nói dựa vào tiến độ phát AudioTrack, không dựa riêng vào `tts start`. Đang nghe dùng nét bình tĩnh; đang nghĩ dùng `doubt`. Đang chờ thỉnh thoảng nhìn trái/phải. `FaceController.showEmotion` là đầu vào cho các sự kiện khen/thưởng sau này.
- **Cài đặt → Robot**: bật điều khiển giọng nói để dùng đầu. Bánh xe và cử chỉ tự động mặc định tắt. Cử chỉ tự động chỉ dùng đầu, cùng trạng thái cảm xúc và âm thanh với khuôn mặt.
- Có công cụ `self.robot.head` (`up`, `down`, `center`, `nod`), `self.robot.move` và `self.robot.stop`. Visbot chỉ có trục đầu −23°..25°, vì vậy không khai báo `shake`.
- Sau khi thay đổi công cụ được phép, phiên MCP tiếp theo khai báo danh sách mới. Các lệnh cũ vẫn phải qua kiểm tra quyền hiện tại trước khi thực thi.
- Dùng các nút **Thử 1 bước / Thử 1 vòng trái** ở dưới sàn trống để hiệu chỉnh thời gian theo tốc độ đã chọn. Giá trị ban đầu là tham khảo, chưa phải kết quả đo vòng quay của robot này.

## Ràng buộc chuyển động

- Hàng đợi tuần tự; lệnh DỪNG không chờ hàng đợi. Dừng hủy cả lệnh đang chạy và lệnh chờ, gồm servo đầu lẫn bánh xe.
- Chỉ chấp nhận enum và tham số hữu hạn trong giới hạn. Tốc độ bánh xe không quá 15, tốc độ xoay không quá 200; mỗi lệnh bánh xe tối đa 10 giây.
- Tối đa 30 giây chuyển động liên tục; khi chạm giới hạn phải nghỉ 5 giây. Mọi động tác có timeout và giới hạn số lệnh chờ.
- STT có từ `dừng`, `đứng lại`, `stop` gửi dừng ngay mà không chờ LLM. Nút DỪNG hiện khi bánh xe chạy. Đóng cuộc gọi, mất phiên, ra nền hoặc thay đổi chính sách cũng hủy chuyển động.
- Trong lúc bánh xe chạy, app giữ mic mở và bỏ TTS để ưu tiên nghe lệnh dừng; phần đuôi câu bị bỏ không tự phát lại khi dừng bánh. Câu TTS mới khi đứng yên trở lại chế độ chống vọng bình thường. Chính sách này có unit test; chưa nghiệm thu ASR khi bánh xe thực chạy.
- Nếu phần cứng không xác nhận dừng được, MCP trả lỗi và chặn lệnh mới cho đến khi một lần dừng thành công.
- Không có dữ liệu chống rơi/va chạm được xác minh qua ROSA. Android sensorservice chỉ liệt kê gia tốc kế; không coi đó là cảm biến chống rơi.

## Đã xác minh

- Server chính thức gửi `initialize`, `notifications/initialized`, `tools/list` qua MQTT; app trả đúng JSON-RPC và chỉ khai báo công cụ đang được bật.
- Công cụ đầu nhận lệnh thực từ server, ROSA trả thành công. Kiểm thử trực tiếp MCP `nod` hoàn tất hai lần gật.
- Hủy một động tác đầu đang chạy: native xác nhận dừng trong **23 ms**; future động tác trả trạng thái bị hủy. Đây là thời gian từ lúc app gửi dừng, không bao gồm ASR hoặc độ trễ mạng của câu nói.
- Ra màn hình Home: lời gọi chuyển động bị từ chối vì app ở nền. Quay lại Activity: mặt tiếp tục vẽ, không còn giữ trạng thái `paused`/màn đen.
- SVGA chính hãng hiển thị được trên Visbot Android API 27, 308×240. Các file hệ thống không được đưa vào repository/APK.
- Test gồm giao thức và lỗi MCP; chống thực thi lặp theo request ID; thứ tự/hủy hàng đợi; giới hạn chuyển động; quyền bánh xe; lifecycle; lỗi dừng; mapping 21 cảm xúc; fallback trên thiết bị thường; cử chỉ chỉ dùng đầu; regression ticker/audio.
- Bộ regression liên quan có **42 test**; analyzer cho các lớp/test mới sạch. Cử chỉ mở đầu lượt nói được ưu tiên sau cử chỉ suy nghĩ, nhưng không được lặp chỉ vì một khoảng ngắt bộ đệm.
- So sánh cục bộ bằng cùng **51 gói Opus mã hóa trước**, cấp theo mốc 60 ms: mặt đơn giản **3.910 s**, SVGA **3.903 s**. Cả hai có **0 log `断粮`**, cùng một lần tăng bộ đếm underrun ở cuối đoạn. Đây là phép thử ngắn có kiểm soát, không phải cam kết cho mọi tình trạng mạng.

## Sửa các lỗi nền phát hiện trong lúc tích hợp

- MQTT phải dùng `addUTF8String`, không dùng `addString` (UTF-16). Mô tả công cụ tiếng Việt/mũi tên/emoji làm lộ lỗi wire encoding và gây vòng reconnect. Có test UTF-8 round-trip.
- Không ghi đè `SystemChannels.lifecycle` trong `main`: việc đó làm Flutter giữ `paused` dù Activity đã quay lại, gây màn đen và mất thông báo tự dừng khi ra nền. Thay bằng `AppLifecycleListener`.
- Giữ màn hình sáng khi route call mở, bỏ cờ khi đóng route. Thông báo trong call dùng khoảng cách vừa màn hình nhỏ.

## Giới hạn nghiệm thu còn lại

- Bánh xe chưa được thử thực tế và chưa hiệu chỉnh 1 bước/1 vòng: cần robot ở dưới sàn phẳng, trống, xa mép bậc/cầu thang. Không coi test bằng phần cứng giả lập là phép đo vòng quay.
- Không triển khai `dance` vì đó là phần tùy chọn; không có trục ngang để lắc đầu.
- Bộ SVGA vẽ tự do theo refresh rate quá nặng trên CPU/GPU robot ở bản debug. Bản triển khai giới hạn cập nhật **20 fps**, giảm chi phí lọc và thu nhỏ texture từ 640×500 xuống **308×240** trong bộ nhớ. Mẫu đo debug 10 giây sau tối ưu có **166 frame (~16.6 fps)**, raster trung bình **44.9 ms**; chưa đảm bảo đạt trần 20 fps thực tế. Mặt đơn giản vẫn là mặc định; chưa đo profile/release hoặc nghiệm thu âm thanh dài hạn.

## Hiệu chỉnh đầu trên robot ngày 2026-11-10

- Người dùng xác nhận mapping cũ bị ngược: cúi lại ngẩng. Đổi `up` sang −23°, `down` sang +25° theo phản hồi phần cứng thực tế.
- Servo báo tốc độ 2–30, mặc định 15. Đặt tốc độ 25 cho bộ điều khiển chuyển động.
- `nod` dùng ba chu kỳ −18°/+18° rồi về 0°. Đã gọi trên Visbot qua controller; ROSA hoàn tất thành công. Chuỗi up → giữ 2 giây → down → giữ 2 giây → center cũng hoàn tất; còn chờ người dùng xác nhận hình thái quan sát được.
- Tiến/lùi chưa chạy vì cấu hình thực trên robot có `robot_wheels=false`; chưa bật hoặc cho bánh xe chạy khi chưa xác nhận vị trí đặt robot.

### Nghiệm thu tiến/lùi thực tế

- Người dùng xác nhận vị trí an toàn và cho phép chạy bánh xe; đã bật/lưu `robot_voice=true`, `robot_wheels=true` trên thiết bị.
- Phần cứng báo moving speed 1–15, mặc định 7. Chạy thử ở tốc độ 10: tiến 500 ms hoàn tất sau 519 ms; lùi 500 ms sau 490 ms. Gửi dừng xác nhận sau từng lượt. Người dùng xác nhận đúng chiều, cả tiến/lùi đều chạy; gật đầu mới rõ hơn.
- Phiên MCP mới khai báo `self.robot.move`. Log STT có yêu cầu tiến một bước và lùi một bước; server gọi direction forward/backward, steps=1, mỗi lần trả `isError=false`. Có cả yêu cầu văn bản được gửi trong lúc kiểm tra; không dùng thời gian các lượt đó làm phép đo ASR.
- Chưa đo khoảng cách một bước hoặc hiệu chỉnh một vòng quay; thử ngắn trên sàn không thay thế các phép đo đó.

## Khuôn mặt và cài đặt tiếng Việt

- Bỏ lớp nút `DỪNG ROBOT` phủ lên mặt trong call theo yêu cầu người dùng. Nút dừng trong Cài đặt → Robot và lệnh dừng bằng giọng nói vẫn hoạt động.
- Không thay bằng mặt vector trong lúc tải SVGA mới: giữ mắt Visbot hiện tại. Chỉ dùng mặt dự phòng sau khi xác định không có tài nguyên hệ thống. Mắt dùng movie im lặng; miệng vẽ riêng theo RMS cửa sổ 20 ms tại playback head của AudioTrack, đóng khi âm thanh im lặng/dừng. Không dùng vòng lặp miệng SVGA độc lập với tiếng.
- Cài đặt → Robot: VAG (mặt vector) / SVGA (mắt Visbot), hiện/ẩn mặt, xem thử các trạng thái nghe/suy nghĩ/nói không chạy động cơ hoặc phát tiếng.
- Tốc độ đầu 10–30 (mặc định 25), gật 1–3 nhịp, biên độ 5–20°. Đầu có watchdog từng bước 6 giây và tổng lệnh 30 giây để hỗ trợ tốc độ chậm. Bánh xe vẫn tối đa 10 giây/lệnh, tổng 30 giây liên tục rồi nghỉ.
- Tốc độ tiến/lùi 1–15 và xoay 16–200; giữ tương thích tùy chọn Chậm/Vừa cũ. Chỉnh thời gian một bước/một vòng và thử tiến/lùi/gật/xoay. Đổi tốc độ cần hiệu chỉnh lại thời gian/quãng đường.
- Độ nhạy phát hiện giọng nói tại robot: Thấp/Bình thường/Cao; chờ im lặng 300–1500 ms. Bình thường giữ ngưỡng cũ. Server VAD/ASR vẫn quyết định nhận dạng và phân câu ở server; app không tuyên bố thay đổi được cấu hình server qua các mục này.
- Thử mic cục bộ hiển thị mức âm lượng và ngưỡng phát hiện, không mở phiên upload. Không chiếm mic nếu đang ghi âm ở cuộc gọi; đóng trang sẽ trả mic do trang thử mở.
- Công tắc tự gật khi nói độc lập với cử chỉ theo cảm xúc. Công tắc tự di chuyển mặc định tắt, vẫn cần quyền giọng nói + bánh xe: nhích 200 ms ở tốc độ tối đa 5, luân phiên tiến/lùi giữa các lượt, cách ít nhất 15 giây. Không chạy khi đang phát tiếng hoặc đang nghe người nói; hủy nhịp chờ nếu người dùng bắt đầu nói, đóng call hoặc app ra nền.
- Khôi phục mặc định có xác nhận, đặt lại cấu hình robot và tắt quyền giọng nói/bánh xe/tự động; không xóa cấu hình tài khoản hay hội thoại.
- 51 kiểm thử regression qua; có kiểm tra UI ở 308×240, lưu/đọc/migration/reset, clamp giới hạn, ngưỡng giọng nhỏ, cấu hình gật và tốc độ đến hardware giả lập, tự động độc lập và hủy khi đang nghe. Phần envelope Kotlin đã qua harness kiểm tra frame alignment, RMS, khoảng lặng, drain và reset.

### Kiểm tra bản cài cuối trên Visbot

- APK debug ARM đã cài thành công bằng script chunked và mở được Cài đặt → Robot. Ở trang xem thử SVGA, trạng thái nghe có `ready=true,key=default,fallback=false`, suy nghĩ có `ready=true,key=doubt,fallback=false`; nói mô phỏng giữ `fallback=false`.
- Phép thử PCM tại AudioTrack trên robot: hai đoạn có tiếng xen một giây im lặng; callback envelope có 2 lần mức dương, 2 lần về 0, `active=false` khi kết thúc. Đây là kiểm tra đồng bộ theo playback head, không phải đo lip-sync âm vị hoặc nghiệm thu câu TTS trên mạng.
- Tự gật/tự di chuyển vẫn tắt sau kiểm tra; mặt SVGA, đầu tốc độ 25/gật 3 nhịp, bánh xe tốc độ 10 và xoay 120 được giữ trên thiết bị. Các trang xem thử không chạy động cơ.
- Trang thử mic đã mở trực tiếp trên Visbot, nhận mức phòng khoảng 39 dB/ngưỡng 50 dB ở cấu hình Bình thường; đóng trang sau thử để trả mic.

## Cử chỉ tự nhiên — thay cơ chế theo nhịp cố định

Phần này thay thế mô tả tự gật định kỳ và nhích bánh sau mỗi câu ở trên.

- Ba phong cách: Yên tĩnh / Tự nhiên / Sinh động. Phong cách mặc định cho cấu hình mới là Tự nhiên; các công tắc cho phép đầu/bánh xe vẫn độc lập và mặc định tắt. Yên tĩnh chặn mọi cử chỉ tự động.
- Bỏ timer gật theo tiếng và bỏ chuyển động bánh xe sau lời nói trung tính. Cử chỉ có lựa chọn xác suất, khoảng nghỉ đầu 24/15 giây, bánh 45/30 giây theo Tự nhiên/Sinh động. Một lượt nói chỉ cân nhắc một cử chỉ đầu; khoảng trống bộ đệm không tạo lượt mới.
- Câu xác nhận tiếng Việt (vâng, đúng rồi, đồng ý…) có thể gật một nhịp nhỏ. Khi nghe chỉ thỉnh thoảng gật phản hồi sau khi người nói đã nói ổn định. Suy nghĩ/ngạc nhiên/vui dùng tư thế nhỏ, không kéo về 0° sau từng câu. Cử chỉ đầu có tốc độ riêng từng pha, tỉ lệ theo tốc độ đầu đã cài, giới hạn 4–15; cúi nhanh hơn lúc trở về.
- Vui/hào hứng dựa trên emotion happy/funny khi âm thanh thực phát, loại trừ relaxed/loving thông thường. Chỉ một phần các tín hiệu này được chọn. Nếu có khoảng nghỉ hợp lệ trong 8 giây, thực hiện tiến 450 ms → nghỉ 180 ms → lùi 450 ms ở tốc độ tối đa 2. Không phát động cơ khi đang phát tiếng, không thực hiện cho mọi câu vui và không xếp hàng chờ sau khi tín hiệu đã cũ.
- Đổi lượt sang người nói sẽ hủy cử chỉ chờ và dừng động tác tự động đang chạy; lệnh chủ động vẫn được ưu tiên. Nếu dừng giữa tiến, không chạy tiếp pha lùi. Tắt công tắc đầu không vô tình hủy cử chỉ bánh xe độc lập.
- SDK hiện cấp tốc độ cố định cho từng lệnh, chưa có đường ramp gia tốc được xác minh. Nhịp bánh dùng tốc độ thấp hơn và khoảng nghỉ đổi chiều; không tuyên bố đã điều khiển được gia tốc liên tục.
- Bộ regression 58 kiểm thử qua: lời trung tính đứng yên, nhịp gật bất đối xứng, cooldown, Yên tĩnh, hủy khi người dùng nói, tiến–lùi có ngữ cảnh, không chạy lúc phát tiếng, hủy pha lùi, tín hiệu hết hạn, giới hạn quyền và cấu hình.

### Thử phần cứng cử chỉ tự nhiên

- Đã cài bản ARM debug mới qua chunked, bật phong cách Tự nhiên, cử chỉ đầu và tiến–lùi khi vui trên thiết bị theo yêu cầu người dùng. Quyền bánh xe/giọng nói trước đó vẫn bật.
- Gọi một cử chỉ xác nhận nhỏ trên servo thật: hoàn tất thành công trong 2.980 giây. Một cặp tiến 450 ms/nghỉ 180 ms/lùi 450 ms ở tốc độ tối đa 2 hoàn tất trong 1.076 giây; moving=false, đã gửi dừng xác nhận sau thử.
- Chất lượng nhìn thấy của nhịp mới đang chờ nhận xét người dùng; kết quả native thành công không chứng minh độ tự nhiên hoặc độ êm cơ học. Kiểm thử xác suất/ngữ cảnh/hủy lượt nói chạy với đồng hồ và phần cứng giả lập để tái hiện ổn định.

## Tự nghỉ / từ đánh thức

Đã thêm chế độ nghỉ mặc định 5 phút và nhận “Hey Doradino” offline. Chi tiết phạm vi, quyền Android và kết quả thử trong [kế hoạch nghỉ/đánh thức](2026-11-10-standby-wake-word.md).
