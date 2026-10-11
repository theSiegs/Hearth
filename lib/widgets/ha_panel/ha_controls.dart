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

import 'dart:async';

import 'package:flauncher/widgets/focusable_tap.dart';
import 'package:flauncher/widgets/ha_panel/ha_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A round button for the D-pad (a playback button, − and +).
class HaRoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool selected;
  final double size;

  const HaRoundButton(
      {super.key,
      required this.icon,
      required this.label,
      required this.onPressed,
      this.selected = false,
      this.size = 44});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      label: label,
      child: FocusableTap(
        onPressed: onPressed,
        builder: (context, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                selected ? accent.withOpacity(focused ? 0.55 : 0.35) : Colors.white.withOpacity(focused ? 0.2 : 0.08),
            border: Border.all(color: focused ? accent : Colors.transparent, width: 3),
          ),
          child: Icon(icon, size: size * 0.5, color: Colors.white),
        ),
      ),
    );
  }
}

/// A slider for the D-pad: Left and Right move it by [step] while it has the focus, and the value goes to Home
/// Assistant once the presses stop ([onCommit]). What it was moved to shows until Home Assistant's state catches up.
class HaSlider extends StatefulWidget {
  /// 0 to 100.
  final int value;
  final int step;
  final IconData icon;
  final String label;
  final ValueChanged<int> onCommit;
  final Duration settle;

  const HaSlider({
    super.key,
    required this.value,
    required this.icon,
    required this.label,
    required this.onCommit,
    this.step = 5,
    this.settle = const Duration(milliseconds: 400),
  });

  @override
  State<HaSlider> createState() => _HaSliderState();
}

class _HaSliderState extends State<HaSlider> {
  int? _pending;
  Timer? _commit;
  Timer? _forget;
  bool _focused = false;

  int get _value => _pending ?? widget.value;

  @override
  void didUpdateWidget(HaSlider old) {
    super.didUpdateWidget(old);
    if (_pending != null && widget.value == _pending && _commit == null) _pending = null;
  }

  @override
  void dispose() {
    _commit?.cancel();
    _forget?.cancel();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final left = event.logicalKey == LogicalKeyboardKey.arrowLeft;
    final right = event.logicalKey == LogicalKeyboardKey.arrowRight;
    if (!left && !right) return KeyEventResult.ignored;
    if (event is KeyUpEvent) return KeyEventResult.handled;
    final next = (_value + (right ? widget.step : -widget.step)).clamp(0, 100);
    setState(() => _pending = next);
    _commit?.cancel();
    _commit = Timer(widget.settle, () {
      _commit = null;
      widget.onCommit(next);
      // Home Assistant may round it, or not take it: its own value shows again after a while
      _forget?.cancel();
      _forget = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _pending = null);
      });
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final text = Theme.of(context).textTheme;
    return Semantics(
      slider: true,
      label: widget.label,
      value: "$_value%",
      child: Focus(
        onKeyEvent: _onKey,
        onFocusChange: (f) => setState(() => _focused = f),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: haFocusDecoration(context, _focused, radius: 14),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: Colors.white70),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _value / 100,
                    minHeight: _focused ? 12 : 8,
                    backgroundColor: Colors.white.withOpacity(0.12),
                    valueColor: AlwaysStoppedAnimation(_focused ? accent : Colors.white70),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 44,
                child: Text("$_value%", textAlign: TextAlign.end, style: text.bodySmall!.copyWith(color: Colors.white)),
              ),
              if (_focused) ...[
                const SizedBox(width: 4),
                const Icon(Icons.unfold_more, size: 16, color: Colors.white54),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// − and + round a value (a thermostat's target): each press moves what shows at once, and the value goes to Home
/// Assistant once the presses stop.
class HaStepper extends StatefulWidget {
  final double value;
  final double step;
  final String Function(double value) format;
  final double Function(double value) clamp;
  final ValueChanged<double> onCommit;
  final String? caption;
  final String decreaseLabel;
  final String increaseLabel;
  final Duration settle;

  const HaStepper({
    super.key,
    required this.value,
    required this.step,
    required this.format,
    required this.clamp,
    required this.onCommit,
    this.caption,
    this.decreaseLabel = "−",
    this.increaseLabel = "+",
    this.settle = const Duration(seconds: 1),
  });

  @override
  State<HaStepper> createState() => _HaStepperState();
}

class _HaStepperState extends State<HaStepper> {
  double? _pending;
  Timer? _commit;
  Timer? _forget;

  double get _value => _pending ?? widget.value;

  @override
  void didUpdateWidget(HaStepper old) {
    super.didUpdateWidget(old);
    if (_pending != null && widget.value == _pending && _commit == null) _pending = null;
  }

  @override
  void dispose() {
    _commit?.cancel();
    _forget?.cancel();
    super.dispose();
  }

  void _press(double delta) {
    final next = widget.clamp(_value + delta);
    setState(() => _pending = next);
    _commit?.cancel();
    _commit = Timer(widget.settle, () {
      _commit = null;
      widget.onCommit(next);
      _forget?.cancel();
      _forget = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _pending = null);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        HaRoundButton(icon: Icons.remove, label: widget.decreaseLabel, onPressed: () => _press(-widget.step)),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.caption != null)
                Text(widget.caption!, style: text.labelSmall!.copyWith(color: Colors.white60)),
              Text(widget.format(_value),
                  textAlign: TextAlign.center,
                  style: text.headlineSmall!.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        HaRoundButton(icon: Icons.add, label: widget.increaseLabel, onPressed: () => _press(widget.step)),
      ],
    );
  }
}

/// A gauge under a tile's state (a percentage on its way to done).
class HaBarGauge extends StatelessWidget {
  /// 0 to 1.
  final double fraction;

  const HaBarGauge({super.key, required this.fraction});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: fraction.clamp(0, 1),
          minHeight: 10,
          backgroundColor: Colors.white.withOpacity(0.12),
          valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary),
        ),
      );
}
