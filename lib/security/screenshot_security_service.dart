import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ScreenshotSecurityService {
  static const MethodChannel _channel = MethodChannel(
    'secure_pay/screenshot_security',
  );

  static int _secureUseCount = 0;

  static Future<void> enable() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    _secureUseCount += 1;
    if (_secureUseCount == 1) {
      await _setSecure(true);
    }
  }

  static Future<void> disable() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (_secureUseCount == 0) return;

    _secureUseCount -= 1;
    if (_secureUseCount == 0) {
      await _setSecure(false);
    }
  }

  static Future<void> _setSecure(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setSecureFlag', {'enabled': enabled});
    } on MissingPluginException {
      debugPrint('Screenshot security channel is unavailable.');
    } on PlatformException catch (e) {
      debugPrint('Failed to update screenshot security: ${e.message}');
    }
  }
}
