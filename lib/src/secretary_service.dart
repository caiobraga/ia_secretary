// Platform-specific voice service: full implementation on Android/iOS/desktop (dart:io),
// stub (speech_to_text only) on web to avoid dart:ffi and native plugins.
export 'secretary_service_io.dart' if (dart.library.html) 'secretary_service_stub.dart';
