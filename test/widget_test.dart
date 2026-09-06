import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weekend/main.dart';

void main() {
  testWidgets('Weekend app launches', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: WeekendApp()));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
