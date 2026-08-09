import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:crispasr/crispasr.dart' as crisp;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart';

const _modelName = 'kokoro-82m-q8_0.gguf';
const _voiceName = 'kokoro-voice-af_heart.gguf';
const _modelUrl =
    'https://huggingface.co/cstr/kokoro-82m-GGUF/resolve/main/kokoro-82m-q8_0.gguf?download=true';
const _voiceUrl =
    'https://huggingface.co/cstr/kokoro-voices-GGUF/resolve/main/kokoro-voice-af_heart.gguf?download=true';

class MomVoiceService {
  final SpeechToText _speech = SpeechToText();
  final AudioPlayer _player = AudioPlayer();

  bool _speechReady = false;
  Future<_VoiceAssets>? _assetsFuture;
  int _speechGeneration = 0;
  File? _playingFile;
  void Function(bool listening)? _listeningState;
  bool get listening => _speech.isListening;

  Future<bool> initialize() async {
    _speechReady = await _speech.initialize(
      onStatus: (status) {
        if (status == 'listening') {
          _listeningState?.call(true);
        } else if (status == 'notListening' || status == 'done') {
          _listeningState?.call(false);
        }
      },
      onError: (_) => _listeningState?.call(false),
    );
    unawaited(_warmVoiceAssets());
    return _speechReady;
  }

  Future<void> _warmVoiceAssets() async {
    try {
      await _prepareVoiceAssets();
    } catch (_) {
      // Voice download failures must never block startup. speak() retries later.
    }
  }

  Future<_VoiceAssets> _prepareVoiceAssets() async {
    final existing = _assetsFuture;
    if (existing != null) return existing;

    final future = _loadVoiceAssets();
    _assetsFuture = future;
    try {
      return await future;
    } catch (_) {
      if (identical(_assetsFuture, future)) _assetsFuture = null;
      rethrow;
    }
  }

  Future<_VoiceAssets> _loadVoiceAssets() async {
    final dir = await getApplicationSupportDirectory();
    final voiceDir = Directory('${dir.path}/voice');
    await voiceDir.create(recursive: true);

    final model = File('${voiceDir.path}/$_modelName');
    final voice = File('${voiceDir.path}/$_voiceName');
    await _downloadIfMissing(model, _modelUrl);
    await _downloadIfMissing(voice, _voiceUrl);
    return _VoiceAssets(model: model, voice: voice, directory: voiceDir);
  }

  Future<void> listen({
    required void Function(String text) onFinal,
    required void Function(bool listening) onState,
  }) async {
    if (!_speechReady) await initialize();
    _listeningState = onState;
    if (!_speechReady) {
      onState(false);
      return;
    }

    onState(true);
    try {
      await _speech.listen(
        partialResults: true,
        cancelOnError: true,
        onResult: (result) {
          if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
            onFinal(result.recognizedWords.trim());
            onState(false);
          }
        },
      );
      if (!_speech.isListening) onState(false);
    } catch (_) {
      onState(false);
      rethrow;
    }
  }

  Future<void> stopListening() async {
    await _speech.stop();
    _listeningState?.call(false);
    _listeningState = null;
  }

  Future<void> speak(
    String text, {
    void Function()? onSynthesisStart,
    void Function()? onPlaybackStart,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final generation = ++_speechGeneration;
    final assets = await _prepareVoiceAssets();
    if (generation != _speechGeneration) return;

    onSynthesisStart?.call();
    final request = _SynthesisRequest(
      modelPath: assets.model.path,
      voicePath: assets.voice.path,
      text: trimmed,
    );
    final wav = await Isolate.run(() => _synthesize(request));
    if (generation != _speechGeneration) return;

    final output =
        File('${assets.directory.path}/mom-response-$generation.wav');
    await output.writeAsBytes(wav, flush: true);
    if (generation != _speechGeneration) {
      if (await output.exists()) await output.delete();
      return;
    }

    await _player.stop();
    final previous = _playingFile;
    if (previous != null && await previous.exists()) {
      await previous.delete();
    }
    if (generation != _speechGeneration) {
      if (await output.exists()) await output.delete();
      return;
    }

    final completed = _player.onPlayerComplete.first;
    onPlaybackStart?.call();
    await _player.play(DeviceFileSource(output.path));
    _playingFile = output;
    await completed.timeout(
      const Duration(minutes: 2),
      onTimeout: () {},
    );

    if (generation == _speechGeneration && await output.exists()) {
      await output.delete();
      _playingFile = null;
    }
  }

  Future<void> _downloadIfMissing(File file, String url) async {
    if (await file.exists() && await file.length() > 1024) return;

    final partial = File('${file.path}.part');
    final backup = File('${file.path}.bad');
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Voice download failed: ${response.statusCode}');
      }

      final sink = partial.openWrite();
      await response.stream.pipe(sink);
      if (!await partial.exists() || await partial.length() <= 1024) {
        throw const FormatException('Downloaded voice asset is unexpectedly small');
      }

      if (await backup.exists()) await backup.delete();
      final hadExisting = await file.exists();
      if (hadExisting) await file.rename(backup.path);
      try {
        await partial.rename(file.path);
        if (await backup.exists()) await backup.delete();
      } catch (_) {
        if (await file.exists()) await file.delete();
        if (await backup.exists()) await backup.rename(file.path);
        rethrow;
      }
    } finally {
      client.close();
      if (await partial.exists() && await file.exists()) {
        await partial.delete();
      }
      if (await backup.exists() && await file.exists()) {
        await backup.delete();
      }
    }
  }

  Future<void> dispose() async {
    _speechGeneration++;
    _listeningState?.call(false);
    _listeningState = null;
    await _speech.stop();
    await _player.stop();
    await _player.dispose();
    final playing = _playingFile;
    if (playing != null && await playing.exists()) {
      await playing.delete();
    }
  }
}

class _VoiceAssets {
  const _VoiceAssets({
    required this.model,
    required this.voice,
    required this.directory,
  });

  final File model;
  final File voice;
  final Directory directory;
}

class _SynthesisRequest {
  const _SynthesisRequest({
    required this.modelPath,
    required this.voicePath,
    required this.text,
  });

  final String modelPath;
  final String voicePath;
  final String text;
}

Uint8List _synthesize(_SynthesisRequest request) {
  final session = crisp.CrispasrSession.open(
    request.modelPath,
    backend: 'kokoro',
  );
  try {
    session.setVoice(request.voicePath);
    final pcm = session.synthesize(request.text);
    return _pcmToWav(pcm, 24000);
  } finally {
    session.close();
  }
}

Uint8List _pcmToWav(Float32List pcm, int sampleRate) {
  final dataLength = pcm.length * 2;
  final bytes = ByteData(44 + dataLength);

  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  bytes.setUint32(4, 36 + dataLength, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  text(36, 'data');
  bytes.setUint32(40, dataLength, Endian.little);

  var offset = 44;
  for (final sample in pcm) {
    final clamped = sample.clamp(-1.0, 1.0);
    bytes.setInt16(offset, (clamped * 32767).round(), Endian.little);
    offset += 2;
  }
  return bytes.buffer.asUint8List();
}
