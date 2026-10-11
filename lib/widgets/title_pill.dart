import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// A row title on the wallpaper, on a dark rounded pill so it reads on any picture: barely there on a dark
/// wallpaper, darker the lighter the wallpaper is.
class TitlePill extends StatelessWidget {
  final Widget child;

  const TitlePill({super.key, required this.child});

  /// The shadow under a title's text on the pill.
  static const List<Shadow> textShadow = [Shadow(color: Color(0xE6000000), offset: Offset(0, 1), blurRadius: 4)];

  /// The pill's black opacity for a background [brightness] (0-1): 25% up to a dark 0.2, 60% from a light 0.7.
  static double opacityFor(double brightness) => 0.25 + 0.35 * ((brightness - 0.2) / 0.5).clamp(0.0, 1.0);

  /// The pill's opacity for the wallpaper behind [context]'s home; a middle one where there's none (a settings
  /// preview, a test).
  static double opacityOf(BuildContext context) {
    try {
      return opacityFor(context.select<WallpaperService?, double>((w) => w?.brightness ?? 0.5));
    } catch (_) {
      return opacityFor(0.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(opacityOf(context)),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4), child: child),
    );
  }
}

/// The top bar's pills (the profile's name, data used, the weather, the date and time): one height and one look,
/// darker on a light wallpaper like the row titles' pills ([TitlePill.opacityOf]). Focused, the accent rings it.
class StatusPill extends StatelessWidget {
  static const double height = 44;

  final Widget child;
  final bool focused;

  const StatusPill({super.key, required this.child, this.focused = false});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(TitlePill.opacityOf(context)),
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(
          color: focused ? Theme.of(context).colorScheme.primary : Colors.white.withOpacity(0.12),
          width: 1,
        ),
        boxShadow: focused ? const [BoxShadow(color: Colors.black54, blurRadius: 8, spreadRadius: 1)] : null,
      ),
      child: child,
    );
  }
}

/// A dark fade rising from the bottom of the screen behind Continue Watching's and search's title and details (as
/// HearthTube's details scrim), so they read on any wallpaper. Like [TitlePill] it follows the wallpaper: lighter on
/// a dark picture, up to HearthTube's strength on a light one.
class DetailsScrim extends StatelessWidget {
  final bool visible;

  const DetailsScrim({super.key, required this.visible});

  /// The fade's black opacity at the bottom edge for a background [brightness] (0-1): 0.5 up to a dark 0.2, 0.9 from
  /// a light 0.7.
  static double bottomOpacityFor(double brightness) => 0.5 + 0.4 * ((brightness - 0.2) / 0.5).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    double brightness = 0.5;
    try {
      brightness = context.select<WallpaperService?, double>((w) => w?.brightness ?? 0.5);
    } catch (_) {}
    final double a = bottomOpacityFor(brightness);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 250),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black.withOpacity(a), Colors.black.withOpacity(a * 0.78), Colors.transparent],
              stops: const [0, 0.38, 0.62],
            ),
          ),
        ),
      ),
    );
  }
}
