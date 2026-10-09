import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/update_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("each update error has its own message in the app's language", () async {
    final english = await AppLocalizations.delegate.load(const Locale('en'));
    final french = await AppLocalizations.delegate.load(const Locale('fr'));

    expect(UpdateError.noApkForDevice.message(english), "No release has an APK for this device");
    expect(UpdateError.checkFailed.message(english), "Couldn't check for updates");
    expect(UpdateError.downloadFailed.message(english), "Couldn't download the update");
    expect(UpdateError.values.map((e) => e.message(french)).toSet(), hasLength(UpdateError.values.length));
    expect(UpdateError.downloadFailed.message(french), "Impossible de télécharger la mise à jour");
  });
}
