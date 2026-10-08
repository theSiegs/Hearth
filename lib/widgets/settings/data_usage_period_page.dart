
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/settings/settings_choice_tile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DataUsagePeriodPage extends StatelessWidget {
  static const String routeName = "data_usage_period_panel";

  const DataUsagePeriodPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    return Consumer<SettingsService>(
        builder: (context, service, _) {
          return Column(
            children: [
              Text(localizations.dataUsagePeriod, style: Theme.of(context).textTheme.titleLarge),
              const Divider(),
              Expanded(
                child: ListView(
                  children: [
                    _choice(service, 'Daily', DATA_USAGE_DAILY),
                    _choice(service, 'Weekly', DATA_USAGE_WEEKLY),
                    _choice(service, 'Monthly', DATA_USAGE_MONTHLY),
                  ],
                ),
              ),
            ],
          );
        }
    );
  }

  Widget _choice(SettingsService service, String label, String value) => SettingsChoiceTile<String>(
        title: label,
        value: value,
        groupValue: service.dataUsagePeriod,
        onChanged: service.setDataUsagePeriod,
      );
}
