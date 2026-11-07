import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:ai_assistant/models/xiaozhi_config.dart';
import 'package:ai_assistant/models/dify_config.dart';
import 'package:ai_assistant/models/minimax_config.dart';

class ConfigProvider extends ChangeNotifier {
  List<XiaozhiConfig> _xiaozhiConfigs = [];
  List<DifyConfig> _difyConfigs = [];
  List<MiniMaxConfig> _minimaxConfigs = [];
  bool _isLoaded = false;

  List<XiaozhiConfig> get xiaozhiConfigs => _xiaozhiConfigs;
  List<DifyConfig> get difyConfigs => _difyConfigs;
  List<MiniMaxConfig> get minimaxConfigs => _minimaxConfigs;
  DifyConfig? get difyConfig =>
      _difyConfigs.isNotEmpty ? _difyConfigs.first : null;
  bool get isLoaded => _isLoaded;

  ConfigProvider() {
    _loadConfigs();
  }

  Future<void> _loadConfigs() async {
    final prefs = await SharedPreferences.getInstance();

    // Load Xiaozhi configs
    final xiaozhiConfigsJson = prefs.getStringList('xiaozhiConfigs') ?? [];
    _xiaozhiConfigs =
        xiaozhiConfigsJson
            .map((json) => XiaozhiConfig.fromJson(jsonDecode(json)))
            .toList();

    // 加载多个Dify配置
    final difyConfigsJson = prefs.getStringList('difyConfigs') ?? [];
    _difyConfigs =
        difyConfigsJson
            .map((json) => DifyConfig.fromJson(jsonDecode(json)))
            .toList();

    // Load MiniMax configs
    final minimaxConfigsJson = prefs.getStringList('minimaxConfigs') ?? [];
    _minimaxConfigs =
        minimaxConfigsJson
            .map((json) => MiniMaxConfig.fromJson(jsonDecode(json)))
            .toList();

    // 向后兼容：加载旧版单个Dify配置
    final oldDifyConfigJson = prefs.getString('difyConfig');
    if (oldDifyConfigJson != null && _difyConfigs.isEmpty) {
      final oldConfig = DifyConfig.fromJson(jsonDecode(oldDifyConfigJson));
      // 添加ID和名称，转换为新格式
      final updatedConfig = DifyConfig(
        id: const Uuid().v4(),
        name: "Dify mặc định",
        apiUrl: oldConfig.apiUrl,
        apiKey: oldConfig.apiKey,
      );
      _difyConfigs.add(updatedConfig);

      // 保存为新格式并删除旧数据
      await _saveConfigs();
      await prefs.remove('difyConfig');
    }

    _isLoaded = true;
    notifyListeners();
  }

  Future<void> _saveConfigs() async {
    final prefs = await SharedPreferences.getInstance();

    // Save Xiaozhi configs
    final xiaozhiConfigsJson =
        _xiaozhiConfigs.map((config) => jsonEncode(config.toJson())).toList();
    await prefs.setStringList('xiaozhiConfigs', xiaozhiConfigsJson);

    // 保存多个Dify配置
    final difyConfigsJson =
        _difyConfigs.map((config) => jsonEncode(config.toJson())).toList();
    await prefs.setStringList('difyConfigs', difyConfigsJson);

    // Save MiniMax configs
    final minimaxConfigsJson =
        _minimaxConfigs.map((config) => jsonEncode(config.toJson())).toList();
    await prefs.setStringList('minimaxConfigs', minimaxConfigsJson);
  }

  Future<void> addXiaozhiConfig(
    String name,
    String websocketUrl, {
    String? customMacAddress,
    String? token,
  }) async {
    // 如果提供了自定义MAC地址，直接使用；否则使用设备ID生成
    final macAddress = customMacAddress ?? await _getDeviceMacAddress();

    final newConfig = XiaozhiConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      websocketUrl: websocketUrl,
      macAddress: macAddress,
      token: token ?? '',
    );

    _xiaozhiConfigs.add(newConfig);
    await _saveConfigs();
    notifyListeners();
  }

  /// Sinh MAC address ngẫu nhiên mới với OUI prefix của Espressif.
  /// Dùng cho mỗi config OTA mới để OTA server coi đây là thiết bị mới
  /// và trả về mã kích hoạt (OTP) thay vì coi là thiết bị đã kích hoạt.
  String _generateRandomMac() {
    final random = math.Random.secure();
    final List<int> macBytes = [0x24, 0x0A, 0xC4];
    for (int i = 0; i < 3; i++) {
      macBytes.add(random.nextInt(256));
    }
    return macBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
  }

  // 添加通过OTA激活的小智配置（如 xiaozhi.me 官方服务），WebSocket地址和Token在激活后填入
  Future<XiaozhiConfig> addXiaozhiOtaConfig(
    String name,
    String otaUrl, {
    String? customMacAddress,
  }) async {
    final newConfig = XiaozhiConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      websocketUrl: '',
      // Mỗi config OTA mới dùng MAC ngẫu nhiên để server trả OTP mới
      macAddress: customMacAddress ?? _generateRandomMac(),
      token: '',
      otaUrl: otaUrl,
      clientId: const Uuid().v4(),
    );

    _xiaozhiConfigs.add(newConfig);
    await _saveConfigs();
    notifyListeners();
    return newConfig;
  }

  Future<void> updateXiaozhiConfig(XiaozhiConfig updatedConfig) async {
    final index = _xiaozhiConfigs.indexWhere(
      (config) => config.id == updatedConfig.id,
    );
    if (index != -1) {
      _xiaozhiConfigs[index] = updatedConfig;
      await _saveConfigs();
      notifyListeners();
    }
  }

  Future<void> deleteXiaozhiConfig(String id) async {
    _xiaozhiConfigs.removeWhere((config) => config.id == id);
    await _saveConfigs();
    notifyListeners();
  }

  // 添加Dify配置
  Future<void> addDifyConfig(String name, String apiKey, String apiUrl) async {
    final newConfig = DifyConfig(
      id: const Uuid().v4(),
      name: name,
      apiUrl: apiUrl,
      apiKey: apiKey,
    );

    _difyConfigs.add(newConfig);
    await _saveConfigs();
    notifyListeners();
  }

  // 更新Dify配置
  Future<void> updateDifyConfig(DifyConfig updatedConfig) async {
    final index = _difyConfigs.indexWhere(
      (config) => config.id == updatedConfig.id,
    );
    if (index != -1) {
      _difyConfigs[index] = updatedConfig;
      await _saveConfigs();
      notifyListeners();
    }
  }

  // 删除Dify配置
  Future<void> deleteDifyConfig(String id) async {
    _difyConfigs.removeWhere((config) => config.id == id);
    await _saveConfigs();
    notifyListeners();
  }

  // 添加MiniMax配置
  Future<void> addMiniMaxConfig(
    String name,
    String apiKey, {
    String model = 'MiniMax-M2.7',
  }) async {
    final newConfig = MiniMaxConfig(
      id: const Uuid().v4(),
      name: name,
      apiKey: apiKey,
      model: model,
    );

    _minimaxConfigs.add(newConfig);
    await _saveConfigs();
    notifyListeners();
  }

  // 更新MiniMax配置
  Future<void> updateMiniMaxConfig(MiniMaxConfig updatedConfig) async {
    final index = _minimaxConfigs.indexWhere(
      (config) => config.id == updatedConfig.id,
    );
    if (index != -1) {
      _minimaxConfigs[index] = updatedConfig;
      await _saveConfigs();
      notifyListeners();
    }
  }

  // 删除MiniMax配置
  Future<void> deleteMiniMaxConfig(String id) async {
    _minimaxConfigs.removeWhere((config) => config.id == id);
    await _saveConfigs();
    notifyListeners();
  }

  // 向后兼容的旧方法，设置第一个Dify配置
  Future<void> setDifyConfig(String apiKey, String apiUrl) async {
    if (_difyConfigs.isEmpty) {
      await addDifyConfig("Dify mặc định", apiKey, apiUrl);
    } else {
      final updated = _difyConfigs.first.copyWith(
        apiKey: apiKey,
        apiUrl: apiUrl,
      );
      await updateDifyConfig(updated);
    }
  }

  // 简化版的设备ID获取方法，不依赖上下文
  Future<String> _getSimpleDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    String deviceId = '';

    try {
      // 简单地尝试获取Android或iOS设备ID，不依赖平台判断
      try {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
      } catch (_) {
        try {
          final iosInfo = await deviceInfo.iosInfo;
          deviceId = iosInfo.identifierForVendor ?? '';
        } catch (_) {
          final webInfo = await deviceInfo.webBrowserInfo;
          deviceId = webInfo.userAgent ?? '';
        }
      }
    } catch (e) {
      // 出现任何错误，使用时间戳
      deviceId = DateTime.now().millisecondsSinceEpoch.toString();
    }

    // 如果ID为空，使用时间戳
    if (deviceId.isEmpty) {
      deviceId = DateTime.now().millisecondsSinceEpoch.toString();
    }

    return deviceId;
  }

  String _generateMacFromDeviceId(String deviceId) {
    // Sử dụng OUI prefix của Espressif (ESP32) để trông như MAC thật
    final List<int> macBytes = [0x24, 0x0A, 0xC4];
    final bytes = utf8.encode(deviceId);
    final digest = md5.convert(bytes);
    final hash = digest.toString();

    // Lấy 3 byte còn lại từ hash
    for (int i = 0; i < 3; i++) {
      macBytes.add(int.parse(hash.substring(i * 2, i * 2 + 2), radix: 16));
    }

    // Format thành XX:XX:XX:XX:XX:XX
    return macBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
  }

  // 获取设备MAC地址
  Future<String> _getDeviceMacAddress() async {
    final deviceId = await _getSimpleDeviceId();

    // 如果设备ID本身就是MAC地址格式,直接使用
    if (_isMacAddress(deviceId)) {
      return deviceId;
    }

    // 否则生成一个MAC地址
    return _generateMacFromDeviceId(deviceId);
  }

  /// Public wrapper để lấy MAC địa chỉ từ bên ngoài provider
  Future<String> getDeviceMacAddress() async => _getDeviceMacAddress();

  // 检查字符串是否是MAC地址格式
  bool _isMacAddress(String str) {
    final macRegex = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$');
    return macRegex.hasMatch(str);
  }
}
