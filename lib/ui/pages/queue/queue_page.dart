import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../services/player_provider.dart';

class QueuePage extends StatefulWidget {
  const QueuePage({super.key});

  @override
  State<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> {
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final queue = player.queue;
    final currentTrack = player.currentTrack;
    final history = player.playbackHistory;
    final occurrenceCounts = <String, int>{};
    final queueKeys = queue.map((track) {
      final occurrence = occurrenceCounts.update(
        track.id,
        (count) => count + 1,
        ifAbsent: () => 0,
      );
      return '${track.id}-$occurrence';
    }).toList();

    return Scaffold(
      appBar: AppBar(title: Text(_showHistory ? 'History' : 'Up Next')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'queue_history_toggle',
        onPressed: () {
          setState(() {
            _showHistory = !_showHistory;
          });
        },
        icon: Icon(_showHistory ? Icons.queue_music : Icons.history),
        label: Text(_showHistory ? 'Queue' : 'History'),
      ),
      body: _showHistory
          ? history.isEmpty
                ? const Center(child: Text('History is empty'))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final track = history[index];
                      return ListTile(
                        leading: Text(
                          '${index + 1}',
                          style: const TextStyle(color: Colors.grey),
                        ),
                        title: Text(track.title ?? 'Unknown'),
                        subtitle: Text(track.artist ?? 'Unknown Artist'),
                      );
                    },
                  )
          : Column(
              children: [
                if (currentTrack != null)
                  ListTile(
                    leading: Icon(
                      Icons.volume_up,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(
                      currentTrack.title ?? 'Unknown',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    subtitle: Text(currentTrack.artist ?? 'Unknown Artist'),
                    trailing: const Text(
                      'Now Playing',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                const Divider(),
                Expanded(
                  child: queue.isEmpty
                      ? const Center(child: Text('Queue is empty'))
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.only(bottom: 88),
                          itemCount: queue.length,
                          buildDefaultDragHandles: false,
                          onReorderItem: player.reorderQueue,
                          itemBuilder: (context, index) {
                            final track = queue[index];
                            return ReorderableDelayedDragStartListener(
                              key: ValueKey(queueKeys[index]),
                              index: index,
                              child: ListTile(
                                leading: Text(
                                  '${index + 1}',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                                title: Text(track.title ?? 'Unknown'),
                                subtitle: Text(
                                  track.artist ?? 'Unknown Artist',
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    player.removeFromQueue(track);
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
