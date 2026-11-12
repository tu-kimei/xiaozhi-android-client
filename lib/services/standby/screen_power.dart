import 'package:flutter/services.dart';

abstract interface class StandbyScreen {
  Future<bool> canSleep();
  Future<void> startLocalListening(String phrase);
  Future<void> stopLocalListening();
  Future<void> sleep();
  Future<void> wake();
}

class AndroidStandbyScreen implements StandbyScreen {
  static const channel = MethodChannel('doradino/screen_power');
  @override
  Future<bool> canSleep() async {
    try {
      return await channel.invokeMethod<bool>('adminActive') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> requestPermission() async =>
      await channel.invokeMethod<bool>('requestAdmin') ?? false;
  @override
  Future<void> startLocalListening(String phrase) =>
      channel.invokeMethod('startWakeListening', {'phrase': phrase});
  @override
  Future<void> stopLocalListening() async {
    try {
      await channel.invokeMethod('stopWakeListening');
    } on MissingPluginException {
      /* Other platforms. */
    }
  }

  @override
  Future<void> sleep() => channel.invokeMethod('sleep');
  @override
  Future<void> wake() => channel.invokeMethod('wake');
}
