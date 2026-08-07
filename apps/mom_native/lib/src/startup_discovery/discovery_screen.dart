import 'package:flutter/material.dart';

import 'discovery_engine.dart';
import 'discovery_models.dart';
import 'discovery_store.dart';

class StartupDiscoveryScreen extends StatefulWidget {
  const StartupDiscoveryScreen({
    super.key,
    required this.onComplete,
  });

  final Future<void> Function(DiscoveryProgress progress) onComplete;

  @override
  State<StartupDiscoveryScreen> createState() => _StartupDiscoveryScreenState();
}

class _StartupDiscoveryScreenState extends State<StartupDiscoveryScreen> {
  final DiscoveryEngine _engine = const DiscoveryEngine();
  final DiscoveryProgressStore _store = DiscoveryProgressStore();
  final PageController _carousel = PageController(viewportFraction: 0.88);

  DiscoveryProgress _progress = const DiscoveryProgress();
  bool _loading = true;
  bool _saving = false;
  int _selectedCard = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final progress = await _store.load();
    if (!mounted) return;
    setState(() {
      _progress = progress;
      _loading = false;
    });
    if (progress.complete) {
      await widget.onComplete(progress);
    }
  }

  Future<void> _choose(DiscoveryNode node, DiscoveryChoice choice) async {
    if (_saving) return;
    setState(() => _saving = true);

    final next = _engine.answer(_progress, node, choice);
    await _store.save(next);

    if (!mounted) return;
    if (next.complete || _engine.nextNode(next) == null) {
      final completed = next.copyWith(complete: true);
      await _store.save(completed);
      setState(() => _progress = completed);
      await widget.onComplete(completed);
      return;
    }

    setState(() {
      _progress = next;
      _selectedCard = 0;
      _saving = false;
    });
    if (_carousel.hasClients) _carousel.jumpToPage(0);
  }

  @override
  void dispose() {
    _carousel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final node = _engine.nextNode(_progress);
    if (node == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final prompt = _engine.promptFor(node, _progress);
    final progressValue = (_progress.answeredCount / DiscoveryEngine.maximumQuestions).clamp(0.0, 1.0);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: progressValue,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('${_progress.answeredCount + 1}', style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
              const SizedBox(height: 34),
              Text(
                _progress.answeredCount < 4 ? 'Let me get my bearings.' : 'Okay, that tells me something.',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                prompt,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              Text('Pick the closest one. It does not have to be perfect.', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 26),
              Expanded(
                child: PageView.builder(
                  controller: _carousel,
                  itemCount: node.choices.length,
                  onPageChanged: (value) => setState(() => _selectedCard = value),
                  itemBuilder: (context, index) {
                    final choice = node.choices[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        elevation: index == _selectedCard ? 6 : 1,
                        child: InkWell(
                          onTap: _saving ? null : () => _choose(node, choice),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  choice.label,
                                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 14),
                                Text(choice.detail, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.35)),
                                const SizedBox(height: 28),
                                Row(
                                  children: [
                                    Icon(Icons.touch_app_outlined, color: Theme.of(context).colorScheme.primary),
                                    const SizedBox(width: 8),
                                    const Text('That sounds like me'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  node.choices.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: index == _selectedCard ? 20 : 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: index == _selectedCard
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _progress.answeredCount < DiscoveryEngine.minimumQuestions
                    ? 'I am choosing what to ask next from your answers.'
                    : 'If I already know enough to start well, I will stop here instead of grilling you.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_saving) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
