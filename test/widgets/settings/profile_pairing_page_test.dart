import 'package:flauncher/widgets/settings/profile_pairing_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PairingChoice choice(String mode, {String? chosen, String? auto}) => PairingChoice.fromMap({
        "hearthProfile": "Alex",
        "kids": false,
        "mode": mode,
        "chosenProfile": chosen,
        "autoMatch": auto,
      });

  test("summaries say what Hearth will pick", () {
    expect(choice("auto", auto: "Alex Morgan").summary, "Alex Morgan (matched by name)");
    expect(choice("auto").summary, "No match yet: shows the picker");
    expect(choice("profile", chosen: "Grown Ups").summary, "Grown Ups");
    expect(choice("picker").summary, "Always show the picker");
  });

  test("a missing mode means match by name", () {
    final parsed = PairingChoice.fromMap({"hearthProfile": "Jordan", "kids": true});
    expect(parsed.mode, "auto");
    expect(parsed.kids, isTrue);
  });
}
