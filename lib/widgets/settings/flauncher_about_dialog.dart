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
import 'package:flauncher/providers/settings_service.dart';

class HearthAboutDialog extends StatelessWidget {
  final PackageInfo packageInfo;

  const HearthAboutDialog({
    Key? key,
    required this.packageInfo,
  }) : super(key: key);

  Color _hexToColor(String hex) {
    return Color(int.parse('FF$hex', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final settingsService = context.watch<SettingsService>();
    final accentColor = _hexToColor(settingsService.accentColorHex);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Container(
        width: 380,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F0F),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.12),
            width: 1,
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Clean App Icon
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

              // Title & Version
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

              // About info description
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

              _AboutButton(
                icon: Icons.code,
                iconColor: Colors.white70,
                label: "Hearth on GitHub",
                accentColor: accentColor,
                autofocus: true,
                onPressed: () => FLauncherChannel().openUrl("https://github.com/theSiegs/Hearth"),
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
              _AboutButton(
                icon: Icons.call_split,
                iconColor: Colors.white70,
                label: "LTvLauncher · LeanBitLab",
                accentColor: accentColor,
                onPressed: () => FLauncherChannel().openUrl("https://github.com/leanbitlab-org/LtvLauncher"),
              ),
              const SizedBox(height: 6),
              _AboutButton(
                icon: Icons.dock,
                iconColor: Colors.white70,
                label: "Arc Launcher · Badis Meddouri",
                accentColor: accentColor,
                onPressed: () => FLauncherChannel().openUrl("https://github.com/meddouribadis/arclauncher"),
              ),
              const SizedBox(height: 6),
              _AboutButton(
                icon: Icons.history,
                iconColor: Colors.white70,
                label: "FLauncher · Étienne Fesser",
                accentColor: accentColor,
                onPressed: () => FLauncherChannel().openUrl("https://gitlab.com/flauncher/flauncher"),
              ),
              const SizedBox(height: 6),
              _AboutButton(
                icon: Icons.history,
                iconColor: Colors.white70,
                label: "FLauncher fork · osrosal",
                accentColor: accentColor,
                onPressed: () => FLauncherChannel().openUrl("https://github.com/osrosal/flauncher"),
              ),
              const SizedBox(height: 10),

              const Text(
                "Free software under the GNU GPL v3, like the projects it builds on.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
              const SizedBox(height: 6),

              // Close Action
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  "Close",
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutButton extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color accentColor;
  final VoidCallback onPressed;
  final bool autofocus;

  const _AboutButton({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.accentColor,
    required this.onPressed,
    this.autofocus = false,
  });

  @override
  State<_AboutButton> createState() => _AboutButtonState();
}

class _AboutButtonState extends State<_AboutButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed()),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => widget.onPressed()),
      },
      child: Focus(
        autofocus: widget.autofocus,
        onFocusChange: (hasFocus) => setState(() => _focused = hasFocus),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _focused ? widget.accentColor.withOpacity(0.2) : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _focused ? Colors.white : Colors.transparent,
                width: _focused ? 2 : 0,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, size: 16, color: _focused ? Colors.white : widget.iconColor),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: _focused ? FontWeight.bold : FontWeight.w500,
                  ),
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
