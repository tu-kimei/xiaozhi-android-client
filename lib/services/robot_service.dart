import 'package:flutter/services.dart';

/// 机器人舵机信息
class ServoInfo {
  final String id;
  final String? name;
  final double minAngle;
  final double maxAngle;
  final double minSpeed;
  final double maxSpeed;
  final double defaultSpeed;

  ServoInfo.fromMap(Map<dynamic, dynamic> map)
    : id = map['id'] as String,
      name = map['name'] as String?,
      minAngle = (map['minAngle'] as num).toDouble(),
      maxAngle = (map['maxAngle'] as num).toDouble(),
      minSpeed = (map['minSpeed'] as num).toDouble(),
      maxSpeed = (map['maxSpeed'] as num).toDouble(),
      defaultSpeed = (map['defaultSpeed'] as num).toDouble();

  @override
  String toString() =>
      '$id ($name): ${minAngle.toStringAsFixed(0)}°..${maxAngle.toStringAsFixed(0)}°, '
      'tốc độ ${defaultSpeed.toStringAsFixed(0)}';
}

/// 机器人控制服务（UBTech Visbot：头部舵机与轮子），通过原生 RosaClient 实现
class RobotService {
  static const MethodChannel _channel = MethodChannel(
    'com.lhht.ai_assistant/robot',
  );

  /// 是否运行在带 ROSA 系统的机器人上
  static Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<List<ServoInfo>> servoDevices() async {
    final list = await _channel.invokeMethod<List<dynamic>>('servoDevices');
    return (list ?? [])
        .map((e) => ServoInfo.fromMap(e as Map<dynamic, dynamic>))
        .toList();
  }

  static Future<Map<dynamic, dynamic>?> locomotionDevice() =>
      _channel.invokeMethod<Map<dynamic, dynamic>>('locomotionDevice');

  /// 转动头部到指定角度（relative=true 时为相对角度），完成后返回结果
  static Future<Map<dynamic, dynamic>?> head(
    double angle, {
    double speed = 0,
    bool relative = false,
    String servoId = 'head',
  }) {
    return _channel.invokeMethod<Map<dynamic, dynamic>>('head', {
      'servoId': servoId,
      'angle': angle,
      'speed': speed,
      'relative': relative,
    });
  }

  /// 移动：speed>0 直行（angle 为方向，distance 为距离，0 表示持续），
  /// turnSpeed/turnAngle 为原地转向；移动结束或被取消后返回结果
  static Future<Map<dynamic, dynamic>?> move({
    double speed = 0,
    double angle = 0,
    double distance = 0,
    double turnSpeed = 0,
    double turnAngle = 0,
    int durationMs = 0,
  }) {
    return _channel.invokeMethod<Map<dynamic, dynamic>>('move', {
      'speed': speed,
      'angle': angle,
      'distance': distance,
      'turnSpeed': turnSpeed,
      'turnAngle': turnAngle,
      'durationMs': durationMs,
    });
  }

  static Future<void> stop() => _channel.invokeMethod('stop');
}
