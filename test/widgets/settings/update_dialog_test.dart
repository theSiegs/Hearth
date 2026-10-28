import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/update_service.dart';
import 'package:flauncher/widgets/settings/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'settings_test_app.dart';

/// UpdateService's state, set by the test; records which of its actions the dialog called.
class _FakeUpdateService extends ChangeNotifier implements UpdateService {
  final List<String> calls = [];

  @override
  UpdateStatus status = UpdateStatus.idle;
  @override
  UpdateInfo? updateInfo;
  @override
  double downloadProgress = 0;
  @override
  UpdateError? error;
  @override
  String? errorMessage;
  @override
  String currentVersion = "2026.10.80+8300";

  void set(UpdateStatus to) {
    status = to;
    notifyListeners();
  }

  @override
  Future<void> checkForUpdate() async => calls.add("checkForUpdate");

  @override
  Future<void> downloadAndInstall() async => calls.add("downloadAndInstall");

  @override
  Future<void> retryInstall() async => calls.add("retryInstall");

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

Future<(_FakeUpdateService, List<String>)> _open(WidgetTester tester, {UpdateStatus status = UpdateStatus.idle}) async {
  final service = _FakeUpdateService()..status = status;
  final events = <String>[];
  final SettingsService settings = await freshSettings();
  await tester.pumpWidget(ChangeNotifierProvider<UpdateService>.value(
    value: service,
    child: settingsTestApp(
      settings,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            await showDialog<void>(context: context, builder: (_) => const UpdateDialog());
            events.add("closed");
          },
          child: const Text("open"),
        ),
      ),
    ),
  ));
  await tester.tap(find.text("open"));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return (service, events);
}

void main() {
  testWidgets("opening it checks for an update and shows the version installed", (tester) async {
    final (service, _) = await _open(tester);

    expect(service.calls, ["checkForUpdate"]);
    expect(find.text("Check for Updates"), findsOneWidget);
    expect(find.text("Current version: 2026.10.80+8300"), findsOneWidget);
    expect(find.text("Checking GitHub for a new release…"), findsOneWidget);
    // While checking, Close is the only button, and it has the focus
    expect(find.text("Check Again"), findsNothing);
    expect(hasFocusOn(tester, "Close"), isTrue);
  });

  testWidgets("an update shows its version and changelog, and OK downloads it", (tester) async {
    final (service, _) = await _open(tester);
    service.updateInfo = UpdateInfo(
        tagName: "v2026.10.90", changelog: "- Faster home screen", downloadUrl: "https://x/a.apk", assetSizeBytes: 1);
    service.set(UpdateStatus.available);
    await tester.pump();

    expect(find.text("Version v2026.10.90 is available"), findsOneWidget);
    expect(find.text("- Faster home screen"), findsOneWidget);
    expect(hasFocusOn(tester, "Download & Install"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(service.calls, ["checkForUpdate", "downloadAndInstall"]);
  });

  testWidgets("a blank changelog shows no box", (tester) async {
    final (service, _) = await _open(tester);
    service.updateInfo =
        UpdateInfo(tagName: "v2026.10.90", changelog: "  \n", downloadUrl: "https://x/a.apk", assetSizeBytes: 1);
    service.set(UpdateStatus.available);
    await tester.pump();

    // The dialog's own scroll view only, no changelog box inside it
    expect(find.byType(SingleChildScrollView), findsOneWidget);

    service.updateInfo = UpdateInfo(
        tagName: "v2026.10.90", changelog: "- Fixes", downloadUrl: "https://x/a.apk", assetSizeBytes: 1);
    service.set(UpdateStatus.available);
    await tester.pump();
    expect(find.byType(SingleChildScrollView), findsNWidgets(2));
  });

  testWidgets("downloading shows the progress and offers only Close", (tester) async {
    final (service, _) = await _open(tester);
    service.downloadProgress = 0.42;
    service.set(UpdateStatus.downloading);
    await tester.pump();

    expect(find.text("Downloading… 42%"), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.42);
    expect(find.text("Download & Install"), findsNothing);

    // Before any byte arrives the bar runs without a value
    service.downloadProgress = 0;
    service.set(UpdateStatus.downloading);
    await tester.pump();
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, isNull);
  });

  testWidgets("a downloaded update offers to retry the install", (tester) async {
    final (service, _) = await _open(tester);
    service.set(UpdateStatus.readyToInstall);
    await tester.pump();

    expect(find.textContaining("Install unknown apps"), findsOneWidget);
    await tester.tap(find.text("Retry Install"));
    await tester.pump();
    expect(service.calls.last, "retryInstall");
  });

  testWidgets("up to date offers to check again", (tester) async {
    final (service, _) = await _open(tester);
    service.set(UpdateStatus.upToDate);
    await tester.pump();

    expect(find.text("You're on the latest version."), findsOneWidget);
    expect(hasFocusOn(tester, "Check Again"), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(service.calls, ["checkForUpdate", "checkForUpdate"]);
  });

  testWidgets("an error says why in the app's language, else its own text", (tester) async {
    final (service, _) = await _open(tester);
    service.error = UpdateError.noApkForDevice;
    service.errorMessage = "No APK asset";
    service.set(UpdateStatus.error);
    await tester.pump();
    expect(find.text("No release has an APK for this device"), findsOneWidget);
    expect(find.text("Check Again"), findsOneWidget);

    service.error = null;
    service.set(UpdateStatus.error);
    await tester.pump();
    expect(find.text("No APK asset"), findsOneWidget);

    service.errorMessage = null;
    service.set(UpdateStatus.error);
    await tester.pump();
    expect(find.text("Something went wrong"), findsOneWidget);
  });

  testWidgets("Close closes it", (tester) async {
    final (service, events) = await _open(tester, status: UpdateStatus.upToDate);
    await tester.tap(find.text("Close"));
    await tester.pumpAndSettle();
    expect(events, ["closed"]);
    expect(find.text("Check for Updates"), findsNothing);
    expect(service.calls, ["checkForUpdate"]);
  });
}
