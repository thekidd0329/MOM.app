import 'dart:io';

import 'package:flutter/material.dart';

import 'config.dart';
import 'mom_build_info.dart';
import 'mom_login_screen.dart';
import 'sync_client.dart';

class MomSettingsScreen extends StatefulWidget {
  const MomSettingsScreen({
    super.key,
    required this.initial,
    required this.sync,
  });

  final MomConfig initial;
  final MomSyncClient sync;

  @override
  State<MomSettingsScreen> createState() => _MomSettingsScreenState();
}

class _MomSettingsScreenState extends State<MomSettingsScreen> {
  late MomConfig config;
  late final TextEditingController apiBase;
  late final TextEditingController model;
  late final TextEditingController modelsDir;
  late final TextEditingController repoRoot;

  String _appearance = 'system';
  bool _autoListen = true;
  bool _captions = true;
  bool _electricEffects = true;

  @override
  void initState() {
    super.initState();
    config = widget.initial.copy();
    apiBase = TextEditingController(text: config.modelApiBase);
    model = TextEditingController(text: config.modelName);
    modelsDir = TextEditingController(text: config.modelsDir);
    repoRoot = TextEditingController(text: config.repoRoot);
  }

  @override
  void dispose() {
    apiBase.dispose();
    model.dispose();
    modelsDir.dispose();
    repoRoot.dispose();
    super.dispose();
  }

  void _save() {
    if (Platform.isLinux) {
      config.modelApiBase = apiBase.text.trim();
      config.modelName = model.text.trim();
      config.modelsDir = modelsDir.text.trim();
      config.repoRoot = repoRoot.text.trim();
    }
    config.modelApiKey = '';

    final fatal = config.validate().where((issue) => issue.fatal).toList();
    if (fatal.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(fatal.map((issue) => issue.message).join('\n'))),
      );
      return;
    }
    Navigator.pop(context, config);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final accent = scheme.primary;
    final panel = dark ? const Color(0xFF0D0912) : const Color(0xFFF8F2FC);
    final border = accent.withOpacity(dark ? 0.34 : 0.26);

    return Scaffold(
      backgroundColor: dark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 36),
        children: [
          _BrandHeader(
            accent: accent,
            dark: dark,
          ),
          const SizedBox(height: 26),
          _SectionLabel('APPEARANCE', accent: accent),
          const SizedBox(height: 8),
          _SettingsPanel(
            color: panel,
            border: border,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Theme',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'system',
                            icon: Icon(Icons.brightness_auto_rounded),
                            label: Text('System'),
                          ),
                          ButtonSegment(
                            value: 'light',
                            icon: Icon(Icons.light_mode_rounded),
                            label: Text('Light'),
                          ),
                          ButtonSegment(
                            value: 'dark',
                            icon: Icon(Icons.dark_mode_rounded),
                            label: Text('Dark'),
                          ),
                        ],
                        selected: {_appearance},
                        showSelectedIcon: false,
                        onSelectionChanged: (value) {
                          if (value.isEmpty) return;
                          setState(() => _appearance = value.first);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              _Divider(border),
              _SwitchRow(
                icon: Icons.bolt_rounded,
                title: 'Electrical effects',
                subtitle: 'Startup zaps, orb glow, and workflow-online effects.',
                value: _electricEffects,
                accent: accent,
                onChanged: (value) => setState(() => _electricEffects = value),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _SectionLabel('VOICE & LISTENING', accent: accent),
          const SizedBox(height: 8),
          _SettingsPanel(
            color: panel,
            border: border,
            children: [
              _SwitchRow(
                icon: Icons.mic_rounded,
                title: 'Auto-listen',
                subtitle: 'Keep MOM ready for the next thing you say.',
                value: _autoListen,
                accent: accent,
                onChanged: (value) => setState(() => _autoListen = value),
              ),
              _Divider(border),
              _SwitchRow(
                icon: Icons.closed_caption_rounded,
                title: 'On-screen captions',
                subtitle: 'Keep MOM\'s latest reply visible under the orb.',
                value: _captions,
                accent: accent,
                onChanged: (value) => setState(() => _captions = value),
              ),
              _Divider(border),
              _ActionRow(
                icon: Icons.graphic_eq_rounded,
                title: 'Voice',
                subtitle: 'Heart',
                accent: accent,
                trailing: const Text('Heart'),
                onTap: null,
              ),
            ],
          ),
          const SizedBox(height: 22),
          _SectionLabel('MEMORY & PRIVACY', accent: accent),
          const SizedBox(height: 8),
          _SettingsPanel(
            color: panel,
            border: border,
            children: [
              _SwitchRow(
                icon: Icons.cloud_sync_rounded,
                title: 'Cloud conversation sync',
                subtitle: 'Keep conversation history available to MOM\'s cloud memory.',
                value: config.cloudChatSync,
                accent: accent,
                onChanged: (value) => setState(() => config.cloudChatSync = value),
              ),
              _Divider(border),
              _SwitchRow(
                icon: Icons.monitor_heart_outlined,
                title: 'Product/runtime data',
                subtitle: 'Collect performance and reliability information.',
                value: config.productTelemetry,
                accent: accent,
                onChanged: (value) => setState(() => config.productTelemetry = value),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _SectionLabel('DEVICES', accent: accent),
          const SizedBox(height: 8),
          _SettingsPanel(
            color: panel,
            border: border,
            children: [
              _ActionRow(
                icon: Icons.devices_other_rounded,
                title: 'Use MOM on another device',
                subtitle: 'Link another device without changing MOM\'s local-first identity.',
                accent: accent,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MomLoginScreen(sync: widget.sync),
                  ),
                ),
              ),
            ],
          ),
          if (Platform.isLinux) ...[
            const SizedBox(height: 22),
            _SectionLabel('LOCAL BRAIN', accent: accent),
            const SizedBox(height: 8),
            _SettingsPanel(
              color: panel,
              border: border,
              children: [
                _SwitchRow(
                  icon: Icons.memory_rounded,
                  title: 'Use local MOM model',
                  subtitle: 'Run MOM through the local llama.cpp service on this computer.',
                  value: config.useLocalLlama,
                  accent: accent,
                  onChanged: (value) => setState(() => config.useLocalLlama = value),
                ),
                _Divider(border),
                _FieldRow(
                  controller: apiBase,
                  label: 'Local model endpoint',
                ),
                _Divider(border),
                _FieldRow(
                  controller: model,
                  label: 'Local model name',
                  hint: 'Use the first exposed model when blank',
                ),
                _Divider(border),
                _FieldRow(
                  controller: modelsDir,
                  label: 'GGUF model folder',
                ),
                _Divider(border),
                _FieldRow(
                  controller: repoRoot,
                  label: 'Live MOM repository folder',
                ),
              ],
            ),
          ],
          const SizedBox(height: 22),
          _SectionLabel('ABOUT', accent: accent),
          const SizedBox(height: 8),
          _SettingsPanel(
            color: panel,
            border: border,
            children: [
              _ActionRow(
                icon: Icons.info_outline_rounded,
                title: 'MOM',
                subtitle: MomBuildInfo.fullVersion,
                accent: accent,
                trailing: Text(
                  MomBuildInfo.version,
                  style: TextStyle(color: accent, fontWeight: FontWeight.w700),
                ),
                onTap: null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.accent, required this.dark});

  final Color accent;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withOpacity(0.34)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withOpacity(dark ? 0.18 : 0.10),
            accent.withOpacity(dark ? 0.04 : 0.02),
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white,
                  const Color(0xFFEBC9FF),
                  accent,
                  const Color(0xFF2A004A),
                ],
                stops: const [0, 0.12, 0.48, 1],
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(0.46),
                  blurRadius: 22,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.bolt_rounded, color: Colors.white),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MOM',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 3),
                Text(MomBuildInfo.fullVersion),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.accent});

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: Text(
        text,
        style: TextStyle(
          color: accent,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.25,
        ),
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.color,
    required this.border,
    required this.children,
  });

  final Color color;
  final Color border;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, thickness: 1, color: color.withOpacity(0.7));
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minVerticalPadding: 12,
      leading: Icon(icon, color: accent),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(subtitle),
      ),
      trailing: Switch.adaptive(value: value, onChanged: onChanged),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minVerticalPadding: 12,
      leading: Icon(icon, color: accent),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(subtitle),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.controller,
    required this.label,
    this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          helperText: hint,
          border: InputBorder.none,
          isDense: true,
        ),
      ),
    );
  }
}
