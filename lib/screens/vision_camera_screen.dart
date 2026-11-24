import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/vision/vision_camera.dart';

/// Parent-only local camera lab. No image preview, AI call, upload or child MCP.
class VisionCameraScreen extends StatefulWidget {
  final VisionCamera? camera;
  final Future<bool> Function()? requestPermission;

  const VisionCameraScreen({super.key, this.camera, this.requestPermission});

  @override
  State<VisionCameraScreen> createState() => _VisionCameraScreenState();
}

class _VisionCameraScreenState extends State<VisionCameraScreen>
    with WidgetsBindingObserver {
  static const _optInKey = 'vision_parent_lab_opt_in';
  late final VisionCamera _camera = widget.camera ?? VisionCamera();
  final _pin = TextEditingController();
  final _currentPin = TextEditingController();
  StreamSubscription<VisionCameraEvent>? _events;
  Timer? _countdown;
  bool _configured = false;
  bool _optIn = false;
  bool _authorized = false;
  bool _busy = false;
  bool _active = false;
  String _state = 'closed';
  String _message =
      'Ảnh chỉ được lưu tạm trên thiết bị. Không tải lên; AI chưa khả dụng.';
  String? _cleanupFailure;
  DateTime? _expires;
  DateTime? _idleExpires;
  int _operation = 0;
  Future<void>? _stopInFlight;
  int _remaining = 0;
  int _idleRemaining = 0;
  VisionSnapshot? _last;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _events = _camera.events.listen(
      _onEvent,
      onError: (Object _) {
        if (mounted) setState(() => _state = 'error');
      },
    );
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configured = await _camera.pinConfigured;
      if (!mounted) return;
      setState(() {
        _configured = configured;
        _optIn = prefs.getBool(_optInKey) ?? false;
      });
    } on VisionCameraException {
      if (mounted) {
        setState(() => _message = 'Không thể đọc cổng PIN trên thiết bị.');
      }
    }
  }

  void _onEvent(VisionCameraEvent event) {
    // A closing session or a failed cleanup owns the visible state until the
    // native method result confirms it; late events must not clear that notice.
    if (!mounted || _cleanupFailure != null || _state == 'stopping') return;
    setState(() {
      _state = event.state;
      _expires = event.expiresAt;
      _idleExpires = event.idleExpiresAt;
      if (event.state == 'closed' || event.state == 'error') _active = false;
    });
    _tick();
  }

  void _tick() {
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      _remaining =
          _expires == null
              ? 0
              : (_expires!.difference(now).inSeconds + 1).clamp(0, 60);
      _idleRemaining =
          _idleExpires == null
              ? 0
              : (_idleExpires!.difference(now).inSeconds + 1).clamp(0, 30);
    });
  }

  Future<void> _toggleOptIn(bool enabled) async {
    if (!enabled) await _stop();
    if (_cleanupFailure != null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_optInKey, enabled);
    if (mounted) setState(() => _optIn = enabled);
  }

  Future<void> _enrollOrChange() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _camera.configureParentPin(
        _pin.text,
        currentPin: _configured ? _currentPin.text : null,
      );
      if (mounted) {
        setState(() {
          _configured = true;
          _authorized = false;
          _cleanupFailure = null;
          _message = 'PIN đã lưu. Hãy nhập PIN để mở từng cửa sổ camera.';
        });
      }
    } on VisionCameraException catch (error) {
      _showError(error);
    } finally {
      _pin.clear();
      _currentPin.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _authorize() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _camera.authorizeParentPin(_pin.text);
      if (mounted) {
        setState(() {
          _authorized = true;
          _cleanupFailure = null;
          _message = 'Đã xác nhận PIN. Bấm mở camera để xin quyền và bắt đầu.';
        });
      }
    } on VisionCameraException catch (error) {
      _showError(error);
    } finally {
      _pin.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _permission() async =>
      widget.requestPermission?.call() ??
      (await Permission.camera.request()).isGranted;

  Future<void> _start() async {
    if (!_optIn || !_configured || !_authorized || _busy || _active) return;
    final operation = ++_operation;
    // Mount the visible indicator before requesting runtime permission/opening.
    setState(() {
      _busy = true;
      _active = true;
      _state = 'opening';
    });
    await WidgetsBinding.instance.endOfFrame;
    try {
      if (!await _permission()) {
        throw const VisionCameraException('permission_denied');
      }
      if (!mounted || operation != _operation) return;
      await _camera.setConsent(true); // Native consumes one recent PIN grant.
      if (!mounted || operation != _operation) {
        // A lifecycle stop or disposal already owns cleanup and its warning.
        return;
      }
      await _camera.startPrewarm();
      if (!mounted || operation != _operation) {
        return;
      }
      setState(() {
        _authorized = false;
        _message =
            'Camera chỉ hoạt động tối đa 60 giây; tự đóng khi rảnh 30 giây.';
      });
    } on VisionCameraException catch (error) {
      _showError(error);
      await _stop();
    } finally {
      if (mounted && operation == _operation) {
        setState(() {
          _busy = false;
          if (_state == 'closed' || _state == 'error') _active = false;
        });
      }
    }
  }

  Future<void> _capture() async {
    if (!_active || _busy || _state != 'ready') return;
    setState(() => _busy = true);
    final operation = _operation;
    try {
      final snapshot = await _camera.captureSnapshot(
        'lab_${DateTime.now().microsecondsSinceEpoch}',
      );
      await _camera.deleteSnapshot(snapshot.reference);
      if (mounted && operation == _operation) {
        setState(() {
          _last = snapshot;
          _message = 'Đã chụp và xóa ảnh tạm. Không tải lên hoặc phân tích AI.';
        });
      }
    } on VisionCameraException catch (error) {
      if (error.code == 'storage_error') {
        _showCleanupFailure('Không xác nhận được xóa ảnh tạm.');
      } else {
        _showError(error);
      }
      await _stop();
    } finally {
      if (mounted && operation == _operation) setState(() => _busy = false);
    }
  }

  Future<void> _safeClose() async {
    VisionCameraException? failure;
    try {
      await _camera.close();
    } on VisionCameraException catch (error) {
      failure = error;
    }
    try {
      await _camera.setConsent(false);
    } on VisionCameraException catch (error) {
      failure ??= error;
    }
    if (failure != null) throw failure;
  }

  Future<void> _stop() {
    if (_stopInFlight != null) return _stopInFlight!;
    final operation = _finishStop();
    _stopInFlight = operation;
    unawaited(operation.whenComplete(() => _stopInFlight = null));
    return operation;
  }

  Future<void> _finishStop() async {
    ++_operation;
    if (mounted) {
      setState(() {
        _authorized = false;
        _state = 'stopping';
        _busy = true;
      });
    }
    try {
      await _safeClose();
      if (mounted) {
        setState(() {
          _active = false;
          _state = 'closed';
          _expires = null;
          _idleExpires = null;
          _busy = false;
          _cleanupFailure = null;
          _message =
              'Đã xác nhận đóng camera và dọn dẹp ảnh tạm trên thiết bị.';
        });
      }
    } on VisionCameraException {
      _showCleanupFailure(
        'Không thể xác nhận đã đóng camera hoặc xóa ảnh tạm. '
        'Không mở lại; thử dừng lần nữa.',
      );
    }
  }

  void _showCleanupFailure(String warning) {
    if (!mounted) return;
    setState(() {
      _cleanupFailure = warning;
      _message = warning;
      _active = true;
      _state = 'cleanup_failed';
      _busy = false;
    });
  }

  void _showError(VisionCameraException error) {
    if (!mounted) return;
    final text = switch (error.code) {
      'pin_locked' => 'Sai PIN nhiều lần. Vui lòng chờ trước khi thử lại.',
      'pin_invalid' ||
      'pin_required' => 'PIN hiện tại không đúng hoặc còn thiếu.',
      'permission_denied' =>
        'Chưa cấp quyền CAMERA. Chỉ xin quyền sau khi nhập PIN.',
      'parent_auth_required' => 'Xác nhận PIN đã hết hạn. Hãy nhập lại.',
      _ => 'Không thể tiếp tục (${error.code}). Camera không gửi ảnh đi.',
    };
    setState(() => _message = text);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(_stop());
    }
  }

  @override
  void dispose() {
    ++_operation;
    WidgetsBinding.instance.removeObserver(this);
    _countdown?.cancel();
    unawaited(_events?.cancel());
    _pin.dispose();
    _currentPin.dispose();
    unawaited(
      _safeClose().then(
        (_) {},
        onError: (Object _) {
          // Route is gone; native lifecycle also revokes. No success is claimed.
        },
      ),
    );
    super.dispose();
  }

  Widget _pinField(TextEditingController controller, String label) => TextField(
    controller: controller,
    obscureText: true,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    maxLength: 12,
    decoration: InputDecoration(labelText: label, counterText: ''),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Camera phụ huynh — thử nghiệm cục bộ')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Thiết lập PIN lần đầu tin người đang cầm thiết bị và mở Cài đặt. '
          'Đây không phải xác thực tài khoản phụ huynh từ xa. Nếu quên PIN, '
          'chưa có cách đặt lại an toàn. Không dùng ảnh trẻ em trong thử nghiệm.',
        ),
        const SizedBox(height: 12),
        Text(_message, key: const Key('vision-disclosure')),
        if (_configured)
          SwitchListTile(
            title: const Text('Cho phép chế độ thử camera trên thiết bị'),
            subtitle: const Text(
              'Không tự mở camera khi khởi động lại ứng dụng.',
            ),
            value: _optIn,
            onChanged: _busy ? null : _toggleOptIn,
          ),
        if (_configured) _pinField(_currentPin, 'PIN hiện tại (khi đổi PIN)'),
        _pinField(
          _pin,
          _configured ? 'PIN mới hoặc PIN để xác nhận' : 'Tạo PIN 6–12 chữ số',
        ),
        ElevatedButton(
          onPressed: _busy ? null : _enrollOrChange,
          child: Text(
            _configured
                ? 'Đổi PIN (cần PIN hiện tại)'
                : 'Thiết lập PIN trên thiết bị',
          ),
        ),
        if (_configured && _optIn)
          ElevatedButton(
            onPressed: _busy ? null : _authorize,
            child: const Text('Xác nhận PIN cho một lần mở'),
          ),
        if (_optIn && _configured && _authorized)
          const Text(
            'CAMERA SẮP MỞ — chỉ khi bấm nút bên dưới. Không có upload/AI.',
            key: Key('vision-indicator'),
          ),
        if (_active || _state == 'stopping')
          Text(
            _state == 'stopping'
                ? 'CAMERA ĐANG ĐÓNG — chờ xác nhận từ thiết bị; chưa xác nhận xóa.'
                : _cleanupFailure != null
                ? 'CẢNH BÁO CAMERA: $_cleanupFailure'
                : 'CAMERA ĐANG HOẠT ĐỘNG: $_state · còn $_remaining giây · '
                    'rảnh $_idleRemaining giây',
            key: const Key('vision-active-indicator'),
          ),
        if (_optIn && _configured)
          ElevatedButton(
            onPressed: _authorized && !_busy && !_active ? _start : null,
            child: const Text('Mở camera 60 giây'),
          ),
        if (_active)
          ElevatedButton(
            onPressed: !_busy && _state == 'ready' ? _capture : null,
            child: const Text('Chụp một ảnh thử — xóa ngay'),
          ),
        if (_active || _state == 'stopping')
          TextButton(
            onPressed: _busy ? null : _stop,
            child: Text(
              _cleanupFailure == null
                  ? 'Dừng camera và xóa ảnh tạm'
                  : 'Thử lại dọn dẹp camera',
            ),
          ),
        if (_last != null)
          Text(
            'Ảnh gần nhất: ${_last!.width}×${_last!.height}, ${_last!.bytes} byte. '
            'Đã yêu cầu xóa; không hiển thị ảnh.',
            key: const Key('vision-metadata'),
          ),
      ],
    ),
  );
}
