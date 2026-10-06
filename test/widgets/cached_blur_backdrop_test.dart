import 'package:flauncher/gradients.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/cached_blur_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.mocks.dart';

void main() {
  MockWallpaperService gradientWallpaper({Color? focusedAppColor}) {
    final service = MockWallpaperService();
    when(service.wallpaper).thenReturn(null);
    when(service.gradient).thenReturn(FLauncherGradients.greatWhale);
    when(service.version).thenReturn(0);
    when(service.focusedAppColor).thenReturn(focusedAppColor);
    return service;
  }

  Widget subject(WallpaperService service) => ChangeNotifierProvider<WallpaperService>.value(
        value: service,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: SizedBox(width: 200, height: 80, child: CachedBlurBackdrop(sigma: 12, child: Text("dock")))),
        ),
      );

  testWidgets("swaps the live blur for a cached snapshot once it's ready", (tester) async {
    await tester.pumpWidget(subject(gradientWallpaper()));
    expect(find.byType(BackdropFilter), findsOneWidget);

    // Let the post-frame snapshot render finish, then rebuild with it.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text("dock"), findsOneWidget);
  });

  testWidgets("keeps the live blur while the background follows the focused app", (tester) async {
    await tester.pumpWidget(subject(gradientWallpaper(focusedAppColor: Colors.red)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    expect(find.byType(BackdropFilter), findsOneWidget);
  });
}
