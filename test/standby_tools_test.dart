import 'package:flutter_test/flutter_test.dart';
import 'package:ai_assistant/services/mcp/mcp_server.dart';
import 'package:ai_assistant/services/mcp/standby_tools.dart';

Map<String, dynamic> request(
  int id,
  String method, [
  Map<String, dynamic>? params,
]) => {
  'jsonrpc': '2.0',
  'id': id,
  'method': method,
  if (params != null) 'params': params,
};
void main() {
  test(
    'server discovers sleep independently of motor permissions; duplicate does not run twice',
    () async {
      var sleeps = 0;
      final server = McpServer();
      registerStandbyTools(
        server,
        sleep: () async {
          sleeps++;
        },
      );
      final tools = await server.handle(request(1, 'tools/list'));
      expect(tools!['result']['tools'][0]['name'], 'self.robot.sleep');
      final call = request(2, 'tools/call', {'name': 'self.robot.sleep'});
      final result = await server.handle(call);
      expect(result!['result']['isError'], isFalse);
      await server.handle(call);
      expect(sleeps, 1);
    },
  );
  test(
    'failed standby is reported to server without false acknowledgement',
    () async {
      final server = McpServer();
      registerStandbyTools(
        server,
        sleep: () async {
          throw StateError('Mic chưa sẵn sàng');
        },
      );
      final result = await server.handle(
        request(1, 'tools/call', {'name': 'self.robot.sleep'}),
      );
      expect(result!['result']['isError'], isTrue);
      expect(
        result['result']['content'][0]['text'],
        contains('Mic chưa sẵn sàng'),
      );
    },
  );
}
