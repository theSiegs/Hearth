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

import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/widgets/app_card.dart';
import 'package:flauncher/widgets/category_container_common.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app.dart';
import '../models/category.dart';

class CategoryRow extends StatelessWidget
{
  final Category category;

  final bool isFirstSection;

  /// False inside the dock, which has no heading.
  final bool showTitle;

  /// Size the row to its apps instead of the full width, so a short dock stays centred.
  final bool shrinkWrap;

  const CategoryRow({
    super.key,
    required this.category,
    this.isFirstSection = false,
    this.showTitle = true,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    final applications = category.applications;
    Widget categoryContent;
    if (applications.isEmpty) {
      categoryContent = categoryContainerEmptyState(context);
    }
    else {
      categoryContent = SizedBox(
        height: category.rowHeight.toDouble(),
        child: ListView.custom(
          shrinkWrap: shrinkWrap,
          clipBehavior: Clip.none,
          padding: const EdgeInsets.all(8),
          scrollDirection: Axis.horizontal,
          childrenDelegate: SliverChildBuilderDelegate(
            childCount: applications.length,
            findChildIndexCallback: _findChildIndex,
            (context, index) => Padding(
                key: Key(applications[index].packageName),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: AppCard(
                  category: category,
                  application: applications[index],
                  autofocus: index == 0,
                  upGoesToTopBar: isFirstSection,
                  isFirstInRow: index == 0,
                  isLastInRow: index == applications.length - 1,
                  onMove: (direction) => _onMove(context, direction, applications[index]),
                  onMoveEnd: () => _onMoveEnd(context),
                  onMoveCancel: () => _onMoveCancel(context),
                )
            )
          )
        )
      );
    }

    if (!showTitle) {
      return categoryContent;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CategoryHeader(title: category.name, count: applications.length),
        categoryContent
      ],
    );
  }

  int? _findChildIndex(Key key) {
    if (key is ValueKey<String>) {
      final index = category.applications.indexWhere((app) => app.packageName == key.value);
      return index >= 0 ? index : null;
    }
    return null;
  }

  void _onMove(BuildContext context, AxisDirection direction, App movingApp) {
    final index = category.applications.indexOf(movingApp);
    if (index == -1) return;

    int newIndex = 0;

    if (direction == AxisDirection.right && index < category.applications.length - 1) {
      newIndex = index + 1;
    } else if (direction == AxisDirection.left && index > 0) {
      newIndex = index - 1;
    } else {
      // Ignore UP/DOWN or at boundaries
      return;
    }

    final appsService = context.read<AppsService>();
    appsService.setPendingReorderFocus(movingApp.packageName, category.id);
    appsService.reorderApplication(category, index, newIndex);
  }

  void _onMoveEnd(BuildContext context) {
    final appsService = context.read<AppsService>();
    appsService.saveApplicationOrderInCategory(category);
  }

  void _onMoveCancel(BuildContext context) {
    final appsService = context.read<AppsService>();
    appsService.cancelReorderApplication(category);
  }
}
