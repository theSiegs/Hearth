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
import 'package:flauncher/models/data_usage.dart';
import 'package:flauncher/providers/home_data_usage.dart';
import 'package:flauncher/providers/network_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/settings/app_icon.dart';
import 'package:flauncher/widgets/title_pill.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const List<Shadow> _shadow = [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 8)];

/// The connection, for the line under the heading: "Wi-Fi · VPN on", "No internet", and on Ethernet that Android
/// doesn't count it.
String dataUsageConnectionText(AppLocalizations l, NetworkService network) {
  final link = switch (network.networkType) {
    NetworkType.wifi => l.dataUsageWifi,
    NetworkType.wired => l.dataUsageEthernet,
    NetworkType.cellular => l.dataUsageMobile,
    NetworkType.none => l.dataUsageNotConnected,
  };
  return [
    link,
    if (network.offline && network.networkType != NetworkType.none) l.dataUsageNoInternet,
    if (network.vpnActive) l.dataUsageVpnOn,
    if (network.networkType == NetworkType.wired) l.dataUsageEthernetNotCounted,
  ].join(" · ");
}

/// The TV's data app by app, over the home in Continue Watching's spot while the top bar's data usage has focus: the
/// largest apps' shares of today's (this week's, this month's) data, and everything else on a last tile. Nothing in
/// it takes focus: the data usage keeps it, and OK there goes on to the next period.
class DataUsageRow extends StatefulWidget {
  /// How many apps get a tile of their own.
  static const int maxApps = 6;

  const DataUsageRow({super.key});

  @override
  State<DataUsageRow> createState() => _DataUsageRowState();
}

class _DataUsageRowState extends State<DataUsageRow> {
  Future<DataUsageBreakdown?>? _breakdown;
  String? _period;
  bool _wasShowing = false;

  /// Asked again each time the row comes up, and for each new period; not on every rebuild.
  Future<DataUsageBreakdown?>? _breakdownFor(NetworkService network, bool showing, String period) {
    if (showing && (!_wasShowing || period != _period || _breakdown == null)) {
      _period = period;
      _breakdown = network.getDataUsageByApp(period);
    }
    _wasShowing = showing;
    return _breakdown;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final home = context.watch<HomeDataUsage?>();
    final network = context.watch<NetworkService?>();
    if (home == null || network == null) return const SizedBox.shrink();
    final period = home.period;
    final future = _breakdownFor(network, home.showing, period);
    final text = Theme.of(context).textTheme;
    final periodName = switch (period) {
      dataUsageWeekly => l.dataUsageThisWeek,
      dataUsageMonthly => l.dataUsageThisMonth,
      _ => l.dataUsageToday,
    };
    final next = switch (period) {
      dataUsageDaily => l.dataUsageShowWeek,
      dataUsageWeekly => l.dataUsageShowMonth,
      _ => l.dataUsageShowToday,
    };
    return FutureBuilder<DataUsageBreakdown?>(
      future: future,
      builder: (context, snapshot) {
        // The same period's answer only: an older one would show last period's numbers under this one's name
        final breakdown = snapshot.connectionState == ConnectionState.done ? snapshot.data : null;
        final connection = dataUsageConnectionText(l, network);
        return Padding(
          // Full width, so it starts at the left like Continue Watching however little it shows
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TitlePill(
                  child: Text(
                    l.dataUsage.toUpperCase(),
                    style: text.labelLarge!
                        .copyWith(color: Colors.white, letterSpacing: 1.0, shadows: TitlePill.textShadow),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (breakdown != null) l.dataUsageOnThisTv(formatDataBytes(breakdown.whole, l.localeName)),
                    periodName,
                  ].join(" · "),
                  style: text.headlineSmall!.copyWith(fontWeight: FontWeight.w700, shadows: _shadow),
                ),
                Text(
                  [if (connection.isNotEmpty) connection, next].join(" · "),
                  style: text.bodyLarge!.copyWith(color: Colors.white70, shadows: _shadow),
                ),
                const SizedBox(height: 12),
                if (breakdown != null) _tiles(context, l, breakdown),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tiles(BuildContext context, AppLocalizations l, DataUsageBreakdown breakdown) {
    final top = breakdown.top(DataUsageRow.maxApps);
    final others = breakdown.othersBytes(DataUsageRow.maxApps);
    if (top.isEmpty && others <= 0) {
      return SizedBox(
        height: _UsageTile.height,
        child: Text(l.dataUsageNone,
            style: Theme.of(context).textTheme.bodyLarge!.copyWith(color: Colors.white70, shadows: _shadow)),
      );
    }
    final whole = breakdown.whole;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final app in top)
            _UsageTile(
              key: Key("data_usage_${app.packageName ?? app.kind.name}"),
              icon: app.kind == DataUsageKind.app
                  ? AppIcon(app.packageName!, size: 40, borderRadius: 8, placeholder: const _GenericIcon(Icons.apps))
                  : const _GenericIcon(Icons.android),
              name: app.kind == DataUsageKind.app ? (app.label ?? app.packageName!) : l.dataUsageAndroid,
              bytes: app.bytes,
              share: whole > 0 ? app.bytes / whole : 0,
            ),
          if (others > 0)
            _UsageTile(
              key: const Key("data_usage_others"),
              icon: const _GenericIcon(Icons.more_horiz),
              name: l.dataUsageEverythingElse,
              bytes: others,
              share: whole > 0 ? others / whole : 0,
            ),
        ],
      ),
    );
  }
}

class _GenericIcon extends StatelessWidget {
  final IconData icon;

  const _GenericIcon(this.icon);

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 40,
        height: 40,
        child: Icon(icon, size: 32, color: Colors.white70),
      );
}

/// One app's data: its icon and name, the amount, and its share of the period's data as a bar.
class _UsageTile extends StatelessWidget {
  /// About a tile's height, kept by "No data used yet" so the row doesn't jump.
  static const double height = 140;

  final Widget icon;
  final String name;
  final int bytes;
  final double share;

  const _UsageTile({super.key, required this.icon, required this.name, required this.bytes, required this.share});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final locale = AppLocalizations.of(context)!.localeName;
    return Container(
      width: 148,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          icon,
          const SizedBox(height: 8),
          Text(name,
              style: text.bodyMedium!.copyWith(color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(formatDataBytes(bytes, locale), style: text.titleLarge!.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: share.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}
