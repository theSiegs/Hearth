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

import 'dart:typed_data';

import 'package:flauncher/models/app.dart';
import 'package:flauncher/models/category.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/widgets/application_info_panel.dart';
import 'package:flauncher/widgets/frosted_glass.dart';
import 'package:flauncher/widgets/glint/glint_look.dart';
import 'package:flauncher/widgets/glint/glint_tile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Every app the profile can open, A to Z, in Windows Phone's style: a big light lower-case title, the letters in the
/// accent, the names in Selawik. Over the home's picture, frosted. Select opens an app; held, its menu.
class GlintAppsPage extends StatelessWidget {
  const GlintAppsPage({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => const GlintAppsPage(),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ),
  );

  /// The heading an app goes under: its first letter, "#" for a digit or anything else.
  static String letterOf(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return "#";
    final first = trimmed.characters.first.toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(first) ? first : "#";
  }

  @override
  Widget build(BuildContext context) {
    final apps = context.watch<AppsService>();
    // The apps on this profile's home, in any section: what it may open (a kids profile sees only its own)
    final byPackage = <String, App>{
      for (final category in apps.launcherSections.whereType<Category>())
        for (final app in category.applications) app.packageName: app,
    };
    final List<App> all = byPackage.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final rows = <Widget>[];
    String? letter;
    bool first = true;
    for (final app in all) {
      final l = letterOf(app.name);
      if (l != letter) {
        letter = l;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
            child: Text(
              l.toLowerCase(),
              style: const TextStyle(
                fontFamily: GlintLook.wpFont,
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: GlintLook.ember,
              ),
            ),
          ),
        );
      }
      rows.add(_AppRow(app: app, autofocus: first));
      first = false;
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const FrostedGlass(sigma: 24, child: ColoredBox(color: Color(0x99000000))),
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 28, 56, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("apps", style: GlintLook.wpTitle),
                const SizedBox(height: 4),
                Expanded(
                  child: FocusTraversalGroup(
                    child: ListView(padding: const EdgeInsets.only(bottom: 48), children: rows),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppRow extends StatefulWidget {
  final App app;
  final bool autofocus;
  const _AppRow({required this.app, this.autofocus = false});

  @override
  State<_AppRow> createState() => _AppRowState();
}

class _AppRowState extends State<_AppRow> {
  bool _focused = false;
  late Future<Uint8List> _icon = context.read<AppsService>().getAppIcon(widget.app.packageName);

  @override
  void didUpdateWidget(_AppRow old) {
    super.didUpdateWidget(old);
    if (old.app.packageName != widget.app.packageName) {
      _icon = context.read<AppsService>().getAppIcon(widget.app.packageName);
    }
  }

  void _open() {
    Navigator.of(context).pop();
    context.read<AppsService>().launchApp(widget.app);
  }

  void _menu() => showDialog(
    context: context,
    builder: (_) => ApplicationInfoPanel(category: null, application: widget.app),
  );

  @override
  Widget build(BuildContext context) => GlintPress(
    autofocus: widget.autofocus,
    onPressed: _open,
    onLongPress: _menu,
    onFocusChange: (f) {
      setState(() => _focused = f);
      if (f) Scrollable.ensureVisible(context, alignment: 0.4, duration: const Duration(milliseconds: 160));
    },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      margin: const EdgeInsets.only(right: 400),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: _focused ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
        border: Border.all(color: _focused ? Colors.white : Colors.transparent, width: 2),
      ),
      child: Row(
        children: [
          _square(),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              widget.app.name,
              style: const TextStyle(
                fontFamily: GlintLook.wpFont,
                fontSize: 22,
                height: 26 / 22,
                fontWeight: FontWeight.w300,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );

  /// Glint's app list square: the accent, with the app's own full-colour icon on a plate inside it.
  Widget _square() => Container(
    width: 44,
    height: 44,
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(color: GlintLook.ember, borderRadius: BorderRadius.circular(2)),
    child: DecoratedBox(
      decoration: BoxDecoration(color: const Color(0xF2FFFFFF), borderRadius: BorderRadius.circular(4)),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: FutureBuilder<Uint8List>(
          future: _icon,
          builder: (context, snapshot) => snapshot.hasData && snapshot.data!.isNotEmpty
              ? Image.memory(snapshot.data!, fit: BoxFit.contain, gaplessPlayback: true)
              : const SizedBox.expand(),
        ),
      ),
    ),
  );
}
