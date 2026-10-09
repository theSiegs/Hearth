import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/settings/hearth_about_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks.mocks.dart';

void main() {
  testWidgets("About credits TMDB with its logo and the notice its terms require", (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1600));
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService(await SharedPreferences.getInstance());
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<FLauncherChannel>.value(value: MockFLauncherChannel()),
        ChangeNotifierProvider<SettingsService>.value(value: settings),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: HearthAboutDialog(
            packageInfo: PackageInfo(appName: "Hearth", packageName: "x", version: "1", buildNumber: "1"),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text(HearthAboutDialog.tmdbNotice), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
  });
}
