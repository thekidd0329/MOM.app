import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum PlasmaOrbState { idle, listening, thinking, talking, error }

extension on PlasmaOrbState {
  String get wireName => name;
}

/// Hosts MOM's Android plasma renderer while keeping the approved orb artwork
/// as a static fallback on non-Android platforms.
class NativePlasmaOrb extends StatefulWidget {
  const NativePlasmaOrb({
    super.key,
    required this.state,
    required this.fallback,
  });

  final PlasmaOrbState state;
  final Widget fallback;

  @override
  State<NativePlasmaOrb> createState() => _NativePlasmaOrbState();
}

class _NativePlasmaOrbState extends State<NativePlasmaOrb> {
  MethodChannel? _channel;

  @override
  void didUpdateWidget(covariant NativePlasmaOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      unawaited(_pushState());
    }
  }

  void _onPlatformViewCreated(int id) {
    _channel = MethodChannel('mom/plasma_orb/$id');
    unawaited(_pushState());
  }

  Future<void> _pushState() async {
    final channel = _channel;
    if (channel == null) return;
    try {
      await channel.invokeMethod<void>('setState', <String, Object>{
        'state': widget.state.wireName,
      });
    } on MissingPluginException {
      // A rebuilt/generated Android shell may not have registered the view yet.
      // Keep the frame alive; the static artwork remains the safe fallback.
    }
  }

  @override
  void dispose() {
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return widget.fallback;
    }

    return AndroidView(
      viewType: 'mom/plasma_orb',
      creationParams: <String, Object>{'state': widget.state.wireName},
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _onPlatformViewCreated,
    );
  }
}
