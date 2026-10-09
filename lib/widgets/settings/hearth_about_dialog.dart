/*
 * FLauncher
 * Copyright (C) 2024 LeanBitLab
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

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:provider/provider.dart';

import 'hearth_dialog.dart';

class HearthAboutDialog extends StatelessWidget {
  final PackageInfo packageInfo;

  /// The notice TMDB's API terms require (section 3), word for word.
  static const String tmdbNotice =
      "This product uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB.";

  const HearthAboutDialog({super.key, required this.packageInfo});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final bing = _bingPhoto(context);
    return HearthDialogFrame(
      width: 380,
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              "assets/icon.png",
              height: 56,
              width: 56,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "Hearth",
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "v${packageInfo.version} (${packageInfo.buildNumber})",
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            localizations.aboutForkOf("LTvLauncher", "LeanBitLab", "Arc Launcher"),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              localizations.aboutDescription,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 14),
          FocusableDialogButton(
            icon: Icons.code,
            label: localizations.aboutHearthOnGitHub,
            autofocus: true,
            onPressed: () => context.read<FLauncherChannel>().openUrl("https://github.com/theSiegs/Hearth"),
          ),
          const SizedBox(height: 14),

          // Hearth stands on these projects (all GPL-3.0).
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              localizations.aboutCredits,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 8),
          FocusableDialogButton(
            icon: Icons.call_split,
            label: "LTvLauncher · LeanBitLab",
            onPressed: () => context.read<FLauncherChannel>().openUrl("https://github.com/leanbitlab-org/LtvLauncher"),
          ),
          const SizedBox(height: 6),
          FocusableDialogButton(
            icon: Icons.dock,
            label: "Arc Launcher · Badis Meddouri",
            onPressed: () => context.read<FLauncherChannel>().openUrl("https://github.com/meddouribadis/arclauncher"),
          ),
          const SizedBox(height: 6),
          FocusableDialogButton(
            icon: Icons.history,
            label: "FLauncher · Étienne Fesser",
            onPressed: () => context.read<FLauncherChannel>().openUrl("https://gitlab.com/flauncher/flauncher"),
          ),
          const SizedBox(height: 6),
          FocusableDialogButton(
            icon: Icons.history,
            label: localizations.aboutFlauncherForkCredit("osrosal"),
            onPressed: () => context.read<FLauncherChannel>().openUrl("https://github.com/osrosal/flauncher"),
          ),
          // TMDB's terms: its logo (less prominent than Hearth's) and this notice, word for word. It's a legal notice,
          // so it stays in English in every language.
          const SizedBox(height: 14),
          Row(
            children: [
              SvgPicture.asset("assets/tmdb_logo.svg", height: 12, semanticsLabel: "TMDB"),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tmdbNotice,
                  style: const TextStyle(color: Colors.white54, fontSize: 10, height: 1.3),
                ),
              ),
            ],
          ),
          // Bing's photo of the day: its title and credit live here, not on the home screen
          if (bing != null) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                localizations.aboutWallpaperPhoto,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                [bing.title, bing.credit].whereType<String>().join("\n"),
                style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            localizations.aboutLicense,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              localizations.close,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// The Bing photo of the day's title and credit while it's the wallpaper; null otherwise (or nothing known).
  static ({String? title, String? credit})? _bingPhoto(BuildContext context) {
    try {
      final wallpaper = context.read<WallpaperService>();
      if (!context.read<SettingsService>().bingWallpaperEnabled || wallpaper.wallpaper == null) return null;
      if (wallpaper.bingTitle == null && wallpaper.bingCredit == null) return null;
      return (title: wallpaper.bingTitle, credit: wallpaper.bingCredit);
    } catch (_) {
      return null;
    }
  }
}
