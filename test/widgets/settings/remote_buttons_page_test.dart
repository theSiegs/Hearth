import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/widgets/settings/remote_buttons_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../mocks.mocks.dart';

void main() {
  testWidgets("lists remapped buttons with readable names", (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('me.efesser.flauncher/method'),
      (call) async => call.method == "getButtonMappings"
          ? '{"183":{"name":"KEYCODE_PROG_RED","short":{"type":"app","target":"com.thesiegs.hearthtube","label":"HearthTube"}}}'
          : null,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('me.efesser.flauncher/method'), null));

    await tester.pumpWidget(ChangeNotifierProvider<AppsService>.value(
      value: MockAppsService(),
      child: const MaterialApp(home: Scaffold(body: RemoteButtonsPage())),
    ));
    await tester.pumpAndSettle();

    expect(find.text("Remap a button"), findsOneWidget);
    expect(find.textContaining("Red\nPress: HearthTube"), findsOneWidget);
    expect(find.textContaining("Hold: Normal"), findsOneWidget);
  });
}
