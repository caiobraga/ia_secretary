# Quick Start Guide

This guide will help you get started with the Flutter Google Speech-to-Text plugin.

## Prerequisites

1. **Google Cloud Project**: Create a project in [Google Cloud Console](https://console.cloud.google.com/)
2. **Enable Speech-to-Text API**: Enable the Cloud Speech-to-Text API for your project
3. **Service Account**: Create a service account and download the JSON key file
4. **Access Token**: Generate an access token for authentication

## Installation

Add the plugin to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_google_stt: ^0.0.1
```

Run:
```bash
flutter pub get
```

## Platform Setup

### Android
Add permissions to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
```

### iOS
Add microphone usage description to `ios/Runner/Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for speech recognition</string>
```

## Getting Access Token

### Option 1: Using Google Cloud SDK
```bash
gcloud auth application-default print-access-token
```

### Option 2: Programmatically (Recommended for production)
Use the `googleapis_auth` package:

```yaml
dependencies:
  googleapis_auth: ^1.4.1
```

```dart
import 'package:googleapis_auth/auth_io.dart';

Future<String> getAccessToken() async {
  final serviceAccountJson = {
    // Your service account JSON content
  };
  
  final credentials = ServiceAccountCredentials.fromJson(serviceAccountJson);
  final scopes = ['https://www.googleapis.com/auth/cloud-platform'];
  
  final client = await clientViaServiceAccount(credentials, scopes);
  final accessToken = client.credentials.accessToken.data;
  client.close();
  
  return accessToken;
}
```

## Basic Usage

```dart
import 'package:flutter_google_stt/flutter_google_stt.dart';

class MyWidget extends StatefulWidget {
  @override
  _MyWidgetState createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  String _transcript = '';
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _initializeSpeech();
  }

  Future<void> _initializeSpeech() async {
    final accessToken = await getAccessToken(); // Your access token method
    
    await FlutterGoogleStt.initialize(
      accessToken: accessToken,
      languageCode: 'en-US',
      sampleRateHertz: 16000,
    );
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await FlutterGoogleStt.stopListening();
      setState(() => _isListening = false);
    } else {
      // Check permissions
      bool hasPermission = await FlutterGoogleStt.hasMicrophonePermission;
      if (!hasPermission) {
        hasPermission = await FlutterGoogleStt.requestMicrophonePermission();
        if (!hasPermission) return;
      }

      // Start listening
      await FlutterGoogleStt.startListening((transcript, isFinal) {
        setState(() {
          _transcript = transcript;
        });
        
        if (isFinal) {
          print('Final: $transcript');
        }
      });
      
      setState(() => _isListening = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(_transcript),
        ElevatedButton(
          onPressed: _toggleListening,
          child: Text(_isListening ? 'Stop' : 'Start'),
        ),
      ],
    );
  }
}
```

## Testing

Run the example app:
```bash
cd example
flutter run
```

Make sure to replace `YOUR_GOOGLE_CLOUD_ACCESS_TOKEN_HERE` in the example with your actual access token.

## Troubleshooting

### Common Issues

1. **"Invalid access token"**: Make sure your token is valid and hasn't expired
2. **"Permission denied"**: Check microphone permissions
3. **"Network error"**: Verify internet connection and API is enabled
4. **"No audio detected"**: Check device microphone and volume

### Debug Mode

Enable debug logging to see what's happening:
```dart
// Android: Check logcat for debug messages
// iOS: Check Xcode console for debug messages
```

## Next Steps

- Explore different language codes
- Implement token refresh for long-running apps
- Add error handling for production use
- Consider caching and offline scenarios

For more details, see the main [README.md](../README.md) file.
