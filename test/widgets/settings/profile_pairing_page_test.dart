import 'package:flauncher/l10n/app_localizations_en.dart';
import 'package:flauncher/widgets/settings/profile_pairing_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l = AppLocalizationsEn();

  PairingChoice choice(String mode, {String? chosen, String? auto}) => PairingChoice.fromMap({
        "hearthProfile": "Alex",
        "kids": false,
        "mode": mode,
        "chosenProfile": chosen,
        "autoMatch": auto,
      });

  test("summaries say what Hearth will pick", () {
    expect(choice("auto", auto: "Alex Morgan").summary(l), "Alex Morgan (matched by name)");
    expect(choice("auto").summary(l), "No match yet: shows the picker");
    expect(choice("profile", chosen: "Grown Ups").summary(l), "Grown Ups");
    expect(choice("picker").summary(l), "Always show the picker");
  });

  test("a missing mode means match by name", () {
    final parsed = PairingChoice.fromMap({"hearthProfile": "Jordan", "kids": true});
    expect(parsed.mode, "auto");
    expect(parsed.kids, isTrue);
  });
}
