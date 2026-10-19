import 'dart:convert';
import 'dart:io';

import 'package:deshplayer/models/cloud_node.dart';
import 'package:deshplayer/models/settings.dart';
import 'package:deshplayer/services/cloud_media_service.dart';
import 'package:deshplayer/services/cloud_provider.dart';
import 'package:deshplayer/services/hive_storage_service.dart';
import 'package:deshplayer/ui/pages/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';

class FakeProvider implements CloudProvider {
  FakeProvider(this.id, this.name);
  @override
  final String id;
  @override
  final String name;
  String? credentials;
  @override
  Future<bool> hasCredentials() async => credentials != null;
  @override
  Future<bool> isConnected() async => credentials != null;
  @override
  Future<void> connect(String token) async {
    credentials = token;
  }

  @override
  Future<void> disconnect() async {
    credentials = null;
  }

  @override
  Future<List<CloudNode>> listPath(
    String path, {
    int limit = 100,
    int offset = 0,
  }) async => [];
  @override
  Future<Map<String, String>> getDownloadHeaders() async => {};
  @override
  Future<String?> getDownloadUrl(String path) async => null;
  @override
  Future<void> uploadFile(String path, File file) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late List<CloudProvider> originalProviders;
  late FakeProvider google;
  late FakeProvider yandex;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('provider_settings');
    Hive.init(directory.path);
    Hive.registerAdapter(AppSettingsAdapter());
    HiveStorageService().settingsBox = await Hive.openBox<AppSettings>(
      'test-settings',
    );
    PackageInfo.setMockInitialValues(
      appName: 'Deshplayer',
      packageName: 'deshplayer',
      version: '1.0',
      buildNumber: '1',
      buildSignature: '',
    );
    originalProviders = List.of(CloudMediaService().providers);
  });
  tearDownAll(() async {
    CloudMediaService().providers
      ..clear()
      ..addAll(originalProviders);
    await Hive.close();
    await directory.delete(recursive: true);
  });
  setUp(() {
    google = FakeProvider('google_drive', 'Google Drive');
    yandex = FakeProvider('yandex_disk', 'Yandex Disk');
    CloudMediaService().providers
      ..clear()
      ..addAll([yandex, google]);
  });

  testWidgets(
    'Connect selects provider, validates credentials, then shows its saved connection',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
      await tester.pumpAndSettle();
      expect(find.text('Google Drive'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Connect').last);
      await tester.pumpAndSettle();
      expect(find.text('Google Drive'), findsOneWidget);
      expect(find.text('Yandex Disk'), findsOneWidget);
      await tester.tap(find.text('Google Drive'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Connect').last);
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsNWidgets(2));
      expect(google.credentials, isNull);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'OAuth Client ID'),
        'client-id',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Refresh Token'),
        'refresh-token',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Connect').last);
      await tester.pumpAndSettle();
      expect(jsonDecode(google.credentials!)['refresh_token'], 'refresh-token');
      expect(find.text('Google Drive'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Yandex Disk'), findsNothing);
      await tester.tap(find.byTooltip('Connection options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      expect(find.text('Google Drive'), findsNothing);
      expect(google.credentials, isNull);
    },
  );

  testWidgets('Yandex connection still accepts an OAuth token', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Connect').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yandex Disk'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'OAuth Access Token'),
      'yandex-token',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Connect').last);
    await tester.pumpAndSettle();
    expect(yandex.credentials, 'yandex-token');
    expect(find.text('Connected'), findsOneWidget);
  });
}
