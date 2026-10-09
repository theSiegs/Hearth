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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/watch_next_program.dart';
import '../providers/apps_service.dart';
import '../providers/watch_next_service.dart';
import 'continue_watching_row.dart';
import 'focusable_tap.dart';

/// Continue Watching's "See all": every program in progress as a grid of the row's own cards, with a pill per app
/// (as search's grid and HearthTube have) to narrow it down.
class ContinueWatchingGridPage extends StatefulWidget {
  final List<WatchNextProgram> programs;

  const ContinueWatchingGridPage({super.key, required this.programs});

  static Future<void> open(BuildContext context, List<WatchNextProgram> programs) =>
      Navigator.of(context).push(PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (_, __, ___) => ContinueWatchingGridPage(programs: programs),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
      ));

  @override
  State<ContinueWatchingGridPage> createState() => _ContinueWatchingGridPageState();
}

class _ContinueWatchingGridPageState extends State<ContinueWatchingGridPage> {
  /// The app whose programs show; null for all.
  String? _app;

  @override
  Widget build(BuildContext context) {
    final appsService = context.watch<AppsService>();
    final watchNextService = context.read<WatchNextService>();
    final textTheme = Theme.of(context).textTheme;
    final packages = <String>[];
    for (final p in widget.programs) {
      if (!packages.contains(p.packageName)) packages.add(p.packageName);
    }
    String appName(String pkg) =>
        appsService.applications.where((a) => a.packageName == pkg).firstOrNull?.name ?? pkg;
    final shown = _app == null ? widget.programs : widget.programs.where((p) => p.packageName == _app).toList();
    final localizations = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: const Color(0xFF121612),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(48, 28, 48, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(localizations.continueWatching, style: textTheme.headlineSmall),
            const SizedBox(height: 18),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(children: [
                _AppPill(
                    label: localizations.cwGridAll,
                    count: widget.programs.length,
                    selected: _app == null,
                    onSelected: () => setState(() => _app = null)),
                for (final pkg in packages) ...[
                  const SizedBox(width: 12),
                  _AppPill(
                    label: appName(pkg),
                    count: widget.programs.where((p) => p.packageName == pkg).length,
                    selected: _app == pkg,
                    onSelected: () => setState(() => _app = pkg),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: SingleChildScrollView(
                clipBehavior: Clip.none,
                child: Wrap(
                  key: ValueKey(_app),
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final (i, program) in shown.indexed)
                      WatchNextCard(
                        key: ValueKey(program.id),
                        program: program,
                        appsService: appsService,
                        watchNextService: watchNextService,
                        upGoesToTopBar: false,
                        autofocus: i == 0,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A HearthTube-style pill: white when selected; focusing it selects it.
class _AppPill extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onSelected;

  const _AppPill({required this.label, required this.count, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final fg = selected ? Colors.black : Colors.white;
    return FocusableTap(
      onPressed: onSelected,
      onFocusChange: (focused) {
        if (focused) onSelected();
      },
      builder: (context, focused) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: focused ? accent : Colors.white.withOpacity(0.15), width: focused ? 3 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(color: fg, fontSize: 17, fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          Text("$count", style: TextStyle(color: fg.withOpacity(0.6), fontSize: 14)),
        ]),
      ),
    );
  }
}
