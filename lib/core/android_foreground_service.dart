import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidForegroundService {
  static const MethodChannel _channel = MethodChannel('io.dlwlrma.nrf/foreground_service');

  static Future<void> start({
    String? deviceId,
    String? deviceName,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('start', <String, String?>{
        'deviceId': deviceId,
        'deviceName': deviceName,
      });
    } catch (e) {
      debugPrint('[AndroidForegroundService] start failed: $e');
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (e) {
      debugPrint('[AndroidForegroundService] stop failed: $e');
    }
  }
}
