import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sync_client.dart';

class MomLoginScreen extends StatefulWidget {
  const MomLoginScreen({super.key, required this.sync});

  final MomSyncClient sync;

  @override
  State<MomLoginScreen> createState() => _MomLoginScreenState();
}

class _MomLoginScreenState extends State<MomLoginScreen> {
  final TextEditingController _code = TextEditingController();
  bool _acknowledged = false;
  bool _busy = false;
  bool _linked = false;
  String? _transferToken;
  String? _expiresAt;
  String? _message;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    try {
      final status = await widget.sync.loginStatus();
      if (!mounted) return;
      setState(() {
        _linked = status['linked'] == true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = 'Login service is unavailable right now.');
    }
  }

  Future<void> _createToken() async {
    if (!_acknowledged || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await widget.sync.createLoginTransferToken();
      if (!mounted) return;
      setState(() {
        _linked = true;
        _transferToken = result['transfer_token'] as String?;
        _expiresAt = result['expires_at'] as String?;
        _message = 'Use this one-time code on the other device.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'MOM could not create a transfer code.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _redeemToken() async {
    if (!_acknowledged || _busy || _code.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.sync.redeemLoginTransferToken(_code.text);
      if (!mounted) return;
      setState(() {
        _linked = true;
        _code.clear();
        _message = 'This device is now linked to your MOM identity.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'That transfer code is invalid or expired.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revokeTokens() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.sync.revokeLoginTransferTokens();
      if (!mounted) return;
      setState(() {
        _transferToken = null;
        _expiresAt = null;
        _message = 'Outstanding transfer codes revoked.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'MOM could not revoke transfer codes.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Use MOM somewhere else')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(
            _linked ? Icons.link : Icons.shield_outlined,
            size: 42,
            color: scheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            _linked ? 'Cross-device identity is on' : 'Anonymous by default',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 10),
          const Text(
            'MOM normally treats this installation as an anonymous device. '
            'If you link another device, MOM must keep one persistent identity '
            'connecting those installations. That means the complete-anonymity '
            'promise no longer applies to the linked account.',
          ),
          const SizedBox(height: 18),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _acknowledged,
            onChanged: _busy
                ? null
                : (value) => setState(() => _acknowledged = value == true),
            title: const Text('I understand and want cross-device login'),
            subtitle: const Text(
              'No email or username is required. Linking itself creates the persistent identity.',
            ),
          ),
          const Divider(height: 32),
          FilledButton.icon(
            onPressed: _acknowledged && !_busy ? _createToken : null,
            icon: const Icon(Icons.key),
            label: const Text('Create one-time transfer code'),
          ),
          if (_transferToken != null) ...[
            const SizedBox(height: 14),
            SelectableText(
              _transferToken!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (_expiresAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Expires: $_expiresAt',
                  textAlign: TextAlign.center,
                ),
              ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _transferToken!));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Transfer code copied.')),
                  );
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy code'),
            ),
          ],
          const SizedBox(height: 24),
          TextField(
            controller: _code,
            enabled: !_busy,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Transfer code from another device',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _acknowledged && !_busy ? _redeemToken : null,
            icon: const Icon(Icons.login),
            label: const Text('Link this device'),
          ),
          if (_transferToken != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy ? null : _revokeTokens,
              child: const Text('Revoke outstanding transfer codes'),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 18),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_message != null) ...[
            const SizedBox(height: 18),
            Text(_message!, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}
