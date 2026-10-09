import 'package:flauncher/gradients.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("every gradient's name is translated, and is its English name in English", () async {
    final english = await AppLocalizations.delegate.load(const Locale('en'));
    final german = await AppLocalizations.delegate.load(const Locale('de'));
    for (final gradient in FLauncherGradients.all) {
      expect(gradient.localizedName(english), gradient.name);
    }
    final germanNames = FLauncherGradients.all.map((g) => g.localizedName(german)).toSet();
    expect(germanNames, hasLength(FLauncherGradients.all.length));
    expect(FLauncherGradients.greatWhale.localizedName(german), "Großer Wal");
  });
}
