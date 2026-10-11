import 'package:flauncher/widgets/settings/remote_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("Down and Up leave the field for the rows around it", (tester) async {
    final a = TextEditingController(), b = TextEditingController();
    final save = FocusNode();
    addTearDown(save.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          RemoteTextField(controller: a, decoration: const InputDecoration(labelText: "Token")),
          RemoteTextField(controller: b, decoration: const InputDecoration(labelText: "Dashboard")),
          TextButton(focusNode: save, onPressed: () {}, child: const Text("Save")),
        ]),
      ),
    ));
    await tester.tap(find.byType(TextField).first);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField).last).focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(save.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField).last).focusNode!.hasFocus, isTrue);
  });

  testWidgets("Moving onto a field only selects it: OK starts editing, leaving ends it", (tester) async {
    final first = TextEditingController(text: "lovelace");
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          RemoteTextField(controller: first, decoration: const InputDecoration(labelText: "Dashboard")),
          RemoteTextField(controller: TextEditingController(), decoration: const InputDecoration(labelText: "Token")),
        ]),
      ),
    ));
    TextField field() => tester.widget<TextField>(find.byType(TextField).first);
    field().focusNode!.requestFocus();
    await tester.pump();
    expect(field().readOnly, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(field().readOnly, isFalse);
    await tester.enterText(find.byType(TextField).first, "tv");
    expect(first.text, "tv");

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(field().readOnly, isTrue);
  });
}
