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

import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/widgets/settings/app_icon.dart';
import 'package:flauncher/widgets/settings/blocked_apps_section.dart';
import 'package:flauncher/widgets/settings/settings_choice_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:transparent_image/transparent_image.dart';

import '../../mocks.dart';
import '../../mocks.mocks.dart';

Widget _wrap(AppsService appsService, Widget child) => ChangeNotifierProvider<AppsService>.value(
      value: appsService,
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    );

void main() {
  late MockAppsService appsService;

  setUp(() {
    appsService = MockAppsService();
    when(appsService.getAppIcon(any)).thenAnswer((_) async => kTransparentImage);
  });

  group("SettingsChoiceTile", () {
    testWidgets("the chosen option takes focus and a press picks one", (tester) async {
      String? picked;
      await tester.pumpWidget(_wrap(
        appsService,
        Column(children: [
          for (final value in ["a", "b", "c"])
            SettingsChoiceTile<String>(title: value, value: value, groupValue: "c", onChanged: (v) => picked = v),
        ]),
      ));
      await tester.pumpAndSettle();

      expect(Focus.of(tester.element(find.text("c"))).hasFocus, isTrue);
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);

      await tester.tap(find.text("b"));
      expect(picked, "b");
    });
  });

  group("AppIcon", () {
    testWidgets("fetches the icon once across rebuilds", (tester) async {
      late StateSetter rebuild;
      await tester.pumpWidget(_wrap(
        appsService,
        StatefulBuilder(builder: (context, setState) {
          rebuild = setState;
          return const AppIcon("pkg.one", size: 32);
        }),
      ));
      await tester.pumpAndSettle();
      for (int i = 0; i < 3; i++) {
        rebuild(() {});
        await tester.pump();
      }

      verify(appsService.getAppIcon("pkg.one")).called(1);
      expect(find.byType(Image), findsOneWidget);
    });
  });

  group("BlockedAppsSection", () {
    Widget section({required List<String> blocked, required void Function(String) onUnblock, VoidCallback? onAll}) =>
        _wrap(
          appsService,
          BlockedAppsSection(
            title: "Blocked (${blocked.length})",
            apps: [if (blocked.contains("pkg.one")) fakeApp(packageName: "pkg.one", name: "One")],
            missingPackages: blocked.where((p) => p != "pkg.one").toList(),
            blockedLabel: "Blocked",
            unblockLabel: "Unblock",
            unblockAllLabel: "Unblock all",
            appIcon: Icons.android,
            emptyIcon: Icons.check,
            emptyTitle: "Nothing blocked",
            emptyMessage: "Every app is allowed.",
            onUnblock: onUnblock,
            onUnblockAll: onAll ?? () {},
          ),
        );

    testWidgets("lists installed and missing packages and unblocks them", (tester) async {
      final unblocked = <String>[];
      var all = false;
      await tester
          .pumpWidget(section(blocked: ["pkg.one", "pkg.gone"], onUnblock: unblocked.add, onAll: () => all = true));
      await tester.pumpAndSettle();

      expect(find.text("Blocked (2)"), findsOneWidget);
      expect(find.text("Nothing blocked"), findsNothing);
      await tester.tap(find.text("One"));
      await tester.tap(find.text("pkg.gone"));
      await tester.tap(find.text("Unblock all"));
      expect(unblocked, ["pkg.one", "pkg.gone"]);
      expect(all, isTrue);
    });

    testWidgets("says so when nothing is blocked", (tester) async {
      await tester.pumpWidget(section(blocked: [], onUnblock: (_) {}));
      await tester.pumpAndSettle();

      expect(find.text("Nothing blocked"), findsOneWidget);
      expect(find.text("Unblock all"), findsNothing);
    });
  });
}
