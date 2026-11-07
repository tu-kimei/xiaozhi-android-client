import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'xiaozhi_websocket_manager.dart'
    show XiaozhiEvent, XiaozhiEventType, XiaozhiWebSocketListener;

/// 小智 MQTT 控制通道管理器。
///
/// 官方 xiaozhi.me 服务使用 MQTT + UDP 双通道：
/// - MQTT(8883/TLS) 负责控制消息（hello/listen/stt/tts/llm）
/// - UDP 负责实时 Opus 音频（语音通话）
///
/// 这里先实现 MQTT 文本聊天，事件接口与 [XiaozhiWebSocketManager] 保持一致，
/// 这样 [XiaozhiService] 可以用同一套事件处理逻辑。
class XiaozhiMqttManager {
  static const String TAG = "XiaozhiMqtt";
  static const int DEFAULT_PORT = 8883;

  final String deviceId; // 设备 MAC，如 24:0A:C4:A6:DA:61
  final String clientId; // OTA 的 Client-Id (UUID)

  final List<XiaozhiWebSocketListener> _listeners = [];

  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;
  bool _isConnected = false;
  bool _helloReceived = false;
  String? _sessionId;
  String? _publishTopic;
  String? _subscribeTopicColon;
  String? _subscribeTopicUnderscore;
  Timer? _helloTimeout;
  Timer? _inflightTimeout;

  /// 已发送但尚未收到服务器响应的文本（用于 goodbye 后自动重试）
  String? _inflightText;

  /// 是否已经发送 hello、正在等待服务器 hello 响应
  bool _helloRequested = false;

  /// 在收到服务器 hello 之前暂存要发送的文本
  final List<String> _pendingTexts = [];

  XiaozhiMqttManager({required this.deviceId, String? clientId})
    : clientId = (clientId == null || clientId.isEmpty) ? deviceId : clientId;

  /// 服务器 hello 中返回的会话 ID
  String? get sessionId => _sessionId;

  bool get isConnected => _isConnected;

  void addListener(XiaozhiWebSocketListener listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  void removeListener(XiaozhiWebSocketListener listener) {
    _listeners.remove(listener);
  }

  void _dispatchEvent(XiaozhiEvent event) {
    for (final listener in List.of(_listeners)) {
      listener(event);
    }
  }

  /// 把小写 MAC 转成 MQTT 主题使用的两种形式
  /// 服务器实际发布使用下划线形式，但不同版本可能使用冒号形式，两者都订阅。
  String get _macColon => deviceId.toLowerCase();
  String get _macUnderscore => deviceId.toLowerCase().replaceAll(':', '_');

  Future<void> connect({
    required String endpoint,
    required String mqttClientId,
    required String username,
    required String password,
    String? publishTopic,
    String? subscribeTopic,
    int port = DEFAULT_PORT,
  }) async {
    if (endpoint.isEmpty) {
      _dispatchEvent(
        XiaozhiEvent(
          type: XiaozhiEventType.error,
          data: "Địa chỉ MQTT không được để trống",
        ),
      );
      return;
    }

    await disconnect();

    _helloReceived = false;
    _helloRequested = false;
    _inflightText = null;
    _sessionId = null;
    _pendingTexts.clear();
    _publishTopic =
        (publishTopic == null || publishTopic.isEmpty || publishTopic == 'null')
            ? 'device-server'
            : publishTopic;
    _subscribeTopicColon = 'devices/p2p/$_macColon';
    _subscribeTopicUnderscore = 'devices/p2p/$_macUnderscore';

    final host = _parseHost(endpoint);
    print('$TAG: 正在连接 MQTT $host:$port, clientId=$mqttClientId');
    print('$TAG: 订阅主题 $_subscribeTopicColon / $_subscribeTopicUnderscore');

    final client = MqttServerClient.withPort(host, mqttClientId, port);
    client.secure = true;
    client.logging(on: false);
    client.keepAlivePeriod = 60;
    client.autoReconnect = true;
    client.connectTimeoutPeriod = 15000;
    client.connectionMessage =
        MqttConnectMessage()
            .withClientIdentifier(mqttClientId)
            .authenticateAs(username, password)
            .startClean();
    // 官方 broker 只接受 MQTT 3.1.1，库默认是 3.1
    client.setProtocolV311();

    client.onDisconnected = _onDisconnected;
    client.onAutoReconnected = _onAutoReconnected;

    _client = client;

    try {
      await client.connect();
    } catch (e) {
      print('$TAG: MQTT 连接异常: $e');
      _dispatchEvent(
        XiaozhiEvent(
          type: XiaozhiEventType.error,
          data: "Tạo kết nối MQTT thất bại: $e",
        ),
      );
      await disconnect();
      return;
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      final reason = client.connectionStatus?.returnCode;
      print('$TAG: MQTT 连接失败: $reason');
      _dispatchEvent(
        XiaozhiEvent(
          type: XiaozhiEventType.error,
          data: "Kết nối MQTT thất bại: $reason",
        ),
      );
      await disconnect();
      return;
    }

    _isConnected = true;

    // 监听服务器下行消息
    _updatesSub = client.updates?.listen(_onMessage);

    _subscribeAll();
    _sendHello();

    _dispatchEvent(XiaozhiEvent(type: XiaozhiEventType.connected, data: null));
    print('$TAG: 已连接 MQTT $host:$port');
  }

  String _parseHost(String endpoint) {
    var host = endpoint.trim();
    if (host.contains('://')) {
      host = Uri.parse(host).host;
    }
    // 去掉可能带上的端口
    final colon = host.lastIndexOf(':');
    if (colon > 0 && !host.contains(']')) {
      final maybePort = host.substring(colon + 1);
      if (int.tryParse(maybePort) != null) {
        host = host.substring(0, colon);
      }
    }
    return host;
  }

  void _subscribeAll() {
    final c = _client;
    if (c == null) return;
    for (final topic in {_subscribeTopicColon, _subscribeTopicUnderscore}) {
      if (topic == null || topic.isEmpty) continue;
      try {
        c.subscribe(topic, MqttQos.atMostOnce);
        print('$TAG: 已订阅 $topic');
      } catch (e) {
        print('$TAG: 订阅 $topic 失败: $e');
      }
    }
  }

  void _onAutoReconnected() {
    print('$TAG: MQTT 自动重连成功，重新订阅并发送 hello');
    _isConnected = true;
    _helloReceived = false;
    _helloRequested = false;
    _sessionId = null;
    _subscribeAll();
    _sendHello();
  }

  void _sendHello() {
    final hello = {
      "type": "hello",
      "version": 3,
      "transport": "udp",
      "features": {"mcp": true, "aec": true},
      "audio_params": {
        "format": "opus",
        "sample_rate": 16000,
        "channels": 1,
        "frame_duration": 60,
      },
    };
    _helloRequested = true;
    sendMessage(jsonEncode(hello));
    print('$TAG: 已发送 hello');
    _helloTimeout?.cancel();
    _helloTimeout = Timer(const Duration(seconds: 12), () {
      if (!_helloReceived) {
        print('$TAG: 12 秒内未收到服务器 hello');
      }
    });
  }

  /// 发送原始 JSON（发布到 device-server）
  void sendMessage(String message) {
    final c = _client;
    if (c == null || !_isConnected) {
      print('$TAG: 发送失败，MQTT 未连接');
      return;
    }
    final topic = _publishTopic ?? 'device-server';
    try {
      final builder = MqttClientPayloadBuilder()..addString(message);
      c.publishMessage(topic, MqttQos.atMostOnce, builder.payload!);
      print('$TAG: >> [$topic] $message');
    } catch (e) {
      print('$TAG: 发布消息失败: $e');
    }
  }

  /// 发送文本请求
  void sendTextRequest(String text) {
    if (_helloReceived && _sessionId != null) {
      _publishTextRequest(text);
      return;
    }
    print('$TAG: 会话未就绪，暂存文本请求并请求新 hello');
    _pendingTexts.add(text);
    if (!_helloRequested) {
      _sendHello();
    }
  }

  void _publishTextRequest(String text) {
    final jsonMessage = <String, dynamic>{
      "type": "listen",
      "state": "detect",
      "text": text,
      "source": "text",
    };
    if (_sessionId != null) {
      jsonMessage['session_id'] = _sessionId;
    }
    _inflightText = text;
    _inflightTimeout?.cancel();
    _inflightTimeout = Timer(const Duration(seconds: 20), () {
      if (_inflightText == text) {
        print('$TAG: 文本请求 20 秒内没有响应，放弃自动重试');
        _inflightText = null;
      }
    });
    print('$TAG: 发送文本请求: $text');
    sendMessage(jsonEncode(jsonMessage));
  }

  void _flushPendingTexts() {
    if (_pendingTexts.isEmpty) return;
    final pending = List<String>.from(_pendingTexts);
    _pendingTexts.clear();
    for (final text in pending) {
      _publishTextRequest(text);
    }
  }

  /// MQTT 模式下音频走 UDP，这里暂不处理
  void sendBinaryMessage(List<int> data) {
    // TODO: 语音通话时通过 UDP + AES-128-CTR 发送 Opus 数据
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final received in messages) {
      final message = received.payload;
      if (message is! MqttPublishMessage) continue;
      final text = MqttPublishPayload.bytesToStringAsString(
        message.payload.message,
      );
      print('$TAG: << [${received.topic}] $text');
      _handleTextMessage(text);
    }
  }

  void _handleTextMessage(String text) {
    try {
      final dynamic decoded = jsonDecode(text);
      if (decoded is Map) {
        final type = decoded['type'];
        if (type == 'hello') {
          _helloReceived = true;
          _helloRequested = false;
          _helloTimeout?.cancel();
          if (decoded['session_id'] != null) {
            _sessionId = decoded['session_id'].toString();
            print('$TAG: 会话ID $_sessionId');
          }
          _flushPendingTexts();
        } else if (type == 'goodbye') {
          print('$TAG: 服务器结束会话，等待下次请求时重新 hello');
          _helloReceived = false;
          _helloRequested = false;
          _sessionId = null;
          // 如果刚发出的文本因会话过期没有得到响应，重新排队重试
          final inflight = _inflightText;
          if (inflight != null) {
            _inflightText = null;
            _inflightTimeout?.cancel();
            _pendingTexts.add(inflight);
            _sendHello();
          }
        } else if (type == 'stt' || type == 'tts' || type == 'llm') {
          if (_inflightText != null) {
            _inflightText = null;
            _inflightTimeout?.cancel();
          }
        }
      }
    } catch (_) {
      // 非 JSON 消息直接透传
    }
    _dispatchEvent(XiaozhiEvent(type: XiaozhiEventType.message, data: text));
  }

  void _onDisconnected() {
    print('$TAG: MQTT 连接已断开');
    _isConnected = false;
    _helloReceived = false;
    _helloRequested = false;
    _inflightText = null;
    _sessionId = null;
    _inflightTimeout?.cancel();
    _dispatchEvent(
      XiaozhiEvent(type: XiaozhiEventType.disconnected, data: null),
    );
  }

  Future<void> disconnect() async {
    _helloTimeout?.cancel();
    _helloTimeout = null;
    _inflightTimeout?.cancel();
    _inflightTimeout = null;
    _pendingTexts.clear();
    _helloReceived = false;
    _helloRequested = false;
    _inflightText = null;
    _sessionId = null;

    await _updatesSub?.cancel();
    _updatesSub = null;

    final c = _client;
    _client = null;
    _isConnected = false;

    if (c != null) {
      try {
        c.disconnect();
      } catch (e) {
        print('$TAG: 断开 MQTT 失败: $e');
      }
    }
  }
}
