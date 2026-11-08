import 'package:ai_assistant/models/conversation.dart';
import 'package:ai_assistant/models/xiaozhi_config.dart';
import 'package:ai_assistant/providers/config_provider.dart';
import 'package:ai_assistant/widgets/conversation_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ConfigProvider giả: trả về danh sách cấu hình cố định, không đọc prefs.
class _FakeConfigProvider extends ConfigProvider {
  final List<XiaozhiConfig> configs;

  _FakeConfigProvider(this.configs);

  @override
  List<XiaozhiConfig> get xiaozhiConfigs => configs;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('ConversationTile không tràn trên màn 308x240 với tên cấu hình dài', (
    tester,
  ) async {
    // Màn hình robot: 308x240, density 120 => dpr 1.0
    tester.view.physicalSize = const Size(308, 240);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final config = XiaozhiConfig(
      id: 'cfg-1',
      name: 'Chat với trợ lý xiaozhi.me rất dài',
      websocketUrl: 'wss://api.tenclass.net/xiaozhi/v1/',
      macAddress: '24:0A:C4:A6:DA:61',
      token: 'test-token',
    );

    final conversation = Conversation(
      id: 'conv-1',
      title: 'Chat với xiaozhi.me và một tiêu đề khá dài',
      type: ConversationType.xiaozhi,
      configId: config.id,
      lastMessageTime: DateTime.now(),
      lastMessage: 'Cuộc gọi thoại đã bắt đầu',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ConfigProvider>.value(
        value: _FakeConfigProvider([config]),
        child: MaterialApp(
          home: Scaffold(body: ConversationTile(conversation: conversation)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
