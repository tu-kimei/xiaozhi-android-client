import 'package:flutter/material.dart';
import '../services/robot_preferences.dart';
import '../services/robot_motion_controller.dart';
import '../services/robot_service.dart';
import 'robot_settings_preview.dart';
import 'standby_settings_panel.dart';

class RobotSettingsPanel extends StatefulWidget {
  const RobotSettingsPanel({super.key});
  @override
  State<RobotSettingsPanel> createState() => _RobotSettingsPanelState();
}

class _RobotSettingsPanelState extends State<RobotSettingsPanel> {
  final _preferences = RobotPreferences.instance;
  bool? _available;
  String? _result;
  bool _testing = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _preferences.load();
    final available = await RobotService.isAvailable();
    if (mounted) setState(() => _available = available);
  }

  Future<void> _test(String direction) async {
    setState(() {
      _testing = true;
      _result = null;
    });
    try {
      await (direction == 'nod'
          ? RobotMotionController.instance.head('nod')
          : RobotMotionController.instance.move(direction));
      if (mounted) setState(() => _result = 'Đã thử xong.');
    } catch (e) {
      if (mounted) setState(() => _result = e.toString());
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            scrollable: true,
            insetPadding: const EdgeInsets.all(12),
            titleTextStyle: Theme.of(context).textTheme.titleMedium,
            title: const Text('Khôi phục mặc định?'),
            content: const Text(
              'Đặt lại khuôn mặt, mic và chuyển động. Điều khiển giọng nói, bánh xe và các động tác tự động sẽ tắt.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Hủy'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Khôi phục'),
              ),
            ],
          ),
    );
    if (confirmed == true) await _preferences.reset();
  }

  Widget _title(String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _preferences,
    builder: (context, _) {
      final p = _preferences;
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            _available == null
                ? 'Đang kiểm tra robot…'
                : _available!
                ? 'Robot Visbot đã sẵn sàng'
                : 'Thiết bị không có phần cứng Visbot',
          ),
          _title('Khuôn mặt'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hiện mặt khi gọi'),
            value: p.faceEnabled,
            onChanged: (v) => p.update(showFace: v),
          ),
          DropdownButtonFormField<String>(
            value: p.faceStyle,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Dạng khuôn mặt'),
            items: const [
              DropdownMenuItem(
                value: 'simple',
                child: Text('VAG — mặt vector'),
              ),
              DropdownMenuItem(
                value: 'visbot',
                child: Text('SVGA — mắt Visbot'),
              ),
            ],
            onChanged: (v) {
              if (v != null) p.update(face: v);
            },
          ),
          const Text(
            'VAG vẽ trực tiếp trong app. SVGA dùng bộ mặt có sẵn trên Visbot.',
          ),
          OutlinedButton(
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => RobotFacePreview(style: p.faceStyle),
                  ),
                ),
            child: const Text('Xem thử mặt'),
          ),
          const StandbySettingsPanel(),
          _title('Giọng nói'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Điều khiển bằng giọng nói'),
            value: p.voiceEnabled,
            onChanged: _available == true ? (v) => p.update(voice: v) : null,
          ),
          DropdownButtonFormField<VoiceSensitivity>(
            value: p.sensitivity,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Độ nhạy phát hiện giọng nói',
            ),
            items: const [
              DropdownMenuItem(
                value: VoiceSensitivity.low,
                child: Text('Thấp — phòng ồn'),
              ),
              DropdownMenuItem(
                value: VoiceSensitivity.normal,
                child: Text('Bình thường'),
              ),
              DropdownMenuItem(
                value: VoiceSensitivity.high,
                child: Text('Cao — nói nhỏ / ở xa'),
              ),
            ],
            onChanged: (v) {
              if (v != null) p.update(mic: v);
            },
          ),
          const Text(
            'Chỉnh phát hiện tại robot. Nhận dạng và ngắt câu trên máy chủ do máy chủ quyết định.',
          ),
          _RobotValueSlider(
            label: 'Chờ im lặng để kết thúc câu',
            value: p.silenceMs,
            min: 300,
            max: 1500,
            divisions: 20,
            unit: 'ms',
            onSave: (v) => p.update(silence: v),
          ),
          OutlinedButton(
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const RobotMicrophonePreview(),
                  ),
                ),
            child: const Text('Thử mic'),
          ),
          _title('Đầu và động tác gật'),
          _RobotValueSlider(
            label: 'Tốc độ gật / cử động đầu',
            value: p.headSpeed,
            min: 10,
            max: 30,
            divisions: 20,
            onSave: (v) => p.update(head: v),
          ),
          _RobotValueSlider(
            label: 'Số nhịp gật theo lệnh',
            value: p.nodCount,
            min: 1,
            max: 3,
            divisions: 2,
            onSave: (v) => p.update(nods: v),
          ),
          _RobotValueSlider(
            label: 'Biên độ gật theo lệnh',
            value: p.nodAngle,
            min: 5,
            max: 20,
            divisions: 15,
            unit: '°',
            onSave: (v) => p.update(amplitude: v),
          ),
          OutlinedButton(
            onPressed:
                !_testing && p.voiceEnabled && _available == true
                    ? () => _test('nod')
                    : null,
            child: const Text('Thử gật đầu'),
          ),
          _title('Bánh xe'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cho phép bánh xe'),
            subtitle: const Text(
              'Bật khi robot ở sàn phẳng, trống, xa mép bậc.',
            ),
            value: p.wheelsEnabled,
            onChanged: _available == true ? (v) => p.update(wheels: v) : null,
          ),
          _RobotValueSlider(
            label: 'Tốc độ tiến / lùi',
            value: p.wheelSpeed,
            min: 1,
            max: 15,
            divisions: 14,
            onSave: (v) => p.update(speed: v),
          ),
          _RobotValueSlider(
            label: 'Tốc độ xoay',
            value: p.turnSpeed,
            min: 16,
            max: 200,
            divisions: 46,
            onSave: (v) => p.update(turn: v),
          ),
          const Text(
            'Đổi tốc độ sẽ đổi quãng đường. Hiệu chỉnh lại thời gian một bước / một vòng bên dưới.',
          ),
          _title('Tự động khi trò chuyện'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cử chỉ đầu tự nhiên'),
            value: p.swayWhenSpeaking,
            onChanged: _available == true ? (v) => p.update(sway: v) : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tiến lùi khi vui / hào hứng'),
            subtitle: const Text(
              'Chỉ khi có cảm xúc vui, tiến rồi lùi chậm trong khoảng nghỉ; cách 30–45 giây. Cần quyền bánh xe và giọng nói.',
            ),
            value: p.moveWhenConversing,
            onChanged: _available == true ? (v) => p.update(autoMove: v) : null,
          ),
          DropdownButtonFormField<GestureIntensity>(
            value: p.gestures,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Phong cách cử chỉ'),
            items: const [
              DropdownMenuItem(
                value: GestureIntensity.off,
                child: Text('Yên tĩnh'),
              ),
              DropdownMenuItem(
                value: GestureIntensity.gentle,
                child: Text('Tự nhiên'),
              ),
              DropdownMenuItem(
                value: GestureIntensity.lively,
                child: Text('Sinh động'),
              ),
            ],
            onChanged:
                _available == true
                    ? (v) {
                      if (v != null) p.update(intensity: v);
                    }
                    : null,
          ),
          const Text(
            'Yên tĩnh tắt mọi cử chỉ tự động. Tự nhiên ưu tiên ánh mắt, ít cử động đầu. Sinh động tăng tần suất nhưng vẫn có khoảng nghỉ.',
          ),
          _title('Hiệu chỉnh bánh xe'),
          _RobotValueSlider(
            label: 'Thời gian một bước',
            value: p.stepMs,
            min: 100,
            max: 1000,
            divisions: 18,
            unit: 'ms',
            onSave: (v) => p.update(step: v),
          ),
          _RobotValueSlider(
            label: 'Thời gian một vòng',
            value: p.rotationMs,
            min: 500,
            max: 6000,
            divisions: 55,
            unit: 'ms',
            onSave: (v) => p.update(rotation: v),
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed:
                    !_testing &&
                            p.voiceEnabled &&
                            p.wheelsEnabled &&
                            _available == true
                        ? () => _test('forward')
                        : null,
                child: const Text('Thử tiến 1 bước'),
              ),
              OutlinedButton(
                onPressed:
                    !_testing &&
                            p.voiceEnabled &&
                            p.wheelsEnabled &&
                            _available == true
                        ? () => _test('backward')
                        : null,
                child: const Text('Thử lùi 1 bước'),
              ),
              OutlinedButton(
                onPressed:
                    !_testing &&
                            p.voiceEnabled &&
                            p.wheelsEnabled &&
                            _available == true
                        ? () => _test('spinleft')
                        : null,
                child: const Text('Thử 1 vòng trái'),
              ),
            ],
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => RobotMotionController.instance.stop(),
            icon: const Icon(Icons.stop_circle),
            label: const Text('DỪNG ROBOT'),
          ),
          if (_result != null) Text(_result!),
          const SizedBox(height: 12),
          const Text(
            'Tối đa 10 giây mỗi lệnh bánh xe; 30 giây liên tục rồi nghỉ. Nói “dừng”, “đứng lại” hoặc “stop” để dừng.',
          ),
          const Divider(),
          OutlinedButton(
            onPressed: _reset,
            child: const Text('Khôi phục cài đặt robot mặc định'),
          ),
        ],
      );
    },
  );
}

/// Save only after dragging ends, avoiding repeated hardware stops/disk writes.
class _RobotValueSlider extends StatefulWidget {
  final String label, unit;
  final int value, min, max, divisions;
  final ValueChanged<int> onSave;
  const _RobotValueSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onSave,
    this.unit = '',
  });
  @override
  State<_RobotValueSlider> createState() => _RobotValueSliderState();
}

class _RobotValueSliderState extends State<_RobotValueSlider> {
  late double _draft;
  @override
  void initState() {
    super.initState();
    _draft = widget.value.toDouble();
  }

  @override
  void didUpdateWidget(_RobotValueSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _draft = widget.value.toDouble();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      Text('${widget.label}: ${_draft.round()} ${widget.unit}'),
      Slider(
        value: _draft.clamp(widget.min.toDouble(), widget.max.toDouble()),
        min: widget.min.toDouble(),
        max: widget.max.toDouble(),
        divisions: widget.divisions,
        label: '${_draft.round()} ${widget.unit}',
        onChanged: (v) => setState(() => _draft = v),
        onChangeEnd: (v) => widget.onSave(v.round()),
      ),
    ],
  );
}
