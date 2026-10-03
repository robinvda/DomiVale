import 'package:domivale/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the app opens on the main menu', (WidgetTester tester) async {
    await tester.pumpWidget(const GameApp());

    expect(find.text('DomiVale'), findsOneWidget);
    expect(find.text('settle · grow · rule'), findsOneWidget);
    expect(find.text('Skirmish'), findsOneWidget);
    expect(find.text('Daily board'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('a mode that is not built yet says so warmly', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const GameApp());
    await tester.tap(find.text('Skirmish'));
    await tester.pump();
    expect(find.text('The valley is still being surveyed.'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
