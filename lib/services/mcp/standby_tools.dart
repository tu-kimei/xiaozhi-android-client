import 'mcp_server.dart';

/// Separate from motor permissions: resting does not require robot movement.
void registerStandbyTools(
  McpServer server, {
  required Future<void> Function() sleep,
}) {
  server.register(
    McpTool(
      name: 'self.robot.sleep',
      description:
          'Cho robot đi ngủ/nghỉ, tắt màn hình để tiết kiệm pin và ngừng trò chuyện. '
          'Gọi khi người dùng yêu cầu robot: đi ngủ đi, ngủ đi, nghỉ đi, nghỉ ngơi đi, '
          'tắt màn hình. Không gọi khi người dùng chỉ hỏi về giấc ngủ hoặc kể chuyện. '
          'Giữ bộ nghe câu đánh thức tại robot nếu đã bật trong Cài đặt; '
          'người dùng gọi câu đánh thức đã lưu để bật màn hình và trò chuyện lại. '
          'Chỉ cần gọi công cụ, không cần nói thêm sau khi thành công.',
      inputSchema: const {
        'type': 'object',
        'properties': {},
        'additionalProperties': false,
      },
      handler: (_) async {
        await sleep();
        return 'Robot đã vào chế độ nghỉ và tắt màn hình.';
      },
    ),
  );
}
