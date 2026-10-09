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
