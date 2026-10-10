/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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
import 'package:flauncher/providers/launcher_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'flauncher.dart';
import 'widgets/setup/setup_flow_launcher.dart';
import 'providers/home_search.dart';

/// Cards and dialogs.
const Color _surfaceColor = Color(0xFF0F0F0F);

/// Behind them: the page and the canvas.
const Color _backgroundColor = Color(0xFF0A0A0A);

class FLauncherApp extends StatelessWidget
{
  static const PrioritizedIntents _backIntents = PrioritizedIntents(orderedIntents: [
    DismissIntent(),
    BackIntent()
  ]);

  static final Typography _typography = Typography.material2018();

  const FLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<SettingsService, (Color, Locale?)>(
      selector: (_, settings) => (settings.accentColor, settings.appLocale),
      builder: (context, tuple, _) {
        final accentColor = tuple.$1;
        final appLocale = tuple.$2;

        return MaterialApp(
          locale: appLocale,
          scrollBehavior: const MaterialScrollBehavior().copyWith(
            overscroll: false,
          ),
          shortcuts: {
            ...WidgetsApp.defaultShortcuts,
            const SingleActivator(LogicalKeyboardKey.escape): _backIntents,
            const SingleActivator(LogicalKeyboardKey.gameButtonB): _backIntents,
            const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
            const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
            const SingleActivator(LogicalKeyboardKey.numpadEnter): const ActivateIntent(),
            const SingleActivator(LogicalKeyboardKey.gameButtonA): const ActivateIntent(),
            const SingleActivator(LogicalKeyboardKey.gameButtonSelect): const ActivateIntent(),
          },
          actions: {
            ...WidgetsApp.defaultActions,
            BackIntent: BackAction(context),
            DirectionalFocusIntent: SoundFeedbackDirectionalFocusAction(context)
          },
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          title: 'Hearth',
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: accentColor,
              brightness: Brightness.dark,
              primary: accentColor,
              secondary: accentColor,
              surface: _surfaceColor,
            ),
            cardColor: _surfaceColor,
            canvasColor: _backgroundColor,
            dialogBackgroundColor: _surfaceColor,
            scaffoldBackgroundColor: _backgroundColor,
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                splashFactory: NoSplash.splashFactory,
              ),
            ),
            dialogTheme: DialogTheme(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: _surfaceColor,
              titleTextStyle: _typography.white.titleLarge,
              contentTextStyle: _typography.white.bodyMedium,
            ),
            appBarTheme: const AppBarTheme(elevation: 0, backgroundColor: Colors.transparent),
            typography: _typography,
            inputDecorationTheme: InputDecorationTheme(
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
              labelStyle: _typography.white.bodyMedium,
            ),
            textSelectionTheme: TextSelectionThemeData(
              cursorColor: accentColor,
              selectionColor: accentColor.withOpacity(0.4),
              selectionHandleColor: accentColor,
            ),
            indicatorColor: accentColor,
            progressIndicatorTheme: ProgressIndicatorThemeData(color: accentColor),
            sliderTheme: SliderThemeData(
              activeTrackColor: accentColor,
              thumbColor: accentColor,
              inactiveTrackColor: accentColor.withOpacity(0.3),
            ),
            toggleButtonsTheme: ToggleButtonsThemeData(
              selectedColor: accentColor,
              fillColor: accentColor.withOpacity(0.1),
            ),
            switchTheme: SwitchThemeData(
              thumbColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return accentColor;
                return null;
              }),
              trackColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return accentColor.withOpacity(0.5);
                return null;
              }),
            ),
          ),
          home: Builder(
            builder: (context) => PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                // A search closes first (the box, then the search itself)
                if (context.read<HomeSearch?>()?.backHandler?.call() ?? false) return;
                LauncherState launcherState = context.read<LauncherState>();
                launcherState.handleBackNavigation(context);
              },
              child: SetupFlowLauncher(child: FLauncher()),
            ),
          ),
        );
      },
    );
  }
}
