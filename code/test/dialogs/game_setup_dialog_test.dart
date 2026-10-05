import 'package:checkers/play_session/game_setup_dialog.dart';
import 'package:checkers/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('GameSetupDialog initializes without context errors', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MultiProvider(
        providers: [Provider(create: (_) => SettingsController())],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showGameSetupDialog(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('Game Setup'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('GameSetupDialog handles cancel correctly', (tester) async {
    SharedPreferences.setMockInitialValues({});

    dynamic result;
    await tester.pumpWidget(
      MultiProvider(
        providers: [Provider(create: (_) => SettingsController())],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showGameSetupDialog(context);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, false);
  });
}
