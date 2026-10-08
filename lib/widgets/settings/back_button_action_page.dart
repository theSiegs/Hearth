import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/settings/back_button_actions.dart';
import 'package:flauncher/widgets/settings/settings_choice_tile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/widgets/settings/settings_page.dart';

class BackButtonActionPage extends StatelessWidget {
  static const String routeName = "back_button_action_panel";

  const BackButtonActionPage({super.key});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    return Consumer<SettingsService>(builder: (context, service, _) {
      return SettingsPage(
        title: localizations.backButtonAction,
        children: [
          _choice(service, localizations.dialogOptionBackButtonActionDoNothing, BACK_BUTTON_ACTION_NOTHING),
          _choice(service, localizations.dialogOptionBackButtonActionShowClock, BACK_BUTTON_ACTION_CLOCK),
          _choice(service, localizations.dialogOptionBackButtonActionShowScreensaver, BACK_BUTTON_ACTION_SCREENSAVER),
        ],
      );
    });
  }

  Widget _choice(SettingsService service, String label, String value) => SettingsChoiceTile<String>(
        title: label,
        value: value,
        groupValue: service.backButtonAction,
        onChanged: service.setBackButtonAction,
      );
}
