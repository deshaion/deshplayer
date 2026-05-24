import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/hive_storage_service.dart';
import '../../models/app_log_record.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final HiveStorageService _storageService = HiveStorageService();
  final TextEditingController _searchController = TextEditingController();
  List<AppLogRecord> _allLogs = [];
  List<AppLogRecord> _filteredLogs = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadLogs() {
    setState(() {
      _allLogs = _storageService.getLogs().reversed.toList();
      _filterLogs();
    });
  }

  void _filterLogs() {
    if (_searchQuery.isEmpty) {
      _filteredLogs = List.from(_allLogs);
    } else {
      final query = _searchQuery.toLowerCase();
      _filteredLogs = _allLogs.where((log) {
        return log.message.toLowerCase().contains(query) ||
               log.loggerName.toLowerCase().contains(query) ||
               log.level.toLowerCase().contains(query) ||
               (log.error != null && log.error!.toLowerCase().contains(query));
      }).toList();
    }
  }

  Future<void> _clearLogs() async {
    await _storageService.clearLogs();
    _loadLogs();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logs cleared')));
    }
  }

  Future<void> _copyLogs() async {
    final buffer = StringBuffer();
    for (final log in _filteredLogs) {
      buffer.writeln('[${log.time}] [${log.level}] (${log.loggerName}): ${log.message}');
      if (log.error != null) {
        buffer.writeln('Error: ${log.error}');
      }
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied logs to clipboard')));
    }
  }

  Widget _buildHighlightedText(String text, TextStyle baseStyle) {
    if (_searchQuery.isEmpty) {
      return Text(text, style: baseStyle);
    }

    final queryLower = _searchQuery.toLowerCase();
    final textLower = text.toLowerCase();

    int start = 0;
    int indexOfMatch;
    final List<TextSpan> spans = [];

    while ((indexOfMatch = textLower.indexOf(queryLower, start)) != -1) {
      if (indexOfMatch > start) {
        spans.add(TextSpan(text: text.substring(start, indexOfMatch)));
      }
      spans.add(TextSpan(
        text: text.substring(indexOfMatch, indexOfMatch + _searchQuery.length),
        style: const TextStyle(backgroundColor: Colors.yellow, color: Colors.black),
      ));
      start = indexOfMatch + _searchQuery.length;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: 'Search logs...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.white70),
          ),
          style: const TextStyle(color: Colors.white, fontSize: 18),
          cursorColor: Colors.white,
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
              _filterLogs();
            });
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _copyLogs,
            tooltip: 'Copy to Clipboard',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear Logs'),
                  content: const Text('Are you sure you want to delete all logs?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _clearLogs();
                      },
                      child: const Text('Clear', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
            },
            tooltip: 'Clear Logs',
          ),
        ],
      ),
      body: ListView.separated(
        itemCount: _filteredLogs.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final log = _filteredLogs[index];

          Color levelColor;
          switch (log.level) {
            case 'SEVERE':
            case 'SHOUT':
              levelColor = Colors.red;
              break;
            case 'WARNING':
              levelColor = Colors.orange;
              break;
            case 'INFO':
              levelColor = Colors.blue;
              break;
            case 'FINE':
            case 'FINER':
            case 'FINEST':
              levelColor = Colors.grey;
              break;
            default:
              levelColor = Colors.black;
          }

          return ListTile(
            title: _buildHighlightedText(
              '[${log.level}] (${log.loggerName})',
              TextStyle(fontWeight: FontWeight.bold, color: levelColor, fontSize: 12)
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                _buildHighlightedText(log.message, const TextStyle(color: Colors.black87)),
                if (log.error != null) ...[
                  const SizedBox(height: 4),
                  _buildHighlightedText('Error: ${log.error}', const TextStyle(color: Colors.redAccent, fontSize: 12)),
                ],
                const SizedBox(height: 4),
                Text(log.time.toString(), style: const TextStyle(color: Colors.grey, fontSize: 10)),
              ],
            ),
          );
        },
      ),
    );
  }
}
