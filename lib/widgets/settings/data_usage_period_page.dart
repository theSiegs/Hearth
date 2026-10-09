import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/settings/settings_choice_tile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flauncher/widgets/settings/settings_page.dart';

class DataUsagePeriodPage extends StatelessWidget {
  static const String routeName = "data_usage_period_panel";

  const DataUsagePeriodPage({super.key});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    return Consumer<SettingsService>(builder: (context, service, _) {
      return SettingsPage(
        title: localizations.dataUsagePeriod,
        children: [
          _choice(service, localizations.dataUsageDaily, dataUsageDaily),
          _choice(service, localizations.dataUsageWeekly, dataUsageWeekly),
          _choice(service, localizations.dataUsageMonthly, dataUsageMonthly),
        ],
      );
    });
  }

  Widget _choice(SettingsService service, String label, String value) => SettingsChoiceTile<String>(
        title: label,
        value: value,
        groupValue: service.dataUsagePeriod,
        onChanged: service.setDataUsagePeriod,
      );
}
