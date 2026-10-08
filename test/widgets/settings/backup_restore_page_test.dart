/*
 * Hearth
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:io';

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/backup_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/settings/backup_restore_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.mocks.dart';

class _FakeBackupService extends Fake implements BackupService {
  final Object? importError;
  final List<String> imported = [];

  _FakeBackupService({this.importError});

  @override
  Future<List<BackupFileEntry>> getBackupFiles() async => [
        BackupFileEntry(
          file: File("hearth_backup.json"),
          name: "hearth_backup.json",
          lastModified: DateTime(2026, 10, 1, 9, 30),
          size: 2048,
        ),
      ];

  @override
  Future<void> importBackup(File backupFile, SettingsService settingsService) async {
    imported.add(backupFile.path);
    if (importError != null) throw importError!;
  }
}

void main() {
  late MockSettingsService settingsService;
  late MockAppsService appsService;

  setUp(() {
    settingsService = MockSettingsService();
    appsService = MockAppsService();
    when(appsService.refreshState()).thenAnswer((_) async {});
  });

  // The page sits on top of another, as it does in the Settings panel, so closing it can be seen.
  Future<void> openPage(WidgetTester tester, BackupService backupService) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<BackupService>.value(value: backupService),
        ChangeNotifierProvider<SettingsService>.value(value: settingsService),
        ChangeNotifierProvider<AppsService>.value(value: appsService),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Text("System")),
      ),
    ));
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: BackupRestorePage())));
    await tester.pumpAndSettle();
  }

  Future<void> importTheBackup(WidgetTester tester) async {
    await tester.tap(find.text("Import Backup"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("hearth_backup.json"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Import"));
    await tester.pumpAndSettle();
  }

  testWidgets("a finished import says so, and OK closes the page", (tester) async {
    final backupService = _FakeBackupService();
    await openPage(tester, backupService);

    await importTheBackup(tester);

    expect(backupService.imported, ["hearth_backup.json"]);
    verify(settingsService.reload()).called(1);
    verify(appsService.refreshState()).called(1);
    expect(find.text("Import Success"), findsOneWidget);
    expect(find.text("Backup imported successfully"), findsOneWidget);

    await tester.tap(find.text("OK"));
    await tester.pumpAndSettle();
    expect(find.byType(BackupRestorePage), findsNothing);
    expect(find.text("System"), findsOneWidget);
  });

  testWidgets("a failed import says why and stays on the page", (tester) async {
    await openPage(tester, _FakeBackupService(importError: Exception("not a backup")));

    await importTheBackup(tester);

    expect(find.text("Import Failed"), findsOneWidget);
    expect(find.text("Failed to import backup: Exception: not a backup"), findsOneWidget);

    await tester.tap(find.text("OK"));
    await tester.pumpAndSettle();
    expect(find.byType(BackupRestorePage), findsOneWidget);
  });
}
