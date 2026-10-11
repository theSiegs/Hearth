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

// The Home Assistant panel's widget tests' helpers: a pretend service and a home to open the panel over.

import 'package:flauncher/flauncher_app.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/ha_calls.dart';
import 'package:flauncher/providers/ha_entities.dart';
import 'package:flauncher/providers/ha_lovelace.dart';
import 'package:flauncher/providers/ha_panel_service.dart';
import 'package:flauncher/widgets/ha_panel/ha_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The panel's data without Home Assistant: a layout and states the test sets.
class FakeHaPanelService extends HaPanelService {
  HaPanelStatus fakeStatus;
  HaPanelLayout fakeLayout;
  Map<String, HaEntity> states;
  final List<HaCall> calls = [];
  int attached = 0;
  Map<String, String> renderedTemplates = {};

  FakeHaPanelService(
      {this.fakeStatus = HaPanelStatus.ready, this.fakeLayout = HaPanelLayout.empty, Map<String, String>? states})
      : states = {for (final e in (states ?? {}).entries) e.key: HaEntity(e.key, e.value)},
        super(connection: () async => null, dashboard: () async => "lovelace");

  void setState(String id, String state, [Map<String, Object?> attributes = const {}]) {
    states = {...states, id: HaEntity(id, state, attributes: attributes)};
    notifyListeners();
  }

  @override
  HaPanelStatus get status => fakeStatus;

  @override
  HaPanelLayout get layout => fakeLayout;

  @override
  bool get layoutLoaded => fakeStatus != HaPanelStatus.notSetUp && fakeLayout.sections.isNotEmpty;

  @override
  Map<String, HaEntity> get entities => states;

  @override
  HaEntity? entity(String id) => states[id];

  @override
  String? translate(String key) => null;

  @override
  HaConditionContext get conditionContext => HaConditionContext(entity);

  @override
  String? rendered(String template) => renderedTemplates[template];

  @override
  void attach() => attached++;

  @override
  void detach() => attached--;

  @override
  Future<bool> callService(String domain, String service,
      {Map<String, Object?>? target, Map<String, Object?>? data}) async {
    calls.add(HaCall("$domain.$service", target: target ?? const {}, data: data ?? const {}));
    return true;
  }
}

HaPanelLayout layoutOf(List<Map<String, Object?>> cards, {List<Map<String, Object?>> more = const []}) =>
    HaLovelace.parse({
      "views": [
        {
          "sections": [
            {"cards": cards},
            ...more,
          ]
        }
      ]
    }, null);

/// The home (one button), with the panel opened over it.
Future<void> openPanel(WidgetTester tester, HaPanelService service, {DateTime? now}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    shortcuts: hearthActivateShortcuts(WidgetsApp.defaultShortcuts),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            autofocus: true,
            onPressed: () => showDialog(
              context: context,
              barrierColor: Colors.transparent,
              builder: (_) => HaPanel(service: service, now: () => now ?? DateTime(2026, 10, 10, 12)),
            ),
            child: const Text("Home"),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.select);
  await tester.pumpAndSettle();
}

/// The card (by its text) whose stop has the focus.
bool focused(WidgetTester tester, String text) {
  final focus = FocusManager.instance.primaryFocus;
  if (focus?.context == null) return false;
  final element = tester.element(find.text(text));
  var found = false;
  focus!.context!.visitChildElements((_) {});
  element.visitAncestorElements((a) {
    if (a == focus.context) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}
