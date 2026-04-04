import 'dart:async';

import 'src/platform_stub.dart' if (dart.library.io) 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'src/app_foreground.dart';
import 'src/assistant_actions.dart';
import 'src/assistant_screen.dart';
import 'src/remote_listen_indicator.dart';
import 'src/remote_listen_ui_state.dart';
import 'src/auth_screen.dart';
import 'src/config.dart';
import 'src/data_visualization_screen.dart';
import 'src/debug_log.dart';
import 'src/overlay_permission_screen.dart';
import 'src/reminder_notification_service.dart';
import 'src/secretary_service.dart';
import 'src/speech_feedback.dart';
import 'src/voice_commands.dart';

/// Quando o Android abre a Activity pelo full-screen intent, chama showAssistant; o app reage aqui.
final ValueNotifier<bool> showAssistantFromNative = ValueNotifier(false);

/// Segundos de áudio por requisição ao STT remoto (1–15). Menor = texto aparece mais cedo.
double _parseRemoteSttChunkSeconds(String? raw) {
  final v = double.tryParse(raw ?? '');
  // Padrão menor = texto aparece mais cedo (mais requisições ao servidor).
  if (v == null || v.isNaN) return 1.5;
  return v.clamp(1.0, 15.0);
}

/// Timeout HTTP do STT remoto (45–600 s). Primeira transcrição no servidor pode levar minutos (baixar modelo).
int _parseRemoteSttTimeoutSeconds(String? raw) {
  final v = int.tryParse(raw ?? '');
  if (v == null) return 180;
  return v.clamp(45, 600);
}

/// Token OAuth para Google Cloud STT (novo nome ou legado GOOGLE_CLOUD_SPEECH_API_KEY).
String? _googleCloudSpeechToken() {
  final a = dotenv.env['GOOGLE_CLOUD_SPEECH_ACCESS_TOKEN']?.trim();
  if (a != null && a.isNotEmpty) return a;
  final b = dotenv.env['GOOGLE_CLOUD_SPEECH_API_KEY']?.trim();
  if (b != null && b.isNotEmpty) return b;
  return null;
}

// Top-level callback for foreground task (required by plugin).
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(SecretaryTaskHandler());
}

class SecretaryTaskHandler extends TaskHandler {
  @override
  Future onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {}
}

void _initAppTimezone() {
  try {
    tzdata.initializeTimeZones();
    final raw = dotenv.env['APP_TIMEZONE']?.trim();
    final name = (raw != null && raw.isNotEmpty) ? raw : 'America/Sao_Paulo';
    tz.setLocalLocation(tz.getLocation(name));
    debugLog('App', 'timezone local: $name');
  } catch (e) {
    debugLog('App', 'timezone init failed: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env', isOptional: true);
  _initAppTimezone();
  debugLog('App', 'Supabase initializing...');
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  debugLog('App', 'Supabase initialized');
  final localNotifications = FlutterLocalNotificationsPlugin();
  await ReminderNotificationService.initNotifications(localNotifications);
  if (Platform.isAndroid) {
    FlutterForegroundTask.initCommunicationPort();
    debugLog('App', 'Foreground task port initialized');
    const MethodChannel('ia_secretary').setMethodCallHandler((MethodCall call) async {
      if (call.method == 'showAssistant') {
        showAssistantFromNative.value = true;
      }
      return null;
    });
  }
  runApp(const IaSecretaryApp());
}

class IaSecretaryApp extends StatefulWidget {
  const IaSecretaryApp({super.key});

  @override
  State<IaSecretaryApp> createState() => _IaSecretaryAppState();
}

class _IaSecretaryAppState extends State<IaSecretaryApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final SecretaryVoiceService _voiceService;
  late final ReminderNotificationService _reminderService;
  bool _signedIn = false;
  /// Android: null = ainda não verificado, true = concedida, false = negada (mostrar tela).
  bool? _overlayGranted;
  bool _assistantVisible = false;
  bool _showDataVisualization = false;
  String _lastTranscript = '';
  final List<Map<String, String>> _commandResults = [];
  bool _loadingVoskModel = false;
  String? _loadingVoskMessage;
  /// Último comando executado (para contexto: "cancela a primeira" só após listar eventos).
  VoiceCommandType? _lastExecutedCommandType;
  /// True enquanto a Ava está falando (TTS); nesse período a escuta fica pausada.
  bool _avaSpeaking = false;
  /// Feedback visual do STT remoto (gravando / transcrevendo).
  RemoteListenUiState? _remoteListenUi;
  Timer? _remoteRestartAfterBackgroundTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voiceService = SecretaryVoiceService(
      localeId: 'pt_BR',
      preferSystemSpeechToText: dotenv.env['USE_SYSTEM_SPEECH_TO_TEXT'] == 'true',
      preferGoogleCloudStt: dotenv.env['USE_GOOGLE_CLOUD_STT'] == 'true',
      googleCloudAccessToken: _googleCloudSpeechToken(),
      googleCloudSpeechLanguage: dotenv.env['GOOGLE_CLOUD_SPEECH_LANGUAGE'] ?? 'pt-BR',
      preferRemoteStt: dotenv.env['USE_REMOTE_STT'] == 'true',
      remoteSttDeferUntilWakeWord: dotenv.env['REMOTE_STT_AFTER_WAKE_WORD'] == 'true',
      remoteSttUrl: dotenv.env['REMOTE_STT_URL'],
      remoteSttToken: dotenv.env['REMOTE_STT_TOKEN'],
      remoteSttLanguage: dotenv.env['REMOTE_STT_LANGUAGE'] ?? 'pt',
      remoteSttPrompt: dotenv.env['REMOTE_STT_PROMPT'],
      remoteSttVadFilter: dotenv.env['REMOTE_STT_VAD_FILTER'] != 'false',
      remoteSttChunkSeconds: _parseRemoteSttChunkSeconds(dotenv.env['REMOTE_STT_CHUNK_SECONDS']),
      remoteSttTimeoutSeconds: _parseRemoteSttTimeoutSeconds(dotenv.env['REMOTE_STT_TIMEOUT_SECONDS']),
      useTfliteAudio: dotenv.env['USE_TFLITE_AUDIO'] == 'true',
      onWakeWordDetected: _onWakeWord,
      onTranscript: _onTranscript,
      onLoadingModel: (isLoading, message) {
        if (mounted) {
          setState(() {
            _loadingVoskModel = isLoading;
            _loadingVoskMessage = message;
          });
        }
      },
      onRemoteListenUi: (state) {
        if (!mounted) return;
        setState(() => _remoteListenUi = state);
      },
    );
    _reminderService = ReminderNotificationService();
    _signedIn = Supabase.instance.client.auth.currentUser != null;
    if (Platform.isAndroid && _signedIn) {
      _overlayGranted = null;
    } else if (!Platform.isAndroid) {
      _overlayGranted = true;
    }
    debugLog('App', 'initState: signedIn=$_signedIn overlayGranted=$_overlayGranted');
    if (_signedIn) {
      _startListening();
      _reminderService.start();
    }
    showAssistantFromNative.addListener(_onShowAssistantFromNative);
  }

  @override
  void dispose() {
    _remoteRestartAfterBackgroundTimer?.cancel();
    _reminderService.stop();
    WidgetsBinding.instance.removeObserver(this);
    showAssistantFromNative.removeListener(_onShowAssistantFromNative);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        Platform.isAndroid &&
        _signedIn &&
        _overlayGranted == false) {
      _checkOverlayPermission();
    }
    // STT remoto + microfone em segundo plano: após várias idas ao fundo o gravador pode ficar preso;
    // reiniciar o loop ao pausar evita deixar de ouvir "secretária" na 2.ª minimização.
    if (state == AppLifecycleState.paused &&
        Platform.isAndroid &&
        _signedIn &&
        _voiceService.engine == 'remote') {
      _remoteRestartAfterBackgroundTimer?.cancel();
      _remoteRestartAfterBackgroundTimer = Timer(const Duration(milliseconds: 400), () {
        if (!mounted || !_voiceService.isListening || _avaSpeaking) return;
        debugLog('App', 'lifecycle paused: restart remote STT loop');
        _voiceService.restartListening();
      });
    }
  }

  Future<void> _checkOverlayPermission() async {
    final status = await Permission.systemAlertWindow.status;
    if (mounted) setState(() => _overlayGranted = status.isGranted);
    if (Platform.isAndroid && status.isGranted) await setFloatingBubbleEnabled(true);
  }

  void _onShowAssistantFromNative() {
    if (showAssistantFromNative.value && mounted) {
      showAssistantFromNative.value = false;
      setState(() => _assistantVisible = true);
    }
  }

  void _onWakeWord() {
    debugLog('App', 'wake word: showing assistant and bringing to front');
    setState(() => _assistantVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      bringAppToFront();
    });
  }

  void _onTranscript(String text, bool isFinal) {
    if (text.trim().isNotEmpty) {
      debugPrint('[App] Transcript: "$text" isFinal=$isFinal');
    }
    setState(() => _lastTranscript = text);
    if (isFinal && text.trim().isNotEmpty) {
      final context = VoiceCommandContext(lastCommandType: _lastExecutedCommandType);
      final cmd = parseCommand(text, context: context);
      if (cmd.type == VoiceCommandType.exitAssistant && _assistantVisible) {
        setState(() {
          _assistantVisible = false;
          _showDataVisualization = false;
        });
        moveAppToBack();
        const msg = 'Ava: ok. Indo para o plano de fundo.';
        setState(() {
          _commandResults.insert(0, {
            'label': commandTypeLabel(cmd.type),
            'result': msg,
          });
        });
        unawaited(_speakThenResumeListening(msg));
        return;
      }
      if (cmd.type != VoiceCommandType.unknown && _assistantVisible) {
        if (!commandMakesSense(cmd)) {
          const msg = 'Ava: não dá para agendar ou remarcar para uma data no passado.';
          setState(() => _commandResults.insert(0, {'label': 'Data inválida', 'result': msg}));
          unawaited(_speakThenResumeListening(msg));
          return;
        }
        final isViewCalendar = cmd.type == VoiceCommandType.viewCalendar;
        AssistantActions.execute(cmd).then((result) async {
          if (mounted) {
            setState(() {
              _lastExecutedCommandType = cmd.type;
              _commandResults.insert(0, {
                'label': commandTypeLabel(cmd.type),
                'result': result,
              });
              if (isViewCalendar) _showDataVisualization = true;
            });
            if (result.trim().isNotEmpty) await _speakThenResumeListening(result);
          }
        });
      }
    }
  }

  void _onSignedIn() {
    debugLog('App', 'onSignedIn');
    setState(() => _signedIn = true);
    _startListening();
    _reminderService.start();
  }

  /// Para a escuta, fala [text] com TTS e, ao terminar, retoma a escuta.
  Future<void> _speakThenResumeListening(String text) async {
    if (mounted) setState(() => _avaSpeaking = true);
    await _voiceService.stopListening();
    await SpeechFeedback.speak(text);
    if (mounted) {
      setState(() => _avaSpeaking = false);
      _voiceService.resumeListening();
    }
  }

  Future<void> _startListening() async {
    debugLog('App', 'startListening...');
    if (Platform.isAndroid) {
      await _initForegroundTask();
      debugLog('App', 'Foreground service started');
    }
    await _requestPermissions();
    debugLog('App', 'Permissions requested');
    if (Platform.isAndroid) {
      final status = await Permission.systemAlertWindow.status;
      if (mounted) setState(() => _overlayGranted = status.isGranted);
      debugLog('App', 'Overlay permission: ${status.isGranted}');
      if (status.isGranted) await setFloatingBubbleEnabled(true);
    }
    final ok = await _voiceService.init();
    debugLog('App', 'Voice service init: ok=$ok');
    if (ok) {
      _voiceService.startListening();
      debugLog('App', 'Voice listening started');
    }
  }

  Future<void> _requestPermissions() async {
    await Permission.microphone.request();
    if (Platform.isAndroid || Platform.isIOS) {
      await Permission.notification.request();
    }
    if (Platform.isAndroid) {
      await ReminderNotificationService.requestAndroidExactAlarmsPermission();
    }
  }

  Future<void> _initForegroundTask() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ia_secretary_listening',
        channelName: 'IA Secretary',
        channelDescription: 'Listening and sending to your API',
        channelImportance: NotificationChannelImportance.MIN,
        priority: NotificationPriority.LOW,
        playSound: false,
        enableVibration: false,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'IA Secretary',
      notificationText: 'Listening…',
      callback: startCallback,
    );
    debugLog('App', 'Foreground task startService done');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: _signedIn
          ? (Platform.isAndroid && _overlayGranted != true
              ? OverlayPermissionScreen(
                  isChecking: _overlayGranted == null,
                  onOpenSettings: () {},
                  onRetry: () async {
                    await _checkOverlayPermission();
                  },
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_showDataVisualization)
                      DataVisualizationScreen(
                        onBack: () => setState(() => _showDataVisualization = false),
                      )
                    else if (_assistantVisible)
                      AssistantScreen(
                        lastTranscript: _lastTranscript,
                        commandResults: List.from(_commandResults),
                        isAvaSpeaking: _avaSpeaking,
                        onMinimize: () => setState(() => _assistantVisible = false),
                        onViewData: () => setState(() => _showDataVisualization = true),
                        remoteListen: _voiceService.engine == 'remote' ? _remoteListenUi : null,
                      )
                    else
                      _TransparentHome(),
                    if (_voiceService.engine == 'remote' &&
                        _remoteListenUi != null &&
                        _remoteListenUi!.phase != RemoteListenPhase.idle &&
                        !_assistantVisible &&
                        !_avaSpeaking &&
                        !_showDataVisualization)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 28,
                        child: RemoteListenOverlayChip(state: _remoteListenUi!),
                      ),
                    if (_loadingVoskModel)
                      _VoskLoadingOverlay(message: _loadingVoskMessage),
                  ],
                )
          )
          : AuthScreen(onSignedIn: _onSignedIn),
    );
  }
}

/// Tela transparente (sem botão flutuante). Abra a assistente dizendo "Ava" ou "secretária".
class _TransparentHome extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Colors.transparent);
  }
}

/// Overlay de carregamento do modelo Vosk com visual futurista.
class _VoskLoadingOverlay extends StatefulWidget {
  const _VoskLoadingOverlay({this.message});
  final String? message;

  @override
  State<_VoskLoadingOverlay> createState() => _VoskLoadingOverlayState();
}

class _VoskLoadingOverlayState extends State<_VoskLoadingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  static const _accentColor = Color(0xFF00d4ff);
  static const _bgStart = Color(0xFF0a0e17);
  static const _bgMid = Color(0xFF0d1321);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _bgStart.withValues(alpha: 0.95),
            _bgMid.withValues(alpha: 0.95),
            _bgStart.withValues(alpha: 0.95),
          ],
        ),
      ),
      child: Stack(
        children: [
          CustomPaint(painter: _LoadingGridPainter(), size: Size.infinite),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Orb animado
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              _accentColor.withValues(alpha: 0.4),
                              _accentColor.withValues(alpha: 0.15),
                              Colors.transparent,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _accentColor.withValues(alpha: 0.3),
                              blurRadius: 30,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            Icons.mic,
                            size: 36,
                            color: _accentColor.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 32),
                // Título
                Text(
                  'PREPARANDO VOZ',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 20),
                // Mensagem
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    widget.message ?? 'Preparando reconhecimento de voz em português…',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                // Barra de progresso estilizada
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 60),
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation(_accentColor.withValues(alpha: 0.8)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                // Nota
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 50),
                  child: Text(
                    'Na primeira vez o modelo é baixado. Nas próximas aberturas carrega do disco.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00d4ff).withValues(alpha: 0.04)
      ..strokeWidth = 1;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
