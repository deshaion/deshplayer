import 'package:flutter/material.dart';
import '../../../services/cloud_media_service.dart';
import '../../../services/cloud_provider.dart';
import '../../../models/cloud_node.dart';
import '../../../models/track.dart';
import '../../../models/playlist.dart';
import '../../../services/hive_storage_service.dart';

class CloudImportPage extends StatefulWidget {
  final Playlist playlist;
  const CloudImportPage({super.key, required this.playlist});

  @override
  State<CloudImportPage> createState() => _CloudImportPageState();
}

class _CloudImportPageState extends State<CloudImportPage> {
  final CloudMediaService _cloudMediaService = CloudMediaService();
  CloudProvider? _selectedProvider;
  String _currentPath = '';
  List<CloudNode> _nodes = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Default to first connected provider if any
    _initProvider();
  }

  Future<void> _initProvider() async {
    for (final p in _cloudMediaService.providers) {
      if (await p.isConnected()) {
        setState(() {
          _selectedProvider = p;
        });
        _loadPath('');
        break;
      }
    }
  }

  Future<void> _loadPath(String path) async {
    if (_selectedProvider == null) return;
    setState(() {
      _isLoading = true;
      _currentPath = path;
    });

    try {
      final nodes = await _selectedProvider!.listPath(path);
      setState(() {
        _nodes = nodes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _importNode(CloudNode node) async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (node.isDir) {
        await _importDirectoryRecursively(node.path);
      } else {
        await _importSingleFile(node);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import complete')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _importDirectoryRecursively(String path) async {
    if (_selectedProvider == null) return;

    // Simple queue for BFS
    List<String> dirsToProcess = [path];

    // We get storageService once
    final storageService = HiveStorageService();
    // Assuming HiveStorageService has already been initialized, we don't call init here

    while(dirsToProcess.isNotEmpty) {
       final currentDir = dirsToProcess.removeAt(0);

       bool hasMore = true;
       int offset = 0;
       int limit = 100;

       while (hasMore) {
         final nodes = await _selectedProvider!.listPath(currentDir, limit: limit, offset: offset);

         if (nodes.isEmpty) {
           hasMore = false;
         } else {
           for (final n in nodes) {
             if (n.isDir) {
                dirsToProcess.add(n.path);
             } else {
                await _importSingleFile(n, storageService);
             }
           }
           if (nodes.length < limit) {
             hasMore = false;
           } else {
             offset += limit;
           }
         }
       }
    }
  }

  Future<void> _importSingleFile(CloudNode node, [HiveStorageService? storageService]) async {
    if (_selectedProvider == null) return;

    // Check if it's audio
    if (node.mimeType == null || !node.mimeType!.startsWith('audio/')) {
        return; // skip non-audio
    }

    final fullCloudPath = '${_selectedProvider!.id}://${node.path}';

    // Check duplicates in playlist
    final storage = storageService ?? HiveStorageService();

    final p = storage.getPlaylist(widget.playlist.id);
    if (p == null) return;

    bool exists = false;
    for (final tId in p.trackIds) {
       final track = storage.getTrack(tId);
       if (track != null && track.cloudPath == fullCloudPath) {
          exists = true;
          break;
       }
    }

    if (exists) return; // skip duplicate

    final newTrack = Track(
       id: DateTime.now().millisecondsSinceEpoch.toString() + node.name, // unique enough
       cloudPath: fullCloudPath,
       title: node.name,
       duration: const Duration(minutes: 0), // Could try to parse metadata later
       fileSize: node.size,
    );

    await storage.saveTrack(newTrack);
    p.trackIds.add(newTrack.id);
    await storage.savePlaylist(p);
  }

  void _goUp() {
    if (_currentPath.isEmpty || _currentPath == 'disk:/') return;

    // Remove last component
    final parts = _currentPath.split('/');
    if (parts.length > 1) {
      parts.removeLast();
      var newPath = parts.join('/');
      if (newPath == 'disk:') newPath = 'disk:/';
      _loadPath(newPath);
    } else {
      _loadPath('');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Cloud Media'),
      ),
      body: Column(
        children: [
          // Provider selector
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: DropdownButton<CloudProvider>(
              value: _selectedProvider,
              hint: const Text('Select Provider'),
              items: _cloudMediaService.providers.map((p) {
                return DropdownMenuItem(
                  value: p,
                  child: Text(p.name),
                );
              }).toList(),
              onChanged: (p) async {
                if (p != null) {
                  final BuildContext currentContext = context;
                  final connected = await p.isConnected();
                  if (!currentContext.mounted) return;
                  if (!connected) {
                    ScaffoldMessenger.of(currentContext).showSnackBar(const SnackBar(content: Text('Provider not connected. Go to settings.')));
                    return;
                  }
                  setState(() {
                    _selectedProvider = p;
                  });
                  _loadPath('');
                }
              },
            ),
          ),

          if (_currentPath.isNotEmpty && _currentPath != 'disk:/')
             ListTile(
               leading: const Icon(Icons.arrow_upward),
               title: const Text('..'),
               onTap: _goUp,
             ),

          const Divider(),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _nodes.length,
                    itemBuilder: (context, index) {
                      final node = _nodes[index];
                      return ListTile(
                        leading: Icon(node.isDir ? Icons.folder : Icons.audiotrack),
                        title: Text(node.name),
                        subtitle: node.mimeType != null ? Text(node.mimeType!) : null,
                        trailing: IconButton(
                           icon: const Icon(Icons.download),
                           onPressed: () => _importNode(node),
                        ),
                        onTap: () {
                           if (node.isDir) {
                              _loadPath(node.path);
                           }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
