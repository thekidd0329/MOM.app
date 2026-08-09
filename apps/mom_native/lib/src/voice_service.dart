import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:crispasr/crispasr.dart' as crisp;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'speech_chunker.dart';
import 'voice_conversation_controller.dart';
import 'voice_playback_state.dart';

const _modelName = 'kokoro-82m-q8_0.gguf';
const _voiceName = 'kokoro-voice-af_heart.gguf';
const _modelUrl =
    'https://huggingface.co/cstr/kokoro-82m-GGUF/resolve/main/kokoro-82m-q8_0.gguf?download=true';
const _voiceUrl =
    'https://huggingface.co/cstr/kokoro-voices-GGUF/resolve/main/kokoro-voice-af_heart.gguf?download=true';

class MomVoiceService {
  final SpeechToText _speech = SpeechToText();
  final AudioPlayer _player = AudioPlayer();
  final MomVoiceConversationController _conversation =
      MomVoiceConversationController();
  final StreamController<MomVoicePlaybackState> _playbackStates =
      StreamController<MomVoicePlaybackState>.broadcast(sync: true);

  bool _speechReady = false;
  Future<_VoiceAssets>? _assetsFuture;
  int _speechGeneration = 0;
  File? _playingFile;
  void Function(bool listening)? _listeningState;
  void Function(String text)? _finalTranscript;
  MomVoicePlaybackState _playbackState = const MomVoicePlaybackState.idle();

  bool get listening => _speech.isListening;
  bool get handsFreeActive => _conversation.active;
  MomVoiceConversationPhase get conversationPhase => _conversation.phase;
  MomVoicePlaybackState get playbackState => _playbackState;
  Stream<MomVoicePlaybackState> get playbackStates => _playbackStates.stream;

  void _emitPlayback(MomVoicePlaybackState state) {
    _playbackState = state;
    if (!_playbackStates.isClosed) _playbackStates.add(state);
  }

  Future<bool> initialize() async {
    _speechReady = await _speech.initialize(
      onStatus: (status) {
        if (status == 'listening') {
          _listeningState?.call(true);
          return;
        }
        if (status == 'notListening' || status == 'done') {
          _listeningState?.call(false);
          if (_conversation.listeningEndedWithoutTurn()) {
            _scheduleSilentRelisten();
          }
        }
      },
      onError: (_) {
        _listeningState?.call(false);
        if (_conversation.listeningEndedWithoutTurn()) {
          _scheduleSilentRelisten();
        }
      },
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
    if (_conversation.active) {
      await stopListening();
      return;
    }

    _listeningState = onState;
    _finalTranscript = onFinal;
    _conversation.enable();
    await _startListeningCycle();
  }

  Future<void> _startListeningCycle() async {
    if (!_conversation.canListen(busy: false)) return;
    if (!_speechReady) await initialize();
    if (!_speechReady || !_conversation.active) {
      _conversation.fail();
      _listeningState?.call(false);
      return;
    }

    _conversation.markListening();
    _listeningState?.call(true);
    try {
      await _speech.listen(
        partialResults: true,
        cancelOnError: true,
        onResult: (result) {
          final text = result.recognizedWords.trim();
          if (!result.finalResult || text.isEmpty || !_conversation.active) {
            return;
          }
          _conversation.markThinking();
          _finalTranscript?.call(text);
          _listeningState?.call(false);
        },
      );
      if (!_speech.isListening &&
          _conversation.listeningEndedWithoutTurn()) {
        _listeningState?.call(false);
        _scheduleSilentRelisten();
      }
    } catch (_) {
      _listeningState?.call(false);
      if (_conversation.listeningEndedWithoutTurn()) {
        _scheduleSilentRelisten();
      } else {
        rethrow;
      }
    }
  }

  void _scheduleSilentRelisten() {
    final generation = _conversation.generation;
    unawaited(Future<void>.delayed(const Duration(milliseconds: 250), () async {
      if (!_conversation.active || generation != _conversation.generation) {
        return;
      }
      if (!_conversation.canListen(busy: false)) return;
      try {
        await _startListeningCycle();
      } catch (_) {
        _conversation.fail();
        _listeningState?.call(false);
      }
    }));
  }

  Future<void> stopListening() async {
    _conversation.disable();
    await _speech.stop();
    _listeningState?.call(false);
    _listeningState = null;
    _finalTranscript = null;
  }

  Future<void> speak(String text) async {
    final chunks = splitSpeechChunks(text);
    if (chunks.isEmpty) return;

    final shouldResumeHandsFree = _conversation.active;
    if (shouldResumeHandsFree) {
      _conversation.markSpeaking();
      await _speech.stop();
      _listeningState?.call(false);
    }

    final generation = ++_speechGeneration;
    try {
      final assets = await _prepareVoiceAssets();
      if (generation != _speechGeneration) return;

      await _player.stop();
      final previous = _playingFile;
      if (previous != null && await previous.exists()) {
        await previous.delete();
      }
      _playingFile = null;

      for (var index = 0; index < chunks.length; index++) {
        if (generation != _speechGeneration) return;
        _emitPlayback(MomVoicePlaybackState(
          phase: MomVoicePlaybackPhase.preparing,
          chunkIndex: index,
          chunkCount: chunks.length,
        ));

        final request = _SynthesisRequest(
          modelPath: assets.model.path,
          voicePath: assets.voice.path,
          text: chunks[index],
        );
        final wav = await Isolate.run(() => _synthesize(request));
        if (generation != _speechGeneration) return;

        final output = File(
          '${assets.directory.path}/mom-response-$generation-$index.wav',
        );
        await output.writeAsBytes(wav, flush: true);
        if (generation != _speechGeneration) {
          if (await output.exists()) await output.delete();
          return;
        }

        final completed = _player.onPlayerComplete.first;
        _emitPlayback(MomVoicePlaybackState(
          phase: MomVoicePlaybackPhase.speaking,
          chunkIndex: index,
          chunkCount: chunks.length,
        ));
        await _player.play(DeviceFileSource(output.path));
        _playingFile = output;
        await completed.timeout(
          const Duration(minutes: 2),
          onTimeout: () {},
        );

        if (await output.exists()) await output.delete();
        if (identical(_playingFile, output)) _playingFile = null;
      }
    } finally {
      _emitPlayback(const MomVoicePlaybackState.idle());
      if (shouldResumeHandsFree && _conversation.active) {
        _conversation.finishTurn();
        try {
          await _startListeningCycle();
        } catch (_) {
          _conversation.fail();
          _listeningState?.call(false);
        }
      }
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
    _conversation.disable();
    _speechGeneration++;
    _listeningState?.call(false);
    _listeningState = null;
    _finalTranscript = null;
    await _speech.stop();
    await _player.stop();
    _emitPlayback(const MomVoicePlaybackState.idle());
    await _playbackStates.close();
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
