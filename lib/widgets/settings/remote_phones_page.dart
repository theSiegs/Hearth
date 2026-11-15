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

/// A phone's told role on the remote API (docs/tv-remote-api.md, V2.4).
enum RemotePhoneRole {
  /// Not this one: every new pairing; kid rules, no minutes.
  none,

  /// One kid's phone: their minutes and asks.
  kid,

  /// An adult's phone (the contract's "parent").
  parent;

  static RemotePhoneRole parse(Object? value) =>
      RemotePhoneRole.values.firstWhere((r) => r.name == value, orElse: () => RemotePhoneRole.none);
}

/// One phone paired with the remote API.
class RemotePhone {
  final String fingerprint;
  final String name;
  final RemotePhoneRole role;

  /// The kid's profile for a kid's phone.
  final String? profileKey;
  final DateTime? lastUsed;

  const RemotePhone({
    required this.fingerprint,
    required this.name,
    required this.role,
    this.profileKey,
    this.lastUsed,
  });

  static RemotePhone fromMap(Map<dynamic, dynamic> map) {
    final lastUsed = map["lastUsed"];
    final role = RemotePhoneRole.parse(map["role"]);
    final profileKey = map["profileKey"] as String?;
    return RemotePhone(
      fingerprint: map["fingerprint"] as String,
      name: (map["name"] as String?) ?? "phone",
      role: role == RemotePhoneRole.kid && profileKey == null ? RemotePhoneRole.none : role,
      profileKey: profileKey,
      lastUsed: lastUsed is int && lastUsed > 0 ? DateTime.fromMillisecondsSinceEpoch(lastUsed) : null,
    );
  }
}

/// A kid a phone can be bound to.
class RemotePhoneKid {
  final String profileKey;
  final String name;

  const RemotePhoneKid({required this.profileKey, required this.name});

  static RemotePhoneKid? fromMap(Map<dynamic, dynamic> map) {
    final key = map["profileKey"];
    if (key is! String) return null;
    return RemotePhoneKid(profileKey: key, name: (map["name"] as String?) ?? key);
  }
}

/// Settings > Family > Phones that control this TV: each paired phone and whose it is (a kid's, an adult's, or not
/// this one), with Remove (docs/tv-remote-api.md "Who a phone is" and V2.4). New phones are "not this one" (kid rules)
/// until an adult's profile binds them.
class RemotePhonesPage extends StatefulWidget {
  static const String routeName = "remote_phones";

  const RemotePhonesPage({super.key});

  @override
  State<RemotePhonesPage> createState() => _RemotePhonesPageState();
}

class _RemotePhonesPageState extends State<RemotePhonesPage> {
  late final FLauncherChannel? _channel = context.read<FLauncherChannel?>();
  List<RemotePhone>? _phones;
  List<RemotePhoneKid> _kids = const [];
  bool _canBind = false;

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
      final kids = (map["kids"] as List?) ?? const [];
      setState(() {
        _phones = [for (final p in list) RemotePhone.fromMap(p as Map)];
        _kids = [for (final k in kids) RemotePhoneKid.fromMap(k as Map)].whereType<RemotePhoneKid>().toList();
        _canBind = map["canBind"] == true;
      });
    } catch (err) {
      noteFailure('remote_phones_page', err);
    }
  }

  String _roleLabel(AppLocalizations l, RemotePhone phone) {
    switch (phone.role) {
      case RemotePhoneRole.parent:
        return l.remotePhonesAdult;
      case RemotePhoneRole.kid:
        final kid = _kids.where((k) => k.profileKey == phone.profileKey).firstOrNull;
        return l.remotePhonesKid(kid?.name ?? "?");
      case RemotePhoneRole.none:
        return l.remotePhonesNotThisOne;
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
            leading: Icon(switch (phone.role) {
              RemotePhoneRole.parent => Icons.phone_android,
              RemotePhoneRole.kid => Icons.child_care,
              RemotePhoneRole.none => Icons.phonelink_lock,
            }),
            title: Text(phone.name, style: textTheme.bodyMedium),
            trailing: Text(_roleLabel(l, phone), style: textTheme.bodySmall),
            onPressed: () => _choose(phone),
          ),
        if (phones != null && phones.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _canBind ? l.remotePhonesAbout : "${l.remotePhonesAbout} ${l.remotePhonesAdultOnly}",
              style: textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Future<void> _choose(RemotePhone phone) async {
    final l = AppLocalizations.of(context)!;
    bool isCurrent(RemotePhoneRole role, [String? kidKey]) =>
        phone.role == role && (role != RemotePhoneRole.kid || phone.profileKey == kidKey);
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(phone.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_canBind) ...[
                for (final (i, kid) in _kids.indexed)
                  TextButton(
                    autofocus: i == 0,
                    onPressed: isCurrent(RemotePhoneRole.kid, kid.profileKey)
                        ? null
                        : () => Navigator.of(context).pop("kid:${kid.profileKey}"),
                    child: Text(l.remotePhonesKid(kid.name)),
                  ),
                TextButton(
                  autofocus: _kids.isEmpty,
                  onPressed: isCurrent(RemotePhoneRole.parent) ? null : () => Navigator.of(context).pop("parent"),
                  child: Text(l.remotePhonesAdult),
                ),
                TextButton(
                  onPressed: isCurrent(RemotePhoneRole.none) ? null : () => Navigator.of(context).pop("none"),
                  child: Text(l.remotePhonesNotThisOne),
                ),
              ],
              TextButton(
                autofocus: !_canBind,
                onPressed: () => Navigator.of(context).pop("remove"),
                child: Text(l.remotePhonesRemove),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == "remove") {
        await _channel?.removeRemotePhone(phone.fingerprint);
      } else if (action.startsWith("kid:")) {
        await _channel?.setRemotePhoneRole(phone.fingerprint, "kid", profileKey: action.substring(4));
      } else {
        await _channel?.setRemotePhoneRole(phone.fingerprint, action);
      }
    } catch (err) {
      noteFailure('remote_phones_page', err);
    }
    await _read();
  }
}
