import 'package:flutter/material.dart';
import '../../../services/stats_service.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  final StatsService _statsService = StatsService();

  String _selectedPeriod = 'This Month';
  List<MapEntry<String, int>> _topTracks = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  void _loadStats() {
    final now = DateTime.now();
    DateTime start;

    if (_selectedPeriod == 'This Week') {
        // Approximate to this month due to YYYY-MM storage
        start = DateTime(now.year, now.month);
    } else if (_selectedPeriod == 'This Month') {
        start = DateTime(now.year, now.month);
    } else { // This Year
        start = DateTime(now.year, 1);
    }

    final aggregated = _statsService.getStatsForPeriod(start, now);

    final entries = aggregated.entries.toList();

    entries.sort((a, b) => b.value.compareTo(a.value));

    setState(() {
       _topTracks = entries;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'This Week', label: Text('This Week')),
                ButtonSegment(value: 'This Month', label: Text('This Month')),
                ButtonSegment(value: 'This Year', label: Text('This Year')),
              ],
              selected: {_selectedPeriod},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() {
                  _selectedPeriod = newSelection.first;
                });
                _loadStats();
              },
            ),
          ),
          const Divider(),
          Expanded(
            child: _topTracks.isEmpty
                ? const Center(child: Text('No stats available for this period.'))
                : ListView.builder(
                    itemCount: _topTracks.length,
                    itemBuilder: (context, index) {
                      final entry = _topTracks[index];
                      final trackKey = entry.key;
                      final count = entry.value;

                      String artist = 'Unknown Artist';
                      String title = 'Unknown';

                      final delimiterIndex = trackKey.indexOf(' - ');
                      if (delimiterIndex != -1) {
                        artist = trackKey.substring(0, delimiterIndex);
                        title = trackKey.substring(delimiterIndex + 3);
                      } else {
                        title = trackKey;
                      }

                      return ListTile(
                        leading: CircleAvatar(
                          child: Text('${index + 1}'),
                        ),
                        title: Text(title),
                        subtitle: Text(artist),
                        trailing: Text('$count plays', style: const TextStyle(fontWeight: FontWeight.bold)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
