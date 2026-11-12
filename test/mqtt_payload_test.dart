import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_assistant/services/xiaozhi_mqtt_manager.dart';

void main() {
  test(
    'MQTT control payloads round-trip Vietnamese MCP descriptions and emoji as UTF-8',
    () {
      final message = jsonEncode({
        'type': 'mcp',
        'payload': {
          'description': 'Gật đầu/đồng ý → nod. Dừng ngay! 🤖😊',
          'text': 'Tiến lên một chút rồi xoay 3 vòng sang trái.',
        },
      });
      final payload =
          XiaozhiMqttManager.buildPayload(message).payload!.toList();
      expect(utf8.decode(payload), message);
      expect(
        jsonDecode(utf8.decode(payload))['payload']['description'],
        contains('Gật đầu/đồng ý → nod'),
      );
      expect(payload, utf8.encode(message));
    },
  );
}
