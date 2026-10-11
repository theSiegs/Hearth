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

import 'package:flauncher/providers/ha_calls.dart';
import 'package:flauncher/widgets/ha_panel/ha_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ha_panel_helpers.dart';

/// The focused stop's semantics label (a round button's or a slider's).
String? focusedLabel() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  String? label;
  context.visitAncestorElements((e) {
    final w = e.widget;
    if (w is Semantics && w.properties.label != null) {
      label = w.properties.label;
      return false;
    }
    return true;
  });
  return label;
}

void main() {
  testWidgets("Thermostat: − and + step the target, which goes once the presses stop; modes are chips", (tester) async {
    final service = FakeHaPanelService(
        fakeLayout: layoutOf([
      {
        "type": "tile",
        "entity": "climate.hall",
        "name": "Hall",
        "features": [
          {"type": "target-temperature"},
          {"type": "climate-hvac-modes", "style": "icons"},
        ]
      },
    ]));
    service.setState("climate.hall", "heat", {
      "temperature": 70,
      "current_temperature": 68,
      "min_temp": 50,
      "max_temp": 90,
      "target_temp_step": 1,
      "temperature_unit": "°F",
      "hvac_modes": ["heat", "cool", "off"],
    });
    await openPanel(tester, service);
    expect(find.text("70 °F"), findsOneWidget);
    // No OK action on a thermostat: the focus starts on −
    expect(focusedLabel(), "Lower");
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedLabel(), "Raise");
    await press(tester, LogicalKeyboardKey.select);
    await press(tester, LogicalKeyboardKey.select);
    expect(find.text("72 °F"), findsOneWidget);
    expect(service.calls, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(service.calls.single,
        HaCall("climate.set_temperature", target: {"entity_id": "climate.hall"}, data: {"temperature": 72.0}));
    // Down to the modes, nearest across: the last chip; Left goes along them
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedLabel(), "off");
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusedLabel(), "cool");
    await press(tester, LogicalKeyboardKey.select);
    expect(service.calls.last,
        HaCall("climate.set_hvac_mode", target: {"entity_id": "climate.hall"}, data: {"hvac_mode": "cool"}));
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets("Light: OK toggles; on the slider Left and Right set the brightness and don't leave", (tester) async {
    final service = FakeHaPanelService(
        fakeLayout: layoutOf([
      {
        "type": "tile",
        "entity": "light.living_room",
        "name": "Living room",
        "tap_action": {"action": "toggle"},
        "features": [
          {"type": "light-brightness"}
        ],
        "grid_options": {"columns": 12},
      },
    ]));
    service.setState("light.living_room", "on", {"brightness": 128});
    await openPanel(tester, service);
    await press(tester, LogicalKeyboardKey.select);
    expect(service.calls.single,
        HaCall("light.toggle", target: {"entity_id": "light.living_room"}, data: <String, Object?>{}));
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedLabel(), "Brightness");
    expect(find.text("50%"), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.text("70%"), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.text("60%"), findsOneWidget);
    expect(find.byType(HaPanel), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(service.calls.last,
        HaCall("light.turn_on", target: {"entity_id": "light.living_room"}, data: {"brightness_pct": 60}));
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets("Player: playback buttons by its features, and the volume", (tester) async {
    final service = FakeHaPanelService(
        fakeLayout: layoutOf([
      {
        "type": "tile",
        "entity": "media_player.kitchen",
        "name": "Kitchen",
        "state_content": ["media_title", "media_artist", "state"],
        "features": [
          {"type": "media-player-playback"},
          {"type": "media-player-volume-slider"},
        ],
      },
    ]));
    service.setState("media_player.kitchen", "playing", {
      "media_title": "A song",
      "media_artist": "A band",
      "volume_level": 0.3,
      "supported_features": HaMediaFeatures.pause |
          HaMediaFeatures.play |
          HaMediaFeatures.previousTrack |
          HaMediaFeatures.nextTrack |
          HaMediaFeatures.volumeSet,
    });
    await openPanel(tester, service);
    expect(find.text("A song · A band · Playing"), findsOneWidget);
    expect(focusedLabel(), "Previous");
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedLabel(), "Pause");
    await press(tester, LogicalKeyboardKey.select);
    expect(service.calls.single.action, "media_player.media_pause");
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedLabel(), "Volume");
    await press(tester, LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 500));
    expect(service.calls.last,
        HaCall("media_player.volume_set", target: {"entity_id": "media_player.kitchen"}, data: {"volume_level": 0.35}));
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets("Scene: OK runs its action", (tester) async {
    final service = FakeHaPanelService(
        fakeLayout: layoutOf([
      {
        "type": "tile",
        "entity": "scene.evening",
        "name": "Evening",
        "tap_action": {
          "action": "perform-action",
          "perform_action": "scene.turn_on",
          "target": {"entity_id": "scene.evening"}
        },
        "grid_options": {"columns": 12},
      },
    ]));
    service.setState("scene.evening", "2026-10-01T18:00:00+00:00");
    await openPanel(tester, service);
    await press(tester, LogicalKeyboardKey.select);
    expect(service.calls.single,
        HaCall("scene.turn_on", target: {"entity_id": "scene.evening"}, data: <String, Object?>{}));
  });
}
