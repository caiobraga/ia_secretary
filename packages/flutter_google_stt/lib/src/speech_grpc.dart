import 'package:grpc/grpc.dart';
import 'package:protobuf/protobuf.dart';

// Official Google Cloud Speech-to-Text gRPC implementation using proper protobuf

/// Audio encoding constants (matching protobuf enum values)
class AudioEncoding {
  static const int encodingUnspecified = 0;
  static const int linear16 = 1;
  static const int flac = 2;
  static const int mulaw = 3;
  static const int amr = 4;
  static const int amrWb = 5;
  static const int oggOpus = 6;
  static const int speexWithHeaderByte = 7;
  static const int webmOpus = 9;
  static const int mp3 = 8;

  // Convenience constants for backward compatibility
  // ignore: constant_identifier_names
  static const int LINEAR16 = linear16;
}

/// Protobuf message for RecognitionConfig
class RecognitionConfig extends GeneratedMessage {
  static final BuilderInfo _i =
      BuilderInfo(
          'RecognitionConfig',
          package: const PackageName('google.cloud.speech.v1'),
          createEmptyInstance: create,
        )
        ..a<int>(
          1,
          'encoding',
          PbFieldType.O3,
          defaultOrMaker: AudioEncoding.encodingUnspecified,
        )
        ..a<int>(2, 'sampleRateHertz', PbFieldType.O3)
        ..aOS(3, 'languageCode')
        ..aOB(11, 'enableAutomaticPunctuation')
        ..aOS(13, 'model');

  RecognitionConfig._() : super();

  factory RecognitionConfig({
    int? encoding,
    int? sampleRateHertz,
    String? languageCode,
    bool? enableAutomaticPunctuation,
    String? model,
  }) {
    final result = create();
    if (encoding != null) {
      result.encoding = encoding;
    }
    if (sampleRateHertz != null) {
      result.sampleRateHertz = sampleRateHertz;
    }
    if (languageCode != null) {
      result.languageCode = languageCode;
    }
    if (enableAutomaticPunctuation != null) {
      result.enableAutomaticPunctuation = enableAutomaticPunctuation;
    }
    if (model != null) {
      result.model = model;
    }
    return result;
  }

  factory RecognitionConfig.fromBuffer(List<int> i) =>
      create()..mergeFromBuffer(i);

  static RecognitionConfig? _defaultInstance;
  static RecognitionConfig get defaultInstance => _defaultInstance ??= create();
  static RecognitionConfig create() => RecognitionConfig._();

  @override
  RecognitionConfig createEmptyInstance() => create();

  @override
  RecognitionConfig clone() => RecognitionConfig()..mergeFromMessage(this);

  @override
  BuilderInfo get info_ => _i;

  int get encoding => $_getIZ(0);
  set encoding(int v) => setField(1, v);

  int get sampleRateHertz => $_getIZ(1);
  set sampleRateHertz(int v) => $_setSignedInt32(1, v);

  String get languageCode => $_getSZ(2);
  set languageCode(String v) => $_setString(2, v);

  bool get enableAutomaticPunctuation => $_getBF(3);
  set enableAutomaticPunctuation(bool v) => $_setBool(3, v);

  String get model => $_getSZ(4);
  set model(String v) => $_setString(4, v);
}

/// Protobuf message for StreamingRecognitionConfig
class StreamingRecognitionConfig extends GeneratedMessage {
  static final BuilderInfo _i =
      BuilderInfo(
          'StreamingRecognitionConfig',
          package: const PackageName('google.cloud.speech.v1'),
          createEmptyInstance: create,
        )
        ..aOM<RecognitionConfig>(
          1,
          'config',
          subBuilder: RecognitionConfig.create,
        )
        ..aOB(2, 'interimResults');

  StreamingRecognitionConfig._() : super();

  factory StreamingRecognitionConfig({
    RecognitionConfig? config,
    bool? interimResults,
  }) {
    final result = create();
    if (config != null) {
      result.config = config;
    }
    if (interimResults != null) {
      result.interimResults = interimResults;
    }
    return result;
  }

  factory StreamingRecognitionConfig.fromBuffer(List<int> i) =>
      create()..mergeFromBuffer(i);

  static StreamingRecognitionConfig? _defaultInstance;
  static StreamingRecognitionConfig get defaultInstance =>
      _defaultInstance ??= create();
  static StreamingRecognitionConfig create() => StreamingRecognitionConfig._();

  @override
  StreamingRecognitionConfig createEmptyInstance() => create();

  @override
  StreamingRecognitionConfig clone() =>
      StreamingRecognitionConfig()..mergeFromMessage(this);

  @override
  BuilderInfo get info_ => _i;

  RecognitionConfig get config => $_getN(0);
  set config(RecognitionConfig v) => setField(1, v);

  bool get interimResults => $_getBF(1);
  set interimResults(bool v) => $_setBool(1, v);
}

/// Protobuf message for StreamingRecognizeRequest
class StreamingRecognizeRequest extends GeneratedMessage {
  static final BuilderInfo _i =
      BuilderInfo(
          'StreamingRecognizeRequest',
          package: const PackageName('google.cloud.speech.v1'),
          createEmptyInstance: create,
        )
        ..aOM<StreamingRecognitionConfig>(
          1,
          'streamingConfig',
          subBuilder: StreamingRecognitionConfig.create,
        )
        ..a<List<int>>(2, 'audioContent', PbFieldType.OY);

  StreamingRecognizeRequest._() : super();

  factory StreamingRecognizeRequest({
    StreamingRecognitionConfig? streamingConfig,
    List<int>? audioContent,
  }) {
    final result = create();
    if (streamingConfig != null) {
      result.streamingConfig = streamingConfig;
    }
    if (audioContent != null) {
      result.audioContent = audioContent;
    }
    return result;
  }

  factory StreamingRecognizeRequest.fromBuffer(List<int> i) =>
      create()..mergeFromBuffer(i);

  static StreamingRecognizeRequest? _defaultInstance;
  static StreamingRecognizeRequest get defaultInstance =>
      _defaultInstance ??= create();
  static StreamingRecognizeRequest create() => StreamingRecognizeRequest._();

  @override
  StreamingRecognizeRequest createEmptyInstance() => create();

  @override
  StreamingRecognizeRequest clone() =>
      StreamingRecognizeRequest()..mergeFromMessage(this);

  @override
  BuilderInfo get info_ => _i;

  StreamingRecognitionConfig get streamingConfig => $_getN(0);
  set streamingConfig(StreamingRecognitionConfig v) => setField(1, v);

  List<int> get audioContent => $_getN(1);
  set audioContent(List<int> v) => $_setBytes(1, v);
}

/// Protobuf message for SpeechRecognitionAlternative
class SpeechRecognitionAlternative extends GeneratedMessage {
  static final BuilderInfo _i =
      BuilderInfo(
          'SpeechRecognitionAlternative',
          package: const PackageName('google.cloud.speech.v1'),
          createEmptyInstance: create,
        )
        ..aOS(1, 'transcript')
        ..a<double>(2, 'confidence', PbFieldType.OF);

  SpeechRecognitionAlternative._() : super();

  factory SpeechRecognitionAlternative({
    String? transcript,
    double? confidence,
  }) {
    final result = create();
    if (transcript != null) {
      result.transcript = transcript;
    }
    if (confidence != null) {
      result.confidence = confidence;
    }
    return result;
  }

  factory SpeechRecognitionAlternative.fromBuffer(List<int> i) =>
      create()..mergeFromBuffer(i);

  static SpeechRecognitionAlternative? _defaultInstance;
  static SpeechRecognitionAlternative get defaultInstance =>
      _defaultInstance ??= create();
  static SpeechRecognitionAlternative create() =>
      SpeechRecognitionAlternative._();

  @override
  SpeechRecognitionAlternative createEmptyInstance() => create();

  @override
  SpeechRecognitionAlternative clone() =>
      SpeechRecognitionAlternative()..mergeFromMessage(this);

  @override
  BuilderInfo get info_ => _i;

  String get transcript => $_getSZ(0);
  set transcript(String v) => $_setString(0, v);

  double get confidence => $_getN(1);
  set confidence(double v) => $_setFloat(1, v);
}

/// Protobuf message for StreamingRecognitionResult
class StreamingRecognitionResult extends GeneratedMessage {
  static final BuilderInfo _i =
      BuilderInfo(
          'StreamingRecognitionResult',
          package: const PackageName('google.cloud.speech.v1'),
          createEmptyInstance: create,
        )
        ..pc<SpeechRecognitionAlternative>(
          1,
          'alternatives',
          PbFieldType.PM,
          subBuilder: SpeechRecognitionAlternative.create,
        )
        ..aOB(2, 'isFinal')
        ..a<double>(3, 'stability', PbFieldType.OF);

  StreamingRecognitionResult._() : super();

  factory StreamingRecognitionResult({
    Iterable<SpeechRecognitionAlternative>? alternatives,
    bool? isFinal,
    double? stability,
  }) {
    final result = create();
    if (alternatives != null) {
      result.alternatives.addAll(alternatives);
    }
    if (isFinal != null) {
      result.isFinal = isFinal;
    }
    if (stability != null) {
      result.stability = stability;
    }
    return result;
  }

  factory StreamingRecognitionResult.fromBuffer(List<int> i) =>
      create()..mergeFromBuffer(i);

  static StreamingRecognitionResult? _defaultInstance;
  static StreamingRecognitionResult get defaultInstance =>
      _defaultInstance ??= create();
  static StreamingRecognitionResult create() => StreamingRecognitionResult._();

  @override
  StreamingRecognitionResult createEmptyInstance() => create();

  @override
  StreamingRecognitionResult clone() =>
      StreamingRecognitionResult()..mergeFromMessage(this);

  @override
  BuilderInfo get info_ => _i;

  List<SpeechRecognitionAlternative> get alternatives => $_getList(0);

  bool get isFinal => $_getBF(1);
  set isFinal(bool v) => $_setBool(1, v);

  double get stability => $_getN(2);
  set stability(double v) => $_setFloat(2, v);
}

/// Protobuf message for gRPC Status
class Status extends GeneratedMessage {
  static final BuilderInfo _i =
      BuilderInfo(
          'Status',
          package: const PackageName('google.rpc'),
          createEmptyInstance: create,
        )
        ..a<int>(1, 'code', PbFieldType.O3)
        ..aOS(2, 'message');

  Status._() : super();

  factory Status({int? code, String? message}) {
    final result = create();
    if (code != null) {
      result.code = code;
    }
    if (message != null) {
      result.message = message;
    }
    return result;
  }

  factory Status.fromBuffer(List<int> i) => create()..mergeFromBuffer(i);

  static Status? _defaultInstance;
  static Status get defaultInstance => _defaultInstance ??= create();
  static Status create() => Status._();

  @override
  Status createEmptyInstance() => create();

  @override
  Status clone() => Status()..mergeFromMessage(this);

  @override
  BuilderInfo get info_ => _i;

  int get code => $_getIZ(0);
  set code(int v) => $_setSignedInt32(0, v);

  String get message => $_getSZ(1);
  set message(String v) => $_setString(1, v);
}

/// Protobuf message for StreamingRecognizeResponse
class StreamingRecognizeResponse extends GeneratedMessage {
  static final BuilderInfo _i =
      BuilderInfo(
          'StreamingRecognizeResponse',
          package: const PackageName('google.cloud.speech.v1'),
          createEmptyInstance: create,
        )
        ..aOM<Status>(1, 'error', subBuilder: Status.create)
        ..pc<StreamingRecognitionResult>(
          2,
          'results',
          PbFieldType.PM,
          subBuilder: StreamingRecognitionResult.create,
        );

  StreamingRecognizeResponse._() : super();

  factory StreamingRecognizeResponse({
    Status? error,
    Iterable<StreamingRecognitionResult>? results,
  }) {
    final result = create();
    if (error != null) {
      result.error = error;
    }
    if (results != null) {
      result.results.addAll(results);
    }
    return result;
  }

  factory StreamingRecognizeResponse.fromBuffer(List<int> i) =>
      create()..mergeFromBuffer(i);

  static StreamingRecognizeResponse? _defaultInstance;
  static StreamingRecognizeResponse get defaultInstance =>
      _defaultInstance ??= create();
  static StreamingRecognizeResponse create() => StreamingRecognizeResponse._();

  @override
  StreamingRecognizeResponse createEmptyInstance() => create();

  @override
  StreamingRecognizeResponse clone() =>
      StreamingRecognizeResponse()..mergeFromMessage(this);

  @override
  BuilderInfo get info_ => _i;

  Status get error => $_getN(0);
  set error(Status v) => setField(1, v);
  bool hasError() => $_has(0);

  List<StreamingRecognitionResult> get results => $_getList(1);
}

/// Official gRPC client for Google Cloud Speech-to-Text API
class SpeechClient extends Client {
  static final _$streamingRecognize =
      ClientMethod<StreamingRecognizeRequest, StreamingRecognizeResponse>(
        '/google.cloud.speech.v1.Speech/StreamingRecognize',
        (StreamingRecognizeRequest value) => value.writeToBuffer(),
        (List<int> value) => StreamingRecognizeResponse.fromBuffer(value),
      );

  SpeechClient(super.channel, {super.options});

  ResponseStream<StreamingRecognizeResponse> streamingRecognize(
    Stream<StreamingRecognizeRequest> request, {
    CallOptions? options,
  }) {
    return $createStreamingCall(
      _$streamingRecognize,
      request,
      options: options,
    );
  }
}
