import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/data_usage.dart';
import 'package:flauncher/providers/home_data_usage.dart';
import 'package:flauncher/providers/network_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/focusable_tap.dart';
import 'package:flauncher/widgets/title_pill.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The top bar's data usage: what this TV sent and received today (or this week or month, by Settings), or "No
/// internet" once the TV has been offline a while. Focused, the data app by app shows over the home
/// ([DataUsageRow]); OK goes on to the next period there. Without usage access, OK asks for it.
class DailyDataUsageWidget extends StatefulWidget {
  final FocusNode? focusNode;

  const DailyDataUsageWidget({super.key, this.focusNode});

  @override
  State<DailyDataUsageWidget> createState() => _DailyDataUsageWidgetState();
}

class _DailyDataUsageWidgetState extends State<DailyDataUsageWidget> {
  Future<int>? _usage;
  (String, int)? _usageFor;

  /// Asks the platform again only for a new period, or after the service's own poll found new numbers;
  /// the service also notifies for every network change.
  Future<int> _usageFuture(NetworkService networkService, String period) {
    final usageFor = (period, networkService.dailyDataUsage);
    if (_usage == null || usageFor != _usageFor) {
      _usageFor = usageFor;
      _usage = networkService.getDataUsageForPeriod(period);
    }
    return _usage!;
  }

  /// Marks where the amount goes in the translated label, so the amount alone can be bold.
  static const String _usageMarker = "\u0000";

  static const TextStyle _textStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w400,
    color: Colors.white,
    shadows: [Shadow(color: Colors.black54, offset: Offset(0, 2), blurRadius: 4)],
  );

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Consumer2<NetworkService, SettingsService>(
      builder: (context, networkService, settingsService, _) {
        final allowed = networkService.hasUsageStatsPermission;
        final period = settingsService.dataUsagePeriod;
        final homeDataUsage = context.read<HomeDataUsage?>();
        return FocusableTap(
          key: const Key("statusbar_data_usage"),
          focusNode: widget.focusNode,
          onFocusChange: (focused) => homeDataUsage?.setShowing(focused && allowed, period: period),
          onPressed: () {
            if (!allowed) {
              networkService.requestPermission();
            } else {
              homeDataUsage?.nextPeriod();
            }
          },
          splashShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          builder: (context, focused) => AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              // Darker on a light wallpaper, like the row titles' pills
              color: Colors.black.withOpacity(TitlePill.opacityOf(context)),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: focused ? Theme.of(context).colorScheme.primary : Colors.white.withOpacity(0.12),
                width: 1,
              ),
              boxShadow: focused ? const [BoxShadow(color: Colors.black54, blurRadius: 8, spreadRadius: 1)] : null,
            ),
            child: _content(context, localizations, networkService, period),
          ),
        );
      },
    );
  }

  Widget _content(BuildContext context, AppLocalizations localizations, NetworkService networkService, String period) {
    if (networkService.offline) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, key: Key("data_usage_offline"), size: 20, color: Color(0xFFFFB74D)),
          const SizedBox(width: 8),
          Text(localizations.dataUsageNoInternet, style: _textStyle.copyWith(fontWeight: FontWeight.bold)),
        ],
      );
    }
    if (!networkService.hasUsageStatsPermission) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.data_usage, size: 20, color: Colors.white),
          const SizedBox(width: 8),
          Text(localizations.dataWidgetGrantPermission, style: _textStyle),
        ],
      );
    }

    final String Function(String usage) label = switch (period) {
      dataUsageWeekly => localizations.dataWidgetWeekly,
      dataUsageMonthly => localizations.dataWidgetMonthly,
      _ => localizations.dataWidgetDaily,
    };
    // The text around the amount, wherever the language puts it ("Daily: " before it in English)
    final labelParts = label(_usageMarker).split(_usageMarker);
    final before = labelParts.first;
    final after = labelParts.skip(1).join();

    return FutureBuilder<int>(
      future: _usageFuture(networkService, period),
      builder: (context, snapshot) {
        final usage = snapshot.data ?? networkService.dailyDataUsage;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RichText(
              text: TextSpan(
                style: _textStyle,
                children: [
                  if (before.isNotEmpty) TextSpan(text: before),
                  TextSpan(
                    text: formatDataBytes(usage, localizations.localeName),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (after.isNotEmpty) TextSpan(text: after),
                ],
              ),
            ),
            // A VPN app is on: its key, as Android's own status bar shows it
            if (networkService.vpnActive) ...[
              const SizedBox(width: 8),
              const Icon(Icons.vpn_key, key: Key("data_usage_vpn"), size: 18, color: Colors.white70),
            ],
          ],
        );
      },
    );
  }
}
