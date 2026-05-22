import 'package:flutter/material.dart';

class ManagePlaylistsPage extends StatelessWidget {
  const ManagePlaylistsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        title: const Text('Manage Playlists'),
      ),
      body: const Center(
        child: Text('Manage Playlists Placeholder'),
      ),
    );
  }
}
