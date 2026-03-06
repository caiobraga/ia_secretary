import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:vosk_flutter_service/vosk_flutter.dart';
import 'package:audioplayers/audioplayers.dart';

/// Tela de testes para comparar diferentes motores de reconhecimento de voz.
class SttTestScreen extends StatefulWidget {
  const SttTestScreen({super.key});

  @override
  State<SttTestScreen> createState() => _SttTestScreenState();
}

class _SttTestScreenState extends State<SttTestScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  final List<SttTestResult> _results = [];
  final List<SttEngine> _engines = [];
  
  bool _isRecording = false;
  bool _isTesting = false;
  bool _isDownloading = false;
  bool _isPlaying = false;
  String? _currentAudioPath;
  String _statusMessage = 'Pressione o botão para gravar';
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  double _downloadProgress = 0;
  String? _downloadingEngine;

  final Map<String, Recognizer> _voskRecognizers = {};
  final Map<String, Model> _voskModels = {};

  @override
  void initState() {
    super.initState();
    _initEngines();
    _checkDownloadedModels();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlaying = false);
    });
  }

  void _initEngines() {
    _engines.addAll([
      SttEngine(
        id: 'vosk_small_pt',
        name: 'Vosk Small PT',
        description: 'Modelo pequeno para português (31MB) - rápido mas menos preciso',
        modelUrl: 'https://alphacephei.com/vosk/models/vosk-model-small-pt-0.3.zip',
        type: SttEngineType.vosk,
        sizeMB: 31,
      ),
      SttEngine(
        id: 'vosk_large_pt',
        name: 'Vosk Large PT (FalaBrasil)',
        description: 'Modelo grande para português brasileiro (1.6GB) - mais preciso',
        modelUrl: 'https://alphacephei.com/vosk/models/vosk-model-pt-fb-v0.1.1-20220516_2113.zip',
        type: SttEngineType.vosk,
        sizeMB: 1600,
      ),
    ]);
  }

  Future<void> _checkDownloadedModels() async {
    setState(() => _statusMessage = 'Verificando modelos baixados...');
    
    final loader = ModelLoader();
    for (final engine in _engines) {
      if (engine.type == SttEngineType.vosk && engine.modelUrl.isNotEmpty) {
        final modelName = _extractModelName(engine.modelUrl);
        try {
          final isLoaded = await loader.isModelAlreadyLoaded(modelName);
          debugPrint('Modelo $modelName: ${isLoaded ? "baixado" : "não baixado"}');
          if (mounted) {
            setState(() => engine.isDownloaded = isLoaded);
          }
        } catch (e) {
          debugPrint('Erro ao verificar modelo $modelName: $e');
        }
      }
    }
    
    if (mounted) {
      final downloaded = _engines.where((e) => e.isDownloaded).length;
      setState(() => _statusMessage = '$downloaded modelo(s) disponível(is). Grave um áudio para testar.');
    }
  }

  String _extractModelName(String url) {
    return url.split('/').last.split('?').first.replaceAll('.zip', '');
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recorder.dispose();
    _player.dispose();
    for (final recognizer in _voskRecognizers.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      setState(() => _statusMessage = 'Permissão de microfone negada');
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _currentAudioPath = '${tempDir.path}/stt_test_$timestamp.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 256000,
      ),
      path: _currentAudioPath!,
    );

    setState(() {
      _isRecording = true;
      _recordingSeconds = 0;
      _statusMessage = 'Gravando... 0s';
      _results.clear();
    });

    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordingSeconds++;
        _statusMessage = 'Gravando... ${_recordingSeconds}s';
      });
    });
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    final path = await _recorder.stop();
    
    if (path != null && File(path).existsSync()) {
      final fileSize = File(path).lengthSync();
      final durationEstimate = (fileSize / (16000 * 2)).toStringAsFixed(1);
      setState(() {
        _isRecording = false;
        _currentAudioPath = path;
        _statusMessage = 'Áudio gravado (~${durationEstimate}s). Selecione motores e clique Testar.';
      });
    } else {
      setState(() {
        _isRecording = false;
        _statusMessage = 'Erro ao gravar áudio';
      });
    }
  }

  Future<void> _playRecording() async {
    if (_currentAudioPath == null || !File(_currentAudioPath!).existsSync()) {
      return;
    }
    
    if (_isPlaying) {
      await _player.stop();
      setState(() => _isPlaying = false);
    } else {
      await _player.play(DeviceFileSource(_currentAudioPath!));
      setState(() => _isPlaying = true);
    }
  }

  Future<void> _runTests() async {
    if (_currentAudioPath == null || !File(_currentAudioPath!).existsSync()) {
      setState(() => _statusMessage = 'Grave um áudio primeiro');
      return;
    }

    final selectedEngines = _engines.where((e) => e.isSelected && e.isDownloaded).toList();
    if (selectedEngines.isEmpty) {
      setState(() => _statusMessage = 'Selecione ao menos um motor baixado');
      return;
    }

    setState(() {
      _isTesting = true;
      _results.clear();
      _statusMessage = 'Testando...';
    });

    for (final engine in selectedEngines) {
      setState(() => _statusMessage = 'Testando ${engine.name}...');
      
      final stopwatch = Stopwatch()..start();
      String? transcript;
      String? error;

      try {
        transcript = await _transcribeWithEngine(engine, _currentAudioPath!);
      } catch (e, stack) {
        error = '$e\n$stack';
        debugPrint('Erro ao transcrever com ${engine.name}: $e');
      }

      stopwatch.stop();

      if (mounted) {
        setState(() {
          _results.add(SttTestResult(
            engine: engine,
            transcript: transcript,
            error: error,
            durationMs: stopwatch.elapsedMilliseconds,
            audioPath: _currentAudioPath!,
          ));
        });
      }
    }

    if (mounted) {
      setState(() {
        _isTesting = false;
        _statusMessage = 'Testes concluídos! ${_results.length} resultado(s).';
      });
    }
  }

  Future<String?> _transcribeWithEngine(SttEngine engine, String audioPath) async {
    switch (engine.type) {
      case SttEngineType.vosk:
        return _transcribeWithVosk(engine, audioPath);
      case SttEngineType.whisper:
        return '[Whisper] Não disponível';
      case SttEngineType.system:
        return '[Sistema] Não suporta arquivos';
      case SttEngineType.custom:
        return '[Custom] Não implementado';
    }
  }

  Future<String?> _transcribeWithVosk(SttEngine engine, String audioPath) async {
    Recognizer? recognizer = _voskRecognizers[engine.id];
    
    if (recognizer == null) {
      debugPrint('Criando reconhecedor para ${engine.name}...');
      final loader = ModelLoader();
      final modelPath = await loader.loadFromNetwork(engine.modelUrl, forceReload: false);
      debugPrint('Modelo carregado de: $modelPath');
      
      final vosk = VoskFlutterPlugin.instance();
      final model = await vosk.createModel(modelPath);
      _voskModels[engine.id] = model;
      
      recognizer = await vosk.createRecognizer(model: model, sampleRate: 16000);
      await recognizer.setMaxAlternatives(3);
      _voskRecognizers[engine.id] = recognizer;
      debugPrint('Reconhecedor criado com sucesso');
    }

    final file = File(audioPath);
    final bytes = await file.readAsBytes();
    debugPrint('Arquivo WAV: ${bytes.length} bytes');
    
    final pcmData = _extractPcmFromWav(bytes);
    if (pcmData == null || pcmData.isEmpty) {
      return '[Erro] Não foi possível extrair dados PCM do arquivo WAV';
    }
    
    final durationSec = pcmData.length / (16000 * 2);
    debugPrint('PCM extraído: ${pcmData.length} bytes (~${durationSec.toStringAsFixed(1)}s)');
    
    // Processar em chunks
    const chunkSize = 8000; // ~0.25s de áudio
    final buffer = StringBuffer();
    int processedChunks = 0;
    
    for (int i = 0; i < pcmData.length; i += chunkSize) {
      final end = (i + chunkSize < pcmData.length) ? i + chunkSize : pcmData.length;
      final chunk = Uint8List.fromList(pcmData.sublist(i, end));
      
      final hasResult = await recognizer.acceptWaveformBytes(chunk);
      processedChunks++;
      
      if (hasResult) {
        final json = await recognizer.getResult();
        final text = _parseVoskResult(json);
        debugPrint('Chunk $processedChunks resultado: "$text"');
        if (text.isNotEmpty) buffer.write('$text ');
      }
    }
    
    final finalJson = await recognizer.getFinalResult();
    final finalText = _parseVoskResult(finalJson);
    debugPrint('Resultado final: "$finalText"');
    if (finalText.isNotEmpty) buffer.write(finalText);
    
    await recognizer.reset();
    
    final result = buffer.toString().trim();
    debugPrint('Transcrição completa: "$result"');
    return result.isEmpty ? '(silêncio ou não reconhecido)' : result;
  }

  Uint8List? _extractPcmFromWav(Uint8List wavBytes) {
    if (wavBytes.length < 44) {
      debugPrint('WAV muito pequeno: ${wavBytes.length} bytes');
      return null;
    }
    
    final riff = String.fromCharCodes(wavBytes.sublist(0, 4));
    if (riff != 'RIFF') {
      debugPrint('Header RIFF não encontrado: $riff');
      return null;
    }
    
    int offset = 12;
    while (offset < wavBytes.length - 8) {
      final chunkId = String.fromCharCodes(wavBytes.sublist(offset, offset + 4));
      final chunkSize = wavBytes[offset + 4] | 
                       (wavBytes[offset + 5] << 8) | 
                       (wavBytes[offset + 6] << 16) | 
                       (wavBytes[offset + 7] << 24);
      
      debugPrint('WAV chunk: $chunkId (${chunkSize} bytes) @ offset $offset');
      
      if (chunkId == 'data') {
        final dataStart = offset + 8;
        final dataEnd = dataStart + chunkSize;
        if (dataEnd <= wavBytes.length) {
          return Uint8List.fromList(wavBytes.sublist(dataStart, dataEnd));
        } else {
          return Uint8List.fromList(wavBytes.sublist(dataStart));
        }
      }
      
      offset += 8 + chunkSize;
      if (chunkSize % 2 != 0) offset++;
    }
    
    debugPrint('Chunk data não encontrado');
    return null;
  }

  String _parseVoskResult(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      
      // Tentar pegar o melhor resultado das alternativas
      final alternatives = map['alternatives'];
      if (alternatives is List && alternatives.isNotEmpty) {
        // Pegar a alternativa com maior confiança
        String bestText = '';
        double bestConf = -1;
        for (final alt in alternatives) {
          if (alt is Map) {
            final text = (alt['text'] ?? '').toString().trim();
            final conf = alt['confidence'] is num ? (alt['confidence'] as num).toDouble() : 0.0;
            if (text.isNotEmpty && conf > bestConf) {
              bestText = text;
              bestConf = conf;
            }
          }
        }
        if (bestText.isNotEmpty) return bestText;
      }
      
      return (map['text'] ?? '').toString().trim();
    } catch (_) {
      return '';
    }
  }

  void _addCustomEngine() {
    showDialog(
      context: context,
      builder: (context) => _AddEngineDialog(
        onAdd: (engine) {
          setState(() => _engines.add(engine));
        },
      ),
    );
  }

  Future<void> _downloadEngine(SttEngine engine) async {
    if (_isDownloading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aguarde o download atual terminar')),
      );
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _downloadingEngine = engine.id;
      _statusMessage = 'Baixando ${engine.name}... (pode demorar)';
    });

    try {
      final loader = ModelLoader();
      
      // Iniciar download em background
      final completer = Completer<String>();
      
      loader.loadFromNetwork(engine.modelUrl, forceReload: false).then((path) {
        completer.complete(path);
      }).catchError((e) {
        completer.completeError(e);
      });
      
      // Atualizar progresso periodicamente
      while (!completer.isCompleted) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted && !completer.isCompleted) {
          setState(() {
            _downloadProgress = (_downloadProgress + 0.02).clamp(0.0, 0.95);
          });
        }
      }
      
      await completer.future;
      
      if (mounted) {
        setState(() {
          _downloadProgress = 1.0;
          engine.isDownloaded = true;
          _statusMessage = '${engine.name} baixado com sucesso!';
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${engine.name} baixado!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = 'Erro ao baixar: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadingEngine = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teste de STT'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Verificar modelos',
            onPressed: _checkDownloadedModels,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Adicionar modelo',
            onPressed: _addCustomEngine,
          ),
        ],
      ),
      body: Column(
        children: [
          // Área de gravação
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isRecording 
                  ? Colors.red.shade50 
                  : (_isDownloading ? Colors.blue.shade50 : Colors.grey.shade100),
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Column(
              children: [
                Text(
                  _statusMessage,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _isRecording ? Colors.red : (_isDownloading ? Colors.blue : Colors.black87),
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_isDownloading) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: _downloadProgress),
                  Text('${(_downloadProgress * 100).toInt()}%', style: const TextStyle(fontSize: 12)),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Gravar
                    ElevatedButton.icon(
                      onPressed: (_isTesting || _isDownloading) 
                          ? null 
                          : (_isRecording ? _stopRecording : _startRecording),
                      icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                      label: Text(_isRecording ? 'Parar' : 'Gravar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isRecording ? Colors.red : Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Ouvir gravação
                    if (_currentAudioPath != null && !_isRecording)
                      ElevatedButton.icon(
                        onPressed: _isTesting ? null : _playRecording,
                        icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                        label: Text(_isPlaying ? 'Parar' : 'Ouvir'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        ),
                      ),
                    const SizedBox(width: 8),
                    // Testar
                    ElevatedButton.icon(
                      onPressed: (_isRecording || _isTesting || _isDownloading || _currentAudioPath == null) 
                          ? null 
                          : _runTests,
                      icon: _isTesting 
                          ? const SizedBox(
                              width: 18, 
                              height: 18, 
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.science),
                      label: Text(_isTesting ? 'Testando...' : 'Testar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Tabs
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: 'Motores'),
                      Tab(text: 'Resultados'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildEnginesList(),
                        _buildResultsList(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnginesList() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _engines.length,
      itemBuilder: (context, index) {
        final engine = _engines[index];
        final isDownloadingThis = _downloadingEngine == engine.id;
        
        return Card(
          child: ListTile(
            leading: Checkbox(
              value: engine.isSelected,
              onChanged: engine.isDownloaded 
                  ? (value) => setState(() => engine.isSelected = value ?? false)
                  : null,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    engine.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: engine.isDownloaded ? Colors.black87 : Colors.grey,
                    ),
                  ),
                ),
                _buildEngineTypeChip(engine.type),
                const SizedBox(width: 4),
                if (engine.isDownloaded)
                  const Icon(Icons.check_circle, color: Colors.green, size: 20)
                else
                  Chip(
                    label: Text('${engine.sizeMB}MB', style: const TextStyle(fontSize: 10)),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(engine.description, style: const TextStyle(fontSize: 12)),
                if (isDownloadingThis) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: _downloadProgress),
                ],
              ],
            ),
            trailing: engine.isDownloaded
                ? null
                : IconButton(
                    icon: isDownloadingThis 
                        ? const SizedBox(
                            width: 24, 
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    onPressed: _isDownloading ? null : () => _downloadEngine(engine),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildEngineTypeChip(SttEngineType type) {
    final (color, label) = switch (type) {
      SttEngineType.vosk => (Colors.purple, 'Vosk'),
      SttEngineType.whisper => (Colors.teal, 'Whisper'),
      SttEngineType.system => (Colors.blue, 'Sistema'),
      SttEngineType.custom => (Colors.orange, 'Custom'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: const TextStyle(fontSize: 10, color: Colors.white)),
    );
  }

  Widget _buildResultsList() {
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.science, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Grave um áudio e execute os testes\npara ver os resultados aqui.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        final hasError = result.error != null;
        
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        result.engine.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: result.durationMs < 2000 
                            ? Colors.green.shade100 
                            : result.durationMs < 5000 
                                ? Colors.yellow.shade100 
                                : Colors.red.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${(result.durationMs / 1000).toStringAsFixed(1)}s',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: hasError ? Colors.red.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: hasError ? Colors.red.shade200 : Colors.grey.shade300,
                    ),
                  ),
                  child: SelectableText(
                    hasError 
                        ? result.error! 
                        : (result.transcript ?? '(sem resultado)'),
                    style: TextStyle(
                      color: hasError ? Colors.red.shade700 : Colors.black87,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AddEngineDialog extends StatefulWidget {
  final void Function(SttEngine) onAdd;

  const _AddEngineDialog({required this.onAdd});

  @override
  State<_AddEngineDialog> createState() => _AddEngineDialogState();
}

class _AddEngineDialogState extends State<_AddEngineDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _urlController = TextEditingController();
  SttEngineType _selectedType = SttEngineType.vosk;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Adicionar Modelo Vosk'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Adicione modelos Vosk de:\nhttps://alphacephei.com/vosk/models',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'Ex: Vosk PT Custom',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Descrição',
                hintText: 'Ex: Modelo treinado para português',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'URL do Modelo (.zip)',
                hintText: 'https://alphacephei.com/vosk/models/...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_nameController.text.isEmpty || _urlController.text.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Preencha nome e URL')),
              );
              return;
            }
            widget.onAdd(SttEngine(
              id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
              name: _nameController.text,
              description: _descriptionController.text.isEmpty 
                  ? 'Modelo customizado' 
                  : _descriptionController.text,
              modelUrl: _urlController.text,
              type: _selectedType,
            ));
            Navigator.pop(context);
          },
          child: const Text('Adicionar'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _urlController.dispose();
    super.dispose();
  }
}

enum SttEngineType { vosk, whisper, system, custom }

class SttEngine {
  final String id;
  final String name;
  final String description;
  final String modelUrl;
  final SttEngineType type;
  final int sizeMB;
  bool isSelected;
  bool isDownloaded;

  SttEngine({
    required this.id,
    required this.name,
    required this.description,
    required this.modelUrl,
    required this.type,
    this.sizeMB = 0,
    this.isSelected = true,
    this.isDownloaded = false,
  });
}

class SttTestResult {
  final SttEngine engine;
  final String? transcript;
  final String? error;
  final int durationMs;
  final String audioPath;

  SttTestResult({
    required this.engine,
    this.transcript,
    this.error,
    required this.durationMs,
    required this.audioPath,
  });
}
