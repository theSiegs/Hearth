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

import 'package:flauncher/flauncher_app.dart';
import 'package:flauncher/l10n/app_localizations.dart';
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
  final List<(String, Map<String, Object?>?, Map<String, Object?>?)> calls = [];
  int attached = 0;

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
  void attach() => attached++;

  @override
  void detach() => attached--;

  @override
  Future<bool> callService(String domain, String service,
      {Map<String, Object?>? target, Map<String, Object?>? data}) async {
    calls.add(("$domain.$service", target, data));
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

void main() {
  final people = layoutOf([
    {"type": "heading", "heading": "People"},
    {
      "type": "tile",
      "entity": "person.alex",
      "name": "Alex",
      "grid_options": {"columns": 6}
    },
    {
      "type": "tile",
      "entity": "person.sam",
      "name": "Sam",
      "grid_options": {"columns": 6}
    },
    {
      "type": "tile",
      "entity": "sensor.outside",
      "name": "Outside",
      "grid_options": {"columns": 12}
    },
    {
      "type": "tile",
      "entity": "media_player.kitchen",
      "name": "Kitchen",
      "grid_options": {"columns": 12},
      "visibility": [
        {
          "condition": "state",
          "entity": "media_player.kitchen",
          "state": ["playing", "paused"]
        }
      ]
    },
    {
      "type": "tile",
      "entity": "person.robin",
      "name": "Robin",
      "grid_options": {"columns": 12}
    },
    {"type": "picture-glance", "entity": "camera.door"},
  ]);

  testWidgets("Draws headings and tiles with their states; what it can't draw is left out", (tester) async {
    final service = FakeHaPanelService(fakeLayout: people, states: {
      "person.alex": "home",
      "person.sam": "not_home",
      "media_player.kitchen": "idle",
    });
    service.setState("sensor.outside", "21.5", {"unit_of_measurement": "°C"});
    await openPanel(tester, service);
    expect(find.text("People"), findsOneWidget);
    expect(find.text("Alex"), findsOneWidget);
    expect(find.text("Home"), findsWidgets);
    expect(find.text("Away"), findsOneWidget);
    expect(find.text("21.5 °C"), findsOneWidget);
    expect(find.text("Kitchen"), findsNothing);
    expect(service.attached, 1);
    // The focus lands on the first tile
    expect(focused(tester, "Alex"), isTrue);
  });

  testWidgets("Up and Down go row by row, Left and Right within a row; Left at the edge closes", (tester) async {
    final service = FakeHaPanelService(fakeLayout: people, states: {"person.alex": "home"});
    await openPanel(tester, service);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(tester, "Sam"), isTrue);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(tester, "Sam"), isTrue, reason: "nothing further right");
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(tester, "Outside"), isTrue);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(tester, "Robin"), isTrue);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(tester, "Robin"), isTrue, reason: "the last row");
    await press(tester, LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focused(tester, "Alex"), isTrue, reason: "the nearer of the pair is the first");
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focused(tester, "Alex"), isTrue);
    expect(find.byType(HaPanel), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.byType(HaPanel), findsNothing);
    expect(service.attached, 0);
  });

  testWidgets("Back closes the panel", (tester) async {
    final service = FakeHaPanelService(fakeLayout: people);
    await openPanel(tester, service);
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(HaPanel), findsNothing);
  });

  testWidgets("Visibility follows the states live, and the focus stays near a card that goes", (tester) async {
    final service = FakeHaPanelService(fakeLayout: people, states: {"media_player.kitchen": "playing"});
    await openPanel(tester, service);
    expect(find.text("Kitchen"), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(tester, "Kitchen"), isTrue);
    service.setState("media_player.kitchen", "off");
    await tester.pumpAndSettle();
    expect(find.text("Kitchen"), findsNothing);
    expect(focused(tester, "Robin") || focused(tester, "Outside"), isTrue);
    // Keys still work
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(FocusManager.instance.primaryFocus, isNotNull);
  });

  testWidgets("Without Home Assistant it says how to set it up, and Left closes it", (tester) async {
    final service = FakeHaPanelService(fakeStatus: HaPanelStatus.notSetUp);
    await openPanel(tester, service);
    expect(find.text("Home Assistant panel isn't set up"), findsOneWidget);
    expect(find.textContaining("access token"), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.byType(HaPanel), findsNothing);
  });

  testWidgets("Unreachable: a quiet row over what was read", (tester) async {
    final service = FakeHaPanelService(fakeLayout: people, fakeStatus: HaPanelStatus.unreachable);
    await openPanel(tester, service);
    expect(find.text("Can't reach Home Assistant"), findsOneWidget);
  });
}
