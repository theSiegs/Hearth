import 'package:flauncher/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Element? findAppCardByPackageName(WidgetTester tester, String packageName) {
  for (var val in tester.elementList(find.byType(AppCard))) {
    if ((val.widget as AppCard).application.packageName == packageName) {
      return val;
    }
  }
  return null;
}

/// The status bar's leftmost button, where Up from the first section lands (the profile button;
/// there's no Settings gear any more).
Element? findSettingsIcon(WidgetTester tester) {
  try {
    return tester.element(find.byIcon(Icons.people_outline));
  } catch (e) {
    return null;
  }
}
