import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/models/xiaozhi_config.dart';
import 'package:ai_assistant/providers/config_provider.dart';
import 'package:ai_assistant/services/xiaozhi_ota_service.dart';

enum _ActivationState { checking, waitingForCode, success, error }

/// 小智设备激活界面：通过OTA获取激活码，等待用户在 xiaozhi.me 绑定设备
class XiaozhiActivationScreen extends StatefulWidget {
  final XiaozhiConfig config;

  const XiaozhiActivationScreen({super.key, required this.config});

  @override
  State<XiaozhiActivationScreen> createState() =>
      _XiaozhiActivationScreenState();
}

class _XiaozhiActivationScreenState extends State<XiaozhiActivationScreen> {
  static const Duration _pollInterval = Duration(seconds: 5);

  _ActivationState _state = _ActivationState.checking;
  String? _code;
  String? _error;
  Timer? _pollTimer;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _checkVersion();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkVersion() async {
    _pollTimer?.cancel();
    setState(() {
      _state = _ActivationState.checking;
      _error = null;
    });

    try {
      final result = await XiaozhiOtaService.checkVersion(
        otaUrl: widget.config.otaUrl,
        macAddress: widget.config.macAddress,
        clientId: widget.config.clientId,
      );
      if (!mounted) return;

      if (result.needsActivation) {
        setState(() {
          _state = _ActivationState.waitingForCode;
          _code = result.activationCode;
        });
        _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
      } else {
        await _saveResult(result);
      }
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      bool activated;
      try {
        activated = await XiaozhiOtaService.activate(
          otaUrl: widget.config.otaUrl,
          macAddress: widget.config.macAddress,
          clientId: widget.config.clientId,
        );
      } catch (e) {
        // 部分服务器不支持 /activate 接口，退回到重新检查OTA
        print('XiaozhiActivation: activate失败，改为检查OTA: $e');
        activated = true;
      }
      if (!activated || !mounted) return;

      final result = await XiaozhiOtaService.checkVersion(
        otaUrl: widget.config.otaUrl,
        macAddress: widget.config.macAddress,
        clientId: widget.config.clientId,
      );
      if (!mounted || result.needsActivation) return;

      _pollTimer?.cancel();
      await _saveResult(result);
    } catch (e) {
      print('XiaozhiActivation: 轮询失败: $e');
    } finally {
      _polling = false;
    }
  }

  Future<void> _saveResult(XiaozhiOtaResult result) async {
    if (result.websocketUrl == null || result.websocketUrl!.isEmpty) {
      _showError('Máy chủ không trả về địa chỉ WebSocket');
      return;
    }

    await Provider.of<ConfigProvider>(context, listen: false)
        .updateXiaozhiConfig(
          widget.config.copyWith(
            websocketUrl: result.websocketUrl,
            token: result.websocketToken ?? '',
          ),
        );
    if (!mounted) return;

    setState(() => _state = _ActivationState.success);
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) Navigator.pop(context, true);
  }

  void _showError(Object e) {
    if (!mounted) return;
    setState(() {
      _state = _ActivationState.error;
      _error = e.toString().replaceFirst('Exception: ', '');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        toolbarHeight: 40,
        title: const Text('Kích hoạt xiaozhi.me', style: TextStyle(fontSize: 16)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _ActivationState.checking:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Đang kết nối máy chủ...'),
          ],
        );

      case _ActivationState.waitingForCode:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Vào xiaozhi.me → Thêm thiết bị, nhập mã:',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            SelectableText(
              _code ?? '',
              style: const TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
            ),
            const SizedBox(height: 8),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Đang chờ kích hoạt...', style: TextStyle(fontSize: 12)),
              ],
            ),
          ],
        );

      case _ActivationState.success:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 48),
            SizedBox(height: 8),
            Text('Kích hoạt thành công!'),
          ],
        );

      case _ActivationState.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 36),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _checkVersion,
              child: const Text('Thử lại'),
            ),
          ],
        );
    }
  }
}
