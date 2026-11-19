import 'package:color_blendr/app/app_update.dart';
import 'package:color_blendr/ui/update_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  tearDown(() => AppUpdate.required.value = false);

  Widget app() => MaterialApp(
    builder: (context, child) =>
        UpdateGate(lockScreen: const UpdateScreen(), child: child!),
    home: const Scaffold(body: Text('Generator')),
  );

  testWidgets('no update needed: the app opens', (tester) async {
    await tester.pumpWidget(app());
    expect(find.text('Generator'), findsOneWidget);
    expect(find.byType(UpdateScreen), findsNothing);
  });

  testWidgets('update needed: only the update page shows', (tester) async {
    AppUpdate.required.value = true;
    await tester.pumpWidget(app());
    expect(find.byType(UpdateScreen), findsOneWidget);
    expect(find.text('Update on Google Play'), findsOneWidget);
    expect(find.text('Generator'), findsNothing);
  });

  testWidgets('update found while open: the app is replaced', (tester) async {
    await tester.pumpWidget(app());
    expect(find.text('Generator'), findsOneWidget);
    AppUpdate.required.value = true;
    await tester.pump();
    expect(find.byType(UpdateScreen), findsOneWidget);
    expect(find.text('Generator'), findsNothing);
  });
}
