// This is a basic Flutter widget test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openwrt_manager/main.dart';

void main() {
  testWidgets('App builds smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const OpenWrtManagerApp());
    expect(find.text('OpenWrt Manager'), findsOneWidget);
  });
}
