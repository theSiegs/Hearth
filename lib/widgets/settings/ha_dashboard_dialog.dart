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
import 'package:flutter/material.dart';

import '../../providers/ha_dashboards.dart';

/// Picks this profile's dashboard for the panel from Home Assistant's own list, then one of its views. Pops with the
/// path ("hearth-tv/home"), "" for the TV's dashboard, or null when cancelled.
class HaDashboardDialog extends StatefulWidget {
  /// Home Assistant to ask; null when it isn't set up (only the TV's dashboard can be picked then).
  final HaDashboards? dashboards;

  const HaDashboardDialog({super.key, required this.dashboards});

  @override
  State<HaDashboardDialog> createState() => _HaDashboardDialogState();
}

class _HaDashboardDialogState extends State<HaDashboardDialog> {
  List<HaDashboardChoice>? _choices;
  HaDashboardChoice? _dashboard;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadDashboards();
  }

  Future<void> _loadDashboards() async {
    final source = widget.dashboards;
    List<HaDashboardChoice>? choices;
    try {
      choices = source == null ? null : await source.dashboards();
    } catch (_) {
      choices = null;
    }
    if (!mounted) return;
    setState(() {
      _choices = choices;
      _failed = choices == null;
      _loading = false;
    });
  }

  Future<void> _pickDashboard(HaDashboardChoice dashboard) async {
    setState(() {
      _dashboard = dashboard;
      _loading = true;
    });
    List<HaDashboardChoice> views;
    try {
      views = await widget.dashboards!.views(dashboard.path);
    } catch (_) {
      views = const [];
    }
    if (!mounted) return;
    // One view or none: nothing to choose
    if (views.length < 2) {
      Navigator.of(context).pop(dashboard.path);
      return;
    }
    setState(() {
      _choices = views;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final dashboard = _dashboard;
    final choices = _choices;
    return AlertDialog(
      title: Text(dashboard == null ? l.haPanelChooseDashboard : l.haPanelChooseView(dashboard.title)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_failed) Text(l.haPanelDashboardsError, style: const TextStyle(color: Colors.redAccent)),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (dashboard == null)
                    ListTile(
                      autofocus: true,
                      dense: true,
                      leading: const Icon(Icons.tv),
                      title: Text(l.haPanelProfileDashboardTv),
                      onTap: () => Navigator.of(context).pop(""),
                    )
                  else
                    ListTile(
                      autofocus: true,
                      dense: true,
                      leading: const Icon(Icons.dashboard_outlined),
                      title: Text(l.haPanelFirstView),
                      onTap: () => Navigator.of(context).pop(dashboard.path),
                    ),
                  if (!_loading && choices != null)
                    for (final choice in choices)
                      ListTile(
                        dense: true,
                        leading: Icon(dashboard == null ? Icons.dashboard_outlined : Icons.view_quilt_outlined),
                        title: Text(choice.title),
                        subtitle: Text(choice.path),
                        onTap: () => dashboard == null
                            ? _pickDashboard(choice)
                            : Navigator.of(context).pop(choice.path),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.cancel)),
      ],
    );
  }
}
