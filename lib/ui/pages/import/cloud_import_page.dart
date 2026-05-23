import 'package:flutter/material.dart';
import '../../../services/cloud_media_service.dart';
import '../../../services/cloud_provider.dart';
import '../../../models/cloud_node.dart';
import '../../../models/track.dart';
import '../../../models/playlist.dart';
import '../../../services/hive_storage_service.dart';
import 'package:logging/logging.dart';

class CloudImportPage extends StatefulWidget {
  final Playlist playlist;
  const CloudImportPage({super.key, required this.playlist});

  @override
  State<CloudImportPage> createState() => _CloudImportPageState();
}

class _CloudImportPageState extends State<CloudImportPage> {
  final _log = Logger('CloudImportPage');
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
    if (_selectedProvider == null) {
      _log.warning('Attempted to load path without selected provider');
      return;
    }

    _log.info('Loading path: $path on provider: ${_selectedProvider!.id}');

    setState(() {
      _isLoading = true;
      _currentPath = path;
    });

    try {
      final nodes = await _selectedProvider!.listPath(path);
      _log.fine('Loaded ${nodes.length} nodes from $path');
      setState(() {
        _nodes = nodes;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      _log.severe('Error loading path: $path', e, stackTrace);
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _importNode(CloudNode node) async {
    _log.info('Starting import for node: ${node.path} (isDir: ${node.isDir})');
    setState(() {
      _isLoading = true;
    });

    try {
      if (node.isDir) {
        await _importDirectoryRecursively(node.path);
      } else {
        await _importSingleFile(node);
      }

      _log.info('Import complete for node: ${node.path}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import complete')));
      }
    } catch (e, stackTrace) {
      _log.severe('Import error for node: ${node.path}', e, stackTrace);
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

    final p = storageService.getPlaylist(widget.playlist.id);
    final Set<String> existingCloudPaths = {};
    if (p != null) {
      for (final tId in p.trackIds) {
        final track = storageService.getTrack(tId);
        if (track != null) {
          existingCloudPaths.add(track.cloudPath);
        }
      }
    }

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
                await _importSingleFile(n, storageService, existingCloudPaths);
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

  Future<void> _importSingleFile(CloudNode node, [HiveStorageService? storageService, Set<String>? existingCloudPaths]) async {
    if (_selectedProvider == null) return;

    // Check if it's audio
    if (node.mimeType == null || !node.mimeType!.startsWith('audio/')) {
        _log.fine('Skipping non-audio file: ${node.path} (mimeType: ${node.mimeType})');
        return; // skip non-audio
    }

    final fullCloudPath = '${_selectedProvider!.id}://${node.path}';

    // Check duplicates in playlist
    final storage = storageService ?? HiveStorageService();

    final p = storage.getPlaylist(widget.playlist.id);
    if (p == null) return;

    final pathsToCheck = existingCloudPaths ?? <String>{};
    if (existingCloudPaths == null) {
      for (final tId in p.trackIds) {
        final track = storage.getTrack(tId);
        if (track != null) {
          pathsToCheck.add(track.cloudPath);
        }
      }
    }

    if (pathsToCheck.contains(fullCloudPath)) {
      _log.fine('Skipping duplicate file: $fullCloudPath');
      return; // skip duplicate
    }

    final newTrack = Track(
       id: DateTime.now().millisecondsSinceEpoch.toString() + node.name, // unique enough
       cloudPath: fullCloudPath,
       title: node.name,
       duration: const Duration(minutes: 0), // Could try to parse metadata later
       fileSize: node.size,
    );

    await storage.saveTrack(newTrack);
    p.trackIds.add(newTrack.id);
    pathsToCheck.add(fullCloudPath);
    await storage.savePlaylist(p);

    _log.info('Successfully imported file: $fullCloudPath');
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
