import 'package:flutter/material.dart';
import '../../services/cloud_media_service.dart';
import '../../services/hive_storage_service.dart';
import '../../models/settings.dart';

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

  @override
  void initState() {
    super.initState();
    _settings = _storageService.getSettings();
    _statsFolderController = TextEditingController(text: _settings.cloudStatsFolder);
    _checkConnections();
  }

  @override
  void dispose() {
     _statsFolderController.dispose();
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
      _settings.cloudStatsFolder = _statsFolderController.text;
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
                  child: TextField(
                     controller: _statsFolderController,
                     decoration: const InputDecoration(
                         labelText: 'Cloud Statistics Folder',
                         helperText: 'e.g., /Statistics',
                     ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton(
                      onPressed: _saveSettings,
                      child: const Text('Save Settings'),
                  ),
                )
              ],
            ),
    );
  }
}
