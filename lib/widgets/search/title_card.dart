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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/apps_service.dart';

/// A wide card in the house style shared with Continue Watching and HearthTube: the picture, the app's icon in the
/// corner, the title and one line of detail over the bottom, an accent ring and a slight lift when focused.
class TitleCard extends StatefulWidget {
  final String title;
  final String detail;
  final String? imageUrl;

  /// The app whose icon sits in the corner (null: none).
  final String? packageName;
  final double width;
  final double height;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback onPressed;
  final ValueChanged<bool>? onFocusChange;

  const TitleCard({
    super.key,
    required this.title,
    required this.detail,
    required this.onPressed,
    this.imageUrl,
    this.packageName,
    this.width = 240,
    this.height = 135,
    this.autofocus = false,
    this.focusNode,
    this.onFocusChange,
  });

  @override
  State<TitleCard> createState() => _TitleCardState();
}

class _TitleCardState extends State<TitleCard> {
  bool _focused = false;
  Uint8List? _icon;

  @override
  void initState() {
    super.initState();
    _loadIcon();
  }

  @override
  void didUpdateWidget(covariant TitleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packageName != widget.packageName) _loadIcon();
  }

  Future<void> _loadIcon() async {
    final pkg = widget.packageName;
    if (pkg == null) {
      if (_icon != null) setState(() => _icon = null);
      return;
    }
    try {
      final bytes = await context.read<AppsService>().getAppIcon(pkg);
      if (mounted && pkg == widget.packageName) setState(() => _icon = bytes.isEmpty ? null : bytes);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final textTheme = Theme.of(context).textTheme;
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed()),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => widget.onPressed()),
      },
      child: Focus(
        autofocus: widget.autofocus,
        focusNode: widget.focusNode,
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          widget.onFocusChange?.call(focused);
          if (focused) Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 120));
        },
        onKeyEvent: (_, event) => KeyEventResult.ignored,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _focused ? 1.06 : 1.0,
            duration: const Duration(milliseconds: 120),
            child: Container(
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2D33),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _focused ? accent : Colors.white.withOpacity(0.08), width: _focused ? 3 : 1),
                boxShadow: _focused ? [BoxShadow(color: accent.withOpacity(0.35), blurRadius: 16)] : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.imageUrl != null)
                    Image.network(widget.imageUrl!,
                        fit: BoxFit.cover,
                        cacheWidth: (widget.width * MediaQuery.devicePixelRatioOf(context)).round(),
                        errorBuilder: (_, __, ___) => const SizedBox.shrink())
                  else
                    const Center(child: Icon(Icons.movie_outlined, size: 40, color: Colors.white24)),
                  if (_icon != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.memory(_icon!, width: 28, height: 28, fit: BoxFit.contain),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                      color: Colors.black.withOpacity(0.65),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleSmall?.copyWith(fontSize: 16, fontWeight: FontWeight.w500)),
                          if (widget.detail.isNotEmpty)
                            Text(widget.detail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodySmall?.copyWith(fontSize: 13, color: Colors.white70)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The card at the end of a row that opens everything ("More results", "See all"), or hands the search on
/// ("Ask Google").
class MoreCard extends StatefulWidget {
  final String label;
  final String detail;
  final double height;

  /// Null: a little wider than tall (height x 1.2).
  final double? width;
  final IconData icon;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;

  const MoreCard(
      {super.key,
      required this.label,
      required this.detail,
      required this.onPressed,
      this.height = 135,
      this.width,
      this.icon = Icons.grid_view_rounded,
      this.focusNode,
      this.autofocus = false,
      this.onFocusChange});

  @override
  State<MoreCard> createState() => _MoreCardState();
}

class _MoreCardState extends State<MoreCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed()),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => widget.onPressed()),
      },
      child: Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          widget.onFocusChange?.call(focused);
          if (focused) Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 120));
        },
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _focused ? 1.06 : 1.0,
            duration: const Duration(milliseconds: 120),
            child: Container(
              width: widget.width ?? widget.height * 1.2,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              height: widget.height,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(_focused ? 0.18 : 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _focused ? accent : Colors.white.withOpacity(0.2), width: _focused ? 3 : 1),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, size: 30, color: Colors.white),
                  const SizedBox(height: 8),
                  Text(widget.label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                  if (widget.detail.isNotEmpty)
                    Text(widget.detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Up from a row, handled by whoever shows it. (Back isn't a key here: Android delivers it as a system "go back",
/// which the home routes to the search.)
KeyEventResult handleKey(KeyEvent event, {VoidCallback? onUp}) {
  if (event is KeyUpEvent) return KeyEventResult.ignored;
  if (onUp != null && event.logicalKey == LogicalKeyboardKey.arrowUp) {
    if (event is KeyDownEvent) onUp();
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}
