import 'package:flutter/services.dart';

/// Metadata-only camera boundary. This bridge never transports image bytes,
/// filesystem paths, provider secrets, or robot movement commands.
class VisionSnapshot {
  final String reference;
  final int width;
  final int height;
  final int bytes;
  final int rotation;
  final DateTime capturedAt;
  final DateTime expiresAt;

  const VisionSnapshot._({
    required this.reference,
    required this.width,
    required this.height,
    required this.bytes,
    required this.rotation,
    required this.capturedAt,
    required this.expiresAt,
  });

  String get mimeType => 'image/jpeg';
  bool get canMove => false;

  factory VisionSnapshot.fromMap(Map<Object?, Object?> data) {
    final reference = data['reference'];
    final width = data['width'];
    final height = data['height'];
    final bytes = data['bytes'];
    final rotation = data['rotation'];
    final captured = data['capturedAt'];
    final expires = data['expiresAt'];
    if (reference is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(reference) ||
        data['mimeType'] != 'image/jpeg' ||
        data['canMove'] != false ||
        width is! int ||
        height is! int ||
        width <= 0 ||
        height <= 0 ||
        width > 1920 ||
        height > 1920 ||
        width * height > 1920 * 1080 ||
        bytes is! int ||
        bytes <= 0 ||
        bytes > 2 * 1024 * 1024 ||
        rotation is! int ||
        !const [0, 90, 180, 270].contains(rotation) ||
        captured is! int ||
        expires is! int ||
        captured < 0 ||
        expires <= captured ||
        expires - captured > 60000 ||
        expires > 8640000000000000) {
      throw const VisionCameraException('invalid_metadata');
    }
    return VisionSnapshot._(
      reference: reference,
      width: width,
      height: height,
      bytes: bytes,
      rotation: rotation,
      capturedAt: DateTime.fromMillisecondsSinceEpoch(captured, isUtc: true),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expires, isUtc: true),
    );
  }
}

/// Contains only a stable code, never the native exception message/details.
class VisionCameraException implements Exception {
  final String code;
  const VisionCameraException(this.code);

  @override
  String toString() => 'VisionCameraException($code)';
}

class VisionCamera {
  static const _methods = MethodChannel('visbot/vision');
  static const _events = EventChannel('visbot/vision/events');

  /// Native rejects enabled=true unless a recent PIN authorization is consumed.
  Future<void> setConsent(bool enabled) =>
      _invoke<void>('setConsent', {'enabled': enabled});

  Future<bool> get pinConfigured async {
    final status = await _invoke<Map<Object?, Object?>>('getParentGateStatus');
    return status?['pinConfigured'] == true;
  }

  /// Initial enrollment trusts local access to Settings; changes require current PIN.
  Future<void> configureParentPin(String newPin, {String? currentPin}) =>
      _invoke<void>('configureParentPin', {
        'newPin': newPin,
        if (currentPin != null) 'currentPin': currentPin,
      });

  Future<void> authorizeParentPin(String pin) =>
      _invoke<void>('authorizeParentPin', {'pin': pin});

  Stream<VisionCameraEvent> get events => _events.receiveBroadcastStream().map(
    (raw) => VisionCameraEvent.fromMap(raw),
  );

  /// Does not request Android permission or open a camera.
  Future<Map<Object?, Object?>> getCapabilities() async =>
      await _invoke<Map<Object?, Object?>>('getCapabilities') ?? const {};

  /// Requires explicit parent action, permission and native foreground checks.
  Future<void> startPrewarm() => _invoke<void>('startPrewarm');

  Future<VisionSnapshot> captureSnapshot(String requestId) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(requestId)) {
      throw const VisionCameraException('invalid_request');
    }
    final result = await _invoke<Map<Object?, Object?>>('captureSnapshot', {
      'requestId': requestId,
    });
    if (result == null) {
      throw const VisionCameraException('invalid_metadata');
    }
    return VisionSnapshot.fromMap(result);
  }

  Future<void> cancel(String requestId) =>
      _invoke<void>('cancel', {'requestId': requestId});

  Future<void> deleteSnapshot(String reference) =>
      _invoke<void>('deleteSnapshot', {'reference': reference});

  Future<void> cleanupStaleSnapshots() =>
      _invoke<void>('cleanupStaleSnapshots');

  Future<void> close() => _invoke<void>('close');

  Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _methods.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      throw const VisionCameraException('unavailable');
    } on PlatformException catch (error) {
      // Never propagate camera/vendor paths or error messages into UI/MCP.
      const safeCodes = {
        'permission_denied',
        'consent_required',
        'not_foreground',
        'screen_off',
        'camera_busy',
        'camera_unavailable',
        'camera_capture',
        'camera_timeout',
        'cancelled',
        'invalid_request',
        'reference_unavailable',
        'storage_error',
        'unavailable',
        'parent_auth_required',
        'pin_required',
        'pin_not_configured',
        'pin_invalid',
        'pin_locked',
        'invalid_pin',
        'pin_storage',
      };
      throw VisionCameraException(
        safeCodes.contains(error.code) ? error.code : 'camera_error',
      );
    }
  }
}

class VisionCameraEvent {
  final String state;
  final DateTime? expiresAt;
  final DateTime? idleExpiresAt;

  const VisionCameraEvent(this.state, this.expiresAt, this.idleExpiresAt);

  factory VisionCameraEvent.fromMap(Object? raw) {
    if (raw is! Map) throw const VisionCameraException('invalid_metadata');
    final state = raw['state'];
    if (state is! String ||
        !const {
          'closed',
          'opening',
          'warming',
          'ready',
          'capturing',
          'error',
        }.contains(state)) {
      throw const VisionCameraException('invalid_metadata');
    }
    DateTime? date(Object? value) =>
        value is int && value > 0
            ? DateTime.fromMillisecondsSinceEpoch(value)
            : null;
    return VisionCameraEvent(
      state,
      date(raw['expiresAt']),
      date(raw['idleExpiresAt']),
    );
  }
}
