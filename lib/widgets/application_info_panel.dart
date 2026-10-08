/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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

import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/widgets/add_to_category_dialog.dart';
import 'package:flauncher/widgets/panel_action_button.dart';
import 'package:flauncher/widgets/side_panel_dialog.dart';
import 'package:provider/provider.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/l10n/app_localizations_en.dart';

import '../models/app.dart';
import '../models/category.dart';

class ApplicationInfoPanel extends StatefulWidget
{
  final Category? category;
  final App application;

  /// The card's banner or icon, shown beside the app's name.
  final ImageProvider? image;

  const ApplicationInfoPanel({
    required this.category,
    required this.application,
    this.image
  });

  @override
  State<ApplicationInfoPanel> createState() => _ApplicationInfoPanelState();
}

class _ApplicationInfoPanelState extends State<ApplicationInfoPanel>
{
  late Future<bool> _hasCustomBannerFuture;

  @override
  void initState() {
    super.initState();
    _hasCustomBannerFuture = context.read<AppsService>()
        .hasCustomBanner(widget.application.packageName);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context) ?? AppLocalizationsEn();

    return SidePanelDialog(
        width: 300,
        isRightSide: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (widget.image != null)
                  Image(
                    image: widget.image!,
                    width: 50,
                    errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined),
                  )
                else
                  const Icon(Icons.image_not_supported_outlined),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.application.name,
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.application.packageName,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              "v${widget.application.version}",
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                 children: [
                   // Add to Category button (First as requested)
                   PanelActionButton(
                     icon: Icons.add_box_outlined,
                     label: 'Add to Category',
                     onPressed: () async {
                       Navigator.of(context).pop(ApplicationInfoPanelResult.none);
                       await showDialog(
                         context: context,
                         builder: (context) => AddToCategoryDialog(widget.application),
                       );
                     },
                   ),
                   // Reorder button (Second as requested)
                   if (widget.category?.sort == CategorySort.manual)
                     PanelActionButton(
                       icon: Icons.open_with,
                       label: localizations.reorder,
                       onPressed: () => Navigator.of(context).pop(ApplicationInfoPanelResult.reorderApp),
                     ),
                   PanelActionButton(
                     icon: Icons.open_in_new,
                     label: localizations.open,
                     onPressed: () async {
                       await context.read<AppsService>().launchApp(widget.application);
                       if (context.mounted) Navigator.of(context).pop(ApplicationInfoPanelResult.none);
                     },
                   ),
                   // Favorites toggle button
                   Builder(
                     builder: (context) {
                       final appsService = context.watch<AppsService>();
                       final isInFavorites = appsService.isAppInFavorites(widget.application);
                       return PanelActionButton(
                         icon: isInFavorites ? Icons.star : Icons.star_border,
                         label: isInFavorites ? 'Remove from Fav' : 'Add to Fav',
                         onPressed: () async {
                           await appsService.toggleFavorite(widget.application);
                           if (context.mounted) Navigator.of(context).pop(ApplicationInfoPanelResult.none);
                         },
                       );
                     },
                   ),
                   PanelActionButton(
                     icon: widget.application.hidden ? Icons.visibility : Icons.visibility_off_outlined,
                     label: widget.application.hidden ? localizations.show : localizations.hide,
                     onPressed: () async {
                       final appsService = context.read<AppsService>();
                       if (widget.application.hidden) {
                         await appsService.showApplication(widget.application);
                       } else {
                         await appsService.hideApplication(widget.application);
                       }
                       if (context.mounted) Navigator.of(context).pop(ApplicationInfoPanelResult.none);
                     },
                   ),
                   if (widget.category != null)
                     PanelActionButton(
                       icon: Icons.delete_sweep_outlined,
                       label: localizations.removeFrom(widget.category?.name ?? ''),
                       maxLines: 2,
                       onPressed: () async {
                         final cat = widget.category;
                         if (cat != null) {
                           await context.read<AppsService>().removeFromCategory(widget.application, cat);
                         }
                         if (context.mounted) Navigator.of(context).pop(ApplicationInfoPanelResult.none);
                       },
                     ),
                   const Divider(),
                   FutureBuilder<bool>(
                     future: _hasCustomBannerFuture,
                     builder: (context, snapshot) {
                       final hasCustom = snapshot.data ?? false;
                       return Column(
                         crossAxisAlignment: CrossAxisAlignment.stretch,
                         children: [
                           PanelActionButton(
                             icon: Icons.image_search,
                             label: 'Set Custom Banner',
                             onPressed: () async {
                               final appsService = context.read<AppsService>();
                               try {
                                 final picker = ImagePicker();
                                 final pickedFile = await picker.pickImage(source: ImageSource.gallery);
                                 if (pickedFile != null) {
                                   final docDir = await getApplicationDocumentsDirectory();
                                   // Sanitize package name for filename
                                   final safePackageName = widget.application.packageName
                                       .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
                                   final savedImage = File('${docDir.path}/custom_banner_$safePackageName.png');
                                   await File(pickedFile.path).copy(savedImage.path);
                                   // Clean up temp file from ImagePicker
                                   await File(pickedFile.path).delete();
                                   await appsService.setCustomAppBanner(widget.application.packageName, savedImage.path);
                                   if (!mounted) return;
                                   // Refresh the future to reflect the change
                                   setState(() {
                                     _hasCustomBannerFuture = appsService.hasCustomBanner(widget.application.packageName);
                                   });
                                 }
                               } catch (e) {
                                 if (context.mounted) {
                                   ScaffoldMessenger.of(context).showSnackBar(
                                     SnackBar(content: Text('Failed to set banner: $e')),
                                   );
                                 }
                               }
                               if (context.mounted) Navigator.of(context).pop(ApplicationInfoPanelResult.none);
                             },
                           ),
                           if (hasCustom)
                             PanelActionButton(
                               icon: Icons.hide_image_outlined,
                               label: 'Clear Custom Banner',
                               onPressed: () async {
                                 final appsService = context.read<AppsService>();
                                 try {
                                   await appsService.removeCustomAppBanner(widget.application.packageName);
                                   if (!mounted) return;
                                   // Refresh the future to reflect the change
                                   setState(() {
                                     _hasCustomBannerFuture = appsService.hasCustomBanner(widget.application.packageName);
                                   });
                                 } catch (e) {
                                   if (context.mounted) {
                                     ScaffoldMessenger.of(context).showSnackBar(
                                       SnackBar(content: Text('Failed to clear banner: $e')),
                                     );
                                   }
                                 }
                                 if (context.mounted) Navigator.of(context).pop(ApplicationInfoPanelResult.none);
                               },
                             ),
                         ],
                       );
                     }
                   ),
                   const Divider(),
                   PanelActionButton(
                     icon: Icons.info_outlined,
                     label: localizations.appInfo,
                     onPressed: () => context.read<AppsService>().openAppInfo(widget.application),
                   ),
                   PanelActionButton(
                     icon: Icons.delete_outlined,
                     label: localizations.uninstall,
                     onPressed: () async {
                       await context.read<AppsService>().uninstallApp(widget.application);
                       if (context.mounted) Navigator.of(context).pop(ApplicationInfoPanelResult.none);
                     },
                   )
                 ]
                )
              )
            )
          ]
        )
      );
  }
}

enum ApplicationInfoPanelResult { none, reorderApp }
