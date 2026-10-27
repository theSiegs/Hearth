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

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps the remote's focus in a dialog while it is the top route. A page under it that keeps refreshing can build a
/// tile with autofocus, which takes the focus from any route (and the settings panel then handles the D-pad, closing
/// the page under the dialog, or the dialog itself); focus that leaves this way comes back to [home]. The arrows move
/// between the dialog's own buttons and never leave it.
class HeldFocus extends StatefulWidget {
  /// Where focus goes when it isn't in the dialog: its safe choice.
  final FocusNode Function() home;
  final Widget child;

  const HeldFocus({super.key, required this.home, required this.child});

  @override
  State<HeldFocus> createState() => _HeldFocusState();
}

class _HeldFocusState extends State<HeldFocus> {
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: "HeldFocus");
  bool _queued = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_check);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_check);
    _scope.dispose();
    super.dispose();
  }

  bool get _isTop => ModalRoute.of(context)?.isCurrent ?? true;

  /// Whether the focus is on something inside the dialog (not merely its scope, which takes no keys of its own).
  bool get _held {
    final focus = FocusManager.instance.primaryFocus;
    return focus != null && focus != _scope && focus.ancestors.contains(_scope);
  }

  void _check() {
    if (!mounted || _queued || !_isTop || _held) return;
    // After the frame: the node that took it may be one that is being built or removed right now
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!mounted || !_isTop || _held) return;
      final home = widget.home();
      if (home.context != null && home.canRequestFocus) {
        home.requestFocus();
      } else {
        _scope.requestFocus();
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final TraversalDirection? direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      LogicalKeyboardKey.arrowRight => TraversalDirection.right,
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      _ => null,
    };
    if (direction == null) return KeyEventResult.ignored;
    if (event is! KeyUpEvent) {
      final focus = FocusManager.instance.primaryFocus;
      if (focus == null || !_held || !focus.focusInDirection(direction)) _check();
    }
    // Moved or not, the arrow stays in the dialog: nothing behind it acts on it
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => FocusScope(node: _scope, onKeyEvent: _onKey, child: widget.child);
}
