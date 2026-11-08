# Việc 1 — Bé điều khiển robot bằng lời nói + robot tự cử chỉ theo ngữ cảnh

## Mục tiêu

1. Bé nói "robot ơi tiến lên một chút rồi xoay 3 vòng sang trái" thì robot làm đúng như vậy, theo thứ tự.
2. Có mục **Cài đặt → Robot** để bật/tắt và giới hạn chuyển động, gồm cả chế độ **cử chỉ tự động**: robot tự gật đầu, ngẩng/cúi, lắc lư khi nói, tuỳ theo ngữ cảnh.

## Hướng tiếp cận: MCP

Server Xiaozhi có sẵn cơ chế cho thiết bị khai báo "công cụ". LLM trên server tự hiểu câu nói (kể cả câu ghép nhiều bước) và gọi công cụ trên thiết bị. Cách này không cần tự viết bộ phân tích câu lệnh tiếng Việt. Lily dùng đúng cách này.

### Giao thức (JSON-RPC 2.0 trong tin nhắn `type: "mcp"`, đi qua MQTT như các tin nhắn điều khiển khác)

Server → thiết bị:

```json
{"session_id":"…","type":"mcp","payload":{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{…}}}}
{"session_id":"…","type":"mcp","payload":{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{"cursor":""}}}
{"session_id":"…","type":"mcp","payload":{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"self.robot.move","arguments":{…}}}}
```

Thiết bị trả lời (theo đúng hình dạng Lily dùng, đã kiểm chứng chạy với xiaozhi.me):

```json
{"session_id":"…","type":"mcp","payload":{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","capabilities":{"tools":{}},"serverInfo":{"name":"xiaozhi-android","version":"1.0.0"}}}}
{"session_id":"…","type":"mcp","payload":{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"…","description":"…","inputSchema":{"type":"object","properties":{…},"required":[…]}}]}}}
{"session_id":"…","type":"mcp","payload":{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"ok"}],"isError":false}}}
```

Khi lỗi: `{"jsonrpc":"2.0","id":N,"error":{"code":-32601,"message":"…"}}`.

Tham khảo: tài liệu `docs/mcp-protocol.md` trong repo `78/xiaozhi-esp32`, và code Lily (lớp xử lý `mcp`, đăng ký công cụ, `tools/call`).

### Lily làm gì (đã dịch ngược)

- Ba công cụ robot:
  - **`self.robot.move`**:
    - `direction`: forward/backward/left/right/spinleft/spinright;
    - `steps`: 1 bước ≈ 0.5s;
    - `rotations`: 1 vòng ≈ 1.5s;
    - mỗi lệnh tối đa 12s;
    - tốc độ đi thẳng `±15`, tốc độ xoay `±200`.
  - **`self.robot.stop`**.
  - **`self.robot.head`** (up = 25°, center = 0°, down = -23°).
- Mô tả công cụ viết bằng tiếng Việt, liệt kê nhiều cách nói (ví dụ "tiến lên", "đi tới", "quay vòng"…). Đây là phần quan trọng nhất để LLM gọi đúng công cụ.
- "Nhảy khi nói": trong lúc robot đang nói, gật đầu hoặc lắc thân lùi/tiến nhẹ, nhịp 70–500ms tuỳ âm lượng.

## Thiết kế

### A. Lớp MCP dùng chung (`lib/services/mcp/`)

- `McpServer`:
  - giữ danh sách công cụ, mỗi công cụ là `McpTool {name, description, inputSchema, Future<String> Function(Map args) handler}`;
  - xử lý `initialize`, `tools/list`, `tools/call`;
  - trả lỗi `-32601` khi gặp method lạ.
- Nối vào `XiaozhiService._handleTextMessage`: `case 'mcp'` → `McpServer.handle(payload)` → gửi trả qua `_sendControlMessage({'session_id':…, 'type':'mcp', 'payload':…})`.
- **Việc 2 và 3 sẽ đăng ký thêm công cụ vào đây**, nên lớp này phải tách riêng và có test đơn vị.
- Công cụ chạy lâu (robot đang đi): `tools/call` chỉ trả lời sau khi động tác xong. Có timeout (ví dụ 15s), quá hạn thì dừng robot rồi trả lỗi.

### B. Bộ công cụ robot (`lib/services/mcp/robot_tools.dart`)

Dùng `RobotService` sẵn có. Đề xuất:

| Công cụ | Tham số | Ghi chú |
|---------|---------|---------|
| `self.robot.move` | `direction` (enum), `steps` (int 1–10), `rotations` (number 0.25–5) | Câu "xoay 3 vòng sang trái" → `spinleft`, `rotations=3`. Phải hiệu chỉnh "1 vòng" thực tế = bao nhiêu ms hoặc độ (đo trên robot). |
| `self.robot.head` | `action`: up/down/center/nod/shake | `nod` = gật 2 lần, `shake` = lắc đầu (Visbot chỉ có servo ngẩng/cúi; kiểm tra `servoDevices()` xem có trục ngang không, nếu không thì bỏ `shake`). |
| `self.robot.stop` | — | Luôn được phép, kể cả khi đã tắt chuyển động. |
| `self.robot.dance` *(tuỳ chọn)* | `name` (enum từ danh sách có sẵn) | Phát file `.orch` trong `/system/media/visbot/dance*` qua OrchestrationManager của ROSA. Cần thêm hàm vào `RosaClient.kt`; tham khảo `VisbotTlvOrchParser` trong SDK đã dịch ngược. Làm sau cùng. |

- **Chuỗi lệnh**: LLM thường gọi lần lượt từng công cụ. Không cần công cụ "chuỗi" riêng, nhưng phải đảm bảo các lệnh **chạy tuần tự**: có hàng đợi; lệnh sau chờ lệnh trước xong.
- **Mô tả công cụ** viết bằng tiếng Việt, kèm ví dụ cách bé nói, giống Lily. Ví dụ: "Di chuyển robot. Dùng khi bé nói: tiến lên, đi tới, lùi lại, quay trái, xoay vòng…".

### C. An toàn (bé 5 tuổi)

- Giới hạn cứng trong code, không phụ thuộc LLM:
  - tốc độ tối đa;
  - mỗi lệnh tối đa 10s;
  - tổng thời gian di chuyển liên tục tối đa ~30s rồi tự nghỉ.
- **Từ khoá dừng khẩn cấp ngay trên thiết bị**: khi STT chứa "dừng", "đứng lại", "stop" thì gọi `RobotService.stop()` ngay, không chờ LLM.
- Nút **DỪNG** to trên màn gọi, hiện khi robot đang chuyển động.
- Robot đang di chuyển thì vẫn nghe được bé nói, vì mic không bị chặn khi có chuyển động.
- Kiểm tra cảm biến chống rơi hoặc va chạm của Visbot (nếu ROSA có) và cân nhắc dùng.

### D. Cử chỉ tự động (`lib/services/robot_gestures.dart`)

Robot tự cử động theo ngữ cảnh, không cần bé ra lệnh:

| Tình huống | Nguồn tín hiệu | Cử chỉ |
|-----------|----------------|--------|
| Robot đang nói | `voiceState == speaking`, mức âm lượng phát | gật/lắc lư nhẹ theo nhịp (kiểu Lily), chỉ dùng servo đầu |
| Cảm xúc từ server | tin nhắn `llm.emotion` | happy/laughing → gật 2 lần; sad/crying → cúi đầu; surprised → ngẩng nhanh; thinking → nghiêng/ngẩng chậm |
| Bé bắt đầu nói | VAD `listening` | ngẩng đầu "lắng nghe" |
| Chờ lâu | `waiting` > 60s | thỉnh thoảng nhìn quanh |

Mặc định cử chỉ tự động **chỉ dùng đầu**; dùng bánh xe phải bật riêng. Có thể đồng bộ với Việc 2: cùng một sự kiện cảm xúc thì vừa đổi mặt vừa cử chỉ.

### E. Cài đặt (`settings_screen.dart`, tab mới "Robot")

- Cho phép điều khiển bằng giọng nói (bật/tắt).
- Cho phép di chuyển bánh xe (bật/tắt; tắt thì chỉ được cử động đầu).
- Tốc độ tối đa (chậm / vừa).
- Cử chỉ tự động: tắt / nhẹ / nhiều.
- Lắc lư khi nói (bật/tắt).
- Hiệu chỉnh: thời gian 1 bước, thời gian 1 vòng xoay. Có nút "thử" để đo.
- Lưu bằng `shared_preferences`. `tools/list` chỉ khai báo những công cụ đang được bật.

## Các bước

1. Lớp `McpServer`, test đơn vị cho `initialize`, `tools/list`, `tools/call` và lỗi. Nối vào `XiaozhiService`; log đầy đủ tin nhắn `mcp` vào/ra.
2. Kiểm chứng trên robot: server có gửi `tools/list` sau hello không. **Lưu ý**: server có thể chỉ hỏi khi phiên mới bắt đầu, và có thể cần bật MCP/IoT cho thiết bị trên console xiaozhi.me.
3. Công cụ `head` và `stop`, rồi `move`, có hàng đợi tuần tự và các giới hạn an toàn.
4. Từ khoá dừng khẩn cấp, nút DỪNG.
5. Hiệu chỉnh bước/vòng trên robot thật.
6. Cử chỉ tự động, rồi màn Cài đặt.
7. (Tuỳ chọn) `dance` qua orchestration.

## Tiêu chí nghiệm thu (thử trên robot)

- "Robot ơi tiến lên một chút" → đi thẳng khoảng 1 bước rồi dừng.
- "Xoay 3 vòng sang trái" → quay trái khoảng 3 vòng, sai số ±½ vòng.
- "Tiến lên một chút rồi xoay 3 vòng sang trái" → làm đúng thứ tự.
- "Gật đầu đi" → gật đầu. "Dừng lại!" giữa lúc đang xoay → dừng trong vòng dưới 1 giây.
- Tắt "di chuyển bánh xe" thì câu "tiến lên" chỉ nhận lời từ chối, robot không lăn.
- Bật cử chỉ tự động thì khi robot nói câu vui có gật đầu, câu buồn có cúi đầu; tắt thì đứng yên.
- Hội thoại vẫn mượt: mic mở lại đúng lúc, không lỗi âm thanh mới.

## Rủi ro và câu hỏi mở

- Chưa xác minh server xiaozhi.me gọi MCP với thiết bị đi qua MQTT. Lily dùng WebSocket. Làm bước 2 sớm; nếu không chạy thì phải xem console có tuỳ chọn bật không.
- Tiếng servo/bánh xe lọt vào mic có thể kích VAD hoặc làm ASR bịa câu. Có thể cần chặn mic trong lúc robot di chuyển.
