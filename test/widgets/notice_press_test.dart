import 'package:flauncher/widgets/notice_press.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("a Hearth notice's button", () {
    test("the press comes from the Java side's map, and asks phones only with phone approval on", () {
      final press = NoticePress.from({"person": "", "item": "ha:1", "index": 0, "title": "Out of time", "button": "+15"});
      expect(press?.item, "ha:1");
      expect(press?.phone, isFalse);
      expect(NoticePress.from({"person": "", "item": "ha:1", "index": 0, "phone": true})?.phone, isTrue);
      expect(NoticePress.from({"item": "ha:1"}), isNull);
    });

    test("a wrong PIN asks the phones only when Home Assistant has no Parent PIN, unlocked, and not asked yet", () {
      final noPin = {"result": "wrong_pin", "retryAfter": 0, "noParentPin": true};
      expect(offerPhoneAfterWrongPin(noPin, asked: false), isTrue);
      // One request per pad
      expect(offerPhoneAfterWrongPin(noPin, asked: true), isFalse);
      // Home Assistant has PINs: it was just a wrong one
      expect(offerPhoneAfterWrongPin({"result": "wrong_pin", "retryAfter": 0, "noParentPin": false}, asked: false),
          isFalse);
      // Locked out there
      expect(offerPhoneAfterWrongPin({"result": "wrong_pin", "retryAfter": 30, "noParentPin": true}, asked: false),
          isFalse);
    });
  });
}
