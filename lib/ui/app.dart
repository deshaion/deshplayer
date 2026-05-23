import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/hive_storage_service.dart';
import '../services/player_provider.dart';
import '../models/playlist.dart';
import 'layouts/responsive_layout.dart';
import 'layouts/mobile/mobile_layout.dart';
import 'layouts/desktop/desktop_layout.dart';

class DeshPlayerApp extends StatefulWidget {
  final HiveStorageService storageService;
  const DeshPlayerApp({super.key, required this.storageService});

  @override
  State<DeshPlayerApp> createState() => _DeshPlayerAppState();
}

class _DeshPlayerAppState extends State<DeshPlayerApp> {
  List<Playlist> _playlists = [];
  bool _isLoading = true;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<String>? _errorSubscription;

  @override
  void initState() {
    super.initState();
    _loadData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final playerProvider = Provider.of<PlayerProvider>(
        context,
        listen: false,
      );
      _errorSubscription = playerProvider.errorStream.listen((errorMessage) {
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
    });
  }

  @override
  void dispose() {
    _errorSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    // Read from Hive
    final playlists = widget.storageService.getPlaylists();
    setState(() {
      _playlists = playlists;
      _isLoading = false;
    });
  }

  void _addPlaylist(String name) async {
    final newPlaylist = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      trackIds: [],
    );
    await widget.storageService.savePlaylist(newPlaylist);
    _loadData();
  }

  void _renamePlaylist(String id, String newName) async {
    final p = widget.storageService.getPlaylist(id);
    if (p != null) {
      p.name = newName;
      await widget.storageService.savePlaylist(p);
      _loadData();
    }
  }

  void _deletePlaylist(String id) async {
    await widget.storageService.deletePlaylist(id);
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: _scaffoldMessengerKey,
      title: 'DeshPlayer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto', // Default clean font
      ),
      home: _isLoading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : ResponsiveLayout(
              mobileLayout: MobileLayout(
                playlists: _playlists,
                onAddPlaylist: _addPlaylist,
                onRenamePlaylist: _renamePlaylist,
                onDeletePlaylist: _deletePlaylist,
              ),
              desktopLayout: DesktopLayout(
                playlists: _playlists,
                onAddPlaylist: _addPlaylist,
                onRenamePlaylist: _renamePlaylist,
                onDeletePlaylist: _deletePlaylist,
              ),
            ),
    );
  }
}
