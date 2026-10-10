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

import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/cached_blur_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// One dot in the setup flow's progress strip.
enum SetupDot { todo, here, done, skipped }

/// A group in the progress strip: the essentials, or one card, with its dots and, while its steps run, how far along
/// it is ("1/2").
class SetupStripGroup {
  final String label;
  final List<SetupDot> dots;
  final String? progress;

  const SetupStripGroup(this.label, this.dots, {this.progress});
}

/// The setup flow's page: the home's wallpaper blurred and dimmed, the progress strip and Finish later across the
/// top, and one card in the middle holding the current screen.
class SetupFrame extends StatelessWidget {
  /// Null: no strip (a single screen, like the lost Home button).
  final List<SetupStripGroup>? strip;

  /// Null: no Finish later button.
  final String? finishLaterLabel;
  final VoidCallback? onFinishLater;
  final Widget child;

  /// The home shows through clearly (no blur, little dimming): the look screen previews it.
  final bool preview;

  const SetupFrame(
      {super.key, this.strip, this.finishLaterLabel, this.onFinishLater, required this.child, this.preview = false});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Tests and an unusual start may have no wallpaper to blur
    final hasWallpaper = Provider.of<WallpaperService?>(context, listen: false) != null;
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: preview
                ? const SizedBox.expand()
                : hasWallpaper
                    ? const CachedBlurBackdrop(sigma: 18, child: SizedBox.expand())
                    : const ColoredBox(color: Color(0xFF0A0A0A)),
          ),
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              color: Colors.black.withOpacity(preview ? 0.15 : 0.55),
            ),
          ),
          // While previewing, the home's own top bar would show through under the strip
          if (preview)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 160,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black, Color(0xE6000000), Colors.transparent],
                    stops: [0, 0.6, 1],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 24, 48, 24),
            child: Column(
              children: [
                SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      if (strip != null) Expanded(child: SetupProgressStrip(groups: strip!)) else const Spacer(),
                      if (onFinishLater != null && finishLaterLabel != null)
                        SetupButton(label: finishLaterLabel!, onPressed: onFinishLater!, compact: true),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Center(
                    child: Container(
                      width: (size.width - 96).clamp(320, 760).toDouble(),
                      constraints: BoxConstraints(maxHeight: size.height - 120),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F0F0F),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.10)),
                        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 32)],
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Where the flow is, across the top: "Essentials ● ●   Watching ◉   Updates ○". Not focusable.
class SetupProgressStrip extends StatelessWidget {
  final List<SetupStripGroup> groups;

  const SetupProgressStrip({super.key, required this.groups});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    const labelStyle = TextStyle(color: Colors.white70, fontSize: 12);
    return ExcludeFocus(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final group in groups) ...[
              Text(group.label, style: labelStyle),
              const SizedBox(width: 6),
              for (final dot in group.dots) ...[
                _dot(dot, accent),
                const SizedBox(width: 3),
              ],
              if (group.progress != null) Text(group.progress!, style: labelStyle.copyWith(color: accent)),
              const SizedBox(width: 18),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dot(SetupDot dot, Color accent) {
    final (Color fill, Color border) = switch (dot) {
      SetupDot.done => (accent, accent),
      SetupDot.here => (accent.withOpacity(0.35), Colors.white),
      SetupDot.skipped => (Colors.transparent, Colors.white38),
      SetupDot.todo => (Colors.transparent, Colors.white70),
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: dot == SetupDot.skipped ? 1 : 1.5),
      ),
    );
  }
}

/// A button in the setup flow, made for the remote: filled with the accent colour when it has focus.
class SetupButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool autofocus;
  final IconData? icon;

  /// The small kind, for Finish later and the links under Welcome.
  final bool compact;

  const SetupButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.focusNode,
    this.autofocus = false,
    this.icon,
    this.compact = false,
  });

  @override
  State<SetupButton> createState() => _SetupButtonState();
}

class _SetupButtonState extends State<SetupButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    // Black on a pale accent (white, yellow…), white on the rest
    final onAccent = ThemeData.estimateBrightnessForColor(accent) == Brightness.light ? Colors.black : Colors.white;
    final compact = widget.compact;
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
          if (focused) Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 100));
        },
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20, vertical: compact ? 6 : 10),
            decoration: BoxDecoration(
              color: _focused ? accent : Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(compact ? 8 : 12),
              border: Border.all(color: _focused ? Colors.white : Colors.transparent, width: 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: compact ? 14 : 18, color: _focused ? onAccent : Colors.white70),
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    color: _focused ? onAccent : Colors.white,
                    fontSize: compact ? 12 : 15,
                    fontWeight: _focused ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A screen of the flow inside the card: an icon and title, what it's about, whatever the screen shows, and its
/// buttons along the bottom (the main one last, on the right, where focus starts).
class SetupScreenBody extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String? body;
  final List<Widget> content;
  final List<Widget> buttons;

  /// Lines under the buttons: a footnote, links.
  final List<Widget> below;

  const SetupScreenBody({
    super.key,
    this.icon,
    this.iconColor,
    required this.title,
    this.body,
    this.content = const [],
    required this.buttons,
    this.below = const [],
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 28, color: iconColor ?? Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
            ],
            Expanded(child: Text(title, style: textTheme.headlineSmall?.copyWith(color: Colors.white))),
          ],
        ),
        if (body != null) ...[
          const SizedBox(height: 12),
          Text(body!, style: textTheme.bodyLarge?.copyWith(color: Colors.white70, height: 1.35)),
        ],
        for (final child in content) ...[const SizedBox(height: 14), child],
        const SizedBox(height: 24),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Wrap(spacing: 12, runSpacing: 12, children: buttons),
        ),
        for (final line in below) ...[const SizedBox(height: 12), line],
      ],
    );
  }
}

/// "On the next screen": what to select on Android's screen, in numbered steps, since Google TV can't open (or
/// highlight) the exact switch.
class SetupStepsPicture extends StatelessWidget {
  final String heading;
  final List<String> steps;

  const SetupStepsPicture({super.key, required this.heading, required this.steps});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (index, step) in steps.indexed) ...[
              if (index > 0)
                const Padding(
                  padding: EdgeInsets.only(top: 14),
                  child: Icon(Icons.arrow_forward, size: 16, color: Colors.white38),
                ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 11,
                        backgroundColor: accent,
                        child: Text("${index + 1}",
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(step, style: const TextStyle(color: Colors.white, fontSize: 13))),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Commands to type on a computer, in a box. Selectable, though the remote can't copy them.
class SetupCommandBox extends StatelessWidget {
  final String? heading;
  final List<String> lines;
  final String? note;

  const SetupCommandBox({super.key, this.heading, required this.lines, this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (heading != null) ...[
            Text(heading!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 6),
          ],
          for (final line in lines)
            SelectableText(line,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.amberAccent)),
          if (note != null) ...[
            const SizedBox(height: 6),
            Text(note!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

/// A bullet list ("• follow profile switches…").
class SetupBullets extends StatelessWidget {
  final List<String> items;
  final IconData? icon;
  final Color? iconColor;

  const SetupBullets({super.key, required this.items, this.icon, this.iconColor});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  icon == null
                      ? const Padding(
                          padding: EdgeInsets.fromLTRB(4, 0, 8, 0),
                          child: Text("•", style: TextStyle(color: Colors.white70, fontSize: 15)),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(right: 8, top: 1),
                          child: Icon(icon, size: 16, color: iconColor ?? Colors.white70),
                        ),
                  Expanded(child: Text(item, style: const TextStyle(color: Colors.white, fontSize: 14))),
                ],
              ),
            ),
        ],
      );
}

/// An on/off row in the setup flow, made for the remote: OK flips it.
class SetupSwitch extends StatefulWidget {
  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final FocusNode? focusNode;
  final bool autofocus;

  const SetupSwitch({
    super.key,
    required this.label,
    this.description,
    required this.value,
    required this.onChanged,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<SetupSwitch> createState() => _SetupSwitchState();
}

class _SetupSwitchState extends State<SetupSwitch> {
  bool _focused = false;

  void _flip() => widget.onChanged(!widget.value);

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _flip()),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => _flip()),
      },
      child: Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: GestureDetector(
          onTap: _flip,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _focused ? Colors.white.withOpacity(0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _focused ? accent : Colors.transparent, width: 2),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.label, style: const TextStyle(color: Colors.white, fontSize: 15)),
                      if (widget.description != null)
                        Text(widget.description!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Shows the state only; the row takes the presses
                ExcludeFocus(child: IgnorePointer(child: Switch(value: widget.value, onChanged: (_) {}))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the look screen's choices, made for the remote: a small picture of the home (its wallpaper, a row of
/// cards in the look's accent) over its name. Focusing it previews the look; OK chooses it.
class SetupLookTile extends StatefulWidget {
  final String label;

  /// The wallpaper: a gradient, or null for a picture (the photo of the day).
  final Gradient? gradient;
  final Color accent;

  /// A quiet line under the name ("Now").
  final String? note;
  final VoidCallback onFocused;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool autofocus;

  const SetupLookTile({
    super.key,
    required this.label,
    required this.gradient,
    required this.accent,
    this.note,
    required this.onFocused,
    required this.onPressed,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<SetupLookTile> createState() => _SetupLookTileState();
}

class _SetupLookTileState extends State<SetupLookTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final gradient = widget.gradient;
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
          if (focused) widget.onFocused();
        },
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _focused ? 1.05 : 1,
            duration: const Duration(milliseconds: 120),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    decoration: BoxDecoration(
                      // The photo of the day: a sky, with a picture sign on it
                      gradient: gradient ??
                          const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFF4A7AB5), Color(0xFF9BC1D9), Color(0xFF5E7D4A)],
                          ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _focused ? accent : Colors.white24, width: _focused ? 3 : 1),
                    ),
                    child: Stack(
                      children: [
                        if (gradient == null)
                          const Center(child: Icon(Icons.landscape_outlined, color: Colors.white70, size: 28)),
                        // A row of app cards, the first one focused in the look's accent
                        Positioned(
                          left: 10,
                          right: 10,
                          bottom: 10,
                          child: Row(
                            children: [
                              for (int i = 0; i < 3; i++) ...[
                                Expanded(
                                  child: AspectRatio(
                                    aspectRatio: 16 / 9,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.45),
                                        borderRadius: BorderRadius.circular(4),
                                        border: i == 0 ? Border.all(color: widget.accent, width: 2) : null,
                                      ),
                                    ),
                                  ),
                                ),
                                if (i < 2) const SizedBox(width: 6),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(widget.label,
                    style: TextStyle(
                        color: _focused ? Colors.white : Colors.white70,
                        fontSize: 14,
                        fontWeight: _focused ? FontWeight.w600 : FontWeight.normal)),
                if (widget.note != null)
                  Text(widget.note!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
