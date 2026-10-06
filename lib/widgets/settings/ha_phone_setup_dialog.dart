import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../flauncher_channel.dart';

/// Shows a QR code that opens a one-time page on the TV from a phone, where the Home Assistant address and access
/// token are pasted and sent (QuickBars' method). Pops with true once they arrive.
class HaPhoneSetupDialog extends StatefulWidget {
  final FLauncherChannel channel;

  const HaPhoneSetupDialog({super.key, required this.channel});

  @override
  State<HaPhoneSetupDialog> createState() => _HaPhoneSetupDialogState();
}

class _HaPhoneSetupDialogState extends State<HaPhoneSetupDialog> {
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
      link = await widget.channel.startHaSetup();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _link = link;
      _failed = link == null;
    });
    if (link == null) return;
    _poll = Timer.periodic(const Duration(seconds: 1), (_) async {
      bool received = false;
      try {
        received = await widget.channel.getHaSetupReceived();
      } catch (_) {}
      if (received && mounted) {
        _poll?.cancel();
        Navigator.of(context).pop(true);
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    widget.channel.stopHaSetup().catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70);
    return AlertDialog(
      title: const Text("Set up from your phone"),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_failed)
              const Text("This TV isn't on the home network, so the phone can't reach it.")
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
              Text(
                "Scan with a phone on the same Wi-Fi, paste the Home Assistant address and access token, and "
                "tap Send. The page only works while this is open.",
                style: small,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              SelectableText(_link!, style: small?.copyWith(fontFamily: "monospace", fontSize: 11)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text("Close"),
        ),
      ],
    );
  }
}
