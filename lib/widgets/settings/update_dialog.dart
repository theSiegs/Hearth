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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/update_service.dart';

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  Color _hexToColor(String hex) => Color(int.parse('FF$hex', radix: 16));

  @override
  void initState() {
    super.initState();
    context.read<UpdateService>().checkForUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _hexToColor(context.watch<SettingsService>().accentColorHex);
    final updateService = context.watch<UpdateService>();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Container(
        width: 460,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F0F),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.system_update_outlined, color: Colors.white, size: 24),
                  SizedBox(width: 8),
                  Text(
                    "Check for Updates",
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                "Current version: ${updateService.currentVersion}",
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              _buildBody(context, updateService, accentColor),
              const SizedBox(height: 16),
              _buildActions(context, updateService, accentColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, UpdateService service, Color accentColor) {
    switch (service.status) {
      case UpdateStatus.idle:
      case UpdateStatus.checking:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
              SizedBox(height: 12),
              Text("Checking GitHub for a new release…", style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        );
      case UpdateStatus.upToDate:
        return const Column(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 32),
            SizedBox(height: 8),
            Text("You're on the latest version.", style: TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        );
      case UpdateStatus.available:
        final info = service.updateInfo!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.new_releases_outlined, color: Colors.amberAccent, size: 20),
                const SizedBox(width: 8),
                Text("Version ${info.tagName} is available",
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
            if (info.changelog.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                constraints: const BoxConstraints(maxHeight: 160),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: Text(info.changelog, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ),
              ),
            ],
          ],
        );
      case UpdateStatus.downloading:
        return Column(
          children: [
            LinearProgressIndicator(
              value: service.downloadProgress > 0 ? service.downloadProgress : null,
              color: accentColor,
              backgroundColor: Colors.white.withOpacity(0.1),
            ),
            const SizedBox(height: 8),
            Text("Downloading… ${(service.downloadProgress * 100).toStringAsFixed(0)}%",
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        );
      case UpdateStatus.readyToInstall:
        return const Column(
          children: [
            Icon(Icons.download_done_outlined, color: Colors.greenAccent, size: 32),
            SizedBox(height: 8),
            Text(
              "Downloaded. If the installer didn't open, your device may need\n"
              "\"Install unknown apps\" permission granted for Hearth.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        );
      case UpdateStatus.error:
        return Column(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 32),
            const SizedBox(height: 8),
            Text(service.errorMessage ?? "Something went wrong",
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        );
    }
  }

  Widget _buildActions(BuildContext context, UpdateService service, Color accentColor) {
    final actions = <Widget>[];

    switch (service.status) {
      case UpdateStatus.available:
        actions.add(_ActionButton(
          icon: Icons.download,
          label: "Download & Install",
          accentColor: accentColor,
          autofocus: true,
          onPressed: () => service.downloadAndInstall(),
        ));
        break;
      case UpdateStatus.readyToInstall:
        actions.add(_ActionButton(
          icon: Icons.refresh,
          label: "Retry Install",
          accentColor: accentColor,
          autofocus: true,
          onPressed: () => service.retryInstall(),
        ));
        break;
      case UpdateStatus.error:
      case UpdateStatus.upToDate:
        actions.add(_ActionButton(
          icon: Icons.refresh,
          label: "Check Again",
          accentColor: accentColor,
          autofocus: true,
          onPressed: () => service.checkForUpdate(),
        ));
        break;
      default:
        break;
    }

    actions.add(_ActionButton(
      icon: Icons.close,
      label: "Close",
      accentColor: accentColor,
      autofocus: actions.isEmpty,
      onPressed: () => Navigator.of(context).pop(),
    ));

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          actions[i],
        ],
      ],
    );
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color accentColor;
  final VoidCallback onPressed;
  final bool autofocus;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.onPressed,
    this.autofocus = false,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed()),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => widget.onPressed()),
      },
      child: Focus(
        autofocus: widget.autofocus,
        onFocusChange: (hasFocus) => setState(() => _focused = hasFocus),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _focused ? widget.accentColor.withOpacity(0.3) : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _focused ? Colors.white : Colors.transparent, width: _focused ? 2 : 0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 16, color: Colors.white70),
                const SizedBox(width: 6),
                Text(widget.label,
                    style: TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: _focused ? FontWeight.bold : FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
