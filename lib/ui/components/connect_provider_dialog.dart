import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import '../../services/cloud_provider.dart';

class ConnectProviderDialog extends StatefulWidget {
  const ConnectProviderDialog({super.key, required this.provider});

  final CloudProvider provider;

  @override
  State<ConnectProviderDialog> createState() => _ConnectProviderDialogState();
}

class _ConnectProviderDialogState extends State<ConnectProviderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _token = TextEditingController();
  final _clientId = TextEditingController();
  final _clientSecret = TextEditingController();
  final _refreshToken = TextEditingController();
  final _log = Logger('ProviderConnection');
  bool _autoRefresh = true;
  bool _connecting = false;
  String? _error;

  bool get _isGoogle => widget.provider.id == 'google_drive';

  @override
  void dispose() {
    _token.dispose();
    _clientId.dispose();
    _clientSecret.dispose();
    _refreshToken.dispose();
    super.dispose();
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool secret = true,
    bool required = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextFormField(
        controller: controller,
        obscureText: secret,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: (value) =>
            required && (value?.trim().isEmpty ?? true) ? 'Required' : null,
      ),
    );
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final credentials = _isGoogle
          ? jsonEncode(
              _autoRefresh
                  ? {
                      'client_id': _clientId.text.trim(),
                      'client_secret': _clientSecret.text.trim(),
                      'refresh_token': _refreshToken.text.trim(),
                    }
                  : {'access_token': _token.text.trim()},
            )
          : _token.text.trim();
      await widget.provider.connect(credentials);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      _log.warning(
        'Could not connect to ${widget.provider.name}',
        error,
        stackTrace,
      );
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_connecting,
      child: AlertDialog(
        title: Text('Connect to ${widget.provider.name}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isGoogle) ...[
                    const Text(
                      'Enable Google Drive API in your Google Cloud project. Use OAuth credentials with permission to read and write your Drive files.',
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Automatically refresh connection'),
                      value: _autoRefresh,
                      onChanged: _connecting
                          ? null
                          : (value) => setState(() {
                              _autoRefresh = value;
                              _error = null;
                            }),
                    ),
                    if (_autoRefresh) ...[
                      _field(_clientId, 'OAuth Client ID', secret: false),
                      _field(
                        _clientSecret,
                        'Client Secret (if required)',
                        required: false,
                      ),
                      _field(_refreshToken, 'Refresh Token'),
                    ] else ...[
                      const Text(
                        'Access tokens expire. Reconnect with a new token when needed.',
                      ),
                      _field(_token, 'OAuth Access Token'),
                    ],
                  ] else
                    _field(_token, 'OAuth Access Token'),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _connecting ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _connecting ? null : _connect,
            child: Text(_connecting ? 'Connecting…' : 'Connect'),
          ),
        ],
      ),
    );
  }
}
