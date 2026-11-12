import 'package:flutter/material.dart';
import '../services/robot_preferences.dart';
import '../services/standby/screen_power.dart';
import '../services/standby/wake_phrase_tokenizer.dart';

class StandbySettingsPanel extends StatefulWidget {
  const StandbySettingsPanel({super.key});
  @override
  State<StandbySettingsPanel> createState() => _StandbySettingsPanelState();
}

class _StandbySettingsPanelState extends State<StandbySettingsPanel> {
  final _preferences = RobotPreferences.instance;
  late final TextEditingController _phrase;
  String _savedPhrase = '';
  String? _error;
  bool? _admin;
  @override
  void initState() {
    super.initState();
    _phrase = TextEditingController(text: _preferences.wakePhrase);
    _preferences.addListener(_syncPhrase);
    _load();
  }

  Future<void> _load() async {
    await _preferences.load();
    _syncPhrase();
    final active = await AndroidStandbyScreen().canSleep();
    if (mounted) setState(() => _admin = active);
  }

  void _syncPhrase() {
    if (_savedPhrase != _preferences.wakePhrase) {
      _savedPhrase = _preferences.wakePhrase;
      _phrase.text = _savedPhrase;
    }
  }

  Future<void> _permission() async {
    try {
      final active = await AndroidStandbyScreen.requestPermission();
      if (mounted) setState(() => _admin = active);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Không cấp được quyền tắt màn hình: $e');
      }
    }
  }

  Future<void> _savePhrase() async {
    if (!WakePhraseTokenizer.valid(_phrase.text)) {
      setState(
        () => _error = 'Nhập 2–5 từ bằng chữ cái tiếng Anh, tối đa 48 ký tự.',
      );
      return;
    }
    await _preferences.update(phrase: _phrase.text.trim());
    if (mounted) {
      setState(() => _error = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã lưu câu gọi “${_preferences.wakePhrase}”.')),
      );
    }
  }

  @override
  void dispose() {
    _preferences.removeListener(_syncPhrase);
    _phrase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _preferences,
    builder: (context, _) {
      final p = _preferences;
      final seconds =
          <int>{60, 120, 300, 600, 1800, p.sleepSeconds}.toList()..sort();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              'Nghỉ và đánh thức',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const Text(
            'Áp dụng khi mở cuộc gọi. Khi nghỉ, âm thanh chỉ dùng nhận từ đánh thức tại robot, không gửi lên máy chủ.',
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tự tắt màn hình khi không tương tác'),
            value: p.autoSleep,
            onChanged: (v) => p.update(sleep: v),
          ),
          DropdownButtonFormField<int>(
            value: p.sleepSeconds,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Thời gian không tương tác',
            ),
            items:
                seconds
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text('${(s / 60).round()} phút'),
                      ),
                    )
                    .toList(),
            onChanged:
                p.autoSleep
                    ? (v) {
                      if (v != null) p.update(sleepAfter: v);
                    }
                    : null,
          ),
          const SizedBox(height: 8),
          Text(
            _admin == true
                ? 'Đã có quyền tắt đèn nền.'
                : 'Cần quyền khóa màn hình để tắt đèn nền thật sự.',
          ),
          if (_admin != true)
            OutlinedButton(
              onPressed: _permission,
              child: const Text('Cho phép tắt màn hình'),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Đánh thức bằng giọng nói'),
            subtitle: const Text(
              'Nhận tại máy. Khi tắt mục này, dùng nút nguồn để bật lại màn hình.',
            ),
            value: p.wakeWordEnabled,
            onChanged: (v) => p.update(wakeEnabled: v),
          ),
          TextField(
            controller: _phrase,
            decoration: InputDecoration(
              labelText: 'Câu gọi đánh thức',
              hintText: 'Hey Doredino',
              helperText:
                  'Tùy chọn 2–5 từ bằng chữ cái tiếng Anh, ví dụ Hello Robot. Chưa hỗ trợ câu tiếng Việt có dấu.',
              helperMaxLines: 4,
              errorText: _error,
            ),
            textCapitalization: TextCapitalization.words,
            maxLength: 48,
            onSubmitted: (_) => _savePhrase(),
          ),
          OutlinedButton(
            onPressed: _savePhrase,
            child: const Text('Lưu câu gọi đánh thức'),
          ),
          DropdownButtonFormField<WakeSensitivity>(
            value: p.wakeSensitivity,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Độ nhạy từ đánh thức',
            ),
            items: const [
              DropdownMenuItem(
                value: WakeSensitivity.low,
                child: Text('Thấp — hạn chế thức nhầm'),
              ),
              DropdownMenuItem(
                value: WakeSensitivity.normal,
                child: Text('Bình thường'),
              ),
              DropdownMenuItem(
                value: WakeSensitivity.high,
                child: Text('Cao — dễ gọi hơn'),
              ),
            ],
            onChanged:
                p.wakeWordEnabled
                    ? (v) {
                      if (v != null) p.update(wakeSense: v);
                    }
                    : null,
          ),
          const Text(
            'Gọi từ đánh thức, đợi mặt sáng rồi nói yêu cầu. Chạm hoặc nói trong cuộc gọi sẽ tính lại thời gian nghỉ.',
          ),
        ],
      );
    },
  );
}
