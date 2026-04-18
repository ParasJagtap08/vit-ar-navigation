import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vit_ar_app/main.dart';

void main() {
  testWidgets('App starts without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const VITNavigatorApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
