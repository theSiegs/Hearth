import 'package:flauncher/gradients.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/frosted_glass.dart';
import 'package:flauncher/widgets/painted_once.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.mocks.dart';

void main() {
  MockWallpaperService wallpaper({Color? appColor}) {
    final service = MockWallpaperService();
    when(service.wallpaper).thenReturn(null);
    when(service.gradient).thenReturn(FLauncherGradients.greatWhale);
    when(service.version).thenReturn(0);
    when(service.focusedAppColor).thenReturn(appColor);
    return service;
  }

  Widget glass(WallpaperService service, double sigma) => ChangeNotifierProvider<WallpaperService>.value(
        value: service,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: SizedBox(width: 200, height: 80, child: FrostedGlass(sigma: sigma, child: const Text("dock")))),
        ),
      );

  testWidgets("a live blur only until the blurred wallpaper is ready", (tester) async {
    await tester.pumpWidget(glass(wallpaper(), 11));
    expect(find.byType(BackdropFilter), findsOneWidget);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text("dock"), findsOneWidget);
  });

  testWidgets("live while the background follows the focused app's colour", (tester) async {
    await tester.pumpWidget(glass(wallpaper(appColor: Colors.teal), 13));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets("a gradient is painted live, then shown as its image", (tester) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: PaintedOnce.gradient(const LinearGradient(colors: [Colors.black, Colors.blue])),
    ));
    expect(find.byType(RawImage), findsNothing);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget);
  });
}
