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
}
