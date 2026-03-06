import 'package:flutter/foundation.dart';

/// Local debug logs to the console (visible when running with `flutter run`).
/// Uses [debugPrint] so output appears in debug/profile mode.
void debugLog(String tag, String message) {
  if (kDebugMode) {
    debugPrint('[$tag] $message');
  }
}
