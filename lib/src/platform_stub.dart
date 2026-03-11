// Stub for web: dart:io is not available, so Platform is replaced by this.
// Use: import 'src/platform_stub.dart' if (dart.library.io) 'dart:io' show Platform;
bool get _isAndroid => false;
bool get _isIOS => false;

/// Web stub: not Android/iOS, so platform checks are false.
class Platform {
  static bool get isAndroid => _isAndroid;
  static bool get isIOS => _isIOS;
  static bool get isWindows => false;
  static bool get isMacOS => false;
  static bool get isLinux => false;
}
