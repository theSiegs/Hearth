import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/backup_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/settings/focusable_settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:share_plus/share_plus.dart';

import 'message_dialog.dart';
import 'package:flauncher/widgets/settings/settings_page.dart';

class BackupRestorePage extends StatelessWidget {
  static const String routeName = "backup_restore_panel";

  const BackupRestorePage({super.key});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    return SettingsPage(
      title: localizations.backupAndRestore,
      children: [
        FocusableSettingsTile(
          autofocus: true,
          leading: const Icon(Icons.upload_file),
          title: Text(localizations.exportBackup, style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () => _export(context, localizations),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.download_done),
          title: Text(localizations.importBackup, style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () => _confirmImport(context, localizations),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.share),
          title: Text(localizations.shareBackup, style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () => _share(context, localizations),
        ),
      ],
    );
  }

  Future<void> _share(BuildContext context, AppLocalizations localizations) async {
    try {
      final settingsService = context.read<SettingsService>();
      final pathStr = await context.read<BackupService>().exportBackup(settingsService);
      await Share.shareXFiles([XFile(pathStr)], text: localizations.backupShareText);
    } catch (e) {
      if (context.mounted) {
        showMessageDialog(context,
            title: localizations.backupShareFailedTitle, message: localizations.backupShareFailed(e.toString()));
      }
    }
  }

  Future<void> _export(BuildContext context, AppLocalizations localizations) async {
    try {
      final settingsService = context.read<SettingsService>();
      final path = await context.read<BackupService>().exportBackup(settingsService);
      if (context.mounted) {
        showMessageDialog(context,
            title: localizations.backupExportSuccessTitle, message: localizations.exportSuccess(path));
      }
    } catch (e) {
      if (context.mounted) {
        showMessageDialog(context,
            title: localizations.backupExportFailedTitle, message: localizations.exportError(e.toString()));
      }
    }
  }

  String _formatSize(AppLocalizations localizations, int bytes) {
    if (bytes < 1024) return localizations.backupSizeBytes('$bytes');
    if (bytes < 1024 * 1024) return localizations.backupSizeKilobytes((bytes / 1024).toStringAsFixed(1));
    return localizations.backupSizeMegabytes((bytes / (1024 * 1024)).toStringAsFixed(1));
  }

  String _formatDate(DateTime dateTime) {
    return "${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} "
        "${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
  }

  Future<void> _confirmImport(BuildContext context, AppLocalizations localizations) async {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(localizations.importBackup),
          content: Container(
            width: 400,
            constraints: const BoxConstraints(maxHeight: 300),
            child: FutureBuilder<List<BackupFileEntry>>(
              future: context.read<BackupService>().getBackupFiles(),
              builder: (_, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 100,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Text(
                    localizations.backupLoadError('${snapshot.error}'),
                    style: const TextStyle(color: Colors.red),
                  );
                }
                final entries = snapshot.data ?? [];
                if (entries.isEmpty) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24.0),
                        child: Text(localizations.backupNoFiles),
                      ),
                      TextButton(
                        autofocus: true,
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(localizations.ok),
                      ),
                    ],
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  cacheExtent: 1000,
                  itemCount: entries.length,
                  itemBuilder: (itemContext, index) {
                    final entry = entries[index];
                    return FocusableSettingsTile(
                      // The newest backup is selected as the list loads
                      autofocus: index == 0,
                      leading: const Icon(Icons.settings_backup_restore),
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.name,
                            style: Theme.of(itemContext).textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            localizations.backupFileDetails(
                                _formatDate(entry.lastModified), _formatSize(localizations, entry.size)),
                            style: Theme.of(itemContext).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey,
                                ),
                          ),
                        ],
                      ),
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        // The page's context, as this list closes before the import ends
                        _confirmFileImport(context, localizations, entry);
                      },
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(localizations.cancel),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmFileImport(BuildContext context, AppLocalizations localizations, BackupFileEntry entry) async {
    final backupService = context.read<BackupService>();
    final settingsService = context.read<SettingsService>();
    final appsService = context.read<AppsService>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.importBackup),
        content: Text(localizations.importConfirm),
        actions: [
          // Cancel first: importing replaces the current settings
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(localizations.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                await backupService.importBackup(entry.file, settingsService);
                settingsService.reload();
                await appsService.refreshState();
                if (context.mounted) {
                  final ok = await showMessageDialog(context,
                      title: localizations.backupImportSuccessTitle, message: localizations.importSuccess);
                  if (ok && context.mounted) Navigator.of(context).pop();
                }
              } catch (e) {
                if (context.mounted) {
                  showMessageDialog(context,
                      title: localizations.backupImportFailedTitle, message: localizations.importError(e.toString()));
                }
              }
            },
            child: Text(localizations.backupImport),
          ),
        ],
      ),
    );
  }
}
