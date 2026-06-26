import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_mitra/screens/landing_screen.dart';

void main() {
  testWidgets('Landing screen renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LandingScreen(),
      ),
    );

    // Wait for animation to start
    await tester.pump(const Duration(milliseconds: 500));

    // Verify YATRA MITRA title appears
    expect(find.text('YATRA MITRA'), findsOneWidget);

    // Verify main headline
    expect(find.text('Safety.'), findsOneWidget);
  });
}