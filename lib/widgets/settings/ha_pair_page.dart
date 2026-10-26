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

import 'dart:async';

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/quiet_failure.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../flauncher_channel.dart';
import 'focusable_settings_tile.dart';
import 'remote_text_field.dart';
import 'settings_page.dart';

/// Pairs this TV with the Hearth integration in Home Assistant: the TV asks, shows a code, and an adult confirms the
/// same code in Home Assistant. Paired, the TV reports there (instead of a webhook) and gets each profile's limits.
class HaPairPage extends StatefulWidget {
  static const String routeName = "home_assistant_pair";

  /// How often a waiting pairing is asked about.
  static const Duration pollEvery = Duration(seconds: 2);

  const HaPairPage({super.key});

  @override
  State<HaPairPage> createState() => _HaPairPageState();
}

class _HaPairPageState extends State<HaPairPage> {
  late final FLauncherChannel _channel = context.read<FLauncherChannel>();
  final TextEditingController _url = TextEditingController();
  bool? _paired;
  String? _code;
  String? _message;
  bool _busy = false;
  Timer? _poll;
  DateTime? _until;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _url.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final state = await _channel.getHaIntegration();
      if (!mounted) return;
      setState(() {
        _paired = state["paired"] == true;
        if (_url.text.isEmpty) _url.text = state["url"] as String? ?? "";
      });
    } catch (err) {
      noteFailure('ha_pair_page', err);
    }
  }

  String _error(AppLocalizations l, String? error) => switch (error) {
        "no_address" => l.haPairNoAddress,
        "not_set_up" => l.haPairNotSetUp,
        "no_integration" => l.haPairNoIntegration,
        "unreachable" => l.haPairUnreachable,
        "try_later" => l.haPairTryLater,
        "not_local" => l.haPairNotLocal,
        _ => l.haPairFailed,
      };

  Future<void> _pair() async {
    if (_busy) return;
    final l = AppLocalizations.of(context)!;
    final url = _url.text.trim();
    if (url.isEmpty) {
      setState(() => _message = l.haPairNoAddress);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _code = null;
    });
    try {
      final started = await _channel.startHaPairing(url);
      if (!mounted) return;
      final pairingId = started["pairing_id"] as String?;
      final nonce = started["nonce"] as String?;
      if (pairingId == null || nonce == null || started["code"] == null) {
        setState(() {
          _busy = false;
          _message = _error(l, started["error"] as String?);
        });
        return;
      }
      final seconds = (started["expires_in"] as num?)?.toInt() ?? 600;
      setState(() {
        _code = started["code"] as String;
        _until = DateTime.now().add(Duration(seconds: seconds));
      });
      _poll = Timer.periodic(HaPairPage.pollEvery, (_) => _check(url, pairingId, nonce));
    } catch (err) {
      noteFailure('ha_pair_page', err);
      if (mounted) {
        setState(() {
          _busy = false;
          _message = l.haPairFailed;
        });
      }
    }
  }

  bool _checking = false;

  Future<void> _check(String url, String pairingId, String nonce) async {
    if (_checking) return;
    _checking = true;
    try {
      final status = await _channel.pollHaPairing(url, pairingId, nonce);
      if (!mounted) return;
      final l = AppLocalizations.of(context)!;
      final expired = _until != null && DateTime.now().isAfter(_until!);
      // A dropped answer is asked again, until the request runs out
      if (status == "pending" || (status == "unreachable" && !expired)) return;
      _poll?.cancel();
      setState(() {
        _busy = false;
        _code = null;
        _message = switch (status) {
          "paired" => l.haPairDone,
          "denied" => l.haPairDenied,
          _ => l.haPairEnded,
        };
        if (status == "paired") _paired = true;
      });
    } catch (err) {
      noteFailure('ha_pair_page', err);
    } finally {
      _checking = false;
    }
  }

  Future<void> _unpair() async {
    final l = AppLocalizations.of(context)!;
    try {
      await _channel.unpairHaIntegration();
      if (mounted) {
        setState(() {
          _paired = false;
          _message = l.haPairUnpaired;
        });
      }
    } catch (err) {
      noteFailure('ha_pair_page', err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final note = textTheme.bodySmall?.copyWith(color: Colors.white70);
    Widget text(String value, [TextStyle? style]) =>
        Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4), child: Text(value, style: style ?? note));
    return SettingsPage(
      title: l.haPairTitle,
      children: [
        if (_paired == true) ...[
          text(l.haPairIsPaired(_url.text.trim()), textTheme.bodyMedium),
          FocusableSettingsTile(
            autofocus: true,
            leading: const Icon(Icons.link_off),
            title: Text(l.haPairUnpair, style: textTheme.bodyMedium),
            onPressed: _unpair,
          ),
        ] else if (_paired == false) ...[
          text(l.haPairIntro),
          if (_code == null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: RemoteTextField(
                controller: _url,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _pair(),
                decoration: const InputDecoration(labelText: "Home Assistant", hintText: "http://192.0.2.10:8123"),
              ),
            ),
            // Focus starts here, not in the text field, so the keyboard doesn't pop up on the way in
            FocusableSettingsTile(
              autofocus: true,
              leading: const Icon(Icons.link),
              title: Text(l.haPairStart, style: textTheme.bodyMedium),
              onPressed: _busy ? null : _pair,
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Text(_code!, style: textTheme.displayMedium?.copyWith(letterSpacing: 8)),
            ),
            text(l.haPairCode),
          ],
        ],
        if (_message != null) text(_message!),
      ],
    );
  }
}
