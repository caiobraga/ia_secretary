import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter_google_stt/flutter_google_stt.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _transcript = 'No speech detected yet...';
  bool _isListening = false;
  bool _isInitialized = false;
  String _status = 'Not initialized';

  @override
  void initState() {
    super.initState();
  }

  Future<void> _initializePlugin() async {
    try {
      // Replace with your actual Google Cloud access token
      const String accessToken = 'YOUR_ACCESS_TOKEN_HERE';

      final bool success = await FlutterGoogleStt.initialize(
        accessToken: accessToken,
        languageCode: 'en-US',
        sampleRateHertz: 16000,
      );

      setState(() {
        _isInitialized = success;
        _status = success ? 'Initialized successfully' : 'Failed to initialize';
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
    }
  }

  Future<void> _startListening() async {
    if (!_isInitialized) {
      await _initializePlugin();
      return;
    }

    // Check and request microphone permission
    bool hasPermission = await FlutterGoogleStt.hasMicrophonePermission;
    if (!hasPermission) {
      hasPermission = await FlutterGoogleStt.requestMicrophonePermission();
      if (!hasPermission) {
        setState(() {
          _status = 'Microphone permission denied';
        });
        return;
      }
    }

    try {
      final bool success = await FlutterGoogleStt.startListening((
        transcript,
        isFinal,
      ) {
        setState(() {
          _transcript = transcript;
          _status = isFinal ? 'Final result' : 'Interim result';
        });
      });

      setState(() {
        _isListening = success;
        if (!success) _status = 'Failed to start listening';
      });
    } catch (e) {
      setState(() {
        _status = 'Error starting listening: $e';
      });
    }
  }

  Future<void> _stopListening() async {
    try {
      final bool success = await FlutterGoogleStt.stopListening();
      setState(() {
        _isListening = false;
        _status = success ? 'Stopped listening' : 'Failed to stop listening';
      });
    } catch (e) {
      setState(() {
        _status = 'Error stopping listening: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Google Speech-to-Text Demo'),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        'Status',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _status,
                        style: TextStyle(
                          color: _isInitialized ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        'Transcript',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 200,
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SingleChildScrollView(
                          child: Text(
                            _transcript,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (!_isInitialized)
                ElevatedButton.icon(
                  onPressed: _initializePlugin,
                  icon: const Icon(Icons.settings),
                  label: const Text('Initialize Plugin'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                )
              else ...[
                ElevatedButton.icon(
                  onPressed: _isListening ? _stopListening : _startListening,
                  icon: Icon(_isListening ? Icons.stop : Icons.mic),
                  label: Text(
                    _isListening ? 'Stop Listening' : 'Start Listening',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isListening ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Note: Replace "YOUR_ACCESS_TOKEN_HERE" in the code with your actual Google Cloud access token.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
