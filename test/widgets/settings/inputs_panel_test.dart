import 'package:flauncher/models/tv_input.dart';
import 'package:flauncher/providers/tv_inputs_service.dart';
import 'package:flauncher/widgets/settings/inputs_panel.dart';
import 'package:flauncher/widgets/settings/side_panel_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.mocks.dart';
import 'settings_test_app.dart';

/// Opens the panel (in a SidePanelOverlay) over a page, from a button.
Future<void> _open(WidgetTester tester, MockTvInputsService inputs) async {
  await tester.pumpWidget(ChangeNotifierProvider<TvInputsService>.value(
    value: inputs,
    child: settingsTestApp(
      await freshSettings(),
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(PageRouteBuilder(
            opaque: false,
            pageBuilder: (_, _, _) => const InputsPanel(),
          )),
          child: const Text("open"),
        ),
      ),
    ),
  ));
  await tester.tap(find.text("open"));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("lists the TV's inputs with the first one focused", (tester) async {
    final inputs = MockTvInputsService();
    when(inputs.inputs).thenReturn([
      TvInput(id: "hdmi1", label: "Game console", type: TvInputType.hdmi),
      TvInput(id: "tuner", label: "Antenna", type: TvInputType.tuner),
      TvInput(id: "av", label: "Composite", type: TvInputType.av),
      TvInput(id: "x", label: "Other box", type: TvInputType.other),
    ]);
    await _open(tester, inputs);

    expect(find.text("Input Sources"), findsOneWidget);
    expect(find.byType(SidePanelOverlay), findsOneWidget);
    expect(hasFocusOn(tester, "Game console"), isTrue);
    expect(find.byIcon(Icons.settings_input_hdmi), findsOneWidget);
    expect(find.byIcon(Icons.settings_input_antenna_outlined), findsOneWidget);
    expect(find.byIcon(Icons.settings_input_component_outlined), findsOneWidget);
    expect(find.byIcon(Icons.input_outlined), findsOneWidget);
  });

  testWidgets("OK on an input closes the panel and switches to it", (tester) async {
    final inputs = MockTvInputsService();
    when(inputs.inputs).thenReturn([
      TvInput(id: "hdmi1", label: "Game console", type: TvInputType.hdmi),
      TvInput(id: "hdmi2", label: "Media box", type: TvInputType.hdmi),
    ]);
    when(inputs.switchInput(any)).thenAnswer((_) async => true);
    await _open(tester, inputs);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    verify(inputs.switchInput("hdmi2")).called(1);
    verifyNever(inputs.switchInput("hdmi1"));
    expect(find.text("Input Sources"), findsNothing);
  });

  testWidgets("without inputs it says so", (tester) async {
    final inputs = MockTvInputsService();
    when(inputs.inputs).thenReturn([]);
    await _open(tester, inputs);

    expect(find.text("No inputs detected"), findsOneWidget);
    verifyNever(inputs.switchInput(any));
  });

  testWidgets("a tap beside the panel closes it", (tester) async {
    final inputs = MockTvInputsService();
    when(inputs.inputs).thenReturn([]);
    await _open(tester, inputs);

    // The panel sits at the start (left); the right edge of the 800 px test screen is outside it
    await tester.tapAt(const Offset(790, 300));
    await tester.pumpAndSettle();
    expect(find.text("Input Sources"), findsNothing);
    verifyNever(inputs.switchInput(any));
  });
}
