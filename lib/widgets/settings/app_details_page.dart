
import 'package:flauncher/models/app.dart';
import 'package:flauncher/models/category.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/widgets/add_to_category_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flauncher/l10n/app_localizations.dart';

import 'app_icon.dart';

class AppDetailsPage extends StatelessWidget {
  static const String routeName = "app_details_page";

  final App application;

  const AppDetailsPage({super.key, required this.application});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    AppsService appsService = context.watch<AppsService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AppIcon(application.packageName, size: 50),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    application.name,
                    style: Theme.of(context).textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  Text(
                    "v${application.version}",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(),
        Expanded(
          child: ListView(
            children: [
              _buildListTile(
                context,
                icon: Icons.open_in_new,
                title: localizations.open,
                onTap: () async {
                  await appsService.launchApp(application);
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
              _buildListTile(
                context,
                icon: appsService.isAppInFavorites(application) ? Icons.star : Icons.star_border,
                title: appsService.isAppInFavorites(application)
                    ? localizations.appDetailsRemoveFromFavorites
                    : localizations.appDetailsAddToFavorites,
                onTap: () => appsService.toggleFavorite(application),
              ),
              _buildListTile(
                context,
                icon: application.hidden ? Icons.visibility : Icons.visibility_off_outlined,
                title: application.hidden ? localizations.show : localizations.hide,
                onTap: () {
                   if (application.hidden) {
                     appsService.showApplication(application);
                   } else {
                     appsService.hideApplication(application);
                   }
                },
              ),
              if (!application.hidden)
                _buildListTile(
                  context,
                  icon: Icons.add_box_outlined,
                  title: localizations.appDetailsAddToCategory,
                  onTap: () => showDialog<Category>(
                    context: context,
                    builder: (_) => AddToCategoryDialog(application),
                  ),
                ),
              const Divider(),
              _buildListTile(
                context,
                icon: Icons.info_outlined,
                title: localizations.appInfo,
                onTap: () => appsService.openAppInfo(application),
              ),
              _buildListTile(
                context,
                icon: Icons.delete_outlined,
                title: localizations.uninstall,
                onTap: () async {
                  await appsService.uninstallApp(application);
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildListTile(BuildContext context,
      {required IconData icon, required String title, required VoidCallback onTap}) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
