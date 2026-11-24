# Việc 3 — Gia sư tiếng Anh: Tutor Service trên VPS + robot

## Mục tiêu

Robot dạy bé 5 tuổi tiếng Anh qua trò chuyện. Bố mẹ dùng một **Web UI** để soạn giáo trình, chọn bài và xem tiến độ. **Trợ lý lấy giáo trình và ngữ cảnh bài học từ service đó qua MCP, rồi hướng dẫn robot nói với bé.** Robot phải nhớ bé đang học tới bài nào và lần trước sai những gì, để kiểm tra bài cũ.

## Định hướng đã chốt (xem memory `project-self-hosted-server-direction`)

- **xiaozhi.me chỉ là tạm thời.** Sau này sẽ tự chạy server Xiaozhi trên **VPS**, ví dụ dựa trên `xinnan-tech/xiaozhi-esp32-server`.
- **Tutor Service chạy trên chính VPS đó**, cạnh server Xiaozhi.
- Từ giờ mọi thiết kế phải **không phụ thuộc server**:
  - robot giữ giao thức Xiaozhi chuẩn (OTA, MQTT/WS, MCP);
  - đổi server chỉ là đổi cấu hình;
  - không ghi cứng địa chỉ xiaozhi.me hoặc tenclass vào code mới.
- **Trí nhớ học tập nằm trong Tutor Service** (dữ liệu có cấu trúc), **không nằm trong LLM**. Ngữ cảnh của LLM chỉ sống trong một phiên, mà app lại đóng phiên khi im lặng 15–30s. Tính năng memory của xiaozhi.me thì không kiểm soát được.

## Kiến trúc

### Giai đoạn 1 — xiaozhi.me cho giọng nói, Tutor MCP trên VPS

**Cập nhật thiết kế 2026-11-10:** áp dụng cách kết nối MCP endpoint tương tự Bonion. Nhận định cũ “LLM xiaozhi.me không gọi được VPS nên bắt buộc app làm cầu nối” được thay bằng hai đường tích hợp dưới đây. Ưu tiên đường A sau khi PoC xác nhận trên trợ lý thực tế.

```text
Robot ◀──MQTT/UDP hoặc WS──▶ Xiaozhi (ASR → LLM → TTS)
                                  ▲
                                  │ WSS hai chiều: yêu cầu/kết quả MCP
                                  │ bridge trên VPS chủ động mở kết nối
                           Tutor MCP Bridge
                                  │ gọi application service nội bộ
Bố mẹ ──HTTPS──▶ Web UI ──▶ Tutor Service ──▶ PostgreSQL
```

- **Đường A, ưu tiên:** bố mẹ lấy URL MCP endpoint của trợ lý trên console Xiaozhi, nhập vào Web UI riêng. Bridge trên VPS dùng URL đó để mở kết nối WSS ra ngoài. Xiaozhi xác thực endpoint, hỏi `initialize` / `tools/list`, rồi gọi `tools/call` khi cần. Không cần cho Xiaozhi truy cập trực tiếp REST công khai của Tutor Service.
- WSS là đường truyền; MCP quy định cách khám phá và gọi công cụ. Bridge chủ động kết nối về mạng, nhưng Tutor Service là MCP server cung cấp công cụ, Xiaozhi là MCP client gọi công cụ.
- Token endpoint gắn với trợ lý; việc gắn endpoint vào hồ sơ bé do bố mẹ cấu hình trong Tutor Service. Không tin `learnerId` do LLM truyền lên để xác định quyền.
- Khi bé nói “Học tiếng Anh”, LLM gọi `self.tutor.start_lesson`; Tutor Service chọn bài, lấy trí nhớ và trả brief. Những câu trả lời tiếp theo được ghi qua công cụ MCP, không phải ghi nhớ bằng lịch sử chat.
- Mô hình tham khảo là bridge do mình vận hành, không chuyển endpoint hoặc dữ liệu học của bé cho Bonion. Không cần thêm chức năng tutor vào app để chạy PoC đường A.
- **Đường B, dự phòng:** MCP trên robot → `TutorClient` → REST Tutor Service, theo thiết kế client bên dưới. Chỉ triển khai nếu endpoint cloud không đáp ứng hoặc cần cache/hàng đợi tại robot. Không đồng thời công bố cùng tên `self.tutor.*` qua A và B cho một trợ lý.

**Luồng một lượt học:** robot gửi tiếng nói → Xiaozhi nhận dạng → LLM chọn công cụ → bridge thực thi trên Tutor Service → trả bước học/kết quả đã lưu → LLM nói câu ngắn → Xiaozhi phát TTS về robot. Các công cụ `self.robot.*` vẫn thực thi tại robot và tuân theo quyền phần cứng hiện tại.

### Giai đoạn 2 — server Xiaozhi tự chạy trên cùng VPS

```text
Robot ◀──MQTT/UDP hoặc WS──▶ Xiaozhi server (VPS)
                                  │ MCP adapter hoặc plugin nội bộ
                             Tutor Service ◀── Web UI
                                  │
                              PostgreSQL
```

- Robot đổi cấu hình OTA/server. Adapter gọi cùng application service và giữ nguyên schema công cụ, dữ liệu và luật tiến độ.
- Endpoint MCP cloud là tính năng cần kiểm chứng riêng của từng backend; không giả định mọi server Xiaozhi hỗ trợ cùng URL WSS. Khi backend mới không có endpoint tương thích, dùng adapter MCP/plugin nội bộ hoặc đường B.
- API cho thiết bị dùng device token; adapter nội bộ dùng service identity có giới hạn theo binding. Không phát service token cho LLM.

### Phạm vi theo mốc phát hành

- PoC đầu tiên trên một Visbot cho Đăng Minh; pilot có bố mẹ giám sát chỉ sau khi các cổng PoC đạt. Định hướng thương mại hóa Robot AI dùng ESP32-S3 16R8N, có mic, loa, Wi-Fi và màn hình; Tutor Service không phụ thuộc Flutter/Android.
- Mô hình gia đình: một tài khoản bố mẹ quản lý nhiều robot và nhiều hồ sơ bé. Robot thuộc tài khoản gia đình; bố mẹ chọn hồ sơ bé đang dùng trên từng robot. Tiến độ học thuộc hồ sơ bé, không thuộc robot hoặc trợ lý cloud. Chưa tự nhận diện bé bằng giọng nói.
- Mỗi bé chỉ có một buổi học đang mở và một robot được quyền điều phối buổi đó tại một thời điểm. Các bé khác nhau có thể học đồng thời trên các robot khác nhau; không dùng một khóa session toàn hệ thống.
- Hai chủ đề Hello và Colours cho luồng học → ghi kết quả tạm thời → ôn lần sau → bố mẹ sửa kết quả; không gọi tiến độ PoC là đánh giá thành thạo đã xác minh.
- Đường A chạy trước. Cache/hàng đợi trên robot, chuyển quyền nhiều robot, đổi hồ sơ nóng và thư viện 12 chủ đề là các mốc sau, tránh làm app client trước khi kiểm chứng endpoint.

| Mốc | Trong phạm vi | Chưa được tuyên bố |
|-----|----------------|-------------------|
| PoC đường A | Một Visbot, một hồ sơ Đăng Minh do bố mẹ chọn trên Web UI, một binding; kiểm chứng MCP, hàng rào quyền/retention, snapshot, session/attempt idempotent và chấm bảo thủ bằng dữ liệu thử có kiểm soát | Chất lượng tiến độ production, nhiều robot/bé trên cùng context, chuyển quyền, đổi hồ sơ nóng, offline, đường B |
| Pilot giám sát | Ba buổi ngắn với bố mẹ quan sát sau cổng PoC; Web UI xem/sửa và đo sai lệch ASR, tool, correction/retention; giới hạn một robot/binding | Tự động xác nhận phát âm/độ thành thạo hoặc sẵn sàng thương mại |
| Thương mại tương lai | Nhiều robot/hồ sơ gia đình với xác thực nguồn và cách ly context; chuyển chủ/làm sạch; ESP32-S3 16R8N; có thể tự host Xiaozhi sau kiểm chứng adapter | Không mặc định cloud WSS, REST đường B hay bất kỳ cơ chế provider nào đã được chứng minh |

## Công nghệ (mặc định đề xuất, agent triển khai có thể đổi nếu có lý do)

| Thành phần | Lựa chọn | Lý do |
|-----------|----------|-------|
| Backend | **Python 3.12 + FastAPI + SQLAlchemy/SQLModel + Alembic** | Cùng hệ Python với `xiaozhi-esp32-server`, dễ viết plugin gọi chung; có OpenAPI tự sinh |
| MCP adapter | **MCP server Python + worker WSS riêng** | Cùng application service với REST; một worker giữ kết nối cho mỗi binding, tự nối lại |
| CSDL | **PostgreSQL 16** | Dữ liệu quan hệ, truy vấn tiến độ |
| Web UI | **React + Vite + TypeScript**, build tĩnh, backend phục vụ | Một service, một domain |
| Triển khai | **Docker Compose** (api, db, caddy, tutor-mcp-bridge), Caddy cấp HTTPS tự động | VPS đơn giản; sau này thêm container `xiaozhi-server` vào cùng compose |
| Sao lưu | `pg_dump` hằng ngày ra volume hoặc object storage | Dữ liệu của trẻ |

- **Repo riêng**, ví dụ `xiaozhi-tutor-service`. Thư mục này (app Flutter) chỉ chứa phần client trên robot.
- Đặt cấu trúc thư mục sao cho sau này gộp chung compose với server Xiaozhi được.

## Mô hình dữ liệu

| Bảng | Trường chính |
|------|--------------|
| `account` | id, email, password_hash (tài khoản bố mẹ) |
| `learner` | id, account_id, name, birth_year, settings, deleted_at/tombstone; dữ liệu con luôn kiểm tra tombstone, không có undelete cho người dùng |
| `device` | id, account_id, selected_learner_id nullable, context_generation, trạng thái chọn mong muốn/đã xác nhận, trạng thái chuyển chủ/chờ làm sạch, device_mac, token_hash, paired_at, last_seen; hồ sơ phải thuộc cùng gia đình, MAC không xác thực |
| `mcp_binding` | id, account_id, liên kết device/learner đã xác thực, context_generation hoặc tham chiếu hàng rào tương đương, provider, endpoint_url_encrypted, endpoint_fingerprint, status, last_connected_at, last_error_code, revoked_at; unique endpoint_fingerprint; cách chứng minh nguồn robot qua cloud còn cần PoC |
| `pairing_code` | code (6 số), device_mac, expires_at |
| `curriculum` | id, account_id (null = mẫu hệ thống), title, version; version đã tham chiếu được lưu/archived |
| `unit` / `lesson` / `item` | nội dung, thứ tự, định danh nội dung ổn định và phiên bản bất biến cho phần đã tham chiếu; lesson xác định nội dung cốt lõi/mốc coverage, item có từ, ví dụ, hình ảnh/TPR tùy chọn |
| `assignment` | learner_id, lesson_id hoặc unit_id, mode (`next` / `pinned`), created_by |
| `lesson_session` | id, learner_id, lesson/version, status (`active` / `paused` / `done` / `abandoned`), owner_device_id, ownership_generation, current_step, revision, current_turn_id, plan_json (snapshot bất biến gồm assignment/nội dung ôn/turn/luật đánh giá), started_at, resume_expires_at cố định = started_at + 2 giờ, ended_at, end_reason, summary dẫn xuất; partial unique learner khi status active/paused |
| `attempt` | id, lesson_session_id, item/version, result hiệu lực dẫn xuất, heard_text nullable (xóa sau 30 ngày), server_order/occurred_at/timezone, client_ts chỉ tham khảo, idempotency_key, turn_id, evidence_source do adapter đáng tin gắn, judgment_status/loại lượt/mức hỗ trợ; unique (lesson_session_id, turn_id); sự kiện gốc bất biến trừ tẩy nội dung theo retention |
| `attempt_correction` (logic) | attempt_id, version, actor/role, reason, before/after, corrected_at, request key; nhiều bản sửa giữ lịch sử, replay theo thứ tự/thời điểm học gốc |
| `lesson_coverage` (logic) | learner_id, lesson/version, content_id/version, mốc giới thiệu/cơ hội luyện/luyện thực tế, nguồn/trạng thái bằng chứng; tách khỏi session done và Leitner mastery |
| `item_progress` | learner_id, item/version hoặc định danh ổn định có quy tắc migration, box (0–5), due_date, correct_count, wrong_count, last_result, confusions dẫn xuất không chứa transcript thô mặc định; replay sau correction |
| `parent_notification` (logic) | correction_id duy nhất, learner/account, trạng thái phân phối Web UI; chỉ cho hồ sơ còn hiệu lực, chặn đọc sau soft-delete |

Các tên bảng/trường/enum bổ sung ở đây là **yêu cầu logic, chưa chốt thiết kế vật lý**. Cần chốt khóa/version, transaction và hợp đồng API trước migration; không hiểu `result` đơn giản là mọi `proposedResult` đều thành điểm chính thức. Thu hồi binding/thiết bị giữ lịch sử; chuyển chủ xác nhận phải thu hồi credential, chờ làm sạch đã xác minh rồi mới ghép gia đình mới.

### Quyền điều phối và chuyển robot — đã chốt 2026-11-17

- Tách biệt hồ sơ/tiến độ của bé, buổi học (`lesson_session`) và quyền điều phối của robot. Đổi robot không tạo buổi học mới, không xóa tiến độ; đóng/mở lại phiên giọng nói Xiaozhi không tự kết thúc buổi học.
- Robot thứ hai yêu cầu học với hồ sơ đang có robot khác điều phối: trả trạng thái cần xác nhận chuyển, không tự chiếm quyền chỉ vì gọi `start_lesson`. Bản đầu xác nhận qua Web UI của bố mẹ, không dựa vào lời xác nhận do LLM suy diễn.
- Sau xác nhận, service chuyển `owner_device_id` và tăng `ownership_generation` trong cùng transaction; giữ session và kết quả đã commit, tiếp tục lượt chưa xử lý. Không sao chép trạng thái giữa hai robot.
- Mọi lệnh thay đổi session/attempt phải kiểm tra quyền điều phối hiện tại tại thời điểm commit. Chuyển quyền và ghi kết quả được tuần tự hóa trong DB: kết quả commit trước chuyển được giữ; request của chủ cũ commit sau chuyển bị từ chối, không làm đổi tiến độ. Robot mới lấy state/revision mới nhất từ service.
- Thông báo robot cũ dừng điều phối là best-effort; bảo vệ dữ liệu không phụ thuộc robot cũ nhận được thông báo. Không bảo đảm ngắt tức thời âm thanh đã phát hoặc đang đệm ở robot mất mạng.
- Danh tính robot và generation phải gắn với kết nối đã xác thực; không tin `deviceId` hoặc generation chỉ do LLM khai báo. Một worker/binding không thay thế kiểm tra quyền và chống race trong DB.
- Cổng khả thi đường A: PoC phải chứng minh service nhận diện đáng tin cậy từng robot, chẳng hạn binding/kết nối riêng cho từng robot được provider hỗ trợ. Nếu một endpoint chung không phân biệt nguồn gọi, không công bố hỗ trợ chuyển quyền an toàn; pilot giới hạn một robot cho binding đó. Server tự vận hành phải truyền danh tính thiết bị đã xác thực cho adapter.
- Pilot một Visbot chưa cần UI chuyển robot, nhưng data model và kiểm tra quyền phải hỗ trợ hướng này. Schema chi tiết binding–device, constraint/lock DB và thời hạn quyền điều phối cần chốt tiếp; không giả định đã kiểm chứng provider.
- Test bắt buộc trước khi mở tính năng chuyển: chưa xác nhận không đổi owner; xác nhận giữ nguyên session/tiến độ; hai yêu cầu chuyển cạnh tranh không sinh hai owner; attempt cũ đến trễ bị từ chối; robot cũ offline vẫn không ghi được sau chuyển; hai gia đình không chuyển hoặc đọc session của nhau.

### Đổi hồ sơ bé giữa buổi — đã chốt 2026-11-23

- Chọn phương án A: bố mẹ xác nhận đổi hồ sơ trên Web UI; robot dừng luồng hội thoại cũ, hủy tác vụ chờ và bỏ nội dung/TTS đang đệm của bé trước, rồi mới bắt đầu luồng cho bé mới. Không tự chọn bé bằng lời nói do LLM suy diễn.
- Giữ buổi học cũ để resume trong cửa sổ cho phép, không đánh dấu hoàn thành và không tính lượt chưa trả lời là sai. Robot nhả quyền điều phối buổi cũ; nếu tiếp tục sau đó phải kiểm tra/cấp lại quyền theo hợp đồng ownership hiện hành.
- Mỗi lần đổi hồ sơ phải đổi generation của ngữ cảnh thiết bị/binding đã xác thực. Generation này khác `ownership_generation` của một buổi học: chuyển A → B → A cũng không được khiến request cũ của A hợp lệ trở lại. Adapter gắn learner và generation tại đầu request, không tra lại hồ sơ hiện tại rồi gán request cũ cho bé mới.
- Đổi hồ sơ và commit attempt phải được tuần tự hóa: kết quả commit trước lúc đổi được giữ cho bé cũ; request chưa commit với generation cũ bị từ chối, không ghi vào bé cũ hoặc bé mới sau mốc đổi.
- Trước khi phát tool result phải kiểm tra lại learner, generation và quyền truy cập. Brief/kết quả của bé cũ không được đưa vào kết nối đã chuyển sang bé mới, kể cả request đọc bắt đầu trước lúc đổi.
- Hội thoại cho bé mới phải có context riêng: không tái sử dụng lịch sử LLM, brief hay hàng đợi âm thanh của bé trước. Generation không thể thu hồi dữ liệu đã gửi tới cloud; nếu provider không cho reset/cách ly context và dừng output đáng tin cậy, không cho đổi nóng trên cùng context. Phải đóng luồng cũ và chỉ tiếp tục khi có context mới đã cách ly; nếu không chứng minh được thì chặn đổi nóng.
- Khi robot offline hoặc chưa xác nhận dừng/reset context, Web UI hiển thị đang chờ áp dụng; service vẫn chặn request cũ sau mốc đổi. Không tuyên bố đã xóa/ngắt âm thanh đã phát trên thiết bị mất mạng.
- Test bắt buộc: đổi khi đang fetch brief/commit attempt/phát TTS; A → B → A; response cũ đến trễ; retry đổi hồ sơ không áp dụng hai lần; robot offline; context mới không có dữ liệu bé cũ; quyền gia đình khác bị từ chối.

### Ngắt liên kết robot/binding và dữ liệu học — đã chốt 2026-11-23

- Chọn phương án A: thu hồi quyền truy cập của robot/binding không xóa hồ sơ, tiến độ hoặc lịch sử học. Dữ liệu thuộc tài khoản gia đình và có thể được tiếp tục trên thiết bị được cấp quyền khác.
- Phân biệt thao tác ngắt một binding MCP với ngắt thiết bị: ngắt binding vô hiệu hóa binding đó; ngắt thiết bị thu hồi credential và mọi binding/quyền điều phối gắn với thiết bị đó. Không ảnh hưởng các thiết bị hợp lệ khác của gia đình.
- Mốc hiệu lực là transaction thu hồi trên service: kiểm tra trạng thái/generation trước commit ghi và trước khi phát dữ liệu; request bắt đầu trước nhưng chưa được phép commit/phát response tại mốc thu hồi phải bị từ chối. Kết quả đã commit trước đó vẫn được giữ; không rollback lịch sử hợp lệ.
- Vô hiệu hóa quyền điều phối liên quan và ngắt worker/kết nối cũ là best-effort sau khi hàng rào quyền đã có hiệu lực. Giữ session để resume trong cửa sổ cho phép; robot mới phải được xác thực/cấp quyền, không tự nhận credential cũ. Worker còn chạy hoặc reconnect không được khôi phục quyền đã thu hồi.
- “Xóa dữ liệu bé” là thao tác riêng cần xác nhận rõ của bố mẹ và hợp đồng xóa/retention riêng. Không dùng ngắt liên kết như lệnh xóa ngầm, không tuyên bố đã xóa cache trên robot offline hoặc dữ liệu đã gửi tới provider.
- Ngắt liên kết chưa đủ để bán lại robot an toàn: quy trình chuyển chủ phải xử lý credential, cache/context và dữ liệu cục bộ trước khi ghép sang gia đình khác. Chi tiết quy trình này cần chốt tiếp; không cho tài khoản mới thừa hưởng dữ liệu gia đình cũ.
- Test bắt buộc: revoke khi đang fetch/commit; token cũ reconnect; worker chậm nhận revoke; giữ nguyên tiến độ và học tiếp trên thiết bị mới; revoke một binding không vô hiệu hóa nhầm thiết bị khác; thao tác revoke lặp lại an toàn; gia đình mới không đọc được lịch sử gia đình cũ.

### Chống tạo trùng buổi học — đã chốt 2026-11-23

- Chọn phương án A: dùng transaction và ràng buộc PostgreSQL, không chỉ kiểm tra trước khi insert hoặc dựa vào lease của worker. Mỗi learner có tối đa một session ở trạng thái `active` hoặc `paused`; cả hai đều là buổi đang mở.
- Tạo unique partial index trên `lesson_session(learner_id)` với điều kiện `status IN ('active', 'paused')`. Khi start/resume/đóng buổi hết hạn, khóa hàng learner (`SELECT ... FOR UPDATE`) rồi đọc lại session trong cùng transaction. Không khóa toàn bộ các learner.
- Các thao tác end, dừng để đổi bài, chuyển quyền hoặc đổi hồ sơ có tác động tới session phải dùng cùng thứ tự khóa nhất quán để tuần tự hóa với start/attempt; kiểm tra quyền/generation tại thời điểm commit. Chi tiết thứ tự khóa với replay correction phải được thống nhất trong hợp đồng transaction trước triển khai.
- Chưa có session mở thì tạo mới; có session trong cửa sổ resume thì dùng lại; hết hạn thì chuyển buổi cũ thành `abandoned` trước khi tạo buổi mới trong cùng transaction. Giữ attempt cũ và không tính lượt chưa trả lời là sai.
- Hai start đồng thời với request key khác nhau vẫn chỉ tạo một session. Yêu cầu cùng robot/ngữ cảnh hợp lệ nhận lại session hiện tại; robot khác chỉ nhận trạng thái cần xác nhận chuyển, không được nhận brief hoặc quyền ghi chỉ vì nhìn thấy session đã tồn tại.
- Request-key idempotency là lớp riêng: retry cùng thao tác không tạo buổi mới hoặc chuyển quyền lần nữa, nhưng không được vượt qua kiểm tra quyền hiện tại hay phát lại brief của generation đã hết hiệu lực. Unique violation phải được xử lý có kiểm soát sau rollback/savepoint phù hợp, không tiếp tục truy vấn trong transaction PostgreSQL đã lỗi.
- Test bắt buộc: hai start khác key cùng learner trên nhiều worker; hai start khi buổi cũ hết hạn; start cạnh tranh với end/đổi bài/chuyển robot; resume paused; retry sau mất response; nhiều learner vẫn xử lý độc lập. Sau mỗi race, tối đa một session mở và một owner hợp lệ, không ghi chéo hồ sơ.

### Chọn hồ sơ bé trên robot dùng chung — đã chốt 2026-11-23

- Chọn phương án A cho MVP: chỉ bố mẹ đăng nhập Web UI và có quyền với tài khoản gia đình được chọn hồ sơ đang dùng trên từng robot. Hồ sơ được chọn phải thuộc cùng gia đình với robot.
- Robot giữ lựa chọn đã được service xác nhận đến khi bố mẹ đổi hoặc quyền/liên kết bị thu hồi. Chưa chọn hồ sơ thì không bắt đầu bài học hoặc đọc dữ liệu bé; hướng dẫn bố mẹ chọn trên Web UI.
- Bé có thể nói “học tiếng Anh” để bắt đầu/resume theo hồ sơ đã chọn, nhưng lời nói, tên tự khai hoặc tham số LLM không được đổi hồ sơ. MVP không cung cấp lựa chọn hồ sơ tự do trên màn hình robot và không nhận diện bé bằng giọng nói.
- Web UI hiển thị hồ sơ đang được chọn trên từng robot; nếu đổi giữa buổi, áp dụng hợp đồng xác nhận, generation, chặn request cũ và cách ly context ở phần trên. Khi thiết bị chưa áp dụng, phân biệt trạng thái mong muốn với trạng thái đã xác nhận, không báo đổi thành công chỉ từ thao tác lưu lựa chọn.
- Lựa chọn của bố mẹ là ngữ cảnh học được ủy quyền, không phải bằng chứng xác minh ai đang đứng trước robot. Không tuyên bố đã nhận diện bé; bố mẹ cần kiểm tra hồ sơ trước khi cho anh chị em dùng luân phiên.
- Test bắt buộc: chưa chọn hồ sơ; phụ huynh chọn đúng/sai gia đình; yêu cầu đổi do LLM hoặc robot không có quyền; restart giữ lựa chọn nhưng vẫn kiểm tra quyền hiện tại; thu hồi liên kết; đổi khi offline hoặc giữa buổi không làm lẫn dữ liệu.

### Chuyển chủ robot — đã chốt 2026-11-23

- Chọn phương án A: chủ cũ xác nhận chuyển trên Web UI; thu hồi quyền cũ và bắt buộc làm sạch robot trước khi tài khoản gia đình mới ghép đôi. Factory reset vật lý không tự cấp quyền đổi chủ trên service; luồng hỗ trợ ngoại lệ chưa nằm trong quyết định này.
- Khi xác nhận chuyển, service vô hiệu hóa credential, binding và quyền điều phối cũ của thiết bị; giữ hồ sơ/tiến độ tại gia đình cũ. Đánh dấu thiết bị chờ làm sạch, không coi việc revoke là chuyển chủ hoàn tất.
- Robot phải xóa credential và dữ liệu cục bộ của gia đình cũ: cache bài học/brief/attempt chưa đồng bộ, lịch sử và context hội thoại, hàng đợi TTS và artifact chứa dữ liệu bé. Không gửi attempt cũ bằng credential của chủ mới. Nội dung đã commit trên service vẫn thuộc gia đình cũ.
- Chỉ mở ghép đôi với tài khoản mới sau khi xác nhận hoàn tất làm sạch bằng cơ chế quản lý thiết bị đáng tin cậy; không chấp nhận lời khai từ LLM hoặc request không xác thực. Cần đặc tả kênh quản lý giới hạn chỉ cho làm sạch sau khi credential học đã bị thu hồi; không khôi phục quyền đọc/ghi dữ liệu học để làm bước này.
- Robot offline hoặc làm sạch thất bại: giữ trạng thái chờ/chưa hoàn tất, cho retry an toàn; không cho ghép với gia đình mới. Dữ liệu đã gửi tới provider có quy trình retention/xóa riêng, không tuyên bố đã bị xóa bởi reset robot.
- Sau làm sạch, gia đình mới ghép đôi bằng quy trình mới và nhận credential mới; không kế thừa hồ sơ, session, lịch sử, token hoặc context cloud của gia đình cũ. Reset cục bộ đơn thuần không được vượt qua trạng thái ownership trên server.
- Test bắt buộc: offline khi chuyển; lỗi/restart giữa các bước revoke/làm sạch/ghép lại; xác nhận làm sạch giả; retry và mã ghép cũ; reset vật lý không tự chiếm quyền; gia đình mới không có dữ liệu cũ, gia đình cũ vẫn giữ tiến độ trên thiết bị khác.

## "Lesson brief" — cách robot biết bé học tới đâu

Use case start tạo hoặc học tiếp một buổi và trả brief **do service tính** (hàm thuần, có test). Đường REST minh họa bên dưới dành cho adapter nội bộ; adapter MCP đưa brief cho LLM. Ví dụ này chỉ là payload thành công khi đã xác thực binding/robot, chọn hồ sơ và có quyền điều phối, không phải response bắt buộc cho trường hợp chưa có session hoặc đang chờ chuyển robot.

```json
{
  "lessonSessionId": "ls_123",
  "revision": 1,
  "ownershipGeneration": 2,
  "contextGeneration": 7,
  "currentTurnId": "turn_001",
  "resume": null,
  "lesson": {"id":"colours-2","unit":"Colours","pattern":"What colour is it? — It's green."},
  "review": [
    {"itemId":"i_pink","word":"pink","vi":"màu hồng","lastResult":"uncertain","note":"cần ôn thêm"},
    {"itemId":"i_three","word":"three","vi":"số ba","lastResult":"close"}
  ],
  "newWords": [{"itemId":"i_green","word":"green","vi":"màu xanh lá"}],
  "currentPrompt": {"expectedItemId":"i_pink","sayEn":"Can you say pink?","sayVi":"Con nói pink nhé!"},
  "steps": ["greeting","review","new_words","game","wrap_up"],
  "game": "i-spy-colour",
  "lastSessionSummary": "Buổi trước đã luyện red, blue; pink cần ôn thêm.",
  "teacherInstructions": "Ôn các từ review trước, mỗi từ hỏi 1 lần. Từ mới: nói 2 lần, đợi bé nhắc lại, gọi self.tutor.record_answer sau mỗi lần bé trả lời…"
}
```

Quy tắc tính:

- **review**: tối đa 3 từ đến hạn, có ưu tiên và chống bỏ đói backlog theo thuật toán chưa chốt; đề xuất sai từ ASR do LLM báo chưa xác minh không tự trở thành lỗi chính thức. Giữ chỗ cho 2–3 từ mới nếu phù hợp, giảm đến 0 khi gặp khó theo luật service chưa chốt.
- **lesson / newWords**: `assignment` kiểu `pinned` nếu có; nếu không thì bài tiếp theo chưa hoàn thành **coverage nội dung cốt lõi theo version**, không dựa vào session `done` hoặc box Leitner. Kế hoạch buổi đang mở dùng snapshot bất biến.
- **resume**: nếu có `lesson_session` đang `active` hoặc `paused` và thời điểm server hiện tại còn trước `started_at + 2 giờ`, trả về `{step, remainingItems}` sau khi kiểm tra quyền điều phối. Không tạo buổi mới.
- **Lịch ôn (Leitner)**:
  - `correct` đủ điều kiện cập nhật lịch ôn theo chính sách bằng chứng bên dưới → box + 1;
  - `close` → giữ box;
  - `wrong` đã được xác nhận theo chính sách bằng chứng → box = 0; đề xuất sai chỉ từ `llm_reported_asr` không được tự hạ box;
  - khoảng cách ôn theo box: 0 = cùng buổi, 1 = 1 ngày, 2 = 3 ngày, 3 = 7 ngày, 4 = 14 ngày, 5 = 30 ngày. Box giới hạn 0–5; `skip`/`uncertain` không tăng hoặc hạ box. Ngày đến hạn tính theo múi giờ hồ sơ bé, mặc định Asia/Ho_Chi_Minh.
- **Trạng thái buổi**: `active` và `paused` đều là buổi mở; `resume_expires_at` được cố định khi tạo bằng `started_at + 2 giờ` theo thời gian server, không kéo dài bởi reconnect. Đến hạn đóng `abandoned` trước khi tạo buổi mới theo yêu cầu hợp lệ; giữ attempt, không tính phần chưa trả lời là sai.
- **lastSessionSummary**: dẫn xuất từ kết quả hiệu lực theo mẫu câu không chứa lời bé nói thô; khi correction thay đổi kết quả phải tính lại hoặc đánh dấu cũ không còn hiệu lực. Retry end giữ nguyên hiệu ứng đóng/ghi, nhưng response đọc tổng kết hiện hành sau correction không được trả bản tổng kết cũ sai; cách version hóa/cache response cần chốt.

### Dừng sớm và hoàn thành bài — đã chốt 2026-11-23

- Chọn phương án A: yêu cầu kết thúc rõ ràng của bé/bố mẹ đóng buổi, giữ các attempt đã commit và khen phần đã học; không tự đánh dấu lesson hoàn thành chỉ vì gọi `end_lesson`. `done` của session nghĩa là buổi đã kết thúc có chủ đích, không phải bé đã học xong bài hoặc thành thạo từ.
- Ghi lý do kết thúc để phân biệt hoàn tất kịch bản, dừng sớm và lý do khác. Dừng sớm không tính phần chưa học là sai, không ép bé tiếp tục cho đủ bài.
- Theo dõi tiến độ nội dung lesson riêng với trạng thái session và Leitner của từ. Buổi tiếp theo service chọn phần chưa học và từ cần ôn từ dữ liệu đã commit, không bắt học lại toàn bộ và không bỏ qua bài chỉ vì có session `done`.
- Tiêu chí hoàn thành lesson phải do service tính, dựa trên các nội dung/lượt bắt buộc của phiên bản bài và bằng chứng hợp lệ; không tin một cờ “hoàn thành” do LLM tự khai. Hoàn thành nội dung không đồng nghĩa đã thành thạo. Ngưỡng cụ thể và mô hình lưu tiến độ lesson theo phiên bản cần được chốt riêng trước triển khai, không suy ra từ số lần `end_lesson`.
- Phân biệt lời muốn kết thúc với tạm nghỉ: tạm nghỉ có thể chuyển `paused` trong cửa sổ resume; kết thúc rõ ràng đóng buổi ngay. Khi không rõ ý định, hỏi lại ngắn gọn thay vì tự đánh dấu hoàn thành bài.
- End và record_answer đồng thời phải theo cùng hợp đồng transaction: chỉ giữ attempt commit hợp lệ trước lúc đóng, từ chối attempt mới vào session đã đóng; retry end không tạo tác dụng lần hai. Buổi mới không thay đổi snapshot/lịch sử của buổi cũ.
- Test bắt buộc: học một trong ba từ rồi kết thúc; buổi sau còn phần chưa học và ôn phù hợp; `end_lesson` không tự hoàn thành lesson; done do học đủ vẫn không tuyên bố mastery; pause khác end; end cạnh tranh với attempt và retry không đếm trùng.

### Hoàn thành nội dung bài, không đồng nghĩa thành thạo — đã chốt 2026-11-23

- Chọn phương án A: một lesson hoàn thành nội dung khi các từ và mẫu câu cốt lõi bắt buộc của phiên bản bài đã được giới thiệu và có cơ hội luyện tập được ghi nhận. Không yêu cầu mọi từ phải có một lần tự trả lời đúng để được sang bài.
- Mỗi phiên bản bài phải xác định rõ nội dung bắt buộc và mốc giới thiệu/luyện tập; service tính coverage qua các buổi từ sự kiện hợp lệ, không suy ra hoàn thành từ `end_lesson`, thời gian trôi qua hoặc cờ do LLM tự báo. Với đường A cloud, sự kiện do LLM báo vẫn là bằng chứng chưa xác minh, không được mô tả thành xác nhận bé đã nghe hoặc thực hiện.
- Phải phân biệt ít nhất: chưa giới thiệu, đã giới thiệu, đã tạo cơ hội luyện tập, đã có lượt luyện thực tế và mức ghi nhớ. Không gộp coverage với kết quả `correct` hoặc Leitner box.
- `skip`/`uncertain` không được tính là trả lời đúng hoặc bằng chứng đã nhớ. Một cơ hội luyện tập đã thực sự được đưa ra vẫn có thể được ghi nhận dù bé không trả lời; phần chưa luyện thực tế tiếp tục được theo dõi và bố trí ôn/luyện lại ở buổi sau, không biến thành “đã thuộc”.
- Khi đủ coverage bắt buộc, service được chọn bài tiếp theo theo assignment; các từ chưa nhớ và nội dung chưa luyện thực tế không bị xóa khỏi nhu cầu ôn. Hoàn thành nội dung một lần không tự tăng box hoặc correct_count.
- Coverage gắn với lesson version và định danh nội dung ổn định. Không tự kế thừa trạng thái hoàn thành sang nội dung mới/sửa chỉ vì dùng cùng lesson ID; quy tắc tái sử dụng coverage khi sửa giáo trình cần đặc tả riêng, đồng thời giữ snapshot buổi đang mở.
- Test bắt buộc: đủ giới thiệu/cơ hội luyện nhưng còn từ chưa đúng vẫn sang bài; từ chưa nhớ tiếp tục được ôn; skip/uncertain không tăng điểm; chưa có cơ hội luyện nội dung bắt buộc thì chưa hoàn thành; LLM chỉ báo end không đủ coverage; sửa version không âm thầm hoàn thành nội dung mới.

### Cân bằng ôn tập và nội dung mới — đã chốt 2026-11-23

- Chọn phương án A: không bắt ôn hết backlog trước khi học mới. Mặc định tối đa 3 từ ôn và 2–3 từ mới trong một buổi, vẫn giữ mục tiêu 8–12 phút và quyền dừng sớm. Đây là giới hạn tải học, không phải chỉ tiêu phải học đủ.
- Service chọn từ cần ôn nhất trong số đến hạn, dựa trên tiến độ/kết quả hiệu lực theo chính sách bằng chứng, không dùng đề xuất sai chưa xác minh để hạ box hoặc tự tăng mức ưu tiên như lỗi đã xác nhận. Cần thứ tự ưu tiên ổn định và cơ chế tránh bỏ đói từ tồn đọng trong hợp đồng thuật toán.
- Nếu bé gặp khó, giảm hoặc không thêm từ mới trong buổi đó; dùng tín hiệu hữu hạn như lượt chưa xử lý được, skip/uncertain hoặc yêu cầu nghỉ, không suy ra bé kém từ ASR lỗi. Luật điều chỉnh cụ thể phải được định nghĩa và test, không để LLM tự mở rộng số lượt hoặc đổi bài tùy ý.
- Kế hoạch có thể chứa phần mới dự kiến, nhưng chỉ service điều phối có được tiếp tục giới thiệu hay dừng sớm. Không thêm nội dung ngoài snapshot; phần chưa giới thiệu không được đánh dấu đã học/hoàn thành chỉ vì nằm trong brief.
- Backlog còn lại tiếp tục được theo dõi cho các buổi sau. Không coi nghỉ học là trả lời sai, không reset box hoặc ép học bù; khi không có nội dung mới phù hợp, buổi có thể chỉ ôn.
- Giới hạn ôn là số từ khác nhau, không cho lặp vô hạn trên một từ; giữ quy tắc không ép nhắc lại quá hai lần và cho skip/nghỉ. Không kéo dài buổi chỉ để giải quyết hết backlog.
- Test bắt buộc: 10 từ đến hạn vẫn chọn tối đa 3 từ ôn; buổi bình thường có chỗ cho tối đa 2–3 từ mới; gặp khó có thể giảm xuống 0 từ mới; nghỉ nhiều ngày không bị phạt; từ tồn đọng không bị bỏ đói qua nhiều buổi; dừng sớm không hoàn thành phần mới chưa học.

### Cửa sổ học tiếp buổi dở — đã chốt 2026-11-23

- Chọn phương án A: mặc định hết hạn tại `started_at + 2 giờ`, tính bằng thời gian server. Lưu `resume_expires_at` cố định khi tạo session để thay cấu hình sau này không âm thầm thay hạn của session đã mở. Tại `now >= resume_expires_at`, buổi không còn được resume hoặc ghi attempt mới.
- Reconnect, retry, heartbeat, pause/resume, chuyển robot và tương tác học không kéo dài hạn này. Đóng phiên giọng nói do im lặng không kết thúc lesson session và không đặt lại đồng hồ.
- Kiểm tra hết hạn trong các thao tác đọc state/start và trước commit ghi, không phụ thuộc duy nhất vào tác vụ dọn nền. Request bắt đầu trước hạn nhưng commit sau hạn không được ghi attempt mới. Replay kết quả đã commit vẫn phải tuân thủ idempotency, quyền hiện tại và cách ly context.
- Khi hết hạn, đóng buổi cũ thành `abandoned`, giữ kết quả đã commit, không chấm sai phần chưa trả lời. Chỉ tạo buổi mới khi có yêu cầu học hợp lệ; kiểm tra hạn/đóng cũ/tạo mới tuân thủ transaction và khóa theo learner ở phần chống trùng session.
- Nếu bé hoặc bố mẹ kết thúc sớm, buổi đóng ngay; không cần chờ đủ 2 giờ. Hai giờ chỉ là cửa sổ khôi phục buổi dở, không phải thời lượng học: mục tiêu mỗi buổi vẫn 8–12 phút.
- Test bắt buộc: ngay trước/đúng/sau hạn; active và paused; reconnect/chuyển robot không gia hạn; request chậm vượt hạn; hai start đồng thời tại hạn; đổi cấu hình không đổi hạn đã lưu; không tự tạo buổi mới khi chỉ heartbeat hoặc kiểm tra state.

### Sửa giáo trình và đổi bài khi đang học — đã chốt 2026-11-17

- Chọn phương án A: buổi đang mở tiếp tục theo nội dung đã chốt lúc bắt đầu; sửa giáo trình hoặc assignment chỉ áp dụng khi tạo buổi tiếp theo. Resume hoặc chuyển robot không tạo snapshot mới.
- Snapshot của session phải chứa phiên bản giáo trình, bài/assignment đã chọn và nội dung các item được dùng, kể cả phần ôn; không chỉ lưu ID rồi đọc nội dung mới nhất từ bảng đang chỉnh sửa. Câu hỏi, đáp án kỳ vọng và luật đánh giá của lượt đã cấp phải gắn với snapshot đó.
- Sửa, kéo thả thứ tự hoặc xóa nội dung trên Web UI không làm đổi nghĩa `turnId`, hỏng validation của attempt hay xóa lịch sử học. Nội dung đã được tham chiếu phải được giữ bằng version/archive; thao tác xóa khỏi giáo trình hiện hành không hard-delete các bản còn cần cho session/lịch sử.
- Nếu muốn đổi ngay, bố mẹ chọn riêng “Dừng buổi hiện tại và bắt đầu bài mới”, có xác nhận. Buổi cũ đóng thành `abandoned`, giữ các attempt đã commit, không tính các lượt chưa trả lời là sai; buổi mới lấy assignment/nội dung mới. Không đánh dấu bài cũ đã hoàn thành.
- Chuyển bài phải tuần tự hóa với ghi attempt và quyền điều phối trong DB: request cũ không được ghi thêm vào buổi đã đóng hoặc áp dụng sang buổi mới. Retry thao tác chuyển không tạo nhiều buổi mới. Hợp đồng request key và transaction cụ thể cần được định nghĩa khi chốt session API.
- Test bắt buộc: sửa/xóa item sau khi cấp lượt vẫn ghi được theo nội dung snapshot; đổi bài ghim không đổi buổi đang học; resume/chuyển robot giữ snapshot; đổi bài ngay giữ kết quả cũ và chỉ tạo một buổi mới; request từ buổi cũ đến trễ không thay đổi tiến độ.

## REST API (v1)

Các đường dưới `/api/v1` là **phác thảo REST**, chưa phê duyệt tên path, enum, payload hoặc bảo đảm cloud có API này. Bridge đường A dùng use case nội bộ; endpoint thiết bị bên ngoài và cache chỉ cần nếu chọn đường B. Mọi đường đọc/ghi kiểm tra account/learner tombstone, binding, device/context generation và ownership generation phù hợp trước commit hoặc phát dữ liệu.

**Phía robot đường B về sau** (cơ chế device credential đề xuất; không phải API PoC A):

| Method | Path | Dùng cho |
|--------|------|----------|
| POST | `/devices/pair/start` | Robot gửi MAC, nhận mã ghép 6 số để hiện lên màn hình |
| POST | `/devices/pair/poll` | Robot hỏi liên tục cho đến khi bố mẹ nhập mã, rồi nhận `device_token` |
| POST | `/lesson-sessions/start` | Tạo hoặc học tiếp; idempotent theo request key; brief là kết quả |
| GET | `/learners/{id}/brief` | Chỉ xem trước nếu binding/quyền cho phép đúng learner; không tạo hoặc đổi buổi học (Web UI của bố mẹ có use case preview riêng) |
| POST | `/lesson-sessions/{id}/attempts` | Ghi một hoặc nhiều câu trả lời; idempotent theo `idempotency_key`; trả bước tiếp theo |
| POST | `/lesson-sessions/{id}/step` | Xin service chuyển bước với reason/revision; không cho client tự báo đã sang bước hoặc bỏ lượt tùy ý |
| POST | `/lesson-sessions/{id}/end` | Kết thúc, nhận tóm tắt |
| GET | `/curricula/{id}?since_version=` | Lấy giáo trình về cache |

**Phía bố mẹ** (cơ chế phiên chưa chốt): CRUD/version giáo trình và assignment; chọn hồ sơ trên từng robot chỉ qua Web UI; xem tiến độ/lịch sử, correction với audit; ngắt liên kết giữ lịch sử, xác nhận chuyển chủ/làm sạch, soft-delete không thể tự khôi phục; thông báo correction của admin chỉ trong Web UI cho hồ sơ còn hiệu lực. Path cụ thể chưa chốt.

**Nội bộ** (bridge giai đoạn 1 và adapter giai đoạn 2, service identity giới hạn theo binding): cùng các use case start/state, attempts, step, end; không cho truy cập hồ sơ ngoài binding. Cần hợp đồng transaction có thứ tự khóa nhất quán cho learner/session/ownership/context và learner/item correction, kết hợp partial unique session mở, version/replay và hàng rào trước khi phát response; thứ tự khóa chính xác còn chưa chốt.

## Phía robot (đường B dự phòng và tiện ích app)

Dựa trên lớp `McpServer` của Việc 1. Schema công cụ dùng hợp đồng chung ở phần sau; bảng này chỉ mô tả trách nhiệm của app khi chọn đường B.

| Công cụ MCP | App làm gì |
|-------------|-----------|
| `self.tutor.start_lesson` | Gọi use case start; mất VPS chỉ được ôn vui theo cache đã cấp và đúng hồ sơ/context còn quyền, không tự mở session hoặc tuyên bố đã lưu. |
| `self.tutor.record_answer` | Lưu payload theo hợp đồng chung vào `sqflite`, gửi ngay nếu có mạng. Chưa đồng bộ thì trả `pending_sync`, chỉ nói đã lưu trên server sau xác nhận. |
| `self.tutor.get_state` / `self.tutor.next_step` | Đọc state hoặc xin chuyển bước từ service; mất mạng chỉ ôn theo cache, không tự tạo lượt chấm mới. |
| `self.tutor.end_lesson` | Gửi hàng đợi hợp lệ trước, gọi `end`; chưa đồng bộ thì báo pending, không xác nhận đã đóng trên server. |

Các thành phần:

- **`TutorClient`**: REST client đọc URL service và token từ Cài đặt; hàng đợi attempts offline; cache giáo trình và brief.
- **Màn ghép đôi** (Cài đặt → Gia sư):
  - nhập URL service;
  - bấm "Ghép đôi" → robot hiện mã 6 số → bố mẹ nhập mã trên Web UI;
  - robot lưu token.
- **Nút "Học tiếng Anh"** trên màn gọi: gửi tin nhắn văn bản tương đương câu "Bắt đầu học tiếng Anh". App đã có chat văn bản qua MQTT.
- Nối với Việc 1 và 2:
  - item có `tpr_action` → chỉ dùng hành động trong danh sách cho phép, phù hợp quyền phần cứng;
  - bé trả lời đúng → mặt vui; gật đầu nếu tính năng cử chỉ được bật.
- **Prompt trên console** (xiaozhi.me ở giai đoạn 1, file cấu hình agent ở giai đoạn 2) chỉ cần quy tắc ngắn: "khi bé muốn học tiếng Anh hoặc app yêu cầu, gọi `self.tutor.start_lesson` và làm đúng theo `teacherInstructions`; ghi kết quả bằng `self.tutor.record_answer` sau mỗi câu trả lời của bé".

### Danh tính nguồn gọi cloud và giới hạn PoC — đã chốt 2026-11-23

- Chọn phương án A: kiểm chứng khả năng provider cung cấp danh tính thiết bị; nếu không có bằng chứng đủ tin cậy, vẫn cho thử luồng học có bố mẹ giám sát trên trợ lý/binding riêng chỉ kết nối một Visbot và một hồ sơ Đăng Minh được chọn. Không dùng trợ lý thử nghiệm này đồng thời từ thiết bị/client khác.
- Trong trường hợp đó, kết nối WSS chỉ chứng minh quyền của binding/trợ lý đã xác thực; việc gán Visbot vào binding là cấu hình vận hành được bố mẹ kiểm soát, không phải bằng chứng mật mã rằng mọi tools/call đều xuất phát từ đúng phần cứng Visbot. `deviceId` do LLM khai hoặc MAC không nâng được mức bảo đảm này.
- Các yêu cầu PoC về “danh tính đủ cho một robot” được hiểu theo giới hạn trên, không đòi hỏi nhận diện phần cứng mới được thử. Tài liệu kết quả phải phân biệt nguồn đã chứng minh với giả định vận hành; không ghi nhận kiểm tra per-device authentication là đạt khi chỉ đã thử một client.
- Hàng rào tài khoản, learner tombstone, session/revision, idempotency, generation do service quản lý và thu hồi binding vẫn bắt buộc. Chúng bảo vệ trạng thái service nhưng không giải quyết client khác sử dụng cùng trợ lý, dữ liệu đã nằm trong context cloud hoặc âm thanh đã phát.
- Không mở nhiều robot trên cùng binding, chuyển quyền giữa thiết bị hoặc đổi hồ sơ nóng khi chưa chứng minh được nguồn gọi/cách ly context cần thiết. Không tự hạ giới hạn này để mở rộng pilot/thương mại; cần PoC hoặc lựa chọn adapter/server thay thế được duyệt.
- Nếu phát hiện trợ lý bị dùng chung, token lộ hoặc context có dữ liệu ngoài phạm vi, dừng lượt thử và cô lập/thu hồi binding cần thiết trước khi tiếp tục. Thử luồng học không mặc nhiên cho phép ghi âm hoặc bỏ qua consent/retention đã chốt.
- Cập nhật cổng PoC: việc không có per-device provenance không tự chặn thử nghiệm có giới hạn ở trên; chỉ discovery/call, quyền binding và các hợp đồng dữ liệu thực sự không đạt mới chặn nghiệm thu tương ứng. Nhiều thiết bị và bảo đảm thương mại vẫn là cổng riêng.

### Báo cáo đã đưa nội dung/câu hỏi — đã chốt 2026-11-23

- Chọn phương án A cho PoC: bổ sung sự kiện báo đã giới thiệu nội dung hoặc đưa cơ hội luyện tập, gắn với lượt do service cấp. Tên tool/endpoint và enum cụ thể còn là thiết kế API, không mặc định đã được provider chấp nhận.
- Service cấp event/turn và nội dung theo snapshot; LLM chỉ báo hoàn tất hành động đã được cấp, không tự tạo ID/nội dung hay chọn mốc coverage tùy ý. Adapter gắn nguồn báo cáo đáng tin về mặt kết nối; nội dung báo cáo vẫn do LLM cung cấp, chưa xác minh phát TTS hoặc bé đã nghe.
- Báo cáo hợp lệ ghi coverage mức “được báo đã giới thiệu/đã tạo cơ hội luyện tập”, không xác nhận bé nghe, thực hiện hoặc nhớ. Sự kiện không tạo attempt đúng/sai, không tăng Leitner/correct_count và không được tự tạo buổi hoặc vượt qua lượt trả lời còn chờ.
- Tách sự kiện đưa câu hỏi khỏi câu trả lời: bé im lặng không buộc phải bịa `heardText`. Nếu kết thúc lượt không có câu trả lời, service ghi uncertain hoặc skip phù hợp và không tăng/hạ tiến độ; chi tiết cách xin đóng lượt cần nằm trong hợp đồng điều phối.
- Sự kiện có ID do server cấp và revision/ngữ cảnh phù hợp, ghi idempotent: cùng ID/cùng nội dung trả xác nhận, khác nội dung trả conflict. Áp dụng cùng kiểm tra tombstone, quyền/generation, expiry và transaction như các thao tác session khác; không cho request cũ nâng coverage sau đổi hồ sơ/chuyển quyền.
- Có thể dùng coverage chưa xác minh này cho điều phối PoC theo chính sách hoàn thành nội dung đã chốt, nhưng UI và kết quả thử nghiệm phải nêu rõ nguồn bằng chứng. Pilot có bố mẹ quan sát đo tỷ lệ báo đã đưa nội dung nhưng thực tế chưa phát; chưa có ngưỡng chất lượng thương mại được duyệt.
- Test bắt buộc: đưa câu hỏi rồi im lặng; chỉ cấp lượt nhưng chưa có báo cáo thì chưa tăng coverage; replay/conflict; nội dung hoặc ID ngoài snapshot; báo cáo đến trễ sau đổi hồ sơ/hết hạn; sự kiện coverage không tăng điểm; LLM báo sai được phát hiện trong đối chiếu pilot.

## Hợp đồng Tutor MCP và điều phối buổi học

Cả hai adapter dùng cùng schema và application service; tên công cụ dưới đây là đề xuất cần PoC xác nhận Xiaozhi chấp nhận. Không để LLM truy cập SQL, URL tùy ý hoặc công cụ quản trị.

| Công cụ | Đầu vào chính | Kết quả / quy tắc |
|---------|---------------|------------------|
| `self.tutor.start_lesson` | `requestKey` | Tạo/học tiếp theo binding; trả session, revision, turn và brief; gọi lại không tạo hai buổi |
| `self.tutor.get_state` | không có | Trả buổi đang học, bước và lượt hiện tại; dùng khi mất ngữ cảnh hoặc không rõ lần ghi trước thành công |
| Báo đã đưa nội dung/câu hỏi (tên tool chưa chốt) | session, event/turn do server cấp, revision và loại báo cáo trong schema được phép | Ghi coverage idempotent với bằng chứng LLM chưa xác minh; không ghi điểm hoặc thay câu trả lời |
| `self.tutor.record_answer` | `sessionId, turnId, expectedRevision, heardText?, proposedResult` | Kiểm tra lượt/bằng chứng, ghi một lần; trả quyết định đã lưu, revision mới và hành động/lượt kế tiếp; **adapter đáng tin** gắn nguồn bằng chứng, không nhận `evidenceSource` do LLM tự nhận |
| `self.tutor.next_step` | `sessionId, expectedRevision, reason` | Chỉ là yêu cầu tiến bước; service kiểm tra turn, coverage và chính sách skip/pause, không chấp nhận reason tùy ý như bằng chứng đã luyện |
| `self.tutor.end_lesson` | `sessionId, requestKey, reason` | Kết thúc idempotent; trả tóm tắt từ dữ liệu đã lưu |

- Binding cấp quyền qua adapter/kết nối đã xác thực, không qua tham số tool. Adapter gắn device, learner, context generation và nguồn bằng chứng tại đầu request; service kiểm tra lại quyền, tombstone, ownership generation trước commit/phát response. Không tin learner/device/generation/evidenceSource do LLM khai. Với cloud chưa chứng minh được nguồn thiết bị, giới hạn một robot/binding.
- Luồng server: `greeting → review → new_words → game → wrap_up → done`, có `paused`/`abandoned`. Mỗi lượt có `turnId` do service cấp; chỉ service đổi bước, bài và revision.
- Giao dịch ghi attempt + cập nhật tiến độ + tạo lượt kế tiếp phải nguyên tử. Replay cùng `turnId` và cùng nội dung không ghi/đếm lại; cùng ID khác nội dung trả conflict, nhưng trước khi trả lại bất kỳ dữ liệu nào vẫn kiểm tra quyền/generation, tombstone, retention và trạng thái hiệu lực sau correction. JSON-RPC ID chỉ ghép request/response, không dùng làm khóa nghiệp vụ qua reconnect.
- Sai revision trả conflict với hướng dẫn lấy state, không tự ghi đè. Retry `end_lesson` không đóng/đếm lần hai; nếu correction về sau thay đổi summary, trả bản dẫn xuất hiện hành hoặc dấu stale/version thay vì đóng băng thông tin sai.
- Response thành công **khi có session** có thể gồm status, sessionId, revision, currentTurnId, nextAction và teacherInstructions ngắn; no-session, chờ xác nhận chuyển, thiếu hồ sơ, revoked/soft-deleted, expired hoặc lỗi không bắt buộc có các field session. Mã lỗi và tên field chính xác chưa chốt; không trả stack trace, token hay dữ liệu hồ sơ khác cho LLM.
- Khi chưa có session `active` **hoặc `paused`**, chỉ start hợp lệ được tạo buổi. `get_state` trả trạng thái không có buổi mở, không tự tạo; state trên session paused phải thể hiện paused và bước hiện tại, không coi là no-session. LLM không tự chọn bé dựa trên lời nói.

### Retry sau khi xóa bản chép hoặc sửa kết quả — đã chốt 2026-11-23

- Chọn phương án A: khi ghi request lần đầu, lưu dấu kiểm tra có khóa bảo vệ (ví dụ HMAC), phiên bản cách chuẩn hóa payload và phiên bản khóa, thay vì giữ nguyên payload chứa `heardText` để đối chiếu về sau. Không dùng hash không khóa cho lời ngắn dễ đoán; dấu kiểm tra vẫn là dữ liệu cần bảo vệ, không được mô tả là đã ẩn danh hoàn toàn.
- Dấu kiểm tra gắn với thao tác, session/turn và ngữ cảnh nghiệp vụ cần thiết để chống nhầm phạm vi; chỉ so sánh payload nghiệp vụ đã chuẩn hóa theo hợp đồng cố định. Correction không thay dấu của request ghi gốc, và retry không được coi là correction. Quy tắc chuẩn hóa, trường tham gia và vòng đời/rotation khóa phải được đặc tả và test trước triển khai.
- Retry cùng turn/cùng nội dung chỉ xác nhận lần commit cũ, không tạo attempt, thay đổi lịch ôn hoặc tái lưu lời đã xóa. Cùng turn nhưng nội dung khác trả conflict; không âm thầm chấp nhận vì bản chép đã hết hạn.
- Phân biệt metadata xác nhận commit gốc bất biến với kết quả hiệu lực hiện tại: response nêu lượt đã được ghi và trả kết quả/trạng thái correction hiện hành riêng, không phát lại đánh giá cũ như kết quả đang có hiệu lực. Không giữ nguyên response cũ chứa bản chép để replay. Tên field cụ thể chưa chốt.
- Retry lịch sử không phát lại câu hỏi kế tiếp cũ như một hành động mới: caller lấy state hiện tại nếu cần tiếp tục. Nếu session đã đóng/hết hạn thì không mở lại; xác nhận commit không cấp quyền ghi mới.
- Kiểm tra quyền hiện tại, tombstone, binding/context generation và quyền điều phối phù hợp trước khi trả bất kỳ dữ liệu replay nào. Request từ chủ/ngữ cảnh cũ không được dùng idempotency để vượt qua revoke/chuyển hồ sơ/soft-delete.
- Payload nhận lại chỉ được dùng đối chiếu trong bộ nhớ cần thiết, không ghi vào log, audit, trace, dead-letter hoặc kho retry sau khi nội dung đã bị xóa. Nếu khóa cũ không còn dùng được thì từ chối đối chiếu an toàn và hướng dẫn lấy state, không lấy việc thiếu khóa làm bằng chứng payload giống nhau; không lưu nguyên văn để dự phòng.
- Dấu kiểm tra không được dùng như cơ chế tìm lời bé đã nói hoặc cung cấp API thử đoán transcript; quyền vận hành/retention của dấu kiểm tra phải được mô tả riêng. Các nghĩa vụ xóa bắt buộc vẫn áp dụng.
- Test bắt buộc: retry cùng/khác payload sau 30 ngày hoặc xóa sớm; correction giữa lần ghi và retry; session đóng; revoke/chuyển hồ sơ; canonicalization/rotation khóa; thiếu khóa; không hồi sinh bản chép trong DB/log/response; không tăng tiến độ hoặc phát lại nextAction cũ.

### Bé 5 tuổi: ngắn, dễ hiểu, không chấm quá mức

- Giáo trình có 4–6 từ/bài nhưng mặc định mỗi buổi chỉ giới thiệu **2–3 từ mới**, ôn tối đa 3 từ; buổi 8–12 phút, có thể kết thúc sớm khi bé muốn dừng.
- Mỗi lượt một câu hỏi, câu mẫu tiếng Anh ngắn; giải thích tiếng Việt khi cần. Không yêu cầu đọc, đánh vần hoặc thao tác màn hình để hoàn thành bài.
- Bé chưa trả lời: nhắc nhẹ một lần rồi cho lựa chọn hoặc nói mẫu. Không ép nhắc lại quá hai lần cho một từ; cho phép `skip` và nghỉ.
- `proposedResult` là đề xuất của LLM, không phải điểm phát âm. ASR văn bản chỉ phản ánh máy nghe được gì; không đủ để đánh giá âm vị. Không công bố điểm phát âm ở MVP.
- Với ASR mơ hồ, tiếng ồn, lời chen ngang hoặc không có câu trả lời: ghi trạng thái uncertain (result null), không tính sai và không đổi Leitner. `wrong` chỉ áp dụng khi có bằng chứng đủ điều kiện theo chính sách chấm bảo thủ hoặc correction có thẩm quyền; lời rõ do LLM tự báo qua cloud vẫn **không** đủ để reset box. Chấp nhận câu gần đúng, khen nỗ lực rồi nói mẫu chuẩn.
- Đường A được **adapter** gắn nguồn logic `llm_reported_asr`: bản chép do LLM truyền chưa đối chiếu ASR trực tiếp, không phải xác thực bởi việc LLM tự khai `evidenceSource`. Chỉ lưu confidence do backend đáng tin thực sự cung cấp. PoC đo độ trung thực của `heardText` và tỷ lệ bỏ sót tool.

#### Chính sách chấm bảo thủ cho MVP — đã chốt 2026-11-17

- Service quyết định kết quả được áp dụng, không sao chép `proposedResult` thành điểm chính thức. Với nguồn `llm_reported_asr`, mọi nhận định về lời bé nói đều chưa được đối chiếu ASR độc lập; không gọi đây là bằng chứng đã xác minh.
- ASR mơ hồ, tiếng ồn, lời chen ngang hoặc không trả lời: `judgment_status=uncertain`, result null, không tăng/hạ box hoặc đếm sai.
- Nhắc lại ngay sau mẫu, trả lời sau gợi đáp án hoặc lượt không xác định được mức gợi ý: ghi nhận luyện tập, không coi là tự nhớ từ, không tăng box. Service phải ghi loại lượt/mức hỗ trợ trong state và attempt; không chỉ dựa vào LLM tự khai rằng bé trả lời độc lập.
- Câu trả lời được báo là rõ, phù hợp câu hỏi và thuộc lượt tự trả lời không có gợi ý: ghi kết quả tạm thời. Kết quả đúng tạm thời được dùng cho lịch ôn theo Leitner, nhưng phải giữ trạng thái chưa xác minh và không suy ra “đã thành thạo” chỉ từ một lần. Tên enum/schema cụ thể cho kết quả tạm thời và lượt luyện tập phải được chốt trong hợp đồng API trước triển khai.
- Nếu LLM đề xuất `wrong` từ `llm_reported_asr`: lưu đề xuất phục vụ đối chiếu nhưng không áp dụng thành `wrong` chính thức, không hạ box hoặc tăng wrong_count. Robot cho thử lại nhẹ nhàng trong giới hạn số lần, hoặc nói mẫu rồi chuyển tiếp. Không gán lại cùng một lượt đã commit; lần thử tiếp cần turn mới do service cấp.
- Bố mẹ có thể xác nhận/sửa kết quả với audit trail; khi đó service mới áp dụng kết quả đã xác nhận theo quy tắc replay. Nguồn ASR trực tiếp đáng tin cậy trong tương lai phải có chính sách riêng được duyệt, không tự động nới chính sách MVP.
- PoC/pilot phải đo cả chấm sai nhưng tự tin, nhận nhầm lời nói và nhầm lượt luyện tập thành tự nhớ; mục tiêu 19/20 record hợp lệ chỉ đo độ đầy đủ, không thay thế đánh giá độ đúng. Chưa chốt ngưỡng chất lượng để tuyên bố tiến độ đáng tin cậy cho sản phẩm thương mại.

#### Sửa kết quả và hoạt động vận động

- Bố mẹ sửa attempt có audit trail; service tính lại tiến độ từ các attempt hợp lệ theo thứ tự, không sửa đếm bằng cộng/trừ tùy ý.
- TPR ở MVP là bé làm theo lời nói (clap, touch your nose); không tuyên bố bé làm đúng nếu không có cảm biến xác nhận. Cử chỉ robot chỉ qua tool phần cứng sẵn có và quyền hiện tại; không bắt buộc bánh xe/điệu nhảy.

#### Bố mẹ sửa kết quả và tính lại tiến độ — đã chốt 2026-11-17

- Chọn phương án A: sửa kết quả phải có tác dụng với tiến độ, không chỉ đổi thông tin hiển thị. Attempt gốc được giữ bất biến; correction lưu người sửa, thời điểm, kết quả trước/sau và liên kết tới attempt gốc. Nhiều lần sửa phải có thứ tự phiên bản rõ ràng để xác định correction đang có hiệu lực.
- Service replay các attempt đã commit cho từng cặp learner/item theo thứ tự ổn định do server cấp lúc ghi nhận, không dựa vào `client_ts` hoặc thời điểm bố mẹ sửa. Mỗi attempt chỉ đóng góp một lần với kết quả hiệu lực sau correction; correction không tạo thêm một lượt học.
- Tính lại box, due_date, correct_count, wrong_count và last_result theo cùng chính sách bằng chứng. `uncertain`, `skip` và luyện tập có gợi ý không tăng/hạ box; giữ các attempt hợp lệ của buổi `abandoned`, không coi lượt chưa trả lời là sai. Dữ liệu tổng hợp từ kết quả cũ như confusions/tóm tắt phải được cập nhật hoặc đánh dấu đã lỗi thời, không tiếp tục trình bày kết quả sai như hiện hành.
- Ngày ôn tiếp theo được tính theo thời điểm học gốc của attempt và múi giờ áp dụng cho lượt đó, không tính từ ngày correction. Nếu tính lại khiến từ đã đến hạn, đưa vào danh sách ôn cho buổi tiếp theo, không đẩy lịch ra tương lai chỉ vì vừa sửa.
- Không thay đổi snapshot hoặc câu hỏi đã cấp của buổi đang mở; kết quả replay được dùng khi tạo buổi tiếp theo. Lịch sử gốc và audit correction vẫn xem được, nhưng Web UI phải phân biệt dữ liệu gốc với kết quả hiệu lực, thông báo tiến độ đã được tính lại.
- Ghi correction, ghi attempt mới và cập nhật progress phải được tuần tự hóa cho cùng learner/item; replay không được ghi đè mất một attempt vừa commit. API correction phải kiểm tra quyền tài khoản gia đình và xử lý retry không tạo correction trùng; cơ chế khóa, request key và thứ tự phiên bản cụ thể cần chốt trong hợp đồng API.
- Test bắt buộc: sửa `wrong` cũ thành `correct` sau hai buổi tiếp theo; sửa ngược lại hoặc sửa cùng attempt nhiều lần; uncertain/skip/practice và buổi abandoned; ngày đến hạn trong quá khứ; correction đồng thời với attempt mới; retry correction; buổi đang mở giữ snapshot; gia đình khác không sửa được.

### Mất mạng, reconnect và giới hạn của cloud

- Đóng phiên giọng nói sau im lặng không kết thúc buổi học. Phiên mới phải gọi `get_state`/`start_lesson` trước khi dạy tiếp; khôi phục từ PostgreSQL theo binding, không dựa vào session ID của Xiaozhi.
- Bridge có reconnect với exponential backoff + jitter (1–60 giây), timeout tool mục tiêu 5 giây, heartbeat theo thư viện/provider. Chỉ một worker giữ một binding qua lease; process restart không tạo worker trùng. Từ chối xác thực thì báo cần cập nhật token, tránh vòng lặp retry dồn dập.
- Mất bridge/VPS ở đường A: có thể trò chuyện/ôn vui nếu cloud còn hoạt động nhưng không tuyên bố đã lưu hoặc chuyển bài. Những câu trả lời chưa tới service không có bảo đảm phục hồi; không bịa attempt khi nối lại. Gọi `get_state` rồi hỏi lại lượt chưa ghi nếu cần.
- Cloud/Internet của robot mất: đường A không dạy hội thoại offline. Đường B có thể ôn từ cache khi robot còn truy cập được Xiaozhi; cache không thay ASR/LLM/TTS. Khi mất VPS, chỉ giữ pending attempt của lượt server đã cấp, không cấp chuỗi lượt/revision mới ở app; câu trả lời trong phần ôn vui không được tính vào tiến độ.
- Đường B gửi attempt đang chờ còn hợp lệ trước khi hoàn tất buổi; chưa đồng bộ thì hiển thị `pending_sync`, không tuyên bố đã kết thúc thành công trên server. Cache/queue phải bị cách ly theo learner/device/context generation, dọn khi revoke/đổi hồ sơ/chuyển chủ; request cũ hoặc quá hạn bị từ chối, không âm thầm gửi dưới chủ mới.

### Prompt trợ lý mẫu (cần kiểm chứng bằng hội thoại thực)

> Bạn là bạn học tiếng Anh của bé 5 tuổi. Khi bé muốn học, gọi self.tutor.start_lesson. Nếu đang học mà mất ngữ cảnh, gọi self.tutor.get_state. Làm theo bước và câu hỏi service trả về, mỗi lượt chỉ hỏi một câu. Sau câu trả lời liên quan bài học, gọi self.tutor.record_answer với turnId/revision hiện tại và đúng lời máy nghe được; nếu không rõ thì báo uncertain, không đoán bé nói gì. Chỉ nói đã lưu khi công cụ xác nhận. Không tự thay giáo trình hoặc tăng tiến độ. Khi bé muốn dừng, gọi self.tutor.end_lesson và chào bé nhẹ nhàng. Không đọc tên công cụ, JSON hoặc mã kỹ thuật cho bé nghe.

Prompt chỉ hướng dẫn hành vi; service vẫn kiểm tra quyền, thứ tự và idempotency. Nếu cloud không gọi tool ổn định, không coi đây là hệ thống ghi nhận tiến độ đáng tin trước khi đổi adapter/backend.

## Web UI cho bố mẹ

1. **Đăng nhập / đăng ký**, tạo hồ sơ bé. Bố mẹ chọn hồ sơ cho từng robot trên Web UI, không cho LLM/robot tự đổi; hiển thị trạng thái mong muốn/đã xác nhận. Đường A: dán URL WSS từ console, gắn binding với hồ sơ/robot thử nghiệm và xem trạng thái kết nối; `ready` chỉ khi đã initialize và phục vụ tools/list, không chỉ TCP mở. Đường B/ghép đôi thiết bị là mốc về sau.
2. **Giáo trình**:
   - danh sách chủ đề → bài → từ;
   - sửa, thêm, xoá, kéo thả thứ tự;
   - nhập từ bộ mẫu hệ thống (12 chủ đề bên dưới), hoặc nhập/xuất JSON.
3. **Giao bài**: "học tiếp theo thứ tự" hoặc ghim một bài hoặc chủ đề.
4. **Xem trước brief**: robot sẽ dạy gì ở buổi tới (gọi chung hàm tính brief).
5. **Tiến độ**:
   - coverage nội dung, lịch ôn/từ đang học, kết quả tạm thời và kết quả đã xác nhận tách biệt; không gọi một câu đúng từ cloud là “đã thuộc”;
   - lịch sử buổi học;
   - từng attempt và lời máy báo nghe được **nếu chưa hết hạn/xóa sớm**; khi thiếu bản chép hiển thị lý do, không tái dựng từ summary/log;
   - bố mẹ sửa kết quả với audit/replay; thông báo Web UI khi admin sửa hồ sơ còn hiệu lực. Admin xem/sửa dữ liệu soft-deleted trong giao diện quản trị tách biệt, có audit; người dùng không truy cập hoặc undelete được.
6. **Cài đặt bé**: thời lượng buổi, số từ mới mỗi buổi, giờ được học.

## Giáo trình mẫu (seed, Pre-A1, tuổi 4–6)

### Nguyên tắc

- Bám khung Cambridge Pre A1 Starters.
- Học qua nghe, nói và vận động (TPR): robot làm động tác, bé làm theo.
- Mỗi bài gồm 4–6 từ và 1 mẫu câu, chia thành các buổi 2–3 từ mới theo sức của bé.
- Robot giải thích bằng tiếng Việt, từ và câu mẫu nói bằng tiếng Anh.
- Khen nhiều. Bé nói gần đúng thì vẫn khen, rồi nhắc lại mẫu chuẩn.

### 12 chủ đề

| # | Chủ đề | Từ ví dụ | Mẫu câu |
|---|--------|----------|---------|
| 1 | Hello & me | hello, bye, yes, no, name | Hello! My name is … |
| 2 | Colours | red, blue, yellow, green, pink, orange | It's red. What colour is it? |
| 3 | Numbers 1–10 | one … ten | How many? — Three! |
| 4 | My body | head, eyes, nose, mouth, hands, feet | Touch your nose! |
| 5 | Animals | cat, dog, fish, bird, duck, cow | It's a cat. Meow! |
| 6 | Family | mum, dad, baby, brother, sister, grandma | This is my mum. |
| 7 | Food | apple, banana, milk, rice, cake, water | I like apples. |
| 8 | Toys | ball, doll, car, robot, teddy, kite | I have a ball. |
| 9 | Actions | jump, run, clap, sit, stand, dance | Let's jump! |
| 10 | Feelings | happy, sad, hungry, sleepy, angry | I'm happy! |
| 11 | Weather & clothes | sunny, rainy, hat, shoes, coat | It's sunny. |
| 12 | Shapes & places | circle, square, star, home, school, park | It's a star. |

### Cấu trúc một buổi (~12 phút)

Các bước khớp với `steps` trong brief:

1. **greeting** (1 phút): chào bé.
2. **review** (2 phút): ôn các từ đến hạn và các từ sai lần trước.
3. **new_words** (4 phút): mỗi từ, robot nói 2 lần → bé nhắc lại → robot khen hoặc sửa → đặt từ vào mẫu câu.
4. **game** (3 phút): Simon says, đoán con vật, đếm số lần gật đầu, hoặc I spy.
5. **wrap_up** (1 phút): tổng kết các từ, khen bé, chào bé bằng mặt vui; chỉ dùng cử chỉ đã được bố mẹ bật.

### Đường triển khai đầu tiên — đã chốt 2026-11-23

- Chọn phương án A: làm PoC Tutor MCP trên VPS kết nối trợ lý Xiaozhi cloud trước, dùng Visbot và một hồ sơ Đăng Minh dưới sự quan sát của bố mẹ. Chưa triển khai client REST đường B hoặc toàn bộ server Xiaozhi tự host chỉ để bắt đầu PoC.
- PoC phải kiểm chứng discovery/call/result thực tế, ghi attempt và retry sau mất response, khôi phục buổi khi phiên giọng nói đóng, mức dữ liệu ASR tool thực nhận được và độ ổn định gọi tool. Dùng cùng luật quyền, idempotency và chấm bảo thủ đã chốt; không coi PoC là ngoại lệ cho quyền riêng tư hoặc dùng token lộ trong hội thoại.
- Giới hạn một robot cho binding pilot. Chỉ đánh giá hỗ trợ nhiều thiết bị, chuyển quyền hoặc đổi hồ sơ nóng sau khi chứng minh danh tính nguồn gọi và cách ly context; không lấy thành công một tool đọc làm bằng chứng đã đạt các hợp đồng thương mại.
- Nếu discovery/call, ghi nhận tiến độ hoặc cách ly cần thiết không đáp ứng, ghi rõ kết quả đạt/chưa đạt và đưa lựa chọn tự host hoặc đường B ra quyết định tiếp; không tự triển khai đồng thời cả ba đường hoặc âm thầm hạ yêu cầu.
- Đây là thứ tự kiểm chứng, không thay đổi mục tiêu thương mại trên ESP32-S3 16R8N hoặc định hướng server tự vận hành. Chưa phải ủy quyền deploy, thu thập thêm dữ liệu giọng nói của bé hay bắt đầu code toàn bộ service trong lượt chốt spec này.

## Các bước triển khai

0. **PoC MCP endpoint, chặn triển khai đường A nếu chưa đạt**:
   - Repo Tutor Service riêng; worker dùng endpoint riêng của trợ lý thử nghiệm, secrets ngoài git. Không dùng token đã xuất hiện trong hội thoại/tài liệu.
   - Công bố một tool đọc thử `self.tutor.get_state`; xác nhận log `initialize → tools/list → tools/call → result` và câu trả lời thực trên robot. Kiểm tra tên tool, giới hạn schema/kích thước và timeout thực tế.
   - Giả lập tool ghi, ngắt WSS sau commit nhưng trước response; reconnect/retry phải trả cùng kết quả, không tăng lượt hai lần. Thử đóng phiên giọng nói, restart worker, token bị thu hồi, endpoint có Bonion cùng kết nối và tên tool trùng.
   - Không suy luận cloud hỗ trợ nhiều kết nối từ giao diện: đo khả năng đồng tồn tại Bonion/Tutor. Nếu không hỗ trợ, dùng trợ lý riêng cho tutor hoặc ngắt binding cũ do bố mẹ thao tác.
   - Bàn giao transcript đã che thông tin riêng, log correlation và bảng đạt/chưa đạt; nếu discovery/call không ổn định, chọn đường B có ghi lý do.
1. **Thử nghiệm khả thi giọng nói** (làm trước khi mở rộng giáo trình, chỉ khi bố mẹ đồng ý cách thu thập):
   - đánh giá khoảng 20 lượt tiếng Anh trên robot với giám sát và chính sách dữ liệu trẻ; không mặc định lưu ghi âm hoặc đưa nguyên văn bản chép vào log/bàn giao;
   - thử dạy bằng tay một bài bằng prompt trên console;
   - ghi lại chất lượng ASR và TTS.
   - Kết quả quyết định có cần ưu tiên tự chạy server với ASR tốt hơn cho tiếng Anh trẻ em hay không.
2. **Tutor Service khung**:
   - repo mới, Docker Compose (api + db + caddy) chạy trên VPS với HTTPS;
   - Alembic migration cho mô hình dữ liệu;
   - seed 2 chủ đề đầu.
3. **Hàm tính brief và Leitner**, kèm test đơn vị (trường hợp: buổi đầu tiên, có từ đến hạn, học tiếp buổi dở, bài được ghim).
4. **Application service + REST**: start/state, preview brief, attempts, step, end; binding và quyền bố mẹ. Test tích hợp transaction, replay/conflict, uncertain, sửa attempt và cách ly hồ sơ. API ghép đôi thiết bị chỉ cần khi triển khai đường B.
5. **Đường A và Web UI tối thiểu**: worker WSS + lease/reconnect; binding có mã hóa, kết nối/thu hồi và progress; công bố 5 công cụ theo hợp đồng trên. Prompt trợ lý, 2 bài mẫu. API và MCP dùng chung transaction; không duplicate luật học trong worker.
6. **Pilot với bé, có bố mẹ quan sát sau cổng PoC**: 3 buổi ngắn; ghi metadata lượt/tool, kết quả tạm thời, uncertain và correction theo retention. Kiểm tra 20 lượt gắn đúng turn; mục tiêu ≥19/20 có record hợp lệ, 0 duplicate/ghi nhầm bé **chỉ đo độ đầy đủ**, phải đo thêm chấm sai tự tin, nhầm lời và nhầm luyện có gợi ý thành tự nhớ. Chưa có ngưỡng duyệt độ chính xác cho sản phẩm thương mại.
7. **App, chỉ khi chọn đường B hoặc cần tiện ích**: `TutorClient` + hàng đợi offline + màn ghép đôi + công cụ `self.tutor.*` (cần MCP của Việc 1 đã xong) + nút "Học tiếng Anh".
8. **Thử trọn luồng trên robot**: học 1 buổi → dữ liệu lên service → buổi sau ôn đúng từ sai.
9. **Web UI mở rộng**: đăng nhập, ghép đôi, giáo trình, giao bài, tiến độ, xem trước brief.
10. Soạn đủ 12 chủ đề; bố mẹ duyệt nội dung.
11. *(Giai đoạn 2)* Dựng server Xiaozhi trên cùng VPS, đổi URL OTA của robot, xác nhận toàn bộ vẫn chạy. Sau đó cân nhắc plugin phía server gọi thẳng Tutor Service bằng service token.

## Tiêu chí nghiệm thu

- **Cổng PoC A (một Visbot/binding/hồ sơ Đăng Minh):** xác minh initialize/list/call/result, danh tính/ngữ cảnh đủ cho giới hạn này, start/retry sau mất response không trùng, resume active/paused trước hạn cố định 2 giờ; đến hạn bỏ buổi cũ mà không phạt lượt chưa học. Không có tool ghi thành công thì không nói “đã lưu”; mất VPS lấy lại state/turn, không bịa attempt.
- **Cổng PoC về dữ liệu:** snapshot giữ version dù sửa bài; `end` sớm không hoàn thành lesson, coverage đủ cho sang bài dù chưa nhớ hết và backlog vẫn ôn; tối đa 3 review, dự kiến 2–3 từ mới có thể giảm. ASR mơ hồ/`wrong` chỉ do LLM báo không hạ box/đếm sai; tự trả lời đúng chỉ được dùng tạm thời theo chính sách. Correction replay theo thời điểm học gốc và refresh/đánh dấu stale summary; thu hồi giữ lịch sử; 30 ngày xóa cả bản sao lời nói. Các thuật toán/field chưa chốt được thử theo hợp đồng sau khi định nghĩa, không suy ra đã duyệt chi tiết.
- **Cổng pilot giám sát:** bố mẹ chọn hồ sơ trên Web UI, xem/sửa kết quả; ba buổi, mục tiêu record ≥19/20 và 0 trùng/ghi nhầm, đồng thời đo sai lệch đánh giá (chưa có ngưỡng thương mại). Test soft-delete chặn mọi đường của người dùng nhưng giữ dữ liệu cấu trúc nội bộ, admin được xem/sửa có audit, notification Web UI một lần cho hồ sơ live và không phát cho hồ sơ đã xóa.
- **Cổng thương mại tương lai:** nhiều robot/bé cần nguồn thiết bị đã xác thực, handoff xác nhận/generation và cách ly context khi đổi hồ sơ; chuyển chủ chỉ ghép lại sau làm sạch xác minh. Đường B cache/queue và server tự host là các nghiệm thu **nếu** chọn triển khai, không phải điều kiện PoC A; đổi backend phải kiểm chứng lại discovery và giữ luật dữ liệu.

## Bảo mật và quyền riêng tư

- Dữ liệu định danh bé được giới hạn ở tên gọi và năm sinh; dữ liệu học gồm tiến độ, attempts và bản chép lời có thời hạn theo chính sách dưới đây. Tutor Service không lưu ghi âm; không suy ra nhà cung cấp Xiaozhi/ASR/LLM cũng không lưu.
- Endpoint WSS có token là bí mật: mã hóa khi lưu (không chỉ hash vì worker cần dùng lại), khóa mã hóa nằm ngoài CSDL; chỉ bố mẹ có quyền cấu hình. Che query token trong log, lỗi, metrics và UI; hỗ trợ thay/thu hồi, không đưa URL vào prompt/brief. Chỉ cho phép provider/host WSS đã cấu hình để tránh worker truy cập URL nội bộ tùy ý.
- Endpoint đã chia sẻ trong hội thoại phải được thay/thu hồi trước triển khai. Không sao chép token thực vào repo.
- Không đưa tài khoản bố mẹ hoặc hồ sơ bé khác vào tool result; ghi audit thao tác quản trị và lỗi đã che dữ liệu.
- HTTPS bắt buộc. Token thiết bị lưu dạng hash; bố mẹ thu hồi được trong Web UI.
- Sao lưu CSDL hằng ngày; người dùng được xuất dữ liệu còn quyền và yêu cầu soft-delete không thể tự khôi phục, **không** hứa xóa vật lý toàn bộ. Dữ liệu cấu trúc soft-deleted được lưu nội bộ vô thời hạn theo quyết định bên dưới; bản chép lời vẫn xóa sau 30 ngày hoặc sớm hơn theo yêu cầu, kể cả backup/restore phải có quy trình áp lại retention trước khi phục vụ.

### Thời hạn lưu bản chép lời — đã chốt 2026-11-23

- Chọn phương án A: mặc định giữ `heard_text` trong 30 ngày từ lúc service ghi nhận attempt, sau đó xóa nội dung lời nói và chỉ giữ dữ liệu học cần thiết. Retry, correction, resume hoặc chuyển robot không kéo dài hạn lưu. Bố mẹ có thể yêu cầu xóa bản chép sớm hơn mà không xóa tiến độ.
- Sau khi xóa, giữ kết quả hiệu lực, nguồn/trạng thái đánh giá, loại lượt/mức hỗ trợ, thứ tự/thời điểm học và audit correction tối thiểu để tính lại tiến độ; không giữ bản chép gốc dưới tên trường khác. Quy tắc attempt bất biến có ngoại lệ cho việc xóa trường nội dung theo retention/quyền riêng tư; không xóa sự kiện học hoặc viết lại kết quả gốc bằng tác vụ retention.
- Phạm vi xóa phải bao gồm bản sao lời nói trong payload idempotency, correction, confusions, summary, cache và export tạm thuộc Tutor Service. Không sao chép lời ngoài bài học vào audit/log/metrics để lách thời hạn; tóm tắt và metadata cần dùng cấu trúc/mẫu không chứa bản chép tự do. Review dữ liệu hiện có để tránh các trường gián tiếp giữ nguyên lời bé.
- API/Web UI biểu diễn rõ bản chép đã hết hạn/được xóa, không hiểu thiếu văn bản là bé không trả lời hoặc attempt bị mất. Replay request sau xóa không được tái lưu lời nói từ payload cũ; áp dụng dấu kiểm tra có khóa và tách xác nhận commit khỏi kết quả hiệu lực theo hợp đồng retry đã chốt, với chi tiết chuẩn hóa/khóa cần đặc tả.
- Lịch dọn, SLA xóa, thời hạn backup và quy trình restore phải được định nghĩa trước production: bản backup có thể còn dữ liệu tới khi hết retention; restore phải áp lại mốc hết hạn/yêu cầu xóa trước khi phục vụ dữ liệu. Không tuyên bố xóa tức thời khỏi mọi backup khi chưa có cơ chế bảo đảm.
- Chính sách của Xiaozhi, ASR, LLM và các provider khác phải được kiểm chứng/công bố riêng cho bố mẹ; thời hạn 30 ngày ở đây chỉ là hợp đồng của Tutor Service và các bản sao do mình quản lý, không cam kết thay provider.
- Test bắt buộc: trước/đúng/sau mốc 30 ngày; xóa sớm; correction/retry không gia hạn hoặc khôi phục lời đã xóa; xóa các bản sao gián tiếp; progress/replay vẫn đúng khi không còn heard_text; restore không phát lại dữ liệu đã hết hạn hoặc có yêu cầu xóa.

### Xóa hồ sơ bé bằng soft-delete — đã chốt 2026-11-23

- Chọn phương án A với điều chỉnh: thao tác xóa hồ sơ dùng soft-delete trong DB, không hard-delete toàn bộ hàng dữ liệu ngay. Hồ sơ cùng tiến độ, session, attempt và correction liên quan bị loại khỏi mọi đường truy cập của người dùng. Không xóa tài khoản gia đình, thiết bị hoặc dữ liệu bé khác.
- Lưu tombstone/thời điểm xóa trên hồ sơ; quyền truy cập dữ liệu con phải kiểm tra trạng thái hồ sơ cha, không chỉ ẩn danh sách trên Web UI. Từ transaction xóa có hiệu lực, từ chối đọc/ghi hồ sơ qua REST, MCP, Web UI, export, đường dẫn trực tiếp, cache, idempotency replay và kết nối robot; các request đang chạy phải kiểm tra lại trước commit hoặc phát response.
- Bố mẹ xác nhận rõ trước thao tác. Sau soft-delete, người dùng không thể khôi phục, bỏ ẩn hoặc truy cập lại hồ sơ cũ; tạo hồ sơ mới không tái gắn dữ liệu cũ dù cùng tên hoặc thiết bị. Không cung cấp API undelete cho người dùng.
- Vô hiệu hóa lựa chọn hồ sơ trên các robot, đóng quyền điều phối/session liên quan và yêu cầu xóa cache/context/âm thanh chờ theo khả năng thiết bị/provider. Robot offline hoặc dữ liệu đã gửi tới cloud không thể được thu hồi tức thời chỉ bằng tombstone: server chặn truy cập ngay, UI phân biệt phần xóa cục bộ/provider còn chờ. Không tuyên bố soft-delete đã xóa nội dung khỏi DB, backup hoặc thiết bị offline.
- Dữ liệu soft-deleted không được đưa vào brief, thống kê người dùng, tìm kiếm hoặc phân tích sản phẩm. Quyền vận hành nội bộ phải giới hạn và có audit; chính sách lưu nội bộ được chốt ở phần dưới, không mặc nhiên cấp quyền xem/khôi phục.
- Chính sách xóa nội dung `heard_text` sau 30 ngày hoặc khi bố mẹ yêu cầu xóa sớm vẫn áp dụng cả với hồ sơ soft-deleted và các bản sao do mình quản lý; tombstone không được dùng để bỏ qua tác vụ retention. Restore DB phải bảo toàn trạng thái đã xóa và thực thi yêu cầu xóa/retention trước khi phục vụ.
- Test bắt buộc: truy cập trực tiếp bằng ID cũ; export/cache/replay; request đang chạy lúc xóa; restart/restore; tạo hồ sơ cùng tên; robot còn chọn hồ sơ đã xóa; API sửa/undelete không được khôi phục; gia đình khác và dữ liệu anh chị em không bị ảnh hưởng; retention vẫn xử lý bản chép thuộc hồ sơ đã xóa.

### Lưu nội bộ dữ liệu đã soft-delete — đã chốt 2026-11-23

- Chọn phương án B: dữ liệu học có cấu trúc đã soft-delete được giữ nội bộ không đặt thời hạn xóa tự động. Không áp dụng đề xuất tự làm sạch sau 90 ngày. Việc giữ lại không khôi phục bất kỳ quyền truy cập nào của người dùng, kể cả chủ tài khoản cũ.
- Quyết định này không thay đổi chính sách bản chép lời: `heard_text` và các bản sao nội dung vẫn phải được xóa sau tối đa 30 ngày hoặc sớm hơn khi có yêu cầu đã chấp nhận; không giữ lời nói dưới dạng summary/payload/audit để lách retention.
- Soft-delete không phải ẩn danh hoặc xóa vật lý. Trước khi thu thập dữ liệu production, phải công bố trung thực việc dữ liệu học còn được giữ, xác định mục đích lưu, cơ sở pháp lý và phạm vi quyền vận hành; không mô tả thao tác này là đã xóa mọi dữ liệu khỏi hệ thống.
- Chính sách không thời hạn là lựa chọn sản phẩm, không phải kết luận pháp lý. Quyền xóa bắt buộc theo luật hoặc cam kết provider áp dụng phải được đánh giá và có quy trình thực hiện; nếu yêu cầu hard-delete/ẩn danh có hiệu lực thì không được dùng soft-delete để từ chối. Chưa có đánh giá phù hợp thì chưa đủ điều kiện phát hành thương mại.
- Quyền truy cập phần lưu nội bộ theo quyết định admin bên dưới, có audit; không có API khôi phục cho người dùng và không dùng dữ liệu này cho phân tích/huấn luyện theo quyết định retention này.
- Retention của backup phải được chốt riêng, không suy ra giữ mọi backup vô thời hạn. Restore phải giữ tombstone và áp lại yêu cầu xóa bản chép/xóa bắt buộc trước khi phục vụ dữ liệu.
- Test bắt buộc: dữ liệu cấu trúc soft-deleted không bị job 90 ngày xóa theo giả định cũ; người dùng vẫn không truy cập/khôi phục được; tài khoản không có vai trò admin nền tảng bị từ chối; job 30 ngày vẫn xóa bản chép; restore không hồi sinh hồ sơ hoặc nội dung đã có yêu cầu xóa.

### Quyền admin đối với dữ liệu đã soft-delete — đã chốt 2026-11-23

- Chọn phương án B: mọi tài khoản có vai trò admin nền tảng được xem dữ liệu học đã soft-delete trong ứng dụng quản trị; không yêu cầu cấp thêm quyền riêng theo từng vụ việc.
- Admin nền tảng là vai trò vận hành nội bộ, khác tài khoản bố mẹ hoặc người quản lý gia đình. Người dùng không thể tự cấp vai trò này qua đăng ký, cập nhật hồ sơ hoặc tham số API. Tài khoản bố mẹ không được xem lại hồ sơ đã xóa, kể cả hồ sơ thuộc gia đình mình.
- Đây là quyền xem, không mặc nhiên là quyền sửa, khôi phục, xuất hàng loạt hoặc dùng dữ liệu để phân tích/huấn luyện. Các quyền đó cần quyết định riêng; không bỏ bộ lọc tombstone ở API người dùng để tiện làm màn admin.
- Kiểm tra vai trò phía server trên từng đường đọc quản trị và ghi audit truy cập: admin nào, thời điểm, đối tượng và thao tác. Không chép lời bé hoặc toàn bộ dữ liệu học vào audit; dữ liệu đã hết hạn/xóa bắt buộc không được phục hồi để admin xem.
- Thừa nhận phạm vi tiếp cận dữ liệu trẻ rộng hơn mô hình cấp quyền theo vụ việc; trước production phải đưa phạm vi này vào đánh giá quyền riêng tư, quản lý tài khoản admin và công bố phù hợp. Quyền admin không thay thế cơ sở hợp lệ để giữ dữ liệu.
- Test bắt buộc: admin nền tảng đọc được dữ liệu soft-deleted còn được phép giữ; bố mẹ/người dùng không đọc được qua API quản trị hoặc ID trực tiếp; chống tự nâng quyền; mỗi lần truy cập được audit; quyền xem không tự cho phép sửa/khôi phục/export và không vượt retention bản chép.

### Admin sửa kết quả học — đã chốt 2026-11-23

- Chọn phương án A: admin nền tảng được sửa kết quả học bằng cơ chế correction có audit, không sửa trực tiếp attempt gốc, box hoặc bộ đếm. Đây là quyền riêng được quyết định thêm cho admin, ngoài quyền xem ở phần trên.
- Mỗi correction ghi admin thực hiện, thời điểm, lý do và kết quả trước/sau; giữ bản ghi gốc và phiên bản correction. Áp dụng cùng luật replay, thứ tự server, thời điểm học gốc và tuần tự hóa với attempt mới như khi bố mẹ sửa.
- Correction chỉ thay đổi kết quả được phép sửa, không cho đổi learner/item/session để chuyển lịch sử giữa các bé hoặc gia đình. Server kiểm tra vai trò trên từng request; request key/revision phải chống retry trùng và ghi đè correction cạnh tranh.
- Admin được correction dữ liệu còn được phép lưu của hồ sơ soft-deleted, nhưng không được gỡ tombstone, khôi phục quyền truy cập hoặc làm hồ sơ xuất hiện trở lại cho người dùng. Kết quả replay của hồ sơ đã xóa chỉ còn trong phạm vi lưu nội bộ.
- Không khôi phục bản chép đã hết hạn để phục vụ correction. Nếu không còn bằng chứng, UI nêu rõ thiếu bản chép; admin không được biến suy đoán thành bằng chứng ASR đã xác minh. Audit không sao chép nội dung lời bé.
- Test bắt buộc: admin sửa có lý do/audit và replay đúng; không sửa trực tiếp progress hoặc attempt gốc; retry/correction cạnh tranh; correction đồng thời với attempt mới; không chuyển dữ liệu sang bé khác; sửa hồ sơ soft-deleted không khôi phục truy cập; người dùng không có quyền không gọi được API admin.

### Thông báo khi admin sửa kết quả — đã chốt 2026-11-23

- Chọn phương án A: với hồ sơ chưa soft-delete, sau khi correction của admin đã commit và tiến độ được tính lại thành công, tạo thông báo trong Web UI của bố mẹ. Không cần bố mẹ duyệt trước; thông báo không phải điều kiện để correction có hiệu lực.
- Hiển thị kết quả trước/sau và lý do sửa phù hợp cho bố mẹ, liên kết lịch sử correction và cho biết tiến độ đã được tính lại. Không đưa bản chép đã hết hạn, dữ liệu gia đình khác hoặc ghi chú vận hành bí mật vào nội dung thông báo.
- Không ngắt buổi học, không phát thông báo cho bé qua robot/TTS. Không mở rộng quyết định này thành email/push/SMS.
- Tạo thông báo theo correction ID để retry hoặc worker restart không sinh thông báo trùng; bảo đảm correction đã thành công không bị mất thông báo khi tiến trình dừng giữa commit và gửi, ví dụ dùng transactional outbox hoặc cơ chế tương đương. Khi replay thất bại/chưa hoàn tất, không thông báo tiến độ đã tính lại thành công.
- Kiểm tra trạng thái hồ sơ và quyền gia đình tại thời điểm tạo, phân phối và đọc thông báo. Nếu hồ sơ đã soft-delete, không tạo/phát thông báo chứa dữ liệu hồ sơ đó; các thông báo cũ liên quan cũng không được tiếp tục truy cập qua danh sách, ID trực tiếp hoặc lịch sử correction. Không hồi sinh quyền đọc chỉ vì thông báo được tạo trước lúc xóa.
- Audit correction nội bộ vẫn được giữ theo chính sách hiện hành; suppression thông báo cho hồ sơ đã xóa không xóa audit và không làm correction có hiệu lực hai lần.
- Test bắt buộc: correction thành công tạo một thông báo; retry/restart không trùng hoặc mất thông báo; replay lỗi không báo thành công; xóa hồ sơ trước/sau commit hoặc khi thông báo đang chờ không lộ dữ liệu; bố mẹ gia đình khác không đọc được; robot không bị gián đoạn.

## Cổng phát hành, rủi ro và câu hỏi mở (chưa phải quyết định mới)

- **Trước PoC:** xác minh endpoint Xiaozhi thực gọi công cụ, nguồn robot/ngữ cảnh binding đủ tin cậy cho **một** Visbot, retry/timeout và quyền ở DB; không dùng endpoint/token đã lộ. Xác nhận consent, phạm vi dữ liệu thử và cách log không chứa transcript thô; PoC không mặc định cho phép thu âm. Nếu cloud không cách ly được, dừng mở rộng và quyết định đường thay thế.
- **Trước pilot giám sát:** hợp đồng transaction/version và idempotency đủ để kiểm thử session/replay/correction; kiểm thử Web UI, quyền gia đình, retention và audit theo các phần đã chốt; đo thực tế ASR trẻ em, bỏ tool và chấm sai tự tin. `next_step` chỉ là yêu cầu cho service quyết định, không chứng minh LLM đã thực hiện đúng.
- **Trước thương mại:** chứng minh danh tính nguồn gọi, handoff và context reset/generation cho nhiều robot/bé, chuyển chủ có xác nhận làm sạch; quyết định ngưỡng đo chất lượng tiến độ, SLA xóa/backup/restore, thông báo và đánh giá pháp lý/công bố lưu dữ liệu soft-deleted vô thời hạn/quyền admin. Chưa đạt thì không tuyên bố dữ liệu học xác minh hoặc khả năng triển khai đại trà.
- **Rủi ro kỹ thuật:** ASR giọng trẻ và LLM bỏ/chấm nhầm tool; bộ lọc `isNoiseHallucination` có thể chặn nhầm tiếng Anh; VPS/firewall và provider WSS cần đo. Bản chép lời chỉ dùng đối chiếu trong cửa sổ retention, không copy sang brief/confusions/summary/log.

**Câu hỏi ưu tiên để chốt trước thiết kế vật lý (đề xuất, chưa duyệt):**

1. **P0 — kiểm chứng danh tính PoC:** đo provider thực cung cấp nguồn/ngữ cảnh gì; nếu không có per-device provenance, áp dụng phương án thử nghiệm một Visbot trên trợ lý/binding riêng đã chốt, không coi đó là xác thực phần cứng. Chưa chứng minh context/source thì không mở nhiều robot, handoff hoặc đổi hồ sơ nóng.
2. **P0 — chi tiết transaction/API:** đặc tả thứ tự khóa learner/session/context/item khi start/end/revoke/correction, key/revision và unique violation. Chính sách retry sau correction/retention đã chốt; còn chuẩn hóa payload, phiên bản/rotation khóa và tên field cho xác nhận commit/kết quả hiệu lực. Bổ sung schema sự kiện coverage do server cấp, giữ nhãn LLM chưa xác minh.
3. **P1 — thuật toán học/version:** nội dung cốt lõi và sự kiện coverage đáng tin ở đường A là gì; version/migration coverage khi sửa bài, thứ tự review chống bỏ đói, ngưỡng giảm từ mới và loại lượt độc lập/được gợi ý được định nghĩa ra sao?
4. **P1 — dữ liệu trẻ/ra mắt:** SLA scrub bản chép trong backup/cache/restore và consent/provider retention cụ thể; ngưỡng ASR/tool/chấm sai nào đủ để chuyển PoC → pilot → thương mại, và đánh giá pháp lý quyền xóa/lưu nội bộ vô thời hạn?

## Nguồn tham khảo và việc cần xác minh

- [MCP sample của tác giả Xiaozhi](https://github.com/78/mcp-calculator): mẫu bridge nối WSS và chuyển tiếp MCP tới chương trình cung cấp công cụ. Dùng để kiểm chứng cơ chế; không lấy mặc định retry/log của mẫu làm tiêu chuẩn production.
- [Bonion](https://mcp.bonion.io.vn) là ví dụ trải nghiệm nhập endpoint để thêm công cụ; người dùng xác nhận đã hỏi giá vàng thành công. Chưa có mã backend/log Bonion nên không giả định nguồn dữ liệu hoặc cách lưu trạng thái của họ.
- [Tài liệu Feishu người dùng cung cấp](https://my.feishu.cn/wiki/HiPEwZ37XiitnwktX13cEM5KnSb): trình duyệt khách của người dùng đọc được; công cụ tự động hiện chưa lấy được nội dung. Không coi tài liệu này là nguồn đã đọc. Cần đối chiếu khi truy cập được.
- PoC phải xác minh: giới hạn tool/token của trợ lý, nhiều kết nối endpoint, độ ổn định gọi tool theo prompt, phiên cloud mới có khôi phục đúng state không, và bằng chứng ASR mà tool thực sự nhận được.
