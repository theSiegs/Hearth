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
import 'package:flauncher/providers/ha_calls.dart';
import 'package:flauncher/providers/ha_entities.dart';
import 'package:flauncher/providers/ha_lovelace.dart';
import 'package:flauncher/providers/ha_panel_service.dart';
import 'package:flauncher/widgets/focusable_tap.dart';
import 'package:flauncher/widgets/ha_panel/ha_controls.dart';
import 'package:flauncher/widgets/ha_panel/ha_format.dart';
import 'package:flauncher/widgets/ha_panel/ha_icons.dart';
import 'package:flutter/material.dart';

/// How the panel's focus stops look: a big outline in the accent colour while focused.
BoxDecoration haFocusDecoration(BuildContext context, bool focused, {double radius = 16, bool filled = true}) =>
    BoxDecoration(
      color: focused ? Colors.white.withOpacity(0.14) : (filled ? Colors.white.withOpacity(0.06) : Colors.transparent),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: focused ? Theme.of(context).colorScheme.primary : Colors.transparent, width: 3),
    );

/// A tile: the entity's icon, name and state, and its controls under them.
class HaTile extends StatelessWidget {
  final HaTileCard card;
  final HaPanelService service;
  final HaFormat format;

  const HaTile({super.key, required this.card, required this.service, required this.format});

  @override
  Widget build(BuildContext context) {
    final entity = service.entity(card.entity);
    final header = _header(context, entity);
    final controls = _controls(context, entity);
    final tap = HaCalls.tap(card, entity);
    // A tile without controls is one stop; with them, its header is a stop of its own only when OK does something
    if (controls.isEmpty || tap != null) {
      final tapHeader = FocusableTap(
        onPressed: () {
          final call = HaCalls.tap(card, service.entity(card.entity));
          if (call != null) service.run(call);
        },
        builder: (context, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(10),
          decoration: haFocusDecoration(context, focused, filled: controls.isEmpty),
          child: header,
        ),
      );
      if (controls.isEmpty) return tapHeader;
      return _frame(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [tapHeader, ..._spaced(controls)],
      ));
    }
    return _frame(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [Padding(padding: const EdgeInsets.all(7), child: header), ..._spaced(controls)],
    ));
  }

  Widget _frame(Widget child) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      );

  static List<Widget> _spaced(List<Widget> controls) =>
      [for (final c in controls) Padding(padding: const EdgeInsets.fromLTRB(2, 4, 2, 4), child: c)];

  /// The tile's features as controls; those that can't work on the entity now are left out.
  List<Widget> _controls(BuildContext context, HaEntity? entity) {
    if (entity == null || entity.unavailable) return const [];
    final l = AppLocalizations.of(context)!;
    final out = <Widget>[];
    for (final feature in card.features) {
      switch (feature) {
        case HaTargetTemperatureFeature():
          out.addAll(_temperature(entity, l));
        case HaHvacModesFeature(:final modes):
          final attribute = entity.attributes["hvac_modes"];
          final available = [
            if (attribute is List)
              for (final m in attribute) "$m"
          ];
          final shown = modes == null ? available : modes.where(available.contains).toList();
          if (shown.isEmpty) break;
          out.add(Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in shown)
                HaRoundButton(
                  icon: HaIcons.hvacMode(mode),
                  label: format.translate("component.climate.entity_component._.state.$mode") ?? mode,
                  selected: entity.state == mode,
                  size: 40,
                  onPressed: () => service.run(HaCalls.setHvacMode(card.entity, mode)),
                ),
            ],
          ));
        case HaMediaPlaybackFeature():
          final buttons = HaCalls.playback(entity);
          if (buttons.isEmpty) break;
          out.add(Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final b in buttons)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: HaRoundButton(
                    icon: _playbackIcon(b),
                    label: _playbackLabel(l, b),
                    selected: b == HaPlayback.pause || b == HaPlayback.play,
                    onPressed: () => service.run(HaCalls.playbackCall(card.entity, b)),
                  ),
                ),
            ],
          ));
        case HaVolumeSliderFeature():
          if (!entity.supports(HaMediaFeatures.volumeSet)) break;
          final level = entity.number("volume_level")?.toDouble() ?? 0;
          out.add(HaSlider(
            value: (level * 100).round(),
            icon: Icons.volume_up,
            label: l.haControlVolume,
            onCommit: (v) => service.run(HaCalls.volume(card.entity, v / 100)),
          ));
        case HaLightBrightnessFeature():
          out.add(HaSlider(
            value: HaCalls.brightnessPercent(entity),
            step: 10,
            icon: Icons.brightness_6,
            label: l.haControlBrightness,
            onCommit: (v) => service.run(HaCalls.brightness(card.entity, v)),
          ));
        case HaBarGaugeFeature(:final min, :final max):
          final value = num.tryParse(entity.state);
          if (value == null || max <= min) break;
          out.add(HaBarGauge(fraction: (value - min) / (max - min)));
        case HaTemperatureForecastFeature():
        case HaUnsupportedFeature():
          break;
      }
    }
    return out;
  }

  /// A thermostat's target: one − / + pair, or two for a range (heat_cool).
  List<Widget> _temperature(HaEntity entity, AppLocalizations l) {
    final attributeUnit = entity.attributes["temperature_unit"];
    final unit = attributeUnit is String ? attributeUnit : service.temperatureUnit;
    final step = HaCalls.temperatureStep(entity, unit);
    String show(double v) =>
        HaFormat.number(v == v.roundToDouble() ? "${v.round()}" : v.toStringAsFixed(1), unit ?? "°");
    double clamp(double v) => HaCalls.clampTemperature(entity, v, step);
    final target = entity.number("temperature")?.toDouble();
    if (target != null) {
      return [
        HaStepper(
          value: target,
          step: step,
          format: show,
          clamp: clamp,
          decreaseLabel: l.haControlLower,
          increaseLabel: l.haControlRaise,
          onCommit: (v) => service.run(HaCalls.setTemperature(card.entity, v)),
        )
      ];
    }
    final low = entity.number("target_temp_low")?.toDouble();
    final high = entity.number("target_temp_high")?.toDouble();
    if (low == null || high == null) return const [];
    double now(String key, double fallback) => service.entity(card.entity)?.number(key)?.toDouble() ?? fallback;
    return [
      HaStepper(
        value: low,
        step: step,
        format: show,
        clamp: clamp,
        caption: l.haControlLow,
        decreaseLabel: l.haControlLower,
        increaseLabel: l.haControlRaise,
        onCommit: (v) => service.run(HaCalls.setTemperatureRange(card.entity, v, now("target_temp_high", high))),
      ),
      HaStepper(
        value: high,
        step: step,
        format: show,
        clamp: clamp,
        caption: l.haControlHigh,
        decreaseLabel: l.haControlLower,
        increaseLabel: l.haControlRaise,
        onCommit: (v) => service.run(HaCalls.setTemperatureRange(card.entity, now("target_temp_low", low), v)),
      ),
    ];
  }

  static IconData _playbackIcon(HaPlayback b) => switch (b) {
        HaPlayback.turnOn => Icons.power_settings_new,
        HaPlayback.previous => Icons.skip_previous,
        HaPlayback.play => Icons.play_arrow,
        HaPlayback.pause => Icons.pause,
        HaPlayback.stop => Icons.stop,
        HaPlayback.next => Icons.skip_next,
      };

  static String _playbackLabel(AppLocalizations l, HaPlayback b) => switch (b) {
        HaPlayback.turnOn => l.haControlTurnOn,
        HaPlayback.previous => l.haControlPrevious,
        HaPlayback.play => l.haControlPlay,
        HaPlayback.pause => l.haControlPause,
        HaPlayback.stop => l.haControlStop,
        HaPlayback.next => l.haControlNext,
      };

  Widget _header(BuildContext context, HaEntity? entity) {
    final text = Theme.of(context).textTheme;
    final active = HaTileColors.active(entity);
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: (active ?? Colors.white).withOpacity(active == null ? 0.08 : 0.22),
            shape: BoxShape.circle,
          ),
          child: Icon(HaIcons.of(card.icon, entity: entity, entityId: card.entity),
              size: 20, color: active ?? Colors.white70),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(card.name ?? entity?.name ?? card.entity,
                  style: text.bodyMedium!.copyWith(fontWeight: FontWeight.w700, color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(format.tileState(entity, card.stateContent),
                  style: text.bodySmall!.copyWith(color: Colors.white70), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}

/// The colour of a tile's icon while its entity is on (a light lit, a player playing); null while it's off.
class HaTileColors {
  static Color? active(HaEntity? entity) {
    if (entity == null || entity.unavailable) return null;
    switch (entity.domain) {
      case "light":
        return entity.state == "on" ? const Color(0xFFFFC107) : null;
      case "switch":
      case "input_boolean":
      case "fan":
        return entity.state == "on" ? const Color(0xFF42A5F5) : null;
      case "media_player":
        return entity.state == "playing" ? const Color(0xFF7E57C2) : null;
      case "climate":
        return switch (entity.state) {
          "heat" => const Color(0xFFFF7043),
          "cool" => const Color(0xFF29B6F6),
          "heat_cool" || "auto" => const Color(0xFF66BB6A),
          _ => null,
        };
      case "person":
      case "device_tracker":
        return entity.state == "home" ? const Color(0xFF66BB6A) : null;
      case "binary_sensor":
        return entity.state == "on" ? const Color(0xFFFFA726) : null;
    }
    return null;
  }
}
