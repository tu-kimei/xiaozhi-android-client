import 'package:flutter/material.dart';

import '../services/xiaozhi_service.dart';

/// 显示机器人当前是"正在听"还是"已停止听"的状态标签。
class VoiceStateChip extends StatefulWidget {
  final ValueNotifier<XiaozhiVoiceState> state;

  /// 深色背景（语音通话页）时使用白色文字
  final bool onDark;

  const VoiceStateChip({super.key, required this.state, this.onDark = false});

  static ({String label, IconData icon, Color color}) describe(
    XiaozhiVoiceState s,
  ) {
    switch (s) {
      case XiaozhiVoiceState.waiting:
        return (
          label: 'Đang chờ nói',
          icon: Icons.mic_none,
          color: Colors.teal,
        );
      case XiaozhiVoiceState.listening:
        return (label: 'Đang nghe', icon: Icons.mic, color: Colors.green);
      case XiaozhiVoiceState.thinking:
        return (
          label: 'Đã ngừng nghe · đang nghĩ',
          icon: Icons.hourglass_top,
          color: Colors.orange,
        );
      case XiaozhiVoiceState.speaking:
        return (
          label: 'Robot đang nói',
          icon: Icons.volume_up,
          color: Colors.blue,
        );
      case XiaozhiVoiceState.micBusy:
        return (
          label: 'Mic đang bị app khác dùng',
          icon: Icons.mic_external_off,
          color: Colors.red,
        );
      case XiaozhiVoiceState.idle:
        return (
          label: 'Đã ngừng nghe',
          icon: Icons.mic_off,
          color: Colors.grey,
        );
    }
  }

  @override
  State<VoiceStateChip> createState() => _VoiceStateChipState();
}

class _VoiceStateChipState extends State<VoiceStateChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<XiaozhiVoiceState>(
      valueListenable: widget.state,
      builder: (context, s, _) {
        final d = VoiceStateChip.describe(s);
        final active =
            s == XiaozhiVoiceState.listening || s == XiaozhiVoiceState.speaking;
        final textColor = widget.onDark ? Colors.white : d.color.shade700;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color:
                widget.onDark
                    ? d.color.withOpacity(0.35)
                    : d.color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: d.color.withOpacity(0.6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              active
                  ? FadeTransition(
                    opacity: Tween(begin: 0.35, end: 1.0).animate(_pulse),
                    child: Icon(d.icon, size: 15, color: textColor),
                  )
                  : Icon(d.icon, size: 15, color: textColor),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  d.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

extension on Color {
  Color get shade700 =>
      this is MaterialColor ? (this as MaterialColor).shade700 : this;
}
