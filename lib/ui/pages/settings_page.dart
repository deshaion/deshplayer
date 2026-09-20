import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../services/cloud_media_service.dart';
import '../../services/hive_storage_service.dart';
import '../../models/settings.dart';
import '../../utils/cache_size_parser.dart';
import 'logs_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final CloudMediaService _cloudMediaService = CloudMediaService();
  final HiveStorageService _storageService = HiveStorageService();
  bool _isChecking = true;
  Map<String, bool> _connectionStatuses = {};
  Map<String, String> _connectionErrors = {};

  late AppSettings _settings;
  late TextEditingController _statsFolderController;
  late TextEditingController _maxCacheSizeController;
  String? _selectedStatsProviderId;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _settings = _storageService.getSettings();
    _statsFolderController = TextEditingController(
      text: _settings.cloudStatsFolder,
    );
    _maxCacheSizeController = TextEditingController(
      text: CacheSizeParser.format(_settings.maxCacheSizeBytes),
    );
    _selectedStatsProviderId = _settings.cloudStatsProviderId;
    _checkConnections();
    _initPackageInfo();
  }

  Future<void> _initPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = info.version;
      });
    }
  }

  @override
  void dispose() {
    _statsFolderController.dispose();
    _maxCacheSizeController.dispose();
    super.dispose();
  }

  Future<void> _checkConnections() async {
    if (mounted) {
      setState(() {
        _isChecking = true;
        _connectionErrors = {};
      });
    }

    final statuses = <String, bool>{};
    final errors = <String, String>{};
    for (final provider in _cloudMediaService.providers) {
      try {
        statuses[provider.id] = await provider.isConnected();
      } catch (error) {
        statuses[provider.id] = false;
        errors[provider.id] = _connectionErrorMessage(error);
      }
    }

    if (mounted) {
      setState(() {
        _connectionStatuses = statuses;
        _connectionErrors = errors;
        _isChecking = false;
      });
    }
  }

  String _connectionErrorMessage(Object error) {
    if (error is PlatformException) {
      final errorText =
          '${error.code} ${error.message ?? ''} ${error.details ?? ''}';
      if (errorText.toLowerCase().contains('keyringlocked')) {
        return 'Secure storage is unavailable because the system keyring is locked '
            '(KeyringLocked). Unlock your login keyring, then retry.';
      }

      return 'Could not access secure storage (${error.code}): '
          '${error.message ?? 'Unknown platform error'}';
    }

    return 'Could not check the connection: $error';
  }

  void _setProviderError(String providerId, Object error) {
    if (!mounted) return;

    final message = _connectionErrorMessage(error);
    setState(() {
      _connectionStatuses[providerId] = false;
      _connectionErrors[providerId] = message;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showConnectDialog(String providerId) {
    final provider = _cloudMediaService.getProvider(providerId);
    if (provider == null) return;

    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Connect to ${provider.name}'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Access Token',
              hintText: 'Enter your OAuth token',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                try {
                  await provider.connect(controller.text);
                  await _checkConnections();
                } catch (error) {
                  _setProviderError(providerId, error);
                }
              },
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );
  }

  void _disconnectProvider(String providerId) async {
    final provider = _cloudMediaService.getProvider(providerId);
    if (provider == null) return;

    try {
      await provider.disconnect();
      await _checkConnections();
    } catch (error) {
      _setProviderError(providerId, error);
    }
  }

  void _saveSettings() {
    final cacheSizeBytes = CacheSizeParser.parse(_maxCacheSizeController.text);
    if (cacheSizeBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid max cache size (e.g. 500mb, 5gb)'),
        ),
      );
      return;
    }
    _settings.maxCacheSizeBytes = cacheSizeBytes;
    _settings.cloudStatsFolder = _statsFolderController.text;
    _settings.cloudStatsProviderId = _selectedStatsProviderId;
    _storageService.saveSettings(_settings);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          if (_isChecking) const LinearProgressIndicator(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.list_alt),
            title: const Text('View Application Logs'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LogsPage()),
              );
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Cloud Providers',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ..._cloudMediaService.providers.map((provider) {
            final isConnected = _connectionStatuses[provider.id] ?? false;
            final connectionError = _connectionErrors[provider.id];
            return ListTile(
              leading: Icon(
                connectionError == null ? Icons.cloud : Icons.error_outline,
                color: connectionError == null
                    ? null
                    : Theme.of(context).colorScheme.error,
              ),
              title: Text(provider.name),
              subtitle: Text(
                connectionError ??
                    (isConnected ? 'Connected' : 'Not connected'),
                style: connectionError == null
                    ? null
                    : TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              trailing: connectionError != null
                  ? TextButton(
                      onPressed: _isChecking ? null : _checkConnections,
                      child: const Text('Retry'),
                    )
                  : isConnected
                  ? TextButton(
                      onPressed: () => _disconnectProvider(provider.id),
                      child: const Text(
                        'Disconnect',
                        style: TextStyle(color: Colors.red),
                      ),
                    )
                  : TextButton(
                      onPressed: () => _showConnectDialog(provider.id),
                      child: const Text('Connect'),
                    ),
            );
          }),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Application Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _statsFolderController,
                    decoration: const InputDecoration(
                      labelText: 'Cloud Statistics Folder',
                      helperText: 'e.g., /Statistics',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    // ignore: deprecated_member_use
                    value: _selectedStatsProviderId,
                    decoration: const InputDecoration(
                      labelText: 'Provider',
                      helperText: ' ',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('None'),
                      ),
                      ..._cloudMediaService.providers.map(
                        (p) => DropdownMenuItem<String?>(
                          value: p.id,
                          child: Text(p.name),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedStatsProviderId = val;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: TextField(
              controller: _maxCacheSizeController,
              decoration: const InputDecoration(
                labelText: 'Max Cache Size',
                helperText: 'e.g., 500mb, 5gb (defaults to mb)',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: _saveSettings,
              child: const Text('Save Settings'),
            ),
          ),
          if (_appVersion.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Center(
                child: Text(
                  'App Version: $_appVersion',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
