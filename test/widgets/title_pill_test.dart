import 'package:flauncher/widgets/title_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("the pill is faint on dark wallpapers and darker on light ones", () {
    expect(TitlePill.opacityFor(0.05), closeTo(0.25, 0.001));
    expect(TitlePill.opacityFor(0.45), closeTo(0.425, 0.001));
    expect(TitlePill.opacityFor(0.9), closeTo(0.60, 0.001));
  });

  testWidgets("without a wallpaper service it shows a middle pill", (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TitlePill(child: Text("Favorites"))));
    final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
    expect((box.decoration as BoxDecoration).color!.opacity, closeTo(TitlePill.opacityFor(0.5), 0.01));
    expect(find.text("Favorites"), findsOneWidget);
  });

  test("the details scrim is lighter on dark wallpapers, HearthTube's strength on light ones", () {
    expect(DetailsScrim.bottomOpacityFor(0.1), closeTo(0.5, 0.001));
    expect(DetailsScrim.bottomOpacityFor(0.43), closeTo(0.684, 0.001));
    expect(DetailsScrim.bottomOpacityFor(0.95), closeTo(0.9, 0.001));
  });

  testWidgets("the details scrim shows only while its row does", (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DetailsScrim(visible: false)));
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 0);
    await tester.pumpWidget(const MaterialApp(home: DetailsScrim(visible: true)));
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 1);
  });
}
