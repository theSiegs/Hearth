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

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/ha_panel_service.dart';
import 'package:flauncher/widgets/ha_panel/ha_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ha_panel_helpers.dart';

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
    // The next one down takes the focus, not the top
    expect(focused(tester, "Robin"), isTrue);
    // Keys still work
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focused(tester, "Outside"), isTrue);
  });

  testWidgets("A tile with its own picture shows it, round, fetched with the token from Home Assistant",
      (tester) async {
    final service = FakeHaPanelService(
        fakeLayout: layoutOf([
      {
        "type": "tile",
        "entity": "person.alex",
        "name": "Alex",
        "grid_options": {"columns": 12}
      },
      {
        "type": "tile",
        "entity": "person.sam",
        "name": "Sam",
        "grid_options": {"columns": 12}
      },
    ]))
      ..fakeConnection = (url: "http://192.0.2.10:8123", token: "t0ken");
    service.setState("person.alex", "home", {"entity_picture": "/api/image/serve/abc/512x512"});
    service.setState("person.sam", "home");
    await openPanel(tester, service);
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as NetworkImage;
    expect(provider.url, "http://192.0.2.10:8123/api/image/serve/abc/512x512");
    expect(provider.headers, {"Authorization": "Bearer t0ken"});
    expect(find.ancestor(of: find.byType(Image), matching: find.byType(ClipOval)), findsOneWidget);
    // Sam has none, and when a picture can't be had the icon takes its place
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(find.byIcon(Icons.person), findsNWidgets(2));
  });

  testWidgets("The last card going: the focus moves to the one before", (tester) async {
    final last = layoutOf([
      {
        "type": "tile",
        "entity": "person.alex",
        "name": "Alex",
        "grid_options": {"columns": 12}
      },
      {
        "type": "tile",
        "entity": "person.sam",
        "name": "Sam",
        "grid_options": {"columns": 12}
      },
      {
        "type": "tile",
        "entity": "media_player.den",
        "name": "Den",
        "grid_options": {"columns": 12},
        "visibility": [
          {"condition": "state", "entity": "media_player.den", "state": "playing"}
        ]
      },
    ]);
    final service = FakeHaPanelService(fakeLayout: last, states: {"media_player.den": "playing"});
    await openPanel(tester, service);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(tester, "Den"), isTrue);
    service.setState("media_player.den", "idle");
    await tester.pumpAndSettle();
    expect(focused(tester, "Sam"), isTrue);
  });

  testWidgets("Without Home Assistant it says how to set it up, and Left closes it", (tester) async {
    final service = FakeHaPanelService(fakeStatus: HaPanelStatus.notSetUp);
    await openPanel(tester, service);
    expect(find.text("Home Assistant panel isn't set up"), findsOneWidget);
    expect(find.textContaining("access token"), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.byType(HaPanel), findsNothing);
  });

  testWidgets("Markdown (rendered by Home Assistant) and a map as a list", (tester) async {
    const template = "{% if true %}| Kid | Today |\n|---|---:|\n| Alex | 25 min |{% endif %}";
    final service = FakeHaPanelService(
        fakeLayout: layoutOf([
          {"type": "markdown", "content": template},
          {
            "type": "map",
            "entities": ["person.alex"]
          },
          {"type": "picture-glance", "entity": "camera.door"},
        ]),
        states: {"person.alex": "School"})
      ..renderedTemplates = {template: "| Kid | Today |\n|---|---:|\n| Alex | 25 min |"};
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            autofocus: true,
            onPressed: () => HaPanel.open(context, service),
            child: const Text("Home"),
          ),
        ),
      ),
    ));
    await tester.pump();
    await press(tester, LogicalKeyboardKey.select);
    expect(find.byType(Table), findsOneWidget);
    expect(find.text("25 min", findRichText: true), findsOneWidget);
    expect(find.text("person.alex"), findsOneWidget);
    expect(find.text("School"), findsOneWidget);
    // No row for Home Assistant's own dashboard: the panel is the dashboard
    expect(find.text("Open the full dashboard"), findsNothing);
  });

  testWidgets("Unreachable: a quiet row over what was read", (tester) async {
    final service = FakeHaPanelService(fakeLayout: people, fakeStatus: HaPanelStatus.unreachable);
    await openPanel(tester, service);
    expect(find.text("Can't reach Home Assistant"), findsOneWidget);
  });
}
