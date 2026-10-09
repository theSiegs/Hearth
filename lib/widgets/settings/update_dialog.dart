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

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/update_service.dart';

import 'hearth_dialog.dart';

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  @override
  void initState() {
    super.initState();
    context.read<UpdateService>().checkForUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final accentColor = context.select((SettingsService s) => s.accentColor);
    final updateService = context.watch<UpdateService>();

    return HearthDialogFrame(
      width: 460,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      maxHeightFactor: 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.system_update_outlined, color: Colors.white, size: 24),
              const SizedBox(width: 8),
              // A long title in another language wraps instead of overflowing
              Flexible(
                child: Text(
                  localizations.updateCheckForUpdatesTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            localizations.updateCurrentVersion(updateService.currentVersion),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 16),
          _buildBody(localizations, updateService, accentColor),
          const SizedBox(height: 16),
          _buildActions(context, localizations, updateService),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations localizations, UpdateService service, Color accentColor) {
    switch (service.status) {
      case UpdateStatus.idle:
      case UpdateStatus.checking:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(height: 12),
              Text(localizations.updateChecking, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        );
      case UpdateStatus.upToDate:
        return Column(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 32),
            const SizedBox(height: 8),
            Text(localizations.updateUpToDate, style: const TextStyle(color: Colors.white70, fontSize: 13)),
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
                Flexible(
                  child: Text(localizations.updateVersionAvailable(info.tagName),
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
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
            Text(localizations.updateDownloading((service.downloadProgress * 100).toStringAsFixed(0)),
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        );
      case UpdateStatus.readyToInstall:
        return Column(
          children: [
            const Icon(Icons.download_done_outlined, color: Colors.greenAccent, size: 32),
            const SizedBox(height: 8),
            Text(
              localizations.updateDownloadedHint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        );
      case UpdateStatus.error:
        return Column(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 32),
            const SizedBox(height: 8),
            Text(service.errorMessage ?? localizations.updateSomethingWentWrong,
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        );
    }
  }

  Widget _buildActions(BuildContext context, AppLocalizations localizations, UpdateService service) {
    final actions = <Widget>[];

    switch (service.status) {
      case UpdateStatus.available:
        actions.add(FocusableDialogButton(
          icon: Icons.download,
          label: localizations.updateDownloadAndInstall,
          compact: true,
          autofocus: true,
          onPressed: () => service.downloadAndInstall(),
        ));
        break;
      case UpdateStatus.readyToInstall:
        actions.add(FocusableDialogButton(
          icon: Icons.refresh,
          label: localizations.updateRetryInstall,
          compact: true,
          autofocus: true,
          onPressed: () => service.retryInstall(),
        ));
        break;
      case UpdateStatus.error:
      case UpdateStatus.upToDate:
        actions.add(FocusableDialogButton(
          icon: Icons.refresh,
          label: localizations.updateCheckAgain,
          compact: true,
          autofocus: true,
          onPressed: () => service.checkForUpdate(),
        ));
        break;
      default:
        break;
    }

    actions.add(FocusableDialogButton(
      icon: Icons.close,
      label: localizations.close,
      compact: true,
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
