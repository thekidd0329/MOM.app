import 'package:flutter/services.dart';

class MomSpeechRecognitionResult {
  const MomSpeechRecognitionResult({
    required this.recognizedWords,
    required this.finalResult,
    this.confidence,
  });

  final String recognizedWords;
  final bool finalResult;
  final double? confidence;
}

class MomSpeechRecognitionError implements Exception {
  const MomSpeechRecognitionError({
    required this.code,
    required this.message,
    this.permanent = false,
  });

  final String code;
  final String message;
  final bool permanent;

  @override
  String toString() => 'On-device speech error ($code): $message';
}

abstract interface class MomSpeechRecognizer {
  String get mode;
  bool get strictlyOnDevice;
  bool get isListening;

  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(Object error) onError,
  });

  Future<void> listen({
    required void Function(MomSpeechRecognitionResult result) onResult,
    bool partialResults = true,
    bool cancelOnError = true,
    String? locale,
  });

  Future<void> stop();
  Future<void> cancel();
  Future<void> dispose();
}

/// Android's API 31+ on-device recognizer. This adapter deliberately has no
/// generic SpeechRecognizer fallback: unavailable local recognition fails
/// closed and the keyboard remains usable.
class AndroidOnDeviceSpeechRecognizer implements MomSpeechRecognizer {
  AndroidOnDeviceSpeechRecognizer({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName =
      'app.mom.mom_native/on_device_speech_recognizer';

  final MethodChannel _channel;
  void Function(String status)? _onStatus;
  void Function(Object error)? _onError;
  void Function(MomSpeechRecognitionResult result)? _onResult;
  bool _available = false;
  bool _isListening = false;
  bool _disposed = false;
  int _generation = 0;

  @override
  String get mode => 'android_on_device';

  @override
  bool get strictlyOnDevice => true;

  @override
  bool get isListening => _isListening;

  @override
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(Object error) onError,
  }) async {
    if (_disposed) return false;
    _onStatus = onStatus;
    _onError = onError;
    _channel.setMethodCallHandler(_handleNativeCall);
    try {
      _available =
          await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      _available = false;
    } on PlatformException catch (error) {
      _available = false;
      _onError?.call(_platformError(error));
    }
    return _available;
  }

  @override
  Future<void> listen({
    required void Function(MomSpeechRecognitionResult result) onResult,
    bool partialResults = true,
    bool cancelOnError = true,
    String? locale,
  }) async {
    if (_disposed) {
      throw const MomSpeechRecognitionError(
        code: 'recognizer_disposed',
        message: 'The on-device recognizer has already been disposed.',
        permanent: true,
      );
    }
    if (!_available) {
      throw const MomSpeechRecognitionError(
        code: 'on_device_recognizer_unavailable',
        message: 'This phone has no available on-device speech recognizer.',
        permanent: true,
      );
    }
    if (_isListening) {
      throw const MomSpeechRecognitionError(
        code: 'recognizer_busy',
        message: 'The on-device recognizer is already listening.',
      );
    }

    final generation = ++_generation;
    _onResult = onResult;
    _isListening = true;
    try {
      await _channel.invokeMethod<void>('start', {
        'generation': generation,
        'partial_results': partialResults,
        'cancel_on_error': cancelOnError,
        if (locale != null && locale.trim().isNotEmpty)
          'locale': locale.trim(),
      });
    } on PlatformException catch (error) {
      _isListening = false;
      throw _platformError(error);
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed || !_isListening) return;
    try {
      await _channel.invokeMethod<void>('stop', {'generation': _generation});
    } on PlatformException catch (error) {
      _isListening = false;
      throw _platformError(error);
    }
  }

  @override
  Future<void> cancel() async {
    if (_disposed || !_isListening) return;
    final cancelledGeneration = _generation;
    _generation++;
    _isListening = false;
    _onStatus?.call('cancelled');
    try {
      await _channel.invokeMethod<void>(
        'cancel',
        {'generation': cancelledGeneration},
      );
    } on MissingPluginException {
      // The recognizer is already locally invalidated.
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    final arguments = call.arguments;
    if (_disposed || arguments is! Map) return;
    final payload = Map<String, dynamic>.from(arguments);
    final generation = (payload['generation'] as num?)?.toInt();
    if (generation != null && generation != _generation) return;

    switch (call.method) {
      case 'speechStatus':
        final status = '${payload['status'] ?? ''}'.trim();
        if (status == 'done' || status == 'cancelled') {
          _isListening = false;
        }
        if (status.isNotEmpty) _onStatus?.call(status);
        return;
      case 'speechResult':
        final text = '${payload['text'] ?? ''}'.trim();
        if (text.isEmpty) return;
        final finalResult = payload['final'] == true;
        if (finalResult) _isListening = false;
        _onResult?.call(MomSpeechRecognitionResult(
          recognizedWords: text,
          finalResult: finalResult,
          confidence: (payload['confidence'] as num?)?.toDouble(),
        ));
        return;
      case 'speechError':
        _isListening = false;
        _onError?.call(MomSpeechRecognitionError(
          code: '${payload['code'] ?? 'speech_error'}',
          message: '${payload['message'] ?? 'On-device recognition failed.'}',
          permanent: payload['permanent'] == true,
        ));
        return;
    }
  }

  MomSpeechRecognitionError _platformError(PlatformException error) =>
      MomSpeechRecognitionError(
        code: error.code,
        message: error.message ?? 'On-device recognition failed.',
        permanent: error.code == 'on_device_recognizer_unavailable' ||
            error.code == 'unsupported_android_version',
      );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _isListening = false;
    _onResult = null;
    try {
      await _channel.invokeMethod<void>('destroy');
    } on MissingPluginException {
      // No Android plugin exists on non-Android test/desktop targets.
    } finally {
      _channel.setMethodCallHandler(null);
      _onStatus = null;
      _onError = null;
    }
  }
}
