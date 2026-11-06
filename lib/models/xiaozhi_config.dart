class XiaozhiConfig {
  final String id;
  final String name;
  final String websocketUrl;
  final String macAddress;
  final String token;

  /// OTA地址，非空时连接前通过OTA获取WebSocket地址和Token（如 xiaozhi.me 官方服务）
  final String otaUrl;

  /// OTA/WebSocket 使用的 Client-Id (UUID)
  final String clientId;

  XiaozhiConfig({
    required this.id,
    required this.name,
    required this.websocketUrl,
    required this.macAddress,
    required this.token,
    this.otaUrl = '',
    this.clientId = '',
  });

  bool get usesOta => otaUrl.isNotEmpty;

  factory XiaozhiConfig.fromJson(Map<String, dynamic> json) {
    return XiaozhiConfig(
      id: json['id'],
      name: json['name'],
      websocketUrl: json['websocketUrl'],
      macAddress: json['macAddress'],
      token: json['token'],
      otaUrl: json['otaUrl'] ?? '',
      clientId: json['clientId'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'websocketUrl': websocketUrl,
      'macAddress': macAddress,
      'token': token,
      'otaUrl': otaUrl,
      'clientId': clientId,
    };
  }

  XiaozhiConfig copyWith({
    String? name,
    String? websocketUrl,
    String? macAddress,
    String? token,
    String? otaUrl,
    String? clientId,
  }) {
    return XiaozhiConfig(
      id: id,
      name: name ?? this.name,
      websocketUrl: websocketUrl ?? this.websocketUrl,
      macAddress: macAddress ?? this.macAddress,
      token: token ?? this.token,
      otaUrl: otaUrl ?? this.otaUrl,
      clientId: clientId ?? this.clientId,
    );
  }
}
