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

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/quiet_failure.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'focusable_settings_tile.dart';
import 'settings_page.dart';

/// One phone paired with the remote API.
class RemotePhone {
  final String fingerprint;
  final String name;
  final bool adult;
  final DateTime? lastUsed;

  const RemotePhone({required this.fingerprint, required this.name, required this.adult, this.lastUsed});

  static RemotePhone fromMap(Map<dynamic, dynamic> map) {
    final lastUsed = map["lastUsed"];
    return RemotePhone(
      fingerprint: map["fingerprint"] as String,
      name: (map["name"] as String?) ?? "phone",
      adult: map["adult"] == true,
      lastUsed: lastUsed is int && lastUsed > 0 ? DateTime.fromMillisecondsSinceEpoch(lastUsed) : null,
    );
  }
}

/// Settings > Family > Phones that control this TV: each paired phone, adult or kid rules, with Remove
/// (docs/tv-remote-api.md "Who a phone is"). New phones follow kid rules until an adult's profile marks them.
class RemotePhonesPage extends StatefulWidget {
  static const String routeName = "remote_phones";

  const RemotePhonesPage({super.key});

  @override
  State<RemotePhonesPage> createState() => _RemotePhonesPageState();
}

class _RemotePhonesPageState extends State<RemotePhonesPage> {
  late final FLauncherChannel? _channel = context.read<FLauncherChannel?>();
  List<RemotePhone>? _phones;
  bool _canMarkAdult = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final map = await _channel?.getRemotePhones();
      if (!mounted || map == null) return;
      final list = (map["phones"] as List?) ?? const [];
      setState(() {
        _phones = [for (final p in list) RemotePhone.fromMap(p as Map)];
        _canMarkAdult = map["canMarkAdult"] == true;
      });
    } catch (err) {
      noteFailure('remote_phones_page', err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final phones = _phones;
    return SettingsPage(
      title: l.remotePhonesTitle,
      children: [
        if (phones != null && phones.isEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(l.remotePhonesNone, style: textTheme.bodySmall),
          ),
        for (final (i, phone) in (phones ?? const <RemotePhone>[]).indexed)
          FocusableSettingsTile(
            autofocus: i == 0,
            leading: Icon(phone.adult ? Icons.phone_android : Icons.child_care),
            title: Text(phone.name, style: textTheme.bodyMedium),
            trailing: Text(phone.adult ? l.remotePhonesAdult : l.remotePhonesRestricted, style: textTheme.bodySmall),
            onPressed: () => _choose(phone),
          ),
        if (phones != null && phones.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _canMarkAdult ? l.remotePhonesAbout : "${l.remotePhonesAbout} ${l.remotePhonesAdultOnly}",
              style: textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Future<void> _choose(RemotePhone phone) async {
    final l = AppLocalizations.of(context)!;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(phone.name),
        actions: [
          if (_canMarkAdult)
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(phone.adult ? "kid" : "adult"),
              child: Text(phone.adult ? l.remotePhonesMarkRestricted : l.remotePhonesMarkAdult),
            ),
          TextButton(
            autofocus: !_canMarkAdult,
            onPressed: () => Navigator.of(context).pop("remove"),
            child: Text(l.remotePhonesRemove),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == "remove") {
        await _channel?.removeRemotePhone(phone.fingerprint);
      } else {
        await _channel?.setRemotePhoneAdult(phone.fingerprint, action == "adult");
      }
    } catch (err) {
      noteFailure('remote_phones_page', err);
    }
    await _read();
  }
}
