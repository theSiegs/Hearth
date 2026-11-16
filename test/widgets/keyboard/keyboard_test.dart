import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/widgets/keyboard/hearth_keyboard.dart';
import 'package:flauncher/widgets/keyboard/keyboard_choice.dart';
import 'package:flauncher/widgets/settings/remote_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _channel = MethodChannel('me.efesser.flauncher/method');

/// Answers the keyboard calls as a TV whose keyboard is [kind], with or without a phone remote there and the
/// permission to switch; records the calls in [calls].
void _fakeTv(List<String> calls,
    {required String kind, bool phone = false, bool canSwitch = false, bool switches = true, String? said}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
    calls.add(call.method);
    return switch (call.method) {
      "getKeyboardStatus" => {
          "kind": kind,
          "phone": phone,
          "canSwitch": canSwitch,
          "onScreen": "com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME",
        },
      "useOnScreenKeyboard" => switches,
      "voiceSearch" => said,
      _ => null,
    };
  });
}

Widget _app(Widget child) => Provider<FLauncherChannel>.value(
      value: FLauncherChannel(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  tearDown(() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));

  group("which keyboard a field gets", () {
    const gboard = "com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME";

    test("the TV's own when it is on screen, or when Hearth can't tell", () {
      expect(keyboardWayFor(const KeyboardStatus(kind: "onscreen")), KeyboardWay.system);
      expect(keyboardWayFor(KeyboardStatus.unknown), KeyboardWay.system);
    });

    test("a phone's keyboard is never the default: Hearth's own, or the on-screen one put back", () {
      expect(keyboardWayFor(const KeyboardStatus(kind: "phone")), KeyboardWay.hearth);
      expect(keyboardWayFor(const KeyboardStatus(kind: "phone", phone: true)), KeyboardWay.hearth);
      expect(keyboardWayFor(const KeyboardStatus(kind: "phone", canSwitch: true, onScreenId: gboard)),
          KeyboardWay.systemAfterSwitch);
      // A phone remote is there: its keyboard stays the TV's, and Hearth shows its own (with the phone offered)
      expect(keyboardWayFor(const KeyboardStatus(kind: "phone", phone: true, canSwitch: true, onScreenId: gboard)),
          KeyboardWay.hearth);
      // Nothing on screen to put back
      expect(keyboardWayFor(const KeyboardStatus(kind: "phone", canSwitch: true)), KeyboardWay.hearth);
    });

    test("voice-only or no keyboard: Hearth's own", () {
      expect(keyboardWayFor(const KeyboardStatus(kind: "voice")), KeyboardWay.hearth);
      expect(keyboardWayFor(const KeyboardStatus(kind: "none")), KeyboardWay.hearth);
    });

    testWidgets("puts the on-screen keyboard back when it may, else falls back to Hearth's own", (tester) async {
      final calls = <String>[];
      _fakeTv(calls, kind: "phone", canSwitch: true);
      expect((await chooseKeyboard(FLauncherChannel())).way, KeyboardWay.systemAfterSwitch);
      expect(calls, ["getKeyboardStatus", "useOnScreenKeyboard"]);

      calls.clear();
      _fakeTv(calls, kind: "phone", canSwitch: true, switches: false);
      expect((await chooseKeyboard(FLauncherChannel())).way, KeyboardWay.hearth);
    });

    testWidgets("a phone remote there is left alone", (tester) async {
      final calls = <String>[];
      _fakeTv(calls, kind: "phone", phone: true, canSwitch: true);
      final choice = await chooseKeyboard(FLauncherChannel());
      expect(choice.way, KeyboardWay.hearth);
      expect(choice.status.phone, isTrue);
      expect(calls, isNot(contains("useOnScreenKeyboard")));
    });

    test("no channel: the TV's keyboard as before", () async {
      expect((await chooseKeyboard(null)).way, KeyboardWay.system);
    });
  });

  group("Hearth's keyboard", () {
    Future<TextEditingController> pump(WidgetTester tester,
        {VoidCallback? onPhone, VoidCallback? onAction, bool numeric = false}) async {
      final text = TextEditingController();
      addTearDown(text.dispose);
      await tester.pumpWidget(_app(HearthKeyboard(
        controller: text,
        numeric: numeric,
        actionLabel: "Search",
        onAction: onAction ?? () {},
        onVoice: () {},
        onPhone: onPhone,
      )));
      return text;
    }

    testWidgets("types, deletes and capitalises into the field's text", (tester) async {
      final text = await pump(tester);
      await tester.tap(find.bySemanticsLabel("Capital letter"));
      await tester.pump();
      await tester.tap(find.text("D"));
      await tester.pump();
      for (final c in ["u", "n", "e", "e"]) {
        await tester.tap(find.text(c));
        await tester.pump();
      }
      expect(text.text, "Dunee");
      await tester.tap(find.bySemanticsLabel("Delete"));
      await tester.pump();
      await tester.tap(find.text("Space"));
      await tester.pump();
      await tester.tap(find.text("2"));
      await tester.pump();
      expect(text.text, "Dune 2");
    });

    testWidgets("numbers and symbols for addresses", (tester) async {
      final text = await pump(tester);
      await tester.tap(find.text("?123"));
      await tester.pump();
      for (final c in ["@", ":", "/"]) {
        await tester.tap(find.text(c));
        await tester.pump();
      }
      expect(text.text, "@:/");
      expect(find.text("ABC"), findsOneWidget);
    });

    testWidgets("focus starts on the keys and the remote moves over them", (tester) async {
      final text = await pump(tester);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(text.text, "q");
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(text.text, "qw");
    });

    testWidgets("the phone is offered only when the field says one is there", (tester) async {
      await pump(tester);
      expect(find.text("Type on your phone"), findsNothing);
      var phone = false;
      await pump(tester, onPhone: () => phone = true);
      await tester.tap(find.text("Type on your phone"));
      expect(phone, isTrue);
    });

    testWidgets("digits only for a number", (tester) async {
      final text = await pump(tester, numeric: true);
      expect(find.text("q"), findsNothing);
      await tester.tap(find.text("4"));
      await tester.tap(find.text("0"));
      await tester.pump();
      expect(text.text, "40");
    });
  });

  group("a settings field", () {
    Future<(TextEditingController, List<String>)> pump(WidgetTester tester) async {
      final text = TextEditingController();
      addTearDown(text.dispose);
      final submitted = <String>[];
      await tester.pumpWidget(_app(Column(children: [
        RemoteTextField(
          controller: text,
          textInputAction: TextInputAction.done,
          onSubmitted: submitted.add,
          decoration: const InputDecoration(labelText: "Word"),
        ),
      ])));
      tester.widget<TextField>(find.byType(TextField)).focusNode!.requestFocus();
      await tester.pump();
      return (text, submitted);
    }

    testWidgets("with a phone's keyboard stuck, OK opens Hearth's keyboard over the page", (tester) async {
      final calls = <String>[];
      _fakeTv(calls, kind: "phone");
      final (text, submitted) = await pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(HearthKeyboard), findsOneWidget);
      expect(find.text("The TV's keyboard is set to type on a phone, so this is Hearth's own."), findsOneWidget);
      expect(find.text("Type on your phone"), findsNothing);
      await tester.tap(find.text("o"));
      await tester.tap(find.text("k"));
      await tester.pump();
      await tester.tap(find.text("Done"));
      await tester.pumpAndSettle();
      expect(text.text, "ok");
      expect(submitted, ["ok"]);
      expect(find.byType(HearthKeyboard), findsNothing);
    });

    testWidgets("with the TV's on-screen keyboard, OK edits the field as before", (tester) async {
      final calls = <String>[];
      _fakeTv(calls, kind: "onscreen");
      await pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(HearthKeyboard), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);
    });

    testWidgets("a phone remote there: the phone is offered and hands the field to the TV's keyboard", (tester) async {
      final calls = <String>[];
      _fakeTv(calls, kind: "phone", phone: true);
      await pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Type on your phone"));
      await tester.pumpAndSettle();
      expect(find.byType(HearthKeyboard), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);
    });
  });
}
