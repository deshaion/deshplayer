import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

import '../../services/cache_export_service.dart';
import '../../services/cloud_media_service.dart';
import '../../services/hive_storage_service.dart';

class CacheExportPage extends StatefulWidget {
  const CacheExportPage({super.key});

  @override
  State<CacheExportPage> createState() => _CacheExportPageState();
}

class _CacheExportPageState extends State<CacheExportPage> {
  final _log = Logger('CacheExportPage');
  final _service = CacheExportService();
  final _selected = <String>{};
  List<CachedTrack> _tracks = [];
  bool _loading = true;
  bool _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final directory = await CloudMediaService().getCacheDir();
      final tracks = await _service.findCachedTracks(
        HiveStorageService().getAllTracks(),
        directory,
      );
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _selected.retainAll(tracks.map((entry) => entry.track.id));
        _loading = false;
      });
    } catch (error, stackTrace) {
      _log.severe('Could not load cached tracks', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _error = 'Could not load cached tracks. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final result = await _service.exportTracks(
        _tracks.where((entry) => _selected.contains(entry.track.id)).toList(),
      );
      if (!mounted || result == null) return;
      final count = result.copied;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(result.failed.isEmpty ? 'Tracks copied' : 'Copy results'),
          content: SingleChildScrollView(
            child: Text(
              [
                '$count ${count == 1 ? 'track' : 'tracks'} copied to your chosen folder.',
                if (result.failed.isNotEmpty)
                  'Could not copy ${result.failed.length} ${result.failed.length == 1 ? 'track' : 'tracks'}:\n${result.failed.join('\n')}\n\nCheck available space and folder access, then try again.',
              ].join('\n\n'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) await _loadTracks();
    } on MissingPluginException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Folder export is unavailable. Install the latest app build and fully restart the app.',
          ),
        ),
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Could not copy tracks.')),
      );
    } catch (error, stackTrace) {
      _log.severe('Could not finish cache export', error, stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not copy tracks. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allSelected =
        _tracks.isNotEmpty && _selected.length == _tracks.length;
    return PopScope(
      canPop: !_exporting,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Download from cache'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading || _exporting ? null : _loadTracks,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    TextButton(
                      onPressed: _loadTracks,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : _tracks.isEmpty
            ? const Center(child: Text('No cached tracks available.'))
            : Column(
                children: [
                  CheckboxListTile(
                    value: allSelected,
                    title: Text(
                      '${_selected.length} of ${_tracks.length} selected',
                    ),
                    subtitle: const Text('Select all'),
                    onChanged: _exporting
                        ? null
                        : (value) {
                            setState(() {
                              _selected.clear();
                              if (value == true) {
                                _selected.addAll(
                                  _tracks.map((entry) => entry.track.id),
                                );
                              }
                            });
                          },
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _tracks.length,
                      itemBuilder: (context, index) {
                        final entry = _tracks[index];
                        final track = entry.track;
                        return CheckboxListTile(
                          value: _selected.contains(track.id),
                          title: Text(
                            track.title ?? CacheExportService.fileName(track),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              if (track.artist?.isNotEmpty ?? false)
                                track.artist!,
                              CacheExportService.fileName(track),
                              '${(entry.size / (1024 * 1024)).toStringAsFixed(1)} MB',
                            ].join(' · '),
                          ),
                          onChanged: _exporting
                              ? null
                              : (value) {
                                  setState(() {
                                    if (value == true) {
                                      _selected.add(track.id);
                                    } else {
                                      _selected.remove(track.id);
                                    }
                                  });
                                },
                        );
                      },
                    ),
                  ),
                ],
              ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _selected.isEmpty || _loading || _exporting
                ? null
                : _export,
            icon: _exporting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_open),
            label: Text(
              _exporting
                  ? 'Choosing folder / copying…'
                  : 'Choose folder and copy',
            ),
          ),
        ),
      ),
    );
  }
}
