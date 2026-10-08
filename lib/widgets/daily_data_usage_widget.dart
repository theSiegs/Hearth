import 'package:flauncher/providers/network_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DailyDataUsageWidget extends StatefulWidget {
  const DailyDataUsageWidget({super.key});

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

  @override
  Widget build(BuildContext context) {
    return Consumer2<NetworkService, SettingsService>(
      builder: (context, networkService, settingsService, _) {
        if (!networkService.hasUsageStatsPermission) {
          return TextButton.icon(
             icon: const Icon(Icons.data_usage, size: 20),
             label: const Text("Grant Usage Permission"),
             onPressed: () => networkService.requestPermission(),
          );
        }

        final period = settingsService.dataUsagePeriod;
        String label;
        switch (period) {
          case 'weekly':
            label = 'Weekly: ';
            break;
          case 'monthly':
            label = 'Monthly: ';
            break;
          case 'daily':
          default:
            label = 'Daily: ';
            break;
        }

        return FutureBuilder<int>(
          future: _usageFuture(networkService, period),
          builder: (context, snapshot) {
            final usage = snapshot.data ?? networkService.dailyDataUsage;
            final usageString = _formatBytes(usage);

            return RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w400,
                  color: Colors.white,
                  shadows: [
                    Shadow(color: Colors.black54, offset: Offset(0, 2), blurRadius: 4)
                  ],
                ),
                children: [
                  TextSpan(text: label),
                  TextSpan(
                    text: usageString,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return "${d.toStringAsFixed(2)} ${suffixes[i]}";
  }
}
