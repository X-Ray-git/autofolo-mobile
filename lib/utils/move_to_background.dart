import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class MoveToBackground {
  static const MethodChannel _channel = MethodChannel('com.autofolo/move_to_background');
  
  static Future<void> moveTaskToBack() async {
    try {
      await _channel.invokeMethod('moveTaskToBack');
    } catch (e) {
      debugPrint('Failed to move task to back: $e');
    }
  }
}
