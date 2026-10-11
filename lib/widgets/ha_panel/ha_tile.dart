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

import 'package:flauncher/providers/ha_entities.dart';
import 'package:flauncher/providers/ha_lovelace.dart';
import 'package:flauncher/providers/ha_panel_service.dart';
import 'package:flauncher/widgets/focusable_tap.dart';
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
    return FocusableTap(
      onPressed: () {},
      builder: (context, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(10),
        decoration: haFocusDecoration(context, focused),
        child: header,
      ),
    );
  }

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
