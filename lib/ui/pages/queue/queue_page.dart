import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../services/player_provider.dart';

class QueuePage extends StatelessWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final queue = player.queue;
    final currentTrack = player.currentTrack;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Up Next'),
      ),
      body: Column(
        children: [
          if (currentTrack != null)
            ListTile(
              leading: Icon(Icons.volume_up, color: Theme.of(context).colorScheme.primary),
              title: Text(
                currentTrack.title ?? 'Unknown',
                style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
              ),
              subtitle: Text(currentTrack.artist ?? 'Unknown Artist'),
              trailing: const Text('Now Playing', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          const Divider(),
          Expanded(
            child: queue.isEmpty
                ? const Center(child: Text('Queue is empty'))
                : ListView.builder(
                    itemCount: queue.length,
                    itemBuilder: (context, index) {
                      final track = queue[index];
                      return ListTile(
                        leading: Text('${index + 1}', style: const TextStyle(color: Colors.grey)),
                        title: Text(track.title ?? 'Unknown'),
                        subtitle: Text(track.artist ?? 'Unknown Artist'),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            player.removeFromQueue(track);
                          },
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
