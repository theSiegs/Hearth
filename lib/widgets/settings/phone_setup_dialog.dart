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
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Shows a QR code that opens a one-time page on the TV from a phone (the Home Assistant sign-in, streaming PINs).
/// [start] starts the page and gives its link (null without a network), [stop] ends it, and [done] says whether the
/// phone has sent what the page asks for; the dialog pops with true then.
class PhoneSetupDialog extends StatefulWidget {
  final String title;
  final String scanText;
  final Future<String?> Function() start;
  final Future<void> Function() stop;
  final Future<bool> Function() done;

  const PhoneSetupDialog({
    super.key,
    required this.title,
    required this.scanText,
    required this.start,
    required this.stop,
    required this.done,
  });

  @override
  State<PhoneSetupDialog> createState() => _PhoneSetupDialogState();
}

class _PhoneSetupDialogState extends State<PhoneSetupDialog> {
  String? _link;
  bool _failed = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    String? link;
    try {
      link = await widget.start();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _link = link;
      _failed = link == null;
    });
    if (link == null) return;
    _poll = Timer.periodic(const Duration(seconds: 1), (_) async {
      bool done = false;
      try {
        done = await widget.done();
      } catch (_) {}
      if (done && mounted) {
        _poll?.cancel();
        Navigator.of(context).pop(true);
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    widget.stop().catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_failed)
              Text(l.haPhoneSetupNoNetwork)
            else if (_link == null)
              const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())
            else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: QrImageView(
                  data: _link!,
                  version: QrVersions.auto,
                  size: 200,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(widget.scanText, style: small, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              // Without the key after "#": it's only for the phone that scans the code
              SelectableText(_link!.split("#").first, style: small?.copyWith(fontFamily: "monospace", fontSize: 11)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.close),
        ),
      ],
    );
  }
}
