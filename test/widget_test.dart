import 'package:color_blendr/app/app.dart';
import 'package:color_blendr/data/ads.dart';
import 'package:color_blendr/data/session_store.dart';
import 'package:color_blendr/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

void main() {
  Future<FakeColorSource> pumpApp(WidgetTester tester) async {
    final source = FakeColorSource([
      [
        color('2b301f', 'Rangitoto'),
        color('b0bef3', 'Perano'),
        color('8205a0', 'Purple'),
      ],
      [
        color('111111', 'Black'),
        color('222222', 'Mine Shaft'),
        color('333333', 'Tundora'),
      ],
      [
        color('444444', 'Tuatara'),
        color('555555', 'Fuscous Gray'),
        color('666666', 'Dove Gray'),
      ],
    ]);
    final prefs = await testPreferences();
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          colorSourceProvider.overrideWithValue(source),
          sessionStoreProvider.overrideWithValue(MemorySessionStore()),
          googleAuthProvider.overrideWithValue(FakeGoogleAuth()),
          adsProvider.overrideWithValue(const NoAds()),
          prefs,
        ],
        child: const BlendrApp(),
      ),
    );
    await tester.pumpAndSettle();
    return source;
  }

  // Tap the tab, not a page title of the same name.
  Finder tab(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  testWidgets('shows a generated palette and generates another', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('#2B301F'), findsOneWidget);
    expect(find.text('Rangitoto'), findsOneWidget);

    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();
    expect(find.text('#111111'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous palette'));
    await tester.pumpAndSettle();
    expect(find.text('#2B301F'), findsOneWidget);
  });

  testWidgets(
    'switching modes restores each mode\'s palette instead of regenerating',
    (tester) async {
      final source = await pumpApp(tester);
      expect(find.text('#2B301F'), findsOneWidget);

      await tester.tap(find.text('Gradient'));
      await tester.pumpAndSettle();
      expect(
        find.text('#111111'),
        findsOneWidget,
        reason: 'first visit generates',
      );

      await tester.tap(find.text('Palette'));
      await tester.pumpAndSettle();
      expect(
        find.text('#2B301F'),
        findsOneWidget,
        reason: 'previous palette is back',
      );
      expect(source.requests.length, 2, reason: 'no extra generate');
    },
  );

  testWidgets('saving while signed out asks to sign in', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Save to library'));
    await tester.pumpAndSettle();
    expect(find.text('Save your palettes'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets(
    'library and settings tabs show sign-in prompts when signed out',
    (tester) async {
      await pumpApp(tester);

      await tester.tap(tab('Library'));
      await tester.pumpAndSettle();
      expect(find.text('Your saved palettes live here'), findsOneWidget);

      await tester.tap(tab('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to Color Blendr'), findsOneWidget);
      expect(find.text('Colors per palette'), findsOneWidget);
    },
  );

  testWidgets('choosing 2 colors per palette shows a 2-color palette', (
    tester,
  ) async {
    final source = await pumpApp(tester);

    await tester.tap(tab('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<int>),
        matching: find.text('2'),
      ),
    );
    await tester.pumpAndSettle();
    expect(source.requests.last.count, 2);

    await tester.tap(tab('Create'));
    await tester.pumpAndSettle();
    expect(find.text('#111111'), findsOneWidget);
    expect(find.text('#222222'), findsOneWidget);
    expect(find.text('#333333'), findsNothing);
  });
}
