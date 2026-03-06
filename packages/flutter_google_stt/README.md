# Flutter Google Speech-to-Text Plugin

A Flutter plugin for real-time speech-to-text using Google Cloud Speech-to-Text API with native gRPC streaming. This plugin supports both Android (Kotlin) and iOS (Swift) platforms with native audio recording and continuous transcription capabilities.

## ✨ Key Features

- 🚀 **Native gRPC Streaming**: Direct protobuf-based communication with Google Cloud Speech-to-Text
- 📱 **Cross-platform Support**: Native Android (Kotlin) & iOS (Swift) implementations  
- 🎤 **Continuous Audio Processing**: Real-time bidirectional streaming
- ⚡ **Ultra-Low Latency**: Optimal performance with direct gRPC protocol
- 🧠 **Enhanced AI Models**: Uses Google's `latest_long` model with improved accuracy
- 🔒 **Secure Authentication**: Google Cloud access token-based authentication
- 📝 **Automatic Punctuation**: Enhanced readability with smart punctuation
- 🎯 **Production Ready**: Clean, optimized codebase for production deployment

## 🆕 v2.0.0 - gRPC Architecture

This version introduces a major architectural improvement with **native gRPC streaming** replacing the previous WebSocket implementation:

- **Direct Protocol Communication**: Native protobuf messages for optimal performance
- **Bidirectional Streaming**: Real-time audio streaming with immediate results
- **Improved Efficiency**: Eliminated intermediate WebSocket layer
- **Better Error Handling**: Enhanced connection management and error reporting
- **Production Optimized**: Removed debug logging and unnecessary dependencies

## Installation

Add this plugin to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_google_stt: ^2.0.0
  # Or use the latest version from pub.dev
```

Run `flutter pub get` to install the package.

## Quick Start

1. **Get a Google Cloud Access Token** (see Google Cloud Setup section below)
2. **Add the plugin** to your pubspec.yaml
3. **Initialize the plugin** with your access token
4. **Start listening** for speech input

```dart
import 'package:flutter_google_stt/flutter_google_stt.dart';

// Initialize
await FlutterGoogleStt.initialize(
  accessToken: 'your-google-cloud-access-token',
  languageCode: 'en-US',
);

// Start listening
await FlutterGoogleStt.startListening((transcript, isFinal) {
  print('Transcript: $transcript (Final: $isFinal)');
});

// Stop listening
await FlutterGoogleStt.stopListening();
```

## Platform Setup

### Android

The plugin automatically handles microphone permissions. Ensure your app's `android/app/src/main/AndroidManifest.xml` includes:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
```

### iOS

Add microphone usage description to your `ios/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for speech recognition</string>
```

## Google Cloud Setup

1. **Create a Google Cloud Project**: Go to [Google Cloud Console](https://console.cloud.google.com/)
2. **Enable the Speech-to-Text API**:
   - Navigate to "APIs & Services" > "Library"
   - Search for "Cloud Speech-to-Text API"
   - Click on it and press "Enable"
3. **Create API Credentials**:
   - Go to "APIs & Services" > "Credentials"
   - Click "Create Credentials" > "API Key"
   - Copy the generated API key
4. **Secure your API Key** (recommended):
   - Click on the API key you created
   - Under "API restrictions", select "Restrict key"
   - Choose "Cloud Speech-to-Text API" from the list
   - Save the changes

### Using API Key vs Access Token

This plugin supports Google Cloud API Key authentication, which is simpler for development:

```dart
// Using API Key (recommended for development)
await FlutterGoogleStt.initialize(
  accessToken: 'your-google-cloud-api-key-here',
  languageCode: 'en-US',
);
```

For production applications, consider using service account authentication with temporary access tokens:

```bash
# Generate access token using gcloud CLI
gcloud auth application-default print-access-token
```

## Usage

### Basic Usage

```dart
import 'package:flutter_google_stt/flutter_google_stt.dart';

class SpeechExample extends StatefulWidget {
  @override
  _SpeechExampleState createState() => _SpeechExampleState();
}

class _SpeechExampleState extends State<SpeechExample> {
  String _transcript = '';
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _initializeSpeech();
  }

  Future<void> _initializeSpeech() async {
    // Replace with your actual Google Cloud API key
    const String apiKey = 'YOUR_GOOGLE_CLOUD_API_KEY_HERE';
    
    try {
      final success = await FlutterGoogleStt.initialize(
        accessToken: apiKey,  // API key is passed as accessToken parameter
        languageCode: 'en-US',
        sampleRateHertz: 16000,
      );
      
      if (success) {
        print('Speech recognition initialized successfully');
      } else {
        print('Failed to initialize speech recognition');
      }
    } catch (e) {
      print('Initialization error: $e');
    }
  }

  Future<void> _startListening() async {
    // Check permissions first
    bool hasPermission = await FlutterGoogleStt.hasMicrophonePermission();
    if (!hasPermission) {
      hasPermission = await FlutterGoogleStt.requestMicrophonePermission();
      if (!hasPermission) {
        print('Microphone permission denied');
        return;
      }
    }

    // Start listening
    try {
      final success = await FlutterGoogleStt.startListening((transcript, isFinal) {
        setState(() {
          _transcript = transcript;
        });
        
        if (isFinal) {
          print('Final transcript: $transcript');
        } else {
          print('Interim transcript: $transcript');
        }
      });
      
      if (success) {
        setState(() {
          _isListening = true;
        });
      }
    } catch (e) {
      print('Error starting listening: $e');
    }
  }

  Future<void> _stopListening() async {
    try {
      final success = await FlutterGoogleStt.stopListening();
      if (success) {
        setState(() {
          _isListening = false;
        });
      }
    } catch (e) {
      print('Error stopping listening: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Speech Recognition')),
      body: Column(
        children: [
          Expanded(
            child: Container(
              padding: EdgeInsets.all(16),
              child: Text(
                _transcript.isEmpty ? 'No speech detected' : _transcript,
                style: TextStyle(fontSize: 18),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: _isListening ? _stopListening : _startListening,
            child: Text(_isListening ? 'Stop' : 'Start'),
          ),
        ],
      ),
    );
  }
}
```

### Advanced Configuration

```dart
// Initialize with custom settings
await FlutterGoogleStt.initialize(
  accessToken: 'your-api-key-here',
  languageCode: 'es-ES',  // Spanish
  sampleRateHertz: 16000, // Standard audio quality
);

// Check if currently listening
bool isListening = await FlutterGoogleStt.isListening();

// Check microphone permission
bool hasPermission = await FlutterGoogleStt.hasMicrophonePermission();

// Request permission if needed
if (!hasPermission) {
  bool granted = await FlutterGoogleStt.requestMicrophonePermission();
}

// Handle transcription results with detailed logging
FlutterGoogleStt.startListening((transcript, isFinal) {
  if (isFinal) {
    // This is the final result for this speech segment
    print('Final: $transcript');
    // Save or process the final transcript
  } else {
    // This is an interim result (may change as user continues speaking)
    print('Interim: $transcript');
    // Update UI with interim results for better UX
  }
});
```

## API Reference

### Methods

#### `initialize({required String accessToken, String languageCode, int sampleRateHertz})`

Initialize the speech recognition service.

- `accessToken` (required): Google Cloud API key or access token
- `languageCode` (optional): Language for recognition (default: 'en-US')
- `sampleRateHertz` (optional): Audio sample rate (default: 16000)

Returns: `Future<bool>` - true if initialization successful

#### `startListening(TranscriptionCallback onTranscript)`

Start listening for speech input.

- `onTranscript`: Callback function that receives transcript and isFinal status

Returns: `Future<bool>` - true if started successfully

#### `stopListening()`

Stop listening for speech input.

Returns: `Future<bool>` - true if stopped successfully

#### `isListening()`

Check if currently listening.

Returns: `Future<bool>` - true if listening

#### `hasMicrophonePermission()`

Check if microphone permission is granted.

Returns: `Future<bool>` - true if permission granted

#### `requestMicrophonePermission()`

Request microphone permission from user.

Returns: `Future<bool>` - true if permission granted

### Types

#### `TranscriptionCallback`

```dart
typedef TranscriptionCallback = void Function(String transcript, bool isFinal);
```

Callback function for receiving transcription results:
- `transcript`: The transcribed text
- `isFinal`: Whether this is the final result (true) or interim (false)

## Supported Languages

The plugin supports all languages supported by Google Cloud Speech-to-Text API. Common language codes:

- English (US): `en-US`
- English (UK): `en-GB`
- Spanish: `es-ES`
- French: `fr-FR`
- German: `de-DE`
- Italian: `it-IT`
- Portuguese: `pt-BR`
- Japanese: `ja-JP`
- Korean: `ko-KR`
- Chinese (Mandarin): `zh-CN`

For a complete list, see [Google Cloud Speech-to-Text Language Support](https://cloud.google.com/speech-to-text/docs/languages).

## Error Handling

The plugin provides detailed error messages for common issues:

```dart
try {
  final success = await FlutterGoogleStt.initialize(
    accessToken: 'your-api-key-here',
  );
  if (!success) {
    print('Failed to initialize speech recognition');
  }
} catch (e) {
  print('Initialization error: $e');
  // Handle specific error cases
  if (e.toString().contains('INVALID_TOKEN')) {
    print('Invalid API key provided');
  } else if (e.toString().contains('NETWORK_ERROR')) {
    print('Network connection issue');
  }
}

try {
  final success = await FlutterGoogleStt.startListening((transcript, isFinal) {
    // Handle transcription
  });
  if (!success) {
    print('Failed to start listening');
  }
} catch (e) {
  print('Start listening error: $e');
  if (e.toString().contains('PERMISSION_DENIED')) {
    print('Microphone permission not granted');
  }
}
```

Common error scenarios:
- `INVALID_TOKEN`: Invalid or expired API key/access token
- `PERMISSION_DENIED`: Missing microphone permissions
- `NETWORK_ERROR`: Network connectivity issues
- `INITIALIZATION_ERROR`: Failed to initialize the plugin
- `START_ERROR`: Failed to start audio recording
- `STOP_ERROR`: Failed to stop audio recording

## Limitations

- **Internet Connection**: Requires active internet connection for Google Cloud API
- **Audio Processing**: Audio is processed in chunks, consuming bandwidth
- **Authentication**: API keys/access tokens need proper management and renewal
- **Platform Differences**: Implementation varies slightly between Android and iOS
- **Audio Quality**: Best results with clear audio and minimal background noise
- **Language Support**: Limited to languages supported by Google Cloud Speech-to-Text API

## Plugin Architecture

- **Package Name**: `com.guptan404.flutter_google_stt`
- **Android Implementation**: Kotlin with REST API integration
- **iOS Implementation**: Swift with REST API integration  
- **Audio Format**: 16-bit PCM, configurable sample rate
- **API Integration**: Google Cloud Speech-to-Text REST API
- **Permission Handling**: Native platform permission requests

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request at [https://github.com/guptan404/flutter_google_stt](https://github.com/guptan404/flutter_google_stt).

### Development Setup

1. Clone the repository
2. Run `flutter pub get` in the root directory
3. Run `cd example && flutter pub get` to setup the example app
4. Test on Android: `flutter build apk --debug`
5. Test on iOS: `flutter build ios --debug`

### Testing

Run the test suite:
```bash
flutter test
flutter analyze
```

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a detailed list of changes.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For issues and feature requests, please use the [GitHub Issues](https://github.com/guptan404/flutter_google_stt/issues) page.

## About

Developed by [@guptan404](https://github.com/guptan404). This plugin provides a clean, production-ready interface for integrating Google Cloud Speech-to-Text API into Flutter applications.

# flutter_google_stt
