import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../../flauncher_channel.dart';
import 'phone_setup_dialog.dart';

/// Shows a QR code that opens a one-time page on the TV from a phone, where the Home Assistant address and access
/// token are pasted and sent (QuickBars' method). Pops with true once they arrive.
class HaPhoneSetupDialog extends StatelessWidget {
  final FLauncherChannel channel;

  const HaPhoneSetupDialog({super.key, required this.channel});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return PhoneSetupDialog(
      title: l.haSetUpFromPhone,
      scanText: l.haPhoneSetupScan,
      start: channel.startHaSetup,
      stop: channel.stopHaSetup,
      done: channel.getHaSetupReceived,
    );
  }
}
