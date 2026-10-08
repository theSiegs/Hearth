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

import 'dart:typed_data';

import 'package:flauncher/providers/apps_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// An installed app's icon. It's fetched once, not on every rebuild; [placeholder] shows while it loads and when
/// there's no icon.
class AppIcon extends StatefulWidget {
  final String packageName;
  final double size;
  final double borderRadius;

  /// Defaults to the Android robot at [size].
  final Widget? placeholder;

  const AppIcon(this.packageName, {super.key, required this.size, this.borderRadius = 0, this.placeholder});

  @override
  State<AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<AppIcon> {
  late Future<Uint8List> _icon;

  @override
  void initState() {
    super.initState();
    _icon = _load();
  }

  @override
  void didUpdateWidget(AppIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packageName != widget.packageName) {
      _icon = _load();
    }
  }

  Future<Uint8List> _load() => context.read<AppsService>().getAppIcon(widget.packageName);

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
        future: _icon,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) {
            return widget.placeholder ?? Icon(Icons.android, size: widget.size);
          }
          final image = Image.memory(bytes, width: widget.size, height: widget.size, fit: BoxFit.contain);
          return widget.borderRadius == 0
              ? image
              : ClipRRect(borderRadius: BorderRadius.circular(widget.borderRadius), child: image);
        },
      );
}
