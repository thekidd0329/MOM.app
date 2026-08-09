import 'package:record/record.dart';

enum MomMicrophoneState {
  unknown,
  available,
  permissionNeeded,
  unavailable,
  error,
}

class MomMicrophoneStatus {
  const MomMicrophoneStatus({
    required this.state,
    required this.permissionGranted,
    required this.inputCount,
    this.detail = '',
  });

  const MomMicrophoneStatus.unknown()
      : state = MomMicrophoneState.unknown,
        permissionGranted = false,
        inputCount = 0,
        detail = '';

  final MomMicrophoneState state;
  final bool permissionGranted;
  final int inputCount;
  final String detail;

  bool get available => state == MomMicrophoneState.available;

  String get label {
    switch (state) {
      case MomMicrophoneState.available:
        return 'available';
      case MomMicrophoneState.permissionNeeded:
        return 'permission_needed';
      case MomMicrophoneState.unavailable:
        return 'unavailable';
      case MomMicrophoneState.error:
        return 'error';
      case MomMicrophoneState.unknown:
        return 'unknown';
    }
  }

  Map<String, dynamic> toJson() => {
        'state': label,
        'available': available,
        'permission_granted': permissionGranted,
        'input_count': inputCount,
        if (detail.isNotEmpty) 'detail': detail,
      };
}

class MomRuntimeDeviceState {
  static MomMicrophoneStatus microphone =
      const MomMicrophoneStatus.unknown();

  static String get promptContext => '''
## Current device context
Microphone state: ${microphone.label}.
Microphone permission granted: ${microphone.permissionGranted}.
Detected microphone inputs: ${microphone.inputCount}.
Treat this as live device state, not as a personal fact about your person. Do not narrate these implementation details unless they are relevant to what your person asks.
'''.trim();
}

class MomMicrophoneProbe {
  final AudioRecorder _recorder = AudioRecorder();

  MomMicrophoneStatus _publish(MomMicrophoneStatus status) {
    MomRuntimeDeviceState.microphone = status;
    return status;
  }

  Future<MomMicrophoneStatus> probe({bool requestPermission = false}) async {
    try {
      final permission =
          await _recorder.hasPermission(request: requestPermission);

      List<InputDevice> inputs = const [];
      try {
        inputs = await _recorder.listInputDevices();
      } catch (_) {
        // Some platforms do not expose an input list until permission is granted.
      }

      if (inputs.isNotEmpty) {
        return _publish(MomMicrophoneStatus(
          state: permission
              ? MomMicrophoneState.available
              : MomMicrophoneState.permissionNeeded,
          permissionGranted: permission,
          inputCount: inputs.length,
        ));
      }

      if (!permission) {
        return _publish(const MomMicrophoneStatus(
          state: MomMicrophoneState.permissionNeeded,
          permissionGranted: false,
          inputCount: 0,
        ));
      }

      return _publish(const MomMicrophoneStatus(
        state: MomMicrophoneState.unavailable,
        permissionGranted: true,
        inputCount: 0,
      ));
    } catch (error) {
      return _publish(MomMicrophoneStatus(
        state: MomMicrophoneState.error,
        permissionGranted: false,
        inputCount: 0,
        detail: error.runtimeType.toString(),
      ));
    }
  }

  Future<void> dispose() => _recorder.dispose();
}
