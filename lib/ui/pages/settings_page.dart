import 'package:flutter/material.dart';
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

  late AppSettings _settings;
  late TextEditingController _statsFolderController;
  late TextEditingController _maxCacheSizeController;
  String? _selectedStatsProviderId;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _settings = _storageService.getSettings();
    _statsFolderController = TextEditingController(text: _settings.cloudStatsFolder);
    _maxCacheSizeController = TextEditingController(text: CacheSizeParser.format(_settings.maxCacheSizeBytes));
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
    setState(() {
      _isChecking = true;
    });

    final statuses = <String, bool>{};
    for (final provider in _cloudMediaService.providers) {
      statuses[provider.id] = await provider.isConnected();
    }

    if (mounted) {
      setState(() {
        _connectionStatuses = statuses;
        _isChecking = false;
      });
    }
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
                await provider.connect(controller.text);
                _checkConnections();
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

    await provider.disconnect();
    _checkConnections();
  }

  void _saveSettings() {
      final cacheSizeBytes = CacheSizeParser.parse(_maxCacheSizeController.text);
      if (cacheSizeBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid max cache size (e.g. 500mb, 5gb)')));
        return;
      }
      _settings.maxCacheSizeBytes = cacheSizeBytes;
      _settings.cloudStatsFolder = _statsFolderController.text;
      _settings.cloudStatsProviderId = _selectedStatsProviderId;
      _storageService.saveSettings(_settings);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: _isChecking
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
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
                  return ListTile(
                    leading: const Icon(Icons.cloud),
                    title: Text(provider.name),
                    subtitle: Text(isConnected ? 'Connected' : 'Not connected'),
                    trailing: isConnected
                        ? TextButton(
                            onPressed: () => _disconnectProvider(provider.id),
                            child: const Text('Disconnect', style: TextStyle(color: Colors.red)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('None'),
                            ),
                            ..._cloudMediaService.providers.map((p) => DropdownMenuItem<String?>(
                                  value: p.id,
                                  child: Text(p.name),
                                )),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
