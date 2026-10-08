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

import 'package:flauncher/actions.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// The row-edge keys and the press and bump animations of a home screen card.
mixin LauncherCardBehavior<T extends StatefulWidget> on State<T>, TickerProvider {
  bool _pressed = false;

  late final AnimationController _bumpController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  late final Animation<double> _bump = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 8.0).chain(CurveTween(curve: Curves.easeOut)), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 8.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 1),
  ]).animate(_bumpController);

  @override
  void dispose() {
    _bumpController.dispose();
    super.dispose();
  }

  /// Handles the keys that leave a row: Left from its first card opens Settings, Right from its last
  /// opens the Home Assistant panel when that's on (otherwise the card nudges to show the end), and
  /// Up from the top row goes to the top bar. Returns null for any other key.
  KeyEventResult? onEdgeKey(
    LogicalKeyboardKey key, {
    required bool isFirstInRow,
    required bool isLastInRow,
    required bool upGoesToTopBar,
  }) {
    if (key == LogicalKeyboardKey.arrowLeft && isFirstInRow) {
      Actions.maybeInvoke(context, const OpenSettingsIntent());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight && isLastInRow) {
      if (context.read<SettingsService>().haPanelEnabled) {
        Actions.maybeInvoke(context, const OpenHaPanelIntent());
      } else if (!_bumpController.isAnimating) {
        _bumpController.forward(from: 0.0);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && upGoesToTopBar) {
      Actions.invoke(context, const MoveFocusToTopBarIntent());
      return KeyEventResult.handled;
    }
    return null;
  }

  /// Shows the press, then runs [action]. The card looks normal again shortly after, ready for when
  /// the user comes back from the app it opened.
  void pressThenRun(VoidCallback action) {
    if (_pressed) return;
    setState(() => _pressed = true);
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      action();
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _pressed = false);
      });
    });
  }

  /// Nudges [child] sideways when Right is pressed at the end of a row.
  Widget bumpable(Widget child) => AnimatedBuilder(
        animation: _bump,
        builder: (context, child) => Transform.translate(offset: Offset(_bump.value, 0), child: child),
        child: child,
      );

  /// Shrinks and dims [child] while the card shows a press.
  Widget pressable(Widget child) => AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.5 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: child,
        ),
      );
}
