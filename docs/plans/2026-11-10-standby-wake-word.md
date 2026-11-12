# Tự nghỉ và đánh thức Doradino

## Hành vi

- Áp dụng cho màn hình cuộc gọi. Mặc định tự nghỉ sau **5 phút** không chạm/nói; không khóa khi đang nghe, suy nghĩ, nói hoặc mic đang lỗi.
- Khi nghỉ: dừng robot, bỏ phát TTS, gửi abort/stop lên phiên đang hoạt động, đóng đường upload mic. Nếu bật từ đánh thức thì vẫn giữ mic chỉ để nhận từ khóa tại máy.
- Mặc định **Hey Doradino**. Có thể đổi cụm 2–5 từ bằng chữ cái tiếng Anh, tối đa 48 ký tự; đổi độ nhạy Thấp/Bình thường/Cao trong Cài đặt → Robot → Nghỉ và đánh thức. Đây là bộ nhận tiếng Anh; tên riêng có thể cần chỉnh độ nhạy/phát âm theo thử nghiệm thật.
- Sau khi nhận từ khóa: bật đèn nền, bỏ khóa hệ thống khi không có mật khẩu, đợi 300 ms để tránh gửi đuôi từ khóa lên ASR, rồi mở lại phiên nghe. Gọi từ khóa, đợi mặt sáng rồi nói yêu cầu.
- Nút hình mặt trăng trong call cho ngủ ngay. Khi từ đánh thức bị tắt, app cũng dừng mic lúc nghỉ; dùng nút nguồn để mở lại. Chạm màn hình tính lại thời gian khi màn hình đang bật; không tuyên bố touch có thể bật panel đã tắt nếu phần cứng không hỗ trợ.
- Đóng call sẽ đóng detector/dịch vụ nền và trả mic. Feature không phải dịch vụ wake luôn chạy ở màn hình Home hay sau khi thoát ứng dụng.

## Android và quyền

- Dùng DeviceAdminReceiver chỉ khai báo policy force-lock để tắt đèn nền thật, không giả lập màn đen. Nút cấp quyền trong settings dùng màn hình xác nhận tiêu chuẩn Android.
- Trên Visbot thử nghiệm, quyền được kích hoạt bằng `adb shell dpm set-active-admin com.lhht.ai_assistant/.standby.ScreenAdminReceiver` để nghiệm thu. Không đặt device-owner, không xin wipe/password policy.
- Khi ngủ và bật từ đánh thức, foreground service thông báo đang nghe tại robot và giữ PARTIAL_WAKE_LOCK để AudioRecord/KWS không bị dừng cùng panel. Không có root, adb WiFi hoặc sửa system image.
- Mất frame mic quá 6 giây sẽ bật lại màn hình để người dùng không bị kẹt; lỗi chuẩn bị model hoặc thiếu quyền sẽ giữ màn hình bật và báo lỗi.

## Detector offline

- sherpa_onnx 1.13.4 là bản pub giải được với Dart SDK của repo; thư viện Android tương ứng được khóa trong pubspec.lock.
- Model GigaSpeech English 3.3M, encoder/joiner int8 + decoder fp32, khoảng 5.9 MiB asset; source/license trong assets/wake_word. Token hóa Viterbi từ điểm SentencePiece gốc, không gọi dịch vụ mạng để đổi từ khóa.
- Inference chạy ở isolate riêng, một thread CPU. Hàng đợi có giới hạn; quá tải sẽ bật lại màn hình thay vì âm thầm bỏ một lượng audio dài. Copy model sang private storage theo file tạm/rename, kiểm tra kích thước để phục hồi file copy dở.
- Build `--target-platform android-arm` đồng thời lọc JNI của plugin về armeabi-v7a; APK ARM thử nghiệm khoảng 114 MiB thay vì kéo cả thư viện của ba kiến trúc khác.
- [Tài liệu KWS upstream](https://k2-fsa.github.io/sherpa/onnx/kws/index.html), [model phát hành chính thức](https://github.com/k2-fsa/sherpa-onnx/releases/tag/kws-models).

## Đã kiểm tra

- 72 kiểm thử liên quan qua, gồm mốc 5 phút, tương tác mới hoãn ngủ, đang nói không ngủ, hủy prepare khi người dùng tương tác/đóng call/ra nền, thiếu quyền/mic không khóa, mic gián đoạn tự mở màn, từ khóa tắt không mở foreground listener và resume liên tiếp.
- Token hóa so với SentencePiece gốc: Hey Doradino, Hey Dora Dino, Hello Robot, Hey Siri và các fixture khác khớp. Cụm có ký tự điều khiển/không hỗ trợ bị từ chối trước native inference.
- Mẫu giọng tổng hợp “Hey Doradino” nhận được offline ở máy phát triển. Trên Visbot, Android báo Asleep, foreground listener và CPU wake lock còn hoạt động; detector nhận cùng mẫu PCM khi tạm ngưng feed mic thật, sau đó Android về Awake và standby=false, không có lỗi. Một lần decode cả fixture khoảng 1.25 giây cho khoảng 2.2 giây audio. Đây là thử đường nhận/đánh thức, không phải đo tỷ lệ nhận đúng qua mic thật.
- Đã hiệu chỉnh bằng giọng người dùng và nhận xác nhận đánh thức được màn hình; xem mục hiệu chỉnh phía dưới. Chưa đo pin dài hạn hoặc tỷ lệ thức nhầm trong môi trường TV/nhạc.

## Hiệu chỉnh bằng giọng người dùng

- Cấu hình đầu tiên nhận được giọng tổng hợp nhưng người dùng xác nhận chưa đánh thức được qua mic. Đã thu một đoạn 18 giây ngay trong app khi đường upload đang đóng, rồi phân tích hoàn toàn offline. Nhịp frame đúng 16 kHz, giọng rõ; vấn đề nằm ở các cách mô hình tiếng Anh phân đoạn/phát âm tên riêng.
- Giữ ngưỡng Bình thường 0.25 và score 1.5, mở rộng beam từ 4 lên 8 và thêm các biến thể phát âm của tên gọi; mọi biến thể đều trả cùng sự kiện Hey Doradino. Cấu hình nhận đủ 3/3 lần đọc trong mẫu người dùng, cùng kết quả trên runtime desktop 1.13.8 khớp runtime Android.
- Hai file thử upstream không có từ gọi và đoạn nền trước khi đọc đều không tạo phát hiện. Đây là bộ âm tính ngắn, chưa phải phép đo tỷ lệ thức nhầm ngoài thực tế.
- Trên ARM của Visbot, một lần đọc thật được phát lại nội bộ vào detector đã bật màn hình, standby=false, error=null; decode một đoạn 3.5 giây mất khoảng 1.742 giây. Mẫu tự phát từ loa robot chưa đánh thức được (đang bật khử vọng), vì vậy không dùng phép thử loa đó làm bằng chứng nhận giọng người.
- Bản hiệu chỉnh đã được đưa vào APK, không chỉ giữ trong hot reload. Người dùng đã xác nhận màn hình sáng lại khi gọi trực tiếp sau hiệu chỉnh. Mẫu audio hiệu chỉnh không đưa vào repository.

- Người dùng xác nhận gọi trực tiếp đã đánh thức được robot. Đã xóa đoạn thu hiệu chỉnh tạm trên robot và máy phát triển sau khi kiểm tra; không lưu audio người dùng trong repository.
# Bổ sung 2026-11-11: yêu cầu nghỉ qua server và câu gọi tùy chỉnh

- MCP công bố `self.robot.sleep`: server có thể gọi khi người dùng yêu cầu robot đi ngủ, nghỉ hoặc tắt màn hình. Công cụ chỉ thực thi khi màn hình cuộc gọi đang sở hữu bộ nghe cục bộ; không phụ thuộc quyền điều khiển động cơ.
- Dùng lại chế độ nghỉ: dừng phát tiếng và động cơ, ngừng gửi mic lên server, tắt màn hình thật bằng quyền quản trị đã cấp. Nếu đánh thức bằng giọng nói bật, mic và bộ nhận từ khóa vẫn chạy cục bộ. Đây là nghỉ màn hình có nghe mic, không phải tắt nguồn toàn robot.
- Lỗi quyền khóa màn hình, mic hoặc mô hình được trả về MCP, không xác nhận thành công giả. Lệnh ngủ thủ công vẫn dùng được khi tắt hẹn giờ tự ngủ.
- Cài đặt → Robot → Nghỉ và đánh thức → Câu gọi đánh thức: sửa câu rồi bấm Lưu câu gọi đánh thức. Lưu bền qua khởi động lại; cấu hình mới được chuẩn bị ở lần ngủ tiếp theo. Mô hình hiện hỗ trợ câu 2–5 từ bằng chữ cái tiếng Anh, tối đa 48 ký tự; UI giải thích giới hạn này.
- Giữ nguyên câu đã lưu của người dùng. Nếu chọn “Hey Doredino”, các biến thể phát âm đã hiệu chỉnh cho tên “Doradino” cũng được đưa vào bộ nhận và trả cùng sự kiện đánh thức.
- Kiểm tra tự động: MCP discovery/idempotency/lỗi, ngủ theo yêu cầu khi đang nói và tự ngủ tắt, thiếu quyền/mic, rời app, wake trở lại, lưu câu qua UI và nạp lại cấu hình, tokenizer cho “Hey Doredino”.

