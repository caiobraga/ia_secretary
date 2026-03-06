# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] - 2025-07-18

### iOS Critical Bug Fixes
- **CRITICAL FIX**: Resolved iOS app crashes when starting speech recognition
- **Audio Format Fix**: Fixed iOS audio format compatibility issues that caused crashes on iOS devices and simulator
- **Swift Compilation Fix**: Fixed Swift compiler errors related to immutable value passing
- **iOS Audio Engine**: Improved iOS audio engine setup with proper error handling and native format support
- **Audio Resampling**: Added proper audio resampling logic for iOS to ensure 16kHz compatibility
- **Device Compatibility**: Enhanced iOS device and simulator compatibility

### Improvements
- **Enhanced Error Handling**: Added comprehensive error handling for iOS audio session and engine setup
- **Better Audio Processing**: Improved audio buffer processing with proper format conversion
- **iOS Simulator Support**: Added proper iOS simulator detection and handling
- **Cross-Platform Stability**: Improved overall plugin stability across iOS and Android platforms

## [2.0.0] - 2025-07-18 [RETRACTED]

### Major Architecture Change: gRPC Streaming Implementation
- **BREAKING CHANGE**: Replaced Rest API streaming with native gRPC streaming API
- Implemented Google Cloud Speech-to-Text gRPC streaming API for optimal performance
- Added custom protobuf message definitions for direct Google Cloud API communication
- Real-time bidirectional streaming with immediate results
- Eliminated intermediate WebSocket layer for improved efficiency

### Enhanced Features
- **Native gRPC Communication**: Direct protobuf-based communication with Google Cloud Speech-to-Text
- **Improved Performance**: Reduced latency and improved throughput with native gRPC protocol
- **Better Error Handling**: Enhanced error reporting and connection management
- **Streamlined Architecture**: Simplified codebase with direct API communication
- **Production Ready**: Removed all debug logging for production deployment

### Technical Details
- Updated to gRPC ^4.1.0 and protobuf ^4.1.1 for latest features
- Custom protobuf message classes for Google Cloud Speech-to-Text API
- Bidirectional streaming with StreamController for audio data
- Proper authentication with Google Cloud access tokens
- Cross-platform audio capture with gRPC streaming backend
- Cleaned up unused protobuf generation files and dependencies

### Dependencies
- grpc: ^4.1.0
- protobuf: ^4.1.1
- plugin_platform_interface: ^2.1.8 

### Code Quality
- Removed all debug logging statements
- Cleaned up unused files and dependencies
- Optimized for production deployment
- Improved code maintainability

## [1.0.1] - 2025-07-16 (Deprecated)

### Major Improvement: Streaming Speech Recognition
- **BREAKING CHANGE**: Replaced chunked REST API with real-time WebSocket streaming
- Implemented Google Cloud Speech-to-Text Streaming API for continuous audio transcription
- Added WebSocket connections for both Android (OkHttp) and iOS (URLSessionWebSocketTask)
- Real-time interim results with immediate user feedback
- Improved transcription quality and reduced latency for continuous speech

## [1.0.0] - 2025-07-12

### Added
- **Production Release**: First stable release of Flutter Google Speech-to-Text plugin
- Real-time speech recognition using Google Cloud Speech-to-Text REST API
- Cross-platform support for Android (Kotlin) and iOS (Swift)
- Google Cloud API key authentication support
- Microphone permission handling with native platform requests
- Configurable language codes and audio settings (16kHz PCM audio)
- Clean, production-ready codebase with proper error handling
- Comprehensive API documentation and examples
- Full test coverage with unit and integration tests

### Changed
- **Package Name**: Updated to `com.guptan404.flutter_google_stt`
- **API Implementation**: Uses REST API instead of gRPC for better compatibility
- **Error Handling**: Improved error reporting with specific error codes
- **Code Quality**: Removed debug logs and optimized for production use

### Technical Details
- Android implementation using AudioRecord and OkHttp3
- iOS implementation using AVAudioEngine and URLSession
- Method channel communication between Dart and native platforms
- Support for interim and final transcription results
- Automatic audio chunking and processing

## [0.0.1] - 2025-07-11

### Added
- Initial development release
- Basic speech recognition functionality
- Example app for testing
- Full API documentation and setup instructions

### Features
- `initialize()` method for setting up Google Cloud credentials
- `startListening()` method with real-time transcript callbacks
- `stopListening()` method for ending speech recognition
- `isListening` property to check current state
- `hasMicrophonePermission` and `requestMicrophonePermission` for permission management
- Support for interim and final transcription results
- Error handling with detailed error messages

### Technical Details
- Android: Uses AudioRecord for audio capture and Google Cloud Speech gRPC client
- iOS: Uses AVAudioEngine for audio capture and REST API calls
- Proper audio session management on iOS
- Privacy manifest support for iOS App Store requirements
- Gradle dependencies management for Android
- CocoaPods integration for iOS

### Documentation
- Comprehensive README with setup instructions
- API reference documentation
- Example usage code
- Google Cloud setup guide
- Platform-specific configuration instructions
