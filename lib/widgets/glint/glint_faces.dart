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

import 'dart:async';
import 'dart:typed_data';

import 'package:flauncher/actions.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/models/app.dart';
import 'package:flauncher/models/category.dart';
import 'package:flauncher/models/watch_next_program.dart';
import 'package:flauncher/models/weather_data.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/calendars.dart';
import 'package:flauncher/providers/notifications_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/widgets/application_info_panel.dart';
import 'package:flauncher/widgets/glint/glint_apps_page.dart';
import 'package:flauncher/widgets/glint/glint_flip.dart';
import 'package:flauncher/widgets/glint/glint_house_feed.dart';
import 'package:flauncher/widgets/glint/glint_look.dart';
import 'package:flauncher/widgets/glint/glint_tile.dart';
import 'package:flauncher/widgets/settings/notifications_panel.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

/// A live tile's faces: joins the home's ticker with [faces] faces at [pace], is held still while selected, and
/// flips to the face the ticker picks. [builder] draws face [index].
class _LiveTile extends StatefulWidget {
  final Object id;
  final int faces;
  final Duration pace;
  final Widget Function(BuildContext context, int index) builder;
  final void Function(int index)? onPressed;
  final Color? Function(int index)? colourEdge;
  final ImageProvider? Function(int index)? picture;

  const _LiveTile({
    required this.id,
    required this.faces,
    required this.builder,
    this.pace = const Duration(seconds: 20),
    this.onPressed,
    this.colourEdge,
    this.picture,
  });

  @override
  State<_LiveTile> createState() => _LiveTileState();
}

class _LiveTileState extends State<_LiveTile> {
  GlintTicker? _ticker;
  ValueNotifier<int>? _index;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _join();
  }

  @override
  void didUpdateWidget(_LiveTile old) {
    super.didUpdateWidget(old);
    if (old.faces != widget.faces || old.pace != widget.pace) _join();
  }

  void _join() {
    final ticker = GlintTickerScope.of(context);
    if (ticker != _ticker) _ticker?.leave(widget.id);
    _ticker = ticker;
    _index = ticker?.join(widget.id, faces: widget.faces, pace: widget.pace);
  }

  @override
  void dispose() {
    _ticker?.leave(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = _index ?? ValueNotifier(0);
    return ValueListenableBuilder<int>(
      valueListenable: index,
      builder: (context, i, _) {
        final shown = i < widget.faces ? i : 0;
        return GlintTile(
          onPressed: widget.onPressed == null ? null : () => widget.onPressed!(shown),
          onFocusChange: (focused) => _ticker?.hold(widget.id, focused),
          colourEdge: widget.colourEdge?.call(shown),
          picture: widget.picture?.call(shown),
          child: GlintFlip(index: shown, builder: widget.builder),
        );
      },
    );
  }
}

/// Small tracked caps over a face.
Widget _label(String text) =>
    Text(text.toUpperCase(), style: GlintLook.label, maxLines: 1, overflow: TextOverflow.ellipsis);

/// The time, big and light, with the date under it. Select opens nothing: it's the TV's clock.
class ClockFace extends StatefulWidget {
  const ClockFace({super.key});

  @override
  State<ClockFace> createState() => _ClockFaceState();
}

class _ClockFaceState extends State<ClockFace> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    final now = DateTime.now();
    _timer = Timer(Duration(seconds: 60 - now.second, milliseconds: -now.millisecond + 50), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _format(String pattern, String fallback) {
    try {
      return DateFormat(pattern).format(_now);
    } catch (_) {
      return DateFormat(fallback).format(_now);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    return GlintTile(
      child: LayoutBuilder(
        builder: (context, box) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomLeft,
              child: Text(_format(settings.timeFormat, "h:mm"), style: GlintLook.display(box.maxHeight * 0.5)),
            ),
            const SizedBox(height: 6),
            Text(
              _format("EEEE, MMMM d", "EEE, MMM d"),
              style: GlintLook.secondaryText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// What you were watching: the poster full bleed, the title and how far you got. With more than one program, the
/// tile turns through them slowly; select opens the one it shows.
class ContinueWatchingFace extends StatelessWidget {
  final List<WatchNextProgram> programs;
  const ContinueWatchingFace({super.key, required this.programs});

  @override
  Widget build(BuildContext context) {
    final apps = context.read<AppsService>();
    final watchNext = context.read<WatchNextService>();
    ImageProvider? poster(int i) {
      final Uint8List? bytes = programs[i].posterBytes;
      return bytes == null || bytes.isEmpty ? null : MemoryImage(bytes);
    }

    return _LiveTile(
      id: "continue",
      faces: programs.length,
      pace: const Duration(seconds: 24),
      onPressed: (i) => watchNext.launch(programs[i]),
      picture: poster,
      builder: (context, i) {
        final p = programs[i];
        final appName = apps.getApp(p.packageName)?.name;
        final progress = p.duration > 0 ? (p.playbackPosition / p.duration).clamp(0.0, 1.0) : 0.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _label(appName == null ? "Continue watching" : "Continue watching · $appName"),
            const SizedBox(height: 4),
            Text(
              p.title,
              style: GlintLook.primary.copyWith(fontSize: 24, fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (p.description.isNotEmpty)
              Text(p.description, style: GlintLook.secondaryText, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (progress > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  color: GlintLook.ember,
                  backgroundColor: Colors.white24,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The temperature, big and light, then the sky and today's high and low; it turns to tomorrow and back.
class WeatherFace extends StatelessWidget {
  final WeatherData data;
  const WeatherFace({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final tomorrow = data.forecasts.length > 1 ? data.forecasts[1] : null;
    return _LiveTile(
      id: "weather",
      faces: tomorrow == null ? 1 : 2,
      pace: const Duration(seconds: 40),
      builder: (context, i) {
        if (i == 1 && tomorrow != null) {
          return _weatherFace(
            label: "Tomorrow",
            icon: WeatherData.iconFor(tomorrow.conditionCode),
            big: tomorrow.maxTemp == null ? "–" : "${tomorrow.maxTemp}°",
            line: tomorrow.precipProbability != null && tomorrow.precipProbability! >= 30
                ? "${tomorrow.precipProbability}% chance of rain"
                : null,
            small: tomorrow.minTemp == null ? null : "Low ${tomorrow.minTemp}°",
          );
        }
        final hiLo = [
          if (data.todayMaxTemp != null) "H ${data.todayMaxTemp}°",
          if (data.todayMinTemp != null) "L ${data.todayMinTemp}°",
        ].join(" · ");
        return _weatherFace(
          label: data.location ?? "Weather",
          icon: WeatherData.iconFor(data.currentConditionCode),
          big: "${data.currentTemp}°",
          line: data.currentCondition,
          small: hiLo.isEmpty ? null : hiLo,
        );
      },
    );
  }

  Widget _weatherFace({
    required String label,
    required IconData icon,
    required String big,
    String? line,
    String? small,
  }) => LayoutBuilder(
    builder: (context, box) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const Spacer(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFFFFE0B8), size: box.maxHeight * 0.26, shadows: GlintLook.textShadow),
            const SizedBox(width: 10),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(big, style: GlintLook.display(box.maxHeight * 0.36)),
              ),
            ),
          ],
        ),
        const Spacer(),
        if (line != null && line.isNotEmpty)
          Text(line, style: GlintLook.primary, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (small != null) Text(small, style: GlintLook.secondaryText, maxLines: 1),
      ],
    ),
  );
}

/// Today's next events, one at a time: when, then what.
class CalendarFace extends StatelessWidget {
  final List<CalendarEvent> events;
  const CalendarFace({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    String time(DateTime t) {
      try {
        return DateFormat(settings.timeFormat).format(t);
      } catch (_) {
        return DateFormat("h:mm").format(t);
      }
    }

    return _LiveTile(
      id: "calendar",
      faces: events.length,
      pace: const Duration(seconds: 30),
      colourEdge: (i) => events[i].color == null ? null : Color(events[i].color!).withValues(alpha: 1),
      builder: (context, i) {
        final e = events[i];
        final now = DateTime.now();
        final when = e.allDay ? "Today" : (e.isOn(now) ? "Now · until ${time(e.end)}" : "Today · ${time(e.start)}");
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _label(when),
            const SizedBox(height: 4),
            Text(
              e.summary,
              style: GlintLook.primary.copyWith(fontSize: 20),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
      },
    );
  }
}

/// Who's watching: the profile's photo full bleed and its name. Select opens Google TV's profile chooser.
class ProfileFace extends StatelessWidget {
  final String name;
  final Uint8List? avatar;
  const ProfileFace({super.key, required this.name, this.avatar});

  @override
  Widget build(BuildContext context) => GlintTile(
    picture: avatar == null || avatar!.isEmpty ? null : MemoryImage(avatar!),
    onPressed: () => context.read<FLauncherChannel>().openProfileChooser(),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (avatar == null || avatar!.isEmpty) ...[
          const Spacer(),
          Text(name.characters.first.toUpperCase(), style: GlintLook.display(40)),
        ],
        const Spacer(),
        Text(name, style: GlintLook.primary.copyWith(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}

/// An app: its name in big type, its colour down the left edge. No icon on the face (Glint's glass-first rule).
/// Select opens it; held, its menu.
class AppFace extends StatefulWidget {
  final App app;
  final Category? category;
  final bool wide;
  const AppFace({super.key, required this.app, required this.category, this.wide = false});

  @override
  State<AppFace> createState() => _AppFaceState();
}

class _AppFaceState extends State<AppFace> {
  Color? _colour;

  @override
  void initState() {
    super.initState();
    _loadColour();
  }

  @override
  void didUpdateWidget(AppFace old) {
    super.didUpdateWidget(old);
    if (old.app.packageName != widget.app.packageName) _loadColour();
  }

  Future<void> _loadColour() async {
    final colour = await context.read<WallpaperService>().appColor(widget.app.packageName);
    if (mounted) setState(() => _colour = colour == null ? null : _brighten(colour));
  }

  /// The extracted colour is darkened for white text on it; as a thin strip it can be brighter.
  static Color _brighten(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + 0.25).clamp(0.35, 0.7))
        .withSaturation((hsl.saturation + 0.1).clamp(0, 1))
        .toColor();
  }

  @override
  Widget build(BuildContext context) => GlintTile(
    colourEdge: _colour,
    onPressed: () => context.read<AppsService>().launchApp(widget.app),
    onLongPress: () => showDialog(
      context: context,
      builder: (_) => ApplicationInfoPanel(category: widget.category, application: widget.app),
    ),
    padding: EdgeInsets.fromLTRB(widget.wide ? 16 : 12, 10, 12, 10),
    child: Align(
      alignment: Alignment.bottomLeft,
      child: Text(
        widget.app.name,
        style: GlintLook.primary.copyWith(fontSize: widget.wide ? 19 : 14),
        maxLines: widget.wide ? 2 : 3,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}

/// The way to every app: Glint's A–Z list.
class AllAppsFace extends StatelessWidget {
  const AllAppsFace({super.key});

  @override
  Widget build(BuildContext context) => GlintTile(
    onPressed: () => GlintAppsPage.open(context),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.apps_rounded, color: GlintLook.content, size: 26, shadows: GlintLook.textShadow),
        Spacer(),
        Text(
          "All apps",
          style: TextStyle(
            color: GlintLook.content,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            shadows: GlintLook.textShadow,
          ),
        ),
      ],
    ),
  );
}

/// Hearth's Settings.
class SettingsFace extends StatelessWidget {
  const SettingsFace({super.key});

  @override
  Widget build(BuildContext context) => GlintTile(
    onPressed: () =>
        showDialog(context: context, barrierColor: Colors.transparent, builder: (_) => const SettingsPanel()),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.settings_outlined, color: GlintLook.content, size: 26, shadows: GlintLook.textShadow),
        Spacer(),
        Text(
          "Settings",
          style: TextStyle(
            color: GlintLook.content,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            shadows: GlintLook.textShadow,
          ),
        ),
      ],
    ),
  );
}

/// The newest notifications, one at a time: the app, then what it says. Select opens the notifications panel.
class NotificationsFace extends StatelessWidget {
  final List<NotificationItem> items;
  const NotificationsFace({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final shown = items.take(3).toList();
    void open() =>
        showDialog(context: context, barrierColor: Colors.transparent, builder: (_) => const NotificationsPanel());
    if (shown.isEmpty) {
      return GlintTile(
        onPressed: open,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _label("Notifications"),
            const SizedBox(height: 4),
            Text("All caught up", style: GlintLook.primary.copyWith(fontSize: 18)),
          ],
        ),
      );
    }
    return _LiveTile(
      id: "notifications",
      faces: shown.length,
      pace: const Duration(seconds: 30),
      onPressed: (_) => open(),
      builder: (context, i) {
        final n = shown[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _label(n.appLabel)),
                if (items.length > 1) Text("${items.length}", style: GlintLook.label.copyWith(color: GlintLook.ember)),
              ],
            ),
            const Spacer(),
            Text(
              n.title.isNotEmpty ? n.title : n.text,
              style: GlintLook.primary.copyWith(fontSize: 18),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (n.title.isNotEmpty && n.text.isNotEmpty)
              Text(n.text, style: GlintLook.secondaryText, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        );
      },
    );
  }
}

/// A small tile with one glyph and its name: search, the Home Assistant dashboard.
class GlyphFace extends StatelessWidget {
  final IconData icon;
  final String name;
  final VoidCallback onPressed;
  const GlyphFace({super.key, required this.icon, required this.name, required this.onPressed});

  @override
  Widget build(BuildContext context) => GlintTile(
    onPressed: onPressed,
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: GlintLook.content, size: 26, shadows: GlintLook.textShadow),
        const Spacer(),
        Text(name, style: GlintLook.primary.copyWith(fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}

/// Search, as the top bar's magnifier did.
class SearchFace extends StatelessWidget {
  const SearchFace({super.key});

  @override
  Widget build(BuildContext context) => GlyphFace(
    icon: Icons.search,
    name: "Search",
    onPressed: () => Actions.maybeInvoke(context, const StartSearchIntent()),
  );
}

/// The Home Assistant dashboard panel.
class HomeAssistantFace extends StatelessWidget {
  const HomeAssistantFace({super.key});

  @override
  Widget build(BuildContext context) => GlyphFace(
    icon: Icons.home_outlined,
    name: "Home",
    onPressed: () => Actions.maybeInvoke(context, const OpenHaPanelIntent()),
  );
}

/// Around the house, one thing at a time: another TV playing something ("Den TV · Sam · Bluey"), someone in a car.
class HouseFace extends StatelessWidget {
  final List<GlintHouseItem> items;
  const HouseFace({super.key, required this.items});

  @override
  Widget build(BuildContext context) => _LiveTile(
    id: "house",
    faces: items.length,
    pace: const Duration(seconds: 25),
    builder: (context, i) {
      final item = items[i];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _label(item.label),
          const SizedBox(height: 4),
          Text(
            item.line,
            style: GlintLook.primary.copyWith(fontSize: 19),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (item.detail != null)
            Text(item.detail!, style: GlintLook.secondaryText, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      );
    },
  );
}
