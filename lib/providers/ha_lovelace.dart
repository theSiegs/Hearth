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

/// What a visibility condition is checked against: the entities' states, and who the panel is signed in as.
class HaConditionContext {
  final HaEntity? Function(String entityId) entity;
  final String? userId;

  const HaConditionContext(this.entity, {this.userId});
}

/// A card's or a section's visibility condition (Home Assistant's "visibility" list, or a conditional card's).
sealed class HaCondition {
  const HaCondition();

  bool test(HaConditionContext context);

  /// The entities it looks at.
  Iterable<String> get entities;

  /// Every condition in [conditions] holds (an empty list always does).
  static bool all(List<HaCondition> conditions, HaConditionContext context) => conditions.every((c) => c.test(context));

  /// Home Assistant's condition list; conditions it can't read are left out.
  static List<HaCondition> parseList(Object? json) {
    if (json is! List) return const [];
    return [for (final c in json) parse(c)].whereType<HaCondition>().toList(growable: false);
  }

  static HaCondition? parse(Object? json) {
    if (json is! Map) return null;
    final kind = json["condition"];
    switch (kind) {
      case "state":
      case null when json["entity"] is String:
        final entity = json["entity"];
        if (entity is! String) return null;
        if (json.containsKey("state")) return HaStateCondition(entity, _strings(json["state"]));
        if (json.containsKey("state_not")) return HaStateCondition(entity, _strings(json["state_not"]), not: true);
        return null;
      case "numeric_state":
        final entity = json["entity"];
        if (entity is! String) return null;
        return HaNumericStateCondition(entity, above: _num(json["above"]), below: _num(json["below"]));
      case "or":
        return HaAnyCondition(parseList(json["conditions"]));
      case "and":
        return HaAllCondition(parseList(json["conditions"]));
      case "not":
        return HaNotCondition(parseList(json["conditions"]));
      case "user":
        return HaUserCondition(_strings(json["users"]));
      default:
        // A screen size or a place: there's one screen and one place, so it shows
        return const HaAlwaysCondition();
    }
  }

  static List<String> _strings(Object? value) => value is List
      ? [
          for (final v in value)
            if (v != null) "$v"
        ]
      : value == null
          ? const []
          : ["$value"];

  static num? _num(Object? value) => value is num ? value : (value is String ? num.tryParse(value) : null);
}

/// The entity's state is (or, with [not], isn't) one of [states]. A missing entity counts as unavailable.
class HaStateCondition extends HaCondition {
  final String entity;
  final List<String> states;
  final bool not;

  const HaStateCondition(this.entity, this.states, {this.not = false});

  @override
  bool test(HaConditionContext context) {
    final state = context.entity(entity)?.state ?? "unavailable";
    return states.contains(state) != not;
  }

  @override
  Iterable<String> get entities => [entity];
}

class HaNumericStateCondition extends HaCondition {
  final String entity;
  final num? above;
  final num? below;

  const HaNumericStateCondition(this.entity, {this.above, this.below});

  @override
  bool test(HaConditionContext context) {
    final value = num.tryParse(context.entity(entity)?.state ?? "");
    if (value == null) return false;
    return (above == null || value > above!) && (below == null || value < below!);
  }

  @override
  Iterable<String> get entities => [entity];
}

class HaAnyCondition extends HaCondition {
  final List<HaCondition> conditions;

  const HaAnyCondition(this.conditions);

  @override
  bool test(HaConditionContext context) => conditions.isEmpty || conditions.any((c) => c.test(context));

  @override
  Iterable<String> get entities => conditions.expand((c) => c.entities);
}

class HaAllCondition extends HaCondition {
  final List<HaCondition> conditions;

  const HaAllCondition(this.conditions);

  @override
  bool test(HaConditionContext context) => HaCondition.all(conditions, context);

  @override
  Iterable<String> get entities => conditions.expand((c) => c.entities);
}

/// None of [conditions] holds.
class HaNotCondition extends HaCondition {
  final List<HaCondition> conditions;

  const HaNotCondition(this.conditions);

  @override
  bool test(HaConditionContext context) => !conditions.any((c) => c.test(context));

  @override
  Iterable<String> get entities => conditions.expand((c) => c.entities);
}

/// The panel is signed in as one of [users] (Home Assistant user ids). Until it's known who that is, it shows.
class HaUserCondition extends HaCondition {
  final List<String> users;

  const HaUserCondition(this.users);

  @override
  bool test(HaConditionContext context) => context.userId == null || users.contains(context.userId);

  @override
  Iterable<String> get entities => const [];
}

class HaAlwaysCondition extends HaCondition {
  const HaAlwaysCondition();

  @override
  bool test(HaConditionContext context) => true;

  @override
  Iterable<String> get entities => const [];
}

/// What OK on a tile does (its tap_action).
class HaAction {
  /// "toggle", "perform-action", "more-info", "none", ...
  final String action;

  /// "scene.turn_on", for perform-action.
  final String? performAction;
  final Map<String, Object?> target;
  final Map<String, Object?> data;

  const HaAction(this.action, {this.performAction, this.target = const {}, this.data = const {}});

  static HaAction? parse(Object? json) {
    if (json is! Map) return null;
    final action = json["action"];
    if (action is! String) return null;
    // "call-service" and "service" are the older names of perform-action and perform_action
    final perform = json["perform_action"] ?? json["service"];
    return HaAction(
      action == "call-service" ? "perform-action" : action,
      performAction: perform is String ? perform : null,
      target: _map(json["target"]),
      data: _map(json["data"] ?? json["service_data"]),
    );
  }

  static Map<String, Object?> _map(Object? json) =>
      json is Map ? Map<String, Object?>.unmodifiable(json.map((k, v) => MapEntry("$k", v))) : const {};
}

/// A tile's feature: a control (or a gauge) under its name and state.
sealed class HaFeature {
  const HaFeature();

  static HaFeature parse(Object? json) {
    if (json is! Map) return const HaUnsupportedFeature("");
    final type = json["type"];
    switch (type) {
      case "target-temperature":
        return const HaTargetTemperatureFeature();
      case "climate-hvac-modes":
        final modes = json["hvac_modes"];
        return HaHvacModesFeature(modes is List ? [for (final m in modes) "$m"] : null);
      case "media-player-playback":
        return const HaMediaPlaybackFeature();
      case "media-player-volume-slider":
        return const HaVolumeSliderFeature();
      case "light-brightness":
        return const HaLightBrightnessFeature();
      case "bar-gauge":
        return HaBarGaugeFeature(min: HaCondition._num(json["min"]) ?? 0, max: HaCondition._num(json["max"]) ?? 100);
      case "temperature-forecast":
        final hours = HaCondition._num(json["hours_to_show"]);
        return HaTemperatureForecastFeature(
            forecastType: json["forecast_type"] is String ? json["forecast_type"] as String : "hourly",
            hoursToShow: hours?.toInt() ?? 12);
      default:
        return HaUnsupportedFeature(type is String ? type : "");
    }
  }
}

class HaTargetTemperatureFeature extends HaFeature {
  const HaTargetTemperatureFeature();
}

class HaHvacModesFeature extends HaFeature {
  /// The modes to offer; null for all of the entity's.
  final List<String>? modes;

  const HaHvacModesFeature(this.modes);
}

class HaMediaPlaybackFeature extends HaFeature {
  const HaMediaPlaybackFeature();
}

class HaVolumeSliderFeature extends HaFeature {
  const HaVolumeSliderFeature();
}

class HaLightBrightnessFeature extends HaFeature {
  const HaLightBrightnessFeature();
}

class HaBarGaugeFeature extends HaFeature {
  final num min;
  final num max;

  const HaBarGaugeFeature({required this.min, required this.max});
}

class HaTemperatureForecastFeature extends HaFeature {
  final String forecastType;
  final int hoursToShow;

  const HaTemperatureForecastFeature({required this.forecastType, required this.hoursToShow});
}

class HaUnsupportedFeature extends HaFeature {
  final String type;

  const HaUnsupportedFeature(this.type);
}

/// A card on the dashboard, of the kinds the panel draws.
sealed class HaCard {
  final List<HaCondition> visibility;

  /// Its width in a sections view's 12 columns ("full" is 12); null when it doesn't say.
  final int? columns;

  const HaCard({this.visibility = const [], this.columns});

  /// The entities it shows or looks at (for subscribe_entities).
  Iterable<String> get entities => visibility.expand((c) => c.entities);

  /// It takes half the panel's width (two side by side).
  bool get half => false;
}

/// A heading between groups of cards.
class HaHeadingCard extends HaCard {
  final String heading;
  final String? icon;

  const HaHeadingCard(this.heading, {this.icon, super.visibility, super.columns});
}

/// A tile: an entity's name and state, with its features.
class HaTileCard extends HaCard {
  final String entity;
  final String? name;
  final String? icon;

  /// What it shows as its state ("state", or attributes like "media_title"); empty for the state alone.
  final List<String> stateContent;
  final List<HaFeature> features;
  final HaAction? tapAction;

  const HaTileCard(this.entity,
      {this.name,
      this.icon,
      this.stateContent = const [],
      this.features = const [],
      this.tapAction,
      super.visibility,
      super.columns});

  @override
  Iterable<String> get entities => [entity, ...super.entities];

  /// Half width when it says so, and by default when it has no controls under it.
  @override
  bool get half {
    final c = columns;
    if (c != null) return c <= 6;
    return features.every((f) => f is HaUnsupportedFeature);
  }
}

/// Text from Home Assistant: markdown, with Jinja templates Home Assistant renders ([content] as written).
class HaMarkdownCard extends HaCard {
  final String content;
  final String? title;

  const HaMarkdownCard(this.content, {this.title, super.visibility, super.columns});

  /// It has templates for Home Assistant to render.
  bool get templated => content.contains("{{") || content.contains("{%");
}

/// A map: the panel draws nothing for it. A person's tile shows the map when it is focused, so a list of who is where
/// would only repeat that.
class HaMapCard extends HaCard {
  final List<String> mapEntities;
  final String? title;

  const HaMapCard(this.mapEntities, {this.title, super.visibility, super.columns});

  @override
  Iterable<String> get entities => [...mapEntities, ...super.entities];
}

/// A card the panel can't draw (the full dashboard shows it).
class HaUnsupportedCard extends HaCard {
  final String type;

  const HaUnsupportedCard(this.type, {super.visibility, super.columns});
}

/// A group of cards with its own visibility: a section of a sections view (or all of an older view's cards).
class HaSection {
  final List<HaCondition> visibility;
  final List<HaCard> cards;

  const HaSection(this.cards, {this.visibility = const []});

  Iterable<String> get entities => [...visibility.expand((c) => c.entities), ...cards.expand((c) => c.entities)];
}

/// One view of a dashboard, as the panel draws it.
class HaPanelLayout {
  final String? title;
  final List<HaSection> sections;

  const HaPanelLayout(this.sections, {this.title});

  static const empty = HaPanelLayout([]);

  /// Every entity the view shows or looks at.
  Set<String> get entities => sections.expand((s) => s.entities).toSet();

  Iterable<HaCard> get cards => sections.expand((s) => s.cards);

  /// Some card on it can't be drawn here.
  bool get hasUnsupported => cards.any((c) => c is HaUnsupportedCard);
}

/// Reading a dashboard's config (lovelace/config's result) into what the panel draws.
class HaLovelace {
  /// "tv-room/home" → ("tv-room", "home"); "lovelace" → ("lovelace", null). Empty → the default dashboard.
  static (String, String?) splitPath(String path) {
    final clean = path.trim().replaceAll(RegExp(r"^/+|/+$"), "");
    if (clean.isEmpty) return ("lovelace", null);
    final slash = clean.indexOf("/");
    if (slash < 0) return (clean, null);
    final view = clean.substring(slash + 1);
    return (clean.substring(0, slash), view.isEmpty ? null : view);
  }

  /// The view [view] names, by its path, else by its place ("1"); the first one when it names none (or none found).
  static Map? pickView(Object? config, String? view) {
    final views = config is Map ? config["views"] : null;
    if (views is! List || views.isEmpty) return null;
    final maps = views.whereType<Map>().toList();
    if (maps.isEmpty) return null;
    if (view != null) {
      for (final v in maps) {
        if (v["path"] == view) return v;
      }
      final index = int.tryParse(view);
      if (index != null && index >= 0 && index < views.length && views[index] is Map) return views[index] as Map;
    }
    return maps.first;
  }

  /// The view of [config] that [view] names.
  static HaPanelLayout parse(Object? config, String? view) {
    final v = pickView(config, view);
    if (v == null) return HaPanelLayout.empty;
    final title = v["title"] is String ? v["title"] as String : null;
    final sections = <HaSection>[];
    final rawSections = v["sections"];
    if (rawSections is List) {
      for (final s in rawSections) {
        if (s is! Map) continue;
        final cards = <HaCard>[];
        // A section's title is a heading of its own in older configs
        final sectionTitle = s["title"];
        if (sectionTitle is String && sectionTitle.isNotEmpty) cards.add(HaHeadingCard(sectionTitle));
        _addCards(cards, s["cards"], const [], sectionsView: true);
        sections.add(HaSection(cards, visibility: HaCondition.parseList(s["visibility"])));
      }
    }
    final rawCards = v["cards"];
    if (rawCards is List) {
      final cards = <HaCard>[];
      _addCards(cards, rawCards, const [], sectionsView: false);
      sections.add(HaSection(cards));
    }
    return HaPanelLayout(sections, title: title);
  }

  /// [json]'s cards into [out]; stacks and conditional cards are flattened, their conditions passed on to what's in
  /// them ([inherited]).
  static void _addCards(List<HaCard> out, Object? json, List<HaCondition> inherited, {required bool sectionsView}) {
    if (json is! List) return;
    for (final c in json) {
      if (c is! Map) continue;
      final visibility = [...inherited, ...HaCondition.parseList(c["visibility"])];
      final type = c["type"];
      switch (type) {
        case "vertical-stack":
        case "horizontal-stack":
        case "grid":
          final title = c["title"];
          if (title is String && title.isNotEmpty) out.add(HaHeadingCard(title, visibility: visibility));
          _addCards(out, c["cards"], visibility, sectionsView: sectionsView);
        case "conditional":
          _addCards(out, [c["card"]], [...visibility, ...HaCondition.parseList(c["conditions"])],
              sectionsView: sectionsView);
        default:
          final card = _card(c, visibility, sectionsView: sectionsView);
          if (card != null) out.add(card);
      }
    }
  }

  static HaCard? _card(Map c, List<HaCondition> visibility, {required bool sectionsView}) {
    final type = c["type"];
    final columns = sectionsView ? _columns(c["grid_options"]) : 12;
    switch (type) {
      case "heading":
        final heading = c["heading"];
        return HaHeadingCard(heading is String ? heading : "",
            icon: c["icon"] is String ? c["icon"] as String : null, visibility: visibility, columns: columns);
      case "markdown":
        final content = c["content"];
        if (content is! String) return HaUnsupportedCard("markdown", visibility: visibility);
        return HaMarkdownCard(content,
            title: c["title"] is String ? c["title"] as String : null, visibility: visibility, columns: columns);
      case "map":
        final listed = c["entities"];
        final ids = [
          if (listed is List)
            for (final e in listed)
              if (e is String) e else if (e is Map && e["entity"] is String) e["entity"] as String
        ];
        if (ids.isEmpty) return HaUnsupportedCard("map", visibility: visibility);
        return HaMapCard(ids,
            title: c["title"] is String ? c["title"] as String : null, visibility: visibility, columns: columns);
      case "tile":
        final entity = c["entity"];
        if (entity is! String || entity.isEmpty) return HaUnsupportedCard("tile", visibility: visibility);
        final features = c["features"];
        final stateContent = c["state_content"];
        return HaTileCard(
          entity,
          name: c["name"] is String ? c["name"] as String : null,
          icon: c["icon"] is String ? c["icon"] as String : null,
          stateContent: stateContent is List
              ? [for (final s in stateContent) "$s"]
              : stateContent is String
                  ? [stateContent]
                  : const [],
          features: features is List ? [for (final f in features) HaFeature.parse(f)] : const [],
          tapAction: HaAction.parse(c["tap_action"]),
          visibility: visibility,
          columns: columns,
        );
      default:
        return HaUnsupportedCard(type is String ? type : "", visibility: visibility, columns: columns);
    }
  }

  /// grid_options.columns: a number of the section's 12 columns, or "full".
  static int? _columns(Object? gridOptions) {
    if (gridOptions is! Map) return null;
    final columns = gridOptions["columns"];
    if (columns == "full") return 12;
    if (columns is num) return columns.toInt();
    return null;
  }
}
