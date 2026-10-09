import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/parent_pin_dialog.dart';
import 'package:flauncher/widgets/settings/launcher_sections_panel_page.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'ensure_visible.dart';
import 'title_pill.dart';

Widget categoryContainerEmptyState(BuildContext context) {
  AppLocalizations localizations = AppLocalizations.of(context)!;

  return SizedBox(
    height: 110,
    child: EnsureVisible(
      // Centred; this also keeps the first section's title clear of the app bar.
      alignment: 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Card(
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: InkWell(
                // Settings take the parent PIN in kids profiles, from here too
                onTap: () async {
                  final bool allowed = await requireParent(context);
                  if (!allowed || !context.mounted) return;
                  showDialog(
                    context: context,
                    builder: (_) => const SettingsPanel(initialRoute: LauncherSectionsPanelPage.routeName),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Center(
                    child: Text(
                      localizations.textEmptyCategory,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A section's title, and its number of items when that setting is on. Shows nothing while
/// section titles are off.
class CategoryHeader extends StatelessWidget {
  final String title;
  final int count;

  const CategoryHeader({super.key, required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    final (showTitle, showCount) = context.select<SettingsService, (bool, bool)>(
      (s) => (s.showCategoryTitles, s.showCategoryAppCount),
    );
    if (!showTitle) {
      return const SizedBox.shrink();
    }

    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: TitlePill(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: textTheme.titleLarge!.copyWith(shadows: TitlePill.textShadow)),
              if (showCount) ...[
                const SizedBox(width: 8),
                Text('•  $count',
                    style: textTheme.bodyMedium!.copyWith(color: Colors.white70, shadows: TitlePill.textShadow)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
