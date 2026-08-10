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

class MomVoiceException implements Exception {
  const MomVoiceException(this.stage, this.cause);

  final String stage;
  final Object cause;

  @override
  String toString() => 'MOM voice $stage failed: $cause';
}

class MomVoiceService {
  final SpeechToText _speech = SpeechToText();
  final AudioPlayer _player = AudioPlayer();

  bool _speechReady = false;
  Future<_VoiceAssets>? _assetsFuture;
  int _speechGeneration = 0;
  File? _playingFile;
  void Function(bool listening)? _listeningState;
  MomVoiceException? _lastFailure;

  bool get listening => _speech.isListening;
  MomVoiceException? get lastFailure => _lastFailure;

  Future<bool> initialize() async {
    try {
      _speechReady = await _speech.initialize(
        onStatus: (status) {
          if (status == 'listening') {
            _listeningState?.call(true);
          } else if (status == 'notListening' || status == 'done') {
            _listeningState?.call(false);
          }
        },
        onError: (error) {
          _lastFailure = MomVoiceException('speech_recognition', error);
          _listeningState?.call(false);
        },
      );
    } catch (error) {
      _speechReady = false;
      _lastFailure = MomVoiceException('speech_recognition', error);
    }
    unawaited(_warmVoiceAssets());
    return _speechReady;
  }

  Future<void> _warmVoiceAssets() async {
    try {
      await _prepareVoiceAssets();
    } catch (error) {
      _lastFailure = error is MomVoiceException
          ? error
          : MomVoiceException('assets', error);
    }
  }

  Future<_VoiceAssets> _prepareVoiceAssets() async {
    final existing = _assetsFuture;
    if (existing != null) return existing;

    final future = _loadVoiceAssets();
    _assetsFuture = future;
    try {
      final assets = await future;
      _lastFailure = null;
      return assets;
    } catch (error) {
      if (identical(_assetsFuture, future)) _assetsFuture = null;
      final failure = error is MomVoiceException
          ? error
          : MomVoiceException('assets', error);
      _lastFailure = failure;
      throw failure;
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

    if (!await _isValidGguf(model)) {
      throw const FormatException('Kokoro model is not a valid GGUF file');
    }
    if (!await _isValidGguf(voice)) {
      throw const FormatException('Kokoro voice is not a valid GGUF file');
    }

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
      final failure = _lastFailure ??
          const MomVoiceException(
            'speech_recognition',
            'Speech recognition is unavailable on this device',
          );
      _lastFailure = failure;
      throw failure;
    }

    onState(true);
    try {
      await _speech.listen(
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
        ),
        onResult: (result) {
          if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
            onFinal(result.recognizedWords.trim());
            onState(false);
          }
        },
      );
      if (!_speech.isListening) onState(false);
    } catch (error) {
      onState(false);
      final failure = error is MomVoiceException
          ? error
          : MomVoiceException('speech_recognition', error);
      _lastFailure = failure;
      throw failure;
    }
  }

  Future<void> stopListening() async {
    await _speech.stop();
    _listeningState?.call(false);
    _listeningState = null;
  }

  Future<void> stopSpeaking() async {
    _speechGeneration++;
    await _player.stop();
    final playing = _playingFile;
    _playingFile = null;
    if (playing != null && await playing.exists()) {
      await playing.delete();
    }
  }

  Future<void> speak(
    String text, {
    void Function()? onSynthesisStart,
    void Function()? onPlaybackStart,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final generation = ++_speechGeneration;
    late final _VoiceAssets assets;
    try {
      assets = await _prepareVoiceAssets();
    } catch (error) {
      final failure = error is MomVoiceException
          ? error
          : MomVoiceException('assets', error);
      _lastFailure = failure;
      throw failure;
    }
    if (generation != _speechGeneration) return;

    onSynthesisStart?.call();
    final request = _SynthesisRequest(
      modelPath: assets.model.path,
      voicePath: assets.voice.path,
      text: trimmed,
    );

    late final Uint8List wav;
    try {
      wav = await Isolate.run(() => _synthesize(request));
    } catch (error) {
      final failure = MomVoiceException('synthesis', error);
      _lastFailure = failure;
      throw failure;
    }
    if (generation != _speechGeneration) return;
    if (wav.length <= 44) {
      final failure = const MomVoiceException(
        'synthesis',
        'Kokoro returned an empty audio buffer',
      );
      _lastFailure = failure;
      throw failure;
    }

    final output =
        File('${assets.directory.path}/mom-response-$generation.wav');
    try {
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
      _lastFailure = null;
      await completed.timeout(
        const Duration(minutes: 2),
        onTimeout: () {},
      );
    } catch (error) {
      final failure = MomVoiceException('playback', error);
      _lastFailure = failure;
      throw failure;
    } finally {
      if (await output.exists()) await output.delete();
      if (identical(_playingFile, output)) _playingFile = null;
    }
  }

  Future<bool> _isValidGguf(File file) async {
    if (!await file.exists() || await file.length() <= 1024) return false;
    final handle = await file.open();
    try {
      final header = await handle.read(4);
      return header.length == 4 &&
          header[0] == 0x47 &&
          header[1] == 0x47 &&
          header[2] == 0x55 &&
          header[3] == 0x46;
    } finally {
      await handle.close();
    }
  }

  Future<void> _downloadIfMissing(File file, String url) async {
    if (await _isValidGguf(file)) return;
    if (await file.exists()) await file.delete();

    final partial = File('${file.path}.part');
    final client = http.Client();
    try {
      if (await partial.exists()) await partial.delete();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Voice download failed: ${response.statusCode}');
      }

      final sink = partial.openWrite();
      await response.stream.pipe(sink);
      if (!await _isValidGguf(partial)) {
        throw const FormatException('Downloaded voice asset is not valid GGUF');
      }
      await partial.rename(file.path);
    } finally {
      client.close();
      if (await partial.exists()) await partial.delete();
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
