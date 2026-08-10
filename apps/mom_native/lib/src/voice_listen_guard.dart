import 'dart:async';

class MomListenSessionGuard {
  int _generation = 0;
  Timer? _timeout;

  int get generation => _generation;

  int begin({
    required Duration timeout,
    required void Function() onTimeout,
  }) {
    _timeout?.cancel();
    final generation = ++_generation;
    _timeout = Timer(timeout, () {
      if (generation == _generation) onTimeout();
    });
    return generation;
  }

  bool isCurrent(int generation) => generation == _generation;

  void complete(int generation) {
    if (!isCurrent(generation)) return;
    _generation++;
    _timeout?.cancel();
    _timeout = null;
  }

  void invalidate() {
    _generation++;
    _timeout?.cancel();
    _timeout = null;
  }

  void dispose() => invalidate();
}
