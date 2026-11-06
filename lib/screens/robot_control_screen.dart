import 'package:flutter/material.dart';
import 'package:ai_assistant/services/robot_service.dart';

/// 机器人控制测试界面：头部舵机与轮子
class RobotControlScreen extends StatefulWidget {
  const RobotControlScreen({super.key});

  @override
  State<RobotControlScreen> createState() => _RobotControlScreenState();
}

class _RobotControlScreenState extends State<RobotControlScreen> {
  // 每次点击的移动量
  // 单位来自 /locomotor/device：直行速度 1..15（默认7），转向速度 16..238 度/秒（默认70）
  static const double _moveSpeed = 7;
  static const int _moveDurationMs = 1500;
  static const double _turnSpeed = 70;
  static const double _turnStep = 30; // 度

  ServoInfo? _head;
  String _log = 'Đang đọc thông tin servo...';

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      final devices = await RobotService.servoDevices();
      final wheels = await RobotService.locomotionDevice();
      setState(() {
        _head = devices.cast<ServoInfo?>().firstWhere(
          (d) => d!.id == 'head',
          orElse: () => devices.isEmpty ? null : devices.first,
        );
        _log = devices.isEmpty
            ? 'Không tìm thấy servo'
            : devices.map((d) => d.toString()).join('\n');
        _log += '\nBánh xe: $wheels';
      });
    } catch (e) {
      setState(() => _log = 'Lỗi đọc servo: $e');
    }
  }

  Future<void> _run(String label, Future<Map<dynamic, dynamic>?> Function() action) async {
    setState(() => _log = '$label...');
    try {
      final result = await action();
      if (!mounted) return;
      setState(() => _log = '$label: ${result?['result']} (code ${result?['code']}) ${result?['message'] ?? ''}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _log = '$label lỗi: $e');
    }
  }

  void _headTo(String label, double Function(ServoInfo head) angleOf) {
    final head = _head;
    if (head == null) {
      setState(() => _log = 'Chưa có thông tin servo đầu');
      return;
    }
    _run(label, () => RobotService.head(angleOf(head), servoId: head.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        toolbarHeight: 36,
        title: const Text('Điều khiển robot', style: TextStyle(fontSize: 15)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _buildHeadControls()),
                    const VerticalDivider(width: 12),
                    Expanded(child: _buildWheelControls()),
                  ],
                ),
              ),
              SizedBox(
                height: 44,
                child: SingleChildScrollView(
                  child: Text(_log, style: const TextStyle(fontSize: 10)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeadControls() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Đầu', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        _button('Ngẩng', Icons.arrow_upward, () => _headTo('Ngẩng', (h) => h.maxAngle)),
        _button(
          'Giữa',
          Icons.adjust,
          () => _headTo('Giữa', (h) => (h.minAngle + h.maxAngle) / 2),
        ),
        _button('Cúi', Icons.arrow_downward, () => _headTo('Cúi', (h) => h.minAngle)),
      ],
    );
  }

  Widget _buildWheelControls() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _iconButton(Icons.arrow_upward, () => _run(
          'Tiến',
          () => RobotService.move(speed: _moveSpeed, durationMs: _moveDurationMs),
        )),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _iconButton(Icons.rotate_left, () => _run(
              'Quay trái',
              () => RobotService.move(turnAngle: _turnStep, turnSpeed: _turnSpeed),
            )),
            _iconButton(Icons.stop_circle_outlined, () async {
              await RobotService.stop();
              if (mounted) setState(() => _log = 'Đã dừng');
            }, color: Colors.red),
            _iconButton(Icons.rotate_right, () => _run(
              'Quay phải',
              () => RobotService.move(turnAngle: -_turnStep, turnSpeed: -_turnSpeed),
            )),
          ],
        ),
        _iconButton(Icons.arrow_downward, () => _run(
          'Lùi',
          () => RobotService.move(
            speed: -_moveSpeed,
            durationMs: _moveDurationMs,
          ),
        )),
      ],
    );
  }

  Widget _button(String label, IconData icon, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SizedBox(
        width: double.infinity,
        height: 32,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 16),
          label: Text(label, style: const TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onPressed, {Color? color}) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, color: color),
      iconSize: 28,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 40),
    );
  }
}
