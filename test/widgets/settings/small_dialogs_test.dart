import 'package:flauncher/widgets/settings/adb_command_dialog.dart';
import 'package:flauncher/widgets/settings/message_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'settings_test_app.dart';

/// A page whose button runs [open] with its context.
Widget _opener(Future<void> Function(BuildContext context) open) => Builder(
      builder: (context) => TextButton(onPressed: () => open(context), child: const Text("open")),
    );

void main() {
  group("showMessageDialog", () {
    testWidgets("shows the title and message with OK focused; OK closes it with true", (tester) async {
      bool? result;
      await tester.pumpWidget(settingsTestApp(await freshSettings(), _opener((context) async {
        result = await showMessageDialog(context, title: "Done", message: "The TV is set up.");
      })));
      await tester.tap(find.text("open"));
      await tester.pumpAndSettle();

      expect(find.text("Done"), findsOneWidget);
      expect(find.text("The TV is set up."), findsOneWidget);
      expect(hasFocusOn(tester, "OK"), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text("Done"), findsNothing);
      expect(result, isTrue);
    });

    testWidgets("Back closes it with false", (tester) async {
      bool? result;
      await tester.pumpWidget(settingsTestApp(await freshSettings(), _opener((context) async {
        result = await showMessageDialog(context, title: "Done", message: "The TV is set up.");
      })));
      await tester.tap(find.text("open"));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text("Done"), findsNothing);
      expect(result, isFalse);
    });
  });

  group("showAdbCommandDialog", () {
    const command = "adb shell pm grant com.thesiegs.hearth android.permission.READ_TV_LISTINGS";

    testWidgets("shows why and the command; OK just closes it", (tester) async {
      var actions = 0;
      var closed = false;
      await tester.pumpWidget(settingsTestApp(await freshSettings(), _opener((context) async {
        await showAdbCommandDialog(context,
            title: "Watch Next", message: "Run this from a computer.", command: command, onAction: () => actions++);
        closed = true;
      })));
      await tester.tap(find.text("open"));
      await tester.pumpAndSettle();

      expect(find.text("Watch Next"), findsOneWidget);
      expect(find.text("Run this from a computer."), findsOneWidget);
      expect(find.text(command), findsOneWidget);
      // Without a label there's no action button, only OK
      expect(find.byType(TextButton), findsNWidgets(2), reason: "the opener and OK");

      await tester.tap(find.text("OK"));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(actions, 0);
    });

    testWidgets("the action button closes the dialog and runs the action", (tester) async {
      var actions = 0;
      var closed = false;
      await tester.pumpWidget(settingsTestApp(await freshSettings(), _opener((context) async {
        await showAdbCommandDialog(context,
            title: "Watch Next",
            message: "Run this from a computer.",
            command: command,
            actionLabel: "Open settings",
            onAction: () => actions++);
        closed = true;
      })));
      await tester.tap(find.text("open"));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Open settings"));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(actions, 1);
      expect(find.text(command), findsNothing);
    });
  });
}
