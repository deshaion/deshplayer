import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../services/cloud_media_service.dart';
import '../components/connect_provider_dialog.dart';
import 'package:logging/logging.dart';
import '../../services/hive_storage_service.dart';
import '../../models/settings.dart';
import '../../utils/cache_size_parser.dart';
import 'logs_page.dart';
import 'cache_export_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final CloudMediaService _cloudMediaService = CloudMediaService();
  final HiveStorageService _storageService = HiveStorageService();
  final _log = Logger('SettingsPage');
  Set<String> _configuredProviderIds = {};
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
    final configured = <String>{};
    for (final provider in _cloudMediaService.providers) {
      try {
        if (await provider.hasCredentials()) {
          configured.add(provider.id);
          statuses[provider.id] = await provider.isConnected();
        }
      } catch (error, stackTrace) {
        configured.add(provider.id);
        _log.warning(
          'Could not check ${provider.name} connection',
          error,
          stackTrace,
        );
        statuses[provider.id] = false;
        errors[provider.id] = _connectionErrorMessage(error);
      }
    }

    if (mounted) {
      setState(() {
        _configuredProviderIds = configured;
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

  Future<void> _showProviderPicker() async {
    final available = _cloudMediaService.providers
        .where((provider) => !_configuredProviderIds.contains(provider.id))
        .toList();
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose a cloud provider'),
        children: [
          if (available.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('All available providers are already added.'),
            ),
          ...available.map(
            (provider) => SimpleDialogOption(
              onPressed: () => Navigator.pop(context, provider.id),
              child: ListTile(
                leading: const Icon(Icons.cloud_outlined),
                title: Text(provider.name),
              ),
            ),
          ),
        ],
      ),
    );
    if (selected != null && mounted) await _showConnectDialog(selected);
  }

  Future<void> _showConnectDialog(String providerId) async {
    final provider = _cloudMediaService.getProvider(providerId);
    if (provider == null) return;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ConnectProviderDialog(provider: provider),
    );
    if (mounted) await _checkConnections();
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
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Cloud Providers',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _isChecking ? null : _showProviderPicker,
                  icon: const Icon(Icons.add),
                  label: const Text('Connect'),
                ),
              ],
            ),
          ),
          if (!_isChecking && _configuredProviderIds.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'No cloud providers connected. Tap Connect to add one.',
              ),
            ),
          ..._cloudMediaService.providers
              .where((provider) => _configuredProviderIds.contains(provider.id))
              .map((provider) {
                final connected = _connectionStatuses[provider.id] ?? false;
                final error = _connectionErrors[provider.id];
                return ListTile(
                  leading: Icon(connected ? Icons.cloud_done : Icons.cloud_off),
                  title: Text(provider.name),
                  subtitle: Text(
                    error ??
                        (connected
                            ? 'Connected'
                            : 'Connection needs attention'),
                  ),
                  trailing: PopupMenuButton<String>(
                    enabled: !_isChecking,
                    tooltip: 'Connection options',
                    onSelected: (value) {
                      if (value == 'reconnect') _showConnectDialog(provider.id);
                      if (value == 'retry') _checkConnections();
                      if (value == 'disconnect') {
                        _disconnectProvider(provider.id);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'reconnect',
                        child: Text('Edit credentials'),
                      ),
                      PopupMenuItem(
                        value: 'retry',
                        child: Text('Check connection'),
                      ),
                      PopupMenuItem(
                        value: 'disconnect',
                        child: Text('Disconnect'),
                      ),
                    ],
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
          if (Platform.isAndroid || Platform.isIOS)
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Download from cache'),
              subtitle: const Text('Copy cached tracks to a folder'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CacheExportPage()),
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
