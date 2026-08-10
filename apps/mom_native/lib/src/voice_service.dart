import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:crispasr/crispasr.dart' as crisp;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'partial_redirector.dart';
import 'transcript_quality.dart';
import 'tts_chunker.dart';
import 'voice_continuity.dart';

const _modelName = 'kokoro-82m-q8_0.gguf';
const _voiceName = 'kokoro-voice-af_heart.gguf';
const _modelUrl =
    'https://huggingface.co/cstr/kokoro-82m-GGUF/resolve/main/kokoro-82m-q8_0.gguf?download=true';
const _voiceUrl =
    'https://huggingface.co/cstr/kokoro-voices-GGUF/resolve/main/kokoro-voice-af_heart.gguf?download=true';
const _maxSynthesizedAhead = 2;
const _kokoroSampleRate = 24000;

class MomVoiceException implements Exception {
  const MomVoiceException(this.stage, this.cause);

  final String stage;
  final Object cause;

  @override
  String toString() => 'MOM voice $stage failed: $cause';
}

bool looksLikeMomSpeakerEcho(String candidate, String momSpeech) {
  List<String> words(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);

  final heard = words(candidate);
  final spoken = words(momSpeech);
  if (heard.isEmpty || spoken.isEmpty) return false;

  final heardPhrase = heard.join(' ');
  final spokenPhrase = spoken.join(' ');
  if (spokenPhrase.contains(heardPhrase)) return true;

  final spokenSet = spoken.toSet();
  final overlap = heard.where(spokenSet.contains).length / heard.length;
  return heard.length >= 2 && overlap >= 0.80;
}

class MomVoiceService {
  final SpeechToText _speech = SpeechToText();
  final AudioPlayer _player = AudioPlayer();
  final MomTtsChunker _chunker = const MomTtsChunker();
  final MomPartialRedirector _redirector = const MomPartialRedirector();
  final MomTranscriptQuality _transcriptQuality = const MomTranscriptQuality();

  bool _speechReady = false;
  Future<_VoiceAssets>? _assetsFuture;
  int _speechGeneration = 0;
  int _bargeInGeneration = 0;
  File? _playingFile;
  Completer<void>? _playbackCancelled;
  void Function(bool listening)? _listeningState;
  void Function(String text)? _conversationFinal;
  void Function(bool listening)? _conversationListeningState;
  void Function(Object error)? _bargeInError;
  MomVoiceException? _lastFailure;
  bool _bargeInDetected = false;
  bool _redirectInFlight = false;
  bool _clarificationInFlight = false;
  DateTime _redirectCooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastMomSpeech = '';
  String _lastMeaningfulPartial = '';

  String _generatedSpeechText = '';
  final List<String> _completedSpokenChunks = <String>[];
  String _activeChunkText = '';
  DateTime? _activeChunkStartedAt;
  Duration _activeChunkDuration = Duration.zero;

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
          final bargeError = _bargeInError;
          if (bargeError != null) {
            bargeError(error);
          } else {
            _lastFailure = MomVoiceException('speech_recognition', error);
            _listeningState?.call(false);
          }
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
    await stopBargeInDetection();
    if (!_speechReady) await initialize();
    _conversationFinal = onFinal;
    _conversationListeningState = onState;
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
          final text = result.recognizedWords.trim();
          if (text.isEmpty) return;

          if (!result.finalResult) {
            _lastMeaningfulPartial = text;
            if (!_redirectInFlight &&
                !_clarificationInFlight &&
                DateTime.now().isAfter(_redirectCooldownUntil)) {
              final redirect = _redirector.redirectFor(
                lastMomSpeech: _lastMomSpeech,
                partialTranscript: text,
              );
              if (redirect != null) {
                _redirectInFlight = true;
                unawaited(_interruptOffTrackUser(
                  redirect: redirect,
                  onFinal: onFinal,
                  onState: onState,
                ));
              }
            }
            return;
          }

          if (_redirectInFlight || _clarificationInFlight) return;
          final shouldClarify = _transcriptQuality.shouldClarify(
            finalTranscript: text,
            previousPartial: _lastMeaningfulPartial,
          );
          if (shouldClarify) {
            _clarificationInFlight = true;
            unawaited(_clarifyTranscript(onFinal: onFinal, onState: onState));
            return;
          }

          _lastMeaningfulPartial = '';
          onFinal(text);
          onState(false);
        },
      );
      if (!_speech.isListening &&
          !_redirectInFlight &&
          !_clarificationInFlight) {
        onState(false);
      }
    } catch (error) {
      if (_redirectInFlight || _clarificationInFlight) return;
      onState(false);
      final failure = error is MomVoiceException
          ? error
          : MomVoiceException('speech_recognition', error);
      _lastFailure = failure;
      throw failure;
    }
  }

  Future<void> _interruptOffTrackUser({
    required String redirect,
    required void Function(String text) onFinal,
    required void Function(bool listening) onState,
  }) async {
    try {
      if (_speech.isListening) await _speech.stop();
      onState(false);
      _redirectCooldownUntil = DateTime.now().add(const Duration(seconds: 20));
      try {
        await speak(redirect, automaticBargeIn: false);
      } catch (error) {
        _lastFailure = error is MomVoiceException
            ? error
            : MomVoiceException('redirect_speech', error);
      }
    } finally {
      _redirectInFlight = false;
      _lastMeaningfulPartial = '';
    }

    await Future<void>.delayed(const Duration(milliseconds: 80));
    await listen(onFinal: onFinal, onState: onState);
  }

  Future<void> _clarifyTranscript({
    required void Function(String text) onFinal,
    required void Function(bool listening) onState,
  }) async {
    try {
      if (_speech.isListening) await _speech.stop();
      onState(false);
      _redirectCooldownUntil = DateTime.now().add(const Duration(seconds: 10));
      try {
        await speak('Wait, what did you just say?', automaticBargeIn: false);
      } catch (error) {
        _lastFailure = error is MomVoiceException
            ? error
            : MomVoiceException('clarification_speech', error);
      }
    } finally {
      _clarificationInFlight = false;
      _lastMeaningfulPartial = '';
    }

    await Future<void>.delayed(const Duration(milliseconds: 80));
    await listen(onFinal: onFinal, onState: onState);
  }

  Future<void> listenForBargeIn({
    required String Function() expectedMomSpeech,
    required void Function(String partialText) onDetected,
    required void Function(String finalText) onFinal,
    required void Function(Object error) onError,
  }) async {
    if (!_speechReady) await initialize();
    if (!_speechReady) return;

    final generation = ++_bargeInGeneration;
    _bargeInDetected = false;
    _bargeInError = onError;
    _listeningState = null;

    try {
      if (_speech.isListening) await _speech.stop();
      await _speech.listen(
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
        ),
        onResult: (result) {
          if (generation != _bargeInGeneration) return;
          final text = result.recognizedWords.trim();
          if (text.isEmpty) return;

          final echo = looksLikeMomSpeakerEcho(text, expectedMomSpeech());
          if (!_bargeInDetected && !echo) {
            final wordCount = text.split(RegExp(r'\s+')).length;
            if (wordCount >= 2 || text.length >= 8) {
              _bargeInDetected = true;
              onDetected(text);
            }
          }

          if (_bargeInDetected && result.finalResult) {
            onFinal(text);
          }
        },
      );
    } catch (error) {
      if (generation == _bargeInGeneration) onError(error);
    }
  }

  Future<void> _armAutomaticBargeIn(String Function() expectedMomSpeech) async {
    final finalHandler = _conversationFinal;
    final stateHandler = _conversationListeningState;
    if (finalHandler == null || stateHandler == null || !_speechReady) return;

    await listenForBargeIn(
      expectedMomSpeech: expectedMomSpeech,
      onDetected: (_) {
        unawaited(() async {
          await stopSpeaking(preserveContinuity: true);
          await Future<void>.delayed(Duration.zero);
          stateHandler(true);
        }());
      },
      onFinal: (text) {
        if (text.trim().isEmpty) return;
        _bargeInError = null;
        _listeningState = stateHandler;
        stateHandler(false);
        finalHandler(text.trim());
      },
      onError: (error) {
        _lastFailure = MomVoiceException('barge_in_stt', error);
      },
    );
  }

  Future<void> stopBargeInDetection() async {
    _bargeInGeneration++;
    _bargeInDetected = false;
    _bargeInError = null;
    if (_speech.isListening) await _speech.stop();
  }

  Future<void> stopListening() async {
    _bargeInGeneration++;
    _bargeInError = null;
    _lastMeaningfulPartial = '';
    await _speech.stop();
    _listeningState?.call(false);
    _listeningState = null;
  }

  Future<void> stopSpeaking({bool preserveContinuity = false}) async {
    if (preserveContinuity) _preserveInterruptedThought();
    _speechGeneration++;
    final cancellation = _playbackCancelled;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    await _player.stop();
    final playing = _playingFile;
    _playingFile = null;
    if (playing != null && await playing.exists()) {
      await playing.delete();
    }
    _clearSpeechTracking();
  }

  void _beginSpeechTracking(String generatedText) {
    _generatedSpeechText = _normalizeSpeech(generatedText);
    _completedSpokenChunks.clear();
    _activeChunkText = '';
    _activeChunkStartedAt = null;
    _activeChunkDuration = Duration.zero;
  }

  void _updateGeneratedSpeech(String generatedText) {
    _generatedSpeechText = _normalizeSpeech(generatedText);
  }

  void _startActiveChunk(String text, Uint8List wav) {
    _activeChunkText = _normalizeSpeech(text);
    _activeChunkStartedAt = DateTime.now();
    final pcmBytes = math.max(0, wav.length - 44);
    final sampleCount = pcmBytes ~/ 2;
    final microseconds = sampleCount == 0
        ? 0
        : ((sampleCount / _kokoroSampleRate) * 1000000).round();
    _activeChunkDuration = Duration(microseconds: microseconds);
  }

  void _finishActiveChunk(String text) {
    final normalized = _normalizeSpeech(text);
    if (normalized.isNotEmpty) _completedSpokenChunks.add(normalized);
    _activeChunkText = '';
    _activeChunkStartedAt = null;
    _activeChunkDuration = Duration.zero;
  }

  void _preserveInterruptedThought() {
    final fullWords = _normalizeSpeech(_generatedSpeechText)
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (fullWords.isEmpty) return;

    var heardWordCount = _completedSpokenChunks
        .expand((chunk) => chunk.split(RegExp(r'\s+')))
        .where((word) => word.isNotEmpty)
        .length;

    final active = _activeChunkText.trim();
    var partial = false;
    if (active.isNotEmpty) {
      partial = true;
      final activeWords = active
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .toList(growable: false);
      final started = _activeChunkStartedAt;
      final durationMicros = _activeChunkDuration.inMicroseconds;
      var fraction = 0.0;
      if (started != null && durationMicros > 0) {
        fraction = DateTime.now().difference(started).inMicroseconds /
            durationMicros;
      }
      fraction = fraction.clamp(0.0, 1.0);
      final heardInActive = (activeWords.length * fraction).floor();
      heardWordCount += heardInActive;
    }

    heardWordCount = heardWordCount.clamp(0, fullWords.length);
    final heard = fullWords.take(heardWordCount).join(' ').trim();
    final unsaid = fullWords.skip(heardWordCount).join(' ').trim();
    if (unsaid.isEmpty) return;

    MomVoiceContinuity.preserve(
      InterruptedMomThought(
        heardText: heard,
        unsaidText: unsaid,
        currentChunkMayBePartial: partial,
      ),
    );
  }

  String _normalizeSpeech(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  void _clearSpeechTracking() {
    _generatedSpeechText = '';
    _completedSpokenChunks.clear();
    _activeChunkText = '';
    _activeChunkStartedAt = null;
    _activeChunkDuration = Duration.zero;
  }

  Future<void> speak(
    String text, {
    void Function()? onSynthesisStart,
    void Function()? onPlaybackStart,
    bool automaticBargeIn = true,
  }) async {
    final chunks = _chunker.chunk(text);
    if (chunks.isEmpty) return;

    final generation = ++_speechGeneration;
    _beginSpeechTracking(text);
    final assets = await _requireAssets();
    if (generation != _speechGeneration) return;

    onSynthesisStart?.call();
    await _preparePlayerForGeneration();
    final pending = <int, Future<Uint8List>>{};

    Future<Uint8List> synthesizeChunk(int index) =>
        _synthesizeText(chunks[index], assets);

    for (var index = 0; index < chunks.length; index++) {
      if (generation != _speechGeneration) return;

      final prefetchEnd = math.min(
        chunks.length,
        index + _maxSynthesizedAhead,
      );
      for (var queued = index; queued < prefetchEnd; queued++) {
        pending.putIfAbsent(queued, () => synthesizeChunk(queued));
      }
      if (pending.length > _maxSynthesizedAhead) {
        final failure = const MomVoiceException(
          'synthesis',
          'Kokoro synthesis queue exceeded memory bound',
        );
        _lastFailure = failure;
        throw failure;
      }

      final wav = await _awaitSynthesis(pending.remove(index)!);
      if (generation != _speechGeneration) return;
      await _playWav(
        wav,
        chunkText: chunks[index],
        assets: assets,
        generation: generation,
        index: index,
        onPlaybackStart: index == 0
            ? () {
                onPlaybackStart?.call();
                if (automaticBargeIn) {
                  unawaited(_armAutomaticBargeIn(() => text));
                }
              }
            : null,
      );
    }
    if (generation == _speechGeneration) {
      await stopBargeInDetection();
      _lastMomSpeech = _normalizeSpeech(text);
      _clearSpeechTracking();
    }
    _lastFailure = null;
  }

  Future<void> speakStream(
    Stream<String> deltas, {
    void Function()? onSynthesisStart,
    void Function()? onPlaybackStart,
  }) async {
    final generation = ++_speechGeneration;
    _beginSpeechTracking('');
    final assets = await _requireAssets();
    if (generation != _speechGeneration) return;

    await _preparePlayerForGeneration();
    final assembler = MomStreamingTtsAssembler(chunker: _chunker);
    final expectedSpeech = StringBuffer();
    var index = 0;
    var synthesisStarted = false;

    Future<void> speakChunk(String chunk) async {
      if (generation != _speechGeneration || chunk.trim().isEmpty) return;
      if (!synthesisStarted) {
        synthesisStarted = true;
        onSynthesisStart?.call();
      }
      final wav = await _awaitSynthesis(_synthesizeText(chunk, assets));
      if (generation != _speechGeneration) return;
      await _playWav(
        wav,
        chunkText: chunk,
        assets: assets,
        generation: generation,
        index: index,
        onPlaybackStart: index == 0
            ? () {
                onPlaybackStart?.call();
                unawaited(
                  _armAutomaticBargeIn(() => expectedSpeech.toString()),
                );
              }
            : null,
      );
      index++;
    }

    try {
      await for (final delta in deltas) {
        if (generation != _speechGeneration) return;
        expectedSpeech.write(delta);
        _updateGeneratedSpeech(expectedSpeech.toString());
        for (final chunk in assembler.add(delta)) {
          await speakChunk(chunk);
        }
      }
      for (final chunk in assembler.close()) {
        await speakChunk(chunk);
      }
      if (generation == _speechGeneration) {
        await stopBargeInDetection();
        _lastMomSpeech = _normalizeSpeech(expectedSpeech.toString());
        _clearSpeechTracking();
      }
      _lastFailure = null;
    } catch (error) {
      final failure = error is MomVoiceException
          ? error
          : MomVoiceException('stream_playback', error);
      _lastFailure = failure;
      throw failure;
    }
  }

  Future<_VoiceAssets> _requireAssets() async {
    try {
      return await _prepareVoiceAssets();
    } catch (error) {
      final failure = error is MomVoiceException
          ? error
          : MomVoiceException('assets', error);
      _lastFailure = failure;
      throw failure;
    }
  }

  Future<Uint8List> _synthesizeText(String text, _VoiceAssets assets) async {
    final request = _SynthesisRequest(
      modelPath: assets.model.path,
      voicePath: assets.voice.path,
      text: text,
    );
    try {
      final wav = await Isolate.run(() => _synthesize(request));
      if (wav.length <= 44) {
        throw const FormatException('Kokoro returned an empty audio buffer');
      }
      return wav;
    } catch (error) {
      throw MomVoiceException('synthesis', error);
    }
  }

  Future<Uint8List> _awaitSynthesis(Future<Uint8List> synthesis) async {
    try {
      return await synthesis;
    } catch (error) {
      final failure = error is MomVoiceException
          ? error
          : MomVoiceException('synthesis', error);
      _lastFailure = failure;
      throw failure;
    }
  }

  Future<void> _preparePlayerForGeneration() async {
    final previousCancellation = _playbackCancelled;
    if (previousCancellation != null && !previousCancellation.isCompleted) {
      previousCancellation.complete();
    }
    await _player.stop();
    final previous = _playingFile;
    if (previous != null && await previous.exists()) {
      await previous.delete();
    }
    _playingFile = null;
    _playbackCancelled = Completer<void>();
  }

  Future<void> _playWav(
    Uint8List wav, {
    required String chunkText,
    required _VoiceAssets assets,
    required int generation,
    required int index,
    void Function()? onPlaybackStart,
  }) async {
    final output = File(
      '${assets.directory.path}/mom-response-$generation-$index.wav',
    );
    try {
      await output.writeAsBytes(wav, flush: true);
      if (generation != _speechGeneration) return;

      final completed = _player.onPlayerComplete.first;
      final cancelled = _playbackCancelled?.future ?? Future<void>.value();
      await _player.play(DeviceFileSource(output.path));
      _playingFile = output;
      _startActiveChunk(chunkText, wav);
      onPlaybackStart?.call();
      await Future.any<void>([completed, cancelled]).timeout(
        const Duration(minutes: 2),
        onTimeout: () {},
      );
      if (generation == _speechGeneration) _finishActiveChunk(chunkText);
    } catch (error) {
      throw MomVoiceException('playback', error);
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
    _bargeInGeneration++;
    final cancellation = _playbackCancelled;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    _listeningState?.call(false);
    _listeningState = null;
    _conversationFinal = null;
    _conversationListeningState = null;
    _bargeInError = null;
    _lastMeaningfulPartial = '';
    _clearSpeechTracking();
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
    return _pcmToWav(pcm, _kokoroSampleRate);
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
