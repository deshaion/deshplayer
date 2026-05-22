import 'package:flutter/material.dart';
import '../../services/cloud_media_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final CloudMediaService _cloudMediaService = CloudMediaService();
  bool _isChecking = true;
  Map<String, bool> _connectionStatuses = {};

  @override
  void initState() {
    super.initState();
    _checkConnections();
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
              ],
            ),
    );
  }
}
