#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_google_stt.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_google_stt'
  s.version          = '2.0.0'
  s.summary          = 'A Flutter plugin for real-time speech-to-text using Google Cloud Speech-to-Text API via gRPC streaming.'
  s.description      = <<-DESC
A Flutter plugin for real-time speech-to-text using Google Cloud Speech-to-Text API via native gRPC streaming.
Supports both Android and iOS platforms with native audio recording and bidirectional streaming capabilities.
Features production-ready architecture with custom protobuf message definitions for optimal performance.
                       DESC
  s.homepage         = 'https://github.com/guptan404/flutter_google_stt'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Nikhil Gupta' => 'guptan404@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # Privacy manifest for microphone usage
  s.resource_bundles = {'flutter_google_stt_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
