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
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:provider/provider.dart';

import 'hearth_dialog.dart';

class HearthAboutDialog extends StatelessWidget {
  final PackageInfo packageInfo;

  const HearthAboutDialog({super.key, required this.packageInfo});

  @override
  Widget build(BuildContext context) {
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
          const Text(
            "A fork of LTvLauncher by LeanBitLab, with parts of Arc Launcher",
            textAlign: TextAlign.center,
            style: TextStyle(
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
            child: const Text(
              "A private, family-friendly launcher for Google TV, with Google TV profiles and Home Assistant built in. Ad-free and tracker-free.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 14),
          FocusableDialogButton(
            icon: Icons.code,
            label: "Hearth on GitHub",
            autofocus: true,
            onPressed: () => context.read<FLauncherChannel>().openUrl("https://github.com/theSiegs/Hearth"),
          ),
          const SizedBox(height: 14),

          // Hearth stands on these projects (all GPL-3.0).
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Credits",
              style: TextStyle(
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
            label: "FLauncher fork · osrosal",
            onPressed: () => context.read<FLauncherChannel>().openUrl("https://github.com/osrosal/flauncher"),
          ),
          const SizedBox(height: 10),
          const Text(
            "Free software under the GNU GPL v3, like the projects it builds on.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 10),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              "Close",
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
