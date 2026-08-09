import 'package:flutter/material.dart';

import 'startup_intro_screen.dart';

class MomPersonalityScreen extends StatefulWidget {
  const MomPersonalityScreen({super.key});

  @override
  State<MomPersonalityScreen> createState() => _MomPersonalityScreenState();
}

class _MomPersonalityScreenState extends State<MomPersonalityScreen> {
  static const _purple = Color(0xFFA855F7);
  static const _lavender = Color(0xFFD9B4FF);

  final StartupIntroStore _store = StartupIntroStore();
  String _selected = 'mom';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await _store.savedMomStyle();
    if (!mounted) return;
    setState(() {
      _selected = MomPersonalityCatalog.normalize(value);
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _store.saveMomStyle(_selected);
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = MomPersonalityCatalog.byId(_selected);

    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _purple,
          brightness: Brightness.dark,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text('Choose your MOM'),
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: _purple),
              )
            : SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                        children: [
                          const Text(
                            'Same MOM. Same memories. Different mothering energy.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Pick a different personality whenever you want. The change is saved into MOM’s startup/discovery context and takes over the next time MOM starts.',
                            style: TextStyle(
                              color: Colors.white70,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 18),
                          ...MomPersonalityCatalog.all.map(
                            (personality) => _PersonalityOption(
                              personality: personality,
                              selected: personality.id == _selected,
                              onTap: _saving
                                  ? null
                                  : () {
                                      setState(() => _selected = personality.id);
                                    },
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF160C1D),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: _purple.withValues(alpha: 0.55),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selected.label,
                                  style: const TextStyle(
                                    color: _lavender,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  selected.description,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Redirect: “${selected.redirectCue}”',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Clarify: “${selected.clarificationCue}”',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Resume: “${selected.resumeCue}”',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          backgroundColor: _purple,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Text(
                                'USE THIS MOM',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _PersonalityOption extends StatelessWidget {
  const _PersonalityOption({
    required this.personality,
    required this.selected,
    required this.onTap,
  });

  final MomPersonality personality;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${personality.label}. ${personality.description}',
      child: ExcludeSemantics(
        child: Card(
          color: selected ? const Color(0xFF21102E) : const Color(0xFF100914),
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: selected
                  ? const Color(0xFFA855F7)
                  : const Color(0xFF6B3B85),
              width: selected ? 1.8 : 0.8,
            ),
          ),
          child: ListTile(
            onTap: onTap,
            leading: Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: const Color(0xFFA855F7),
            ),
            title: Text(
              personality.label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                personality.description,
                style: const TextStyle(
                  color: Colors.white70,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
