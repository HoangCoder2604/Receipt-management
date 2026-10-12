import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receiptly/main.dart';

void main() {
  testWidgets('Receiptly application launches', (tester) async {
    await tester.pumpWidget(const ReceiptlyApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
