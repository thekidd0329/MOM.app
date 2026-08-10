#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VOICE = ROOT / "apps/mom_native/lib/src/voice_service.dart"
MAIN = ROOT / "apps/mom_native/lib/main.dart"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Phase10 anchor {label!r} expected once, found {count}")
    return text.replace(old, new, 1)


voice = VOICE.read_text()
main = MAIN.read_text()

voice = replace_once(
    voice,
    "  String _lastMeaningfulPartial = '';\n",
    "  String _lastMeaningfulPartial = '';\n"
    "  bool _handsFreeArmed = false;\n"
    "  bool _finalTranscriptDelivered = false;\n"
    "  int _handsFreeGeneration = 0;\n",
    "hands-free fields",
)

voice = replace_once(
    voice,
    "  MomVoiceException? get lastFailure => _lastFailure;\n",
    "  MomVoiceException? get lastFailure => _lastFailure;\n"
    "  bool get handsFreeArmed => _handsFreeArmed;\n",
    "hands-free getter",
)

voice = replace_once(
    voice,
    "  Future<void> listen({\n"
    "    required void Function(String text) onFinal,\n"
    "    required void Function(bool listening) onState,\n"
    "  }) async {\n"
    "    await stopBargeInDetection();\n",
    "  Future<void> listen({\n"
    "    required void Function(String text) onFinal,\n"
    "    required void Function(bool listening) onState,\n"
    "  }) async {\n"
    "    _handsFreeArmed = true;\n"
    "    _finalTranscriptDelivered = false;\n"
    "    await stopBargeInDetection();\n",
    "arm on listen",
)

voice = replace_once(
    voice,
    "          _lastMeaningfulPartial = '';\n"
    "          onFinal(text);\n"
    "          onState(false);\n",
    "          _lastMeaningfulPartial = '';\n"
    "          _finalTranscriptDelivered = true;\n"
    "          onFinal(text);\n"
    "          onState(false);\n",
    "normal final transcript",
)

voice = replace_once(
    voice,
    "        stateHandler(false);\n"
    "        finalHandler(text.trim());\n",
    "        _finalTranscriptDelivered = true;\n"
    "        stateHandler(false);\n"
    "        finalHandler(text.trim());\n",
    "barge-in final transcript",
)

voice = replace_once(
    voice,
    "          if (_speech.isListening) await _speech.stop();\n"
    "          onState(false);\n"
    "        }());\n",
    "          if (_speech.isListening) await _speech.stop();\n"
    "          onState(false);\n"
    "          _scheduleHandsFreeResume(delay: const Duration(milliseconds: 650));\n"
    "        }());\n",
    "listen timeout rearm",
)

voice = replace_once(
    voice,
    "        await speak(redirect, automaticBargeIn: false);\n",
    "        await speak(\n"
    "          redirect,\n"
    "          automaticBargeIn: false,\n"
    "          resumeHandsFree: false,\n"
    "        );\n",
    "redirect speech",
)

voice = replace_once(
    voice,
    "        await speak('Wait, what did you just say?', automaticBargeIn: false);\n",
    "        await speak(\n"
    "          'Wait, what did you just say?',\n"
    "          automaticBargeIn: false,\n"
    "          resumeHandsFree: false,\n"
    "        );\n",
    "clarification speech",
)

voice = replace_once(
    voice,
    "  Future<void> stopListening() async {\n"
    "    _listenGuard.invalidate();\n",
    "  Future<void> stopListening() async {\n"
    "    if (!_finalTranscriptDelivered) {\n"
    "      disarmHandsFree();\n"
    "    }\n"
    "    _finalTranscriptDelivered = false;\n"
    "    _listenGuard.invalidate();\n",
    "manual stop disarm",
)

voice = replace_once(
    voice,
    "  Future<void> stopSpeaking({bool preserveContinuity = false}) async {\n",
    "  void disarmHandsFree() {\n"
    "    _handsFreeArmed = false;\n"
    "    _finalTranscriptDelivered = false;\n"
    "    _handsFreeGeneration++;\n"
    "  }\n\n"
    "  void _scheduleHandsFreeResume({\n"
    "    Duration delay = const Duration(milliseconds: 260),\n"
    "  }) {\n"
    "    if (!_handsFreeArmed) return;\n"
    "    final generation = ++_handsFreeGeneration;\n"
    "    unawaited(() async {\n"
    "      await Future<void>.delayed(delay);\n"
    "      if (!_handsFreeArmed || generation != _handsFreeGeneration) return;\n"
    "      final finalHandler = _conversationFinal;\n"
    "      final stateHandler = _conversationListeningState;\n"
    "      if (finalHandler == null || stateHandler == null) return;\n"
    "      if (_speech.isListening || _playingFile != null) return;\n"
    "      try {\n"
    "        await listen(onFinal: finalHandler, onState: stateHandler);\n"
    "      } catch (error) {\n"
    "        _lastFailure = error is MomVoiceException\n"
    "            ? error\n"
    "            : MomVoiceException('hands_free_listen', error);\n"
    "        disarmHandsFree();\n"
    "        stateHandler(false);\n"
    "      }\n"
    "    }());\n"
    "  }\n\n"
    "  Future<void> stopSpeaking({bool preserveContinuity = false}) async {\n",
    "hands-free helpers",
)

voice = replace_once(
    voice,
    "  Future<void> speak(\n"
    "    String text, {\n"
    "    void Function()? onSynthesisStart,\n"
    "    void Function()? onPlaybackStart,\n"
    "    bool automaticBargeIn = true,\n"
    "  }) async {\n",
    "  Future<void> speak(\n"
    "    String text, {\n"
    "    void Function()? onSynthesisStart,\n"
    "    void Function()? onPlaybackStart,\n"
    "    bool automaticBargeIn = true,\n"
    "    bool resumeHandsFree = true,\n"
    "  }) async {\n",
    "speak resume flag",
)

voice = replace_once(
    voice,
    "      _lastMomSpeech = _normalizeSpeech(text);\n"
    "      _clearSpeechTracking();\n"
    "    }\n"
    "    _lastFailure = null;\n"
    "  }\n\n"
    "  Future<void> speakStream(",
    "      _lastMomSpeech = _normalizeSpeech(text);\n"
    "      _clearSpeechTracking();\n"
    "      if (resumeHandsFree) _scheduleHandsFreeResume();\n"
    "    }\n"
    "    _lastFailure = null;\n"
    "  }\n\n"
    "  Future<void> speakStream(",
    "completed nonstream speech resume",
)

voice = replace_once(
    voice,
    "        _lastMomSpeech = _normalizeSpeech(expectedSpeech.toString());\n"
    "        _clearSpeechTracking();\n"
    "      }\n"
    "      _lastFailure = null;\n",
    "        _lastMomSpeech = _normalizeSpeech(expectedSpeech.toString());\n"
    "        _clearSpeechTracking();\n"
    "        _scheduleHandsFreeResume();\n"
    "      }\n"
    "      _lastFailure = null;\n",
    "completed stream speech resume",
)

main = replace_once(
    main,
    "  Future<void> _voiceFailed(Object error, {required String fallbackStage}) async {\n"
    "    final stage = error is MomVoiceException ? error.stage : fallbackStage;\n",
    "  Future<void> _voiceFailed(Object error, {required String fallbackStage}) async {\n"
    "    _voice.disarmHandsFree();\n"
    "    final stage = error is MomVoiceException ? error.stage : fallbackStage;\n",
    "voice error disarm",
)

main = replace_once(
    main,
    "    if (config == null || sync == null || text.trim().isEmpty) return;\n\n"
    "    if (_voiceState.state == MomVoiceState.listening) {\n",
    "    if (config == null || sync == null || text.trim().isEmpty) return;\n"
    "    if (inputMode != 'voice') _voice.disarmHandsFree();\n\n"
    "    if (_voiceState.state == MomVoiceState.listening) {\n",
    "keyboard disarm",
)

VOICE.write_text(voice)
MAIN.write_text(main)
print("Phase 10 hands-free patch applied")
