# Khảo sát chuyển động Lily trên Visbot

Ngày: 2026-11-11. Nguồn: APK đang cài `com.sensornotes.xiaozhi`, version 3.1.2 (31201), đọc qua ADB. Phân tích tĩnh bằng JADX; chưa đo chuyển động thực tế hoặc độ trễ cơ khí. Không thay app hay kích hoạt bánh xe trong đợt khảo sát này.

## Bằng chứng từ luồng thực thi

- `Pm1` là lớp điều khiển UBTECH: khởi tạo ServoManager, LocomotionManager và OrchestrationManager. Luồng cử chỉ tìm được gọi trực tiếp servo/locomotion; chưa có bằng chứng nó dùng orchestration để làm mượt.
- `Pm1.a(angle, speed)` gửi góc tuyệt đối cho servo `head`, không đợi promise hoàn tất, không tự hủy lệnh đầu cũ ở lớp này.
- `C4780sr` kích hoạt khi trạng thái SPEAKING và chức năng tương ứng bật, có cờ tránh kích hoạt lặp trong cùng trạng thái nói. Khi cả đầu và bánh xe bật, chọn ngẫu nhiên một trong hai.
- Nhịp đầu được tính `500 - sensitivity * 430`, giới hạn 70–500 ms. `Om1` gửi 18° rồi 0°, tốc độ truyền vào SDK 200. Có biến đếm giới hạn 2; JADX cảnh báo giải mã sai vòng lặp nên chưa xác nhận chính xác số lần bằng runtime.
- `Nm1` gửi bánh xe tốc độ +15 trong D ms, đợi D+60 ms, rồi gửi -15 trong D ms. D bằng hai lần nhịp trên, tức 140–1000 ms. Không có lệnh cancel riêng sau từng pha trong hàm này.
- Điều khiển đầu trực tiếp dùng -23° / +25° / 0°, tốc độ truyền vào SDK 100 (`C5481x3`, RobotRemoteViewModel).
- `Pm1.e()` hủy promise bánh xe khi yêu cầu dừng. SDK vẫn có cơ chế phân bổ session; việc không cancel ở lớp app không chứng minh firmware không ngắt lệnh cũ.

Các số 100/200 là tham số APK gửi vào SDK, chưa chứng minh tốc độ thực trên thiết bị. Không sao chép chúng vào app mình trước khi kiểm tra giới hạn servo và hành vi firmware.

## Đối chiếu app mình

- `RobotMotionController.naturalGesture`: góc nhỏ 2–5°, tốc độ cơ sở 6–12, giới hạn 4–15; chờ từng góc hoàn tất rồi nghỉ thêm 60–100 ms. Đây là khác biệt có thể khiến động tác chậm và rời từng đoạn.
- `celebrate`: tiến/lùi 450 ms mỗi pha, có khoảng nghỉ 180 ms. `_move` luôn gọi stop trong finally sau mỗi pha, ngay cả khi pha đã hoàn tất bình thường. Đây là ứng viên gây khựng cần đo; chưa phải kết luận từ thử nghiệm A/B.
- RobotChannel còn hủy yêu cầu cũ trước khi gửi yêu cầu đầu/bánh xe mới. Cần phân biệt lệnh đã kết thúc với lệnh đang chạy khi tối ưu.
- Mình đã có chính sách chọn cử chỉ theo ngữ cảnh và thời gian nghỉ. Nên giữ chính sách này, thay cách phát động tác bên dưới.

## Đề xuất triển khai tiếp

1. Dùng chuỗi động tác native với lịch thời gian nhất quán, tránh vòng chờ Dart → native → hoàn tất → Dart giữa từng pha. Kiểm tra SDK có thực sự hỗ trợ chuỗi servo mong muốn trước khi chọn API.
2. Gật từ vị trí giữa xuống rồi trở lại; thử biên độ 10–18° và nhịp 200–350 ms, sau khi đối chiếu giới hạn phần cứng. Không mặc định mọi câu nói đều gật.
3. Phân biệt kết thúc bình thường và dừng khẩn: bỏ cancel dư chỉ sau khi xác nhận động cơ đã hết thời lượng; giữ dừng khi ngắt lời, lỗi, timeout và thao tác người dùng.
4. Thử tăng/giảm tốc bánh xe theo các đoạn ngắn trước khi đảo chiều. Đây là cải tiến đề xuất của mình, không phải tính năng đã xác nhận Lily có.
5. Đo A/B cùng góc, tải và vị trí robot: thời điểm gửi lệnh, callback, chuyển pha và video. Đánh giá độ mượt riêng với độ trễ nghe/phản hồi; khảo sát APK này chưa giải thích được độ trễ hội thoại.

Mã APK giải mã chỉ lưu tạm ngoài repository tại `/tmp/lily-sources`; không đưa mã hoặc tài nguyên Lily vào dự án.

## Bản triển khai để thử trên Visbot

- Thêm chuỗi ROSA native qua `motionSeries`, dùng đúng cấu trúc typed list của SDK. Một chuỗi có một request để hủy toàn bộ khi ngắt lời, đổi chính sách, lỗi hoặc timeout.
- Gật xác nhận: 0 → 12° → 0, thời lượng mặc định 300 + 380 ms; vui: hai nhịp 15° và 10°. Tốc độ gật trong cài đặt điều chỉnh thời lượng. Không tăng tốc vượt giới hạn bằng cách sao chép tham số 100/200 của Lily.
- Tiến/lùi biểu cảm: một chuỗi hai pha +speed/-speed, mỗi pha 450 ms, giới hạn speed 1–2 như trước. Bỏ khoảng nghỉ Dart 180 ms và lệnh stop dư giữa hai pha. Giữ điều kiện ngữ cảnh, giới hạn thời gian chạy, dừng khẩn và hành vi lệnh trực tiếp.
- Đã thử chuỗi đầu 12°/0 trên robot: ROSA trả success code=0 sau khoảng 760 ms. Chưa có đánh giá chủ quan về độ mượt từ người dùng.
- Thử chuỗi bánh xe tám đoạn tốc độ 0 để kiểm tra giao thức: firmware timeout code=-11 ở đoạn thứ hai. Vì vậy bỏ phương án ramp với các đoạn 0/60 ms; bản cài lại dùng hai pha có tốc độ khác 0. Không tuyên bố firmware hỗ trợ ramp ngắn. Test tại tốc độ 0 này không xác nhận được chuyển động tiến/lùi thực tế.
- Test mới kiểm tra chuỗi đầu/bánh xe, hủy chuỗi đang chạy và dừng phần cứng khi chuỗi lỗi; các test cũ vẫn kiểm tra lệnh giọng nói và chính sách cử chỉ.
