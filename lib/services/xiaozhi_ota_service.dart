import 'dart:convert';
import 'package:http/http.dart' as http;

/// OTA检查结果
class XiaozhiOtaResult {
  final String? websocketUrl;
  final String? websocketToken;

  /// 设备未绑定时服务器返回的6位激活码
  final String? activationCode;
  final String? activationMessage;
  final int activationTimeoutMs;

  XiaozhiOtaResult({
    this.websocketUrl,
    this.websocketToken,
    this.activationCode,
    this.activationMessage,
    this.activationTimeoutMs = 0,
  });

  bool get needsActivation =>
      activationCode != null && activationCode!.isNotEmpty;
}

/// 小智OTA/激活服务，协议参考 xiaozhi-esp32 固件 (ota.cc)
class XiaozhiOtaService {
  static const String TAG = "XiaozhiOta";
  static const String DEFAULT_OTA_URL = "https://api.tenclass.net/xiaozhi/ota/";
  static const String APP_VERSION = "1.6.0";
  static const String BOARD_TYPE = "visbot-android";

  static Map<String, String> _headers(String macAddress, String clientId) => {
    'Device-Id': macAddress,
    'Client-Id': clientId,
    'Activation-Version': '1',
    'User-Agent': '$BOARD_TYPE/$APP_VERSION',
    'Accept-Language': 'vi-VN',
    'Content-Type': 'application/json',
  };

  static Map<String, dynamic> _systemInfo(String macAddress, String clientId) =>
      {
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
          'elf_sha256': '0' * 64,
        },
        'partition_table': [],
        'ota': {'label': 'factory'},
        'board': {
          'type': BOARD_TYPE,
          'name': BOARD_TYPE,
          'mac': macAddress,
        },
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
    final activation = data['activation'] as Map<String, dynamic>?;

    return XiaozhiOtaResult(
      websocketUrl: websocket?['url'] as String?,
      websocketToken: websocket?['token'] as String?,
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
