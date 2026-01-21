import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_manager/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('App starts and renders without errors', (
    WidgetTester tester,
  ) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Basic check to see if the app is rendered.
    // In a real app, you'd check for a login screen or specific dashboard elements.
    expect(find.byType(MyApp), findsOneWidget);
  });
}
