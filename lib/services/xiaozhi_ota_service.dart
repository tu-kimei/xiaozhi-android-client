import 'dart:convert';
import 'package:http/http.dart' as http;

/// OTA检查结果
class XiaozhiOtaResult {
  final String? websocketUrl;
  final String? websocketToken;

  /// MQTT 控制通道配置（官方 xiaozhi.me 服务使用 MQTT + UDP）
  final String? mqttEndpoint;
  final String? mqttClientId;
  final String? mqttUsername;
  final String? mqttPassword;
  final String? mqttPublishTopic;
  final String? mqttSubscribeTopic;

  /// 设备未绑定时服务器返回的6位激活码
  final String? activationCode;
  final String? activationMessage;
  final int activationTimeoutMs;

  XiaozhiOtaResult({
    this.websocketUrl,
    this.websocketToken,
    this.mqttEndpoint,
    this.mqttClientId,
    this.mqttUsername,
    this.mqttPassword,
    this.mqttPublishTopic,
    this.mqttSubscribeTopic,
    this.activationCode,
    this.activationMessage,
    this.activationTimeoutMs = 0,
  });

  /// 是否拿到了可用的 MQTT 配置
  bool get hasMqtt =>
      (mqttEndpoint ?? '').isNotEmpty &&
      (mqttClientId ?? '').isNotEmpty &&
      (mqttUsername ?? '').isNotEmpty &&
      (mqttPassword ?? '').isNotEmpty;

  bool get needsActivation =>
      activationCode != null && activationCode!.isNotEmpty;
}

/// 小智OTA/激活服务，协议参考 xiaozhi-esp32 固件 (ota.cc)
class XiaozhiOtaService {
  static const String TAG = "XiaozhiOta";
  static const String DEFAULT_OTA_URL = "https://api.tenclass.net/xiaozhi/ota/";
  static const String APP_VERSION = "1.6.0";
  static const String BOARD_TYPE = "esp32s3";

  static Map<String, String> _headers(String macAddress, String clientId) => {
    'Device-Id': macAddress,
    'Client-Id': clientId,
    'Activation-Version': '1',
    'User-Agent': 'ESP32_OTA/$APP_VERSION',
    'Accept-Language': 'vi-VN',
    'Content-Type': 'application/json',
  };

  static Map<String, dynamic> _systemInfo(
    String macAddress,
    String clientId,
  ) => {
    'version': 2,
    'language': 'vi-VN',
    'flash_size': 16777216,
    'minimum_free_heap_size': 8318916,
    'mac_address': macAddress,
    'uuid': clientId,
    'chip_model_name': 'esp32s3',
    'chip_info': {'model': 9, 'cores': 2, 'revision': 2, 'features': 18},
    'application': {
      'name': 'xiaozhi',
      'version': APP_VERSION,
      'compile_time': 'Jan 01 2025T00:00:00Z',
      'idf_version': 'v5.4',
      'elf_sha256':
          'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2',
    },
    'partition_table': [],
    'ota': {'label': 'factory'},
    'board': {'type': BOARD_TYPE, 'name': BOARD_TYPE, 'mac': macAddress},
  };

  /// 检查版本，获取WebSocket配置或激活码
  static Future<XiaozhiOtaResult> checkVersion({
    required String otaUrl,
    required String macAddress,
    required String clientId,
  }) async {
    print('$TAG: 检查OTA $otaUrl, Device-Id=$macAddress, Client-Id=$clientId');
    final response = await http
        .post(
          Uri.parse(otaUrl),
          headers: _headers(macAddress, clientId),
          body: jsonEncode(_systemInfo(macAddress, clientId)),
        )
        .timeout(const Duration(seconds: 15));

    print('$TAG: OTA响应 ${response.statusCode}: ${response.body}');
    if (response.statusCode != 200) {
      throw Exception(
        'Máy chủ OTA trả về lỗi ${response.statusCode}: ${response.body}',
      );
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final websocket = data['websocket'] as Map<String, dynamic>?;
    final mqtt = data['mqtt'] as Map<String, dynamic>?;
    final activation = data['activation'] as Map<String, dynamic>?;

    return XiaozhiOtaResult(
      websocketUrl: websocket?['url'] as String?,
      websocketToken: websocket?['token'] as String?,
      mqttEndpoint: mqtt?['endpoint']?.toString(),
      mqttClientId: mqtt?['client_id']?.toString(),
      mqttUsername: mqtt?['username']?.toString(),
      mqttPassword: mqtt?['password']?.toString(),
      mqttPublishTopic: mqtt?['publish_topic']?.toString(),
      mqttSubscribeTopic: mqtt?['subscribe_topic']?.toString(),
      activationCode: activation?['code']?.toString(),
      activationMessage: activation?['message'] as String?,
      activationTimeoutMs: (activation?['timeout_ms'] as num?)?.toInt() ?? 0,
    );
  }

  /// 轮询激活状态：返回true表示已激活，false表示仍在等待用户输入激活码
  static Future<bool> activate({
    required String otaUrl,
    required String macAddress,
    required String clientId,
  }) async {
    final url = otaUrl.endsWith('/') ? '${otaUrl}activate' : '$otaUrl/activate';
    final response = await http
        .post(
          Uri.parse(url),
          headers: _headers(macAddress, clientId),
          body: '{}',
        )
        .timeout(const Duration(seconds: 15));

    print('$TAG: 激活响应 ${response.statusCode}: ${response.body}');
    if (response.statusCode == 200) return true;
    if (response.statusCode == 202) return false;
    throw Exception(
      'Kích hoạt thất bại (${response.statusCode}): ${response.body}',
    );
  }
}
