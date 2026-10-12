import 'package:flutter_test/flutter_test.dart';
import 'package:receiptly/transaction_date_rules.dart';

void main() {
  test('day 13 becomes available only on day 13', () {
    final day12 = DateTime(2026, 10, 12, 23, 59);
    final day13 = DateTime(2026, 10, 13, 0, 0);
    expect(TransactionDateRules.isValid(DateTime(2026, 10, 12), now: day12), isTrue);
    expect(TransactionDateRules.isValid(DateTime(2026, 10, 13), now: day12), isFalse);
    expect(TransactionDateRules.isValid(DateTime(2026, 10, 13), now: day13), isTrue);
    expect(TransactionDateRules.isValid(DateTime(2026, 10, 14), now: day13), isFalse);
  });

  test('next month unlocked only when real month changes', () {
    expect(TransactionDateRules.canGoToNextMonth(DateTime(2026, 10),
      now: DateTime(2026, 10, 31)), isFalse);
    expect(TransactionDateRules.canGoToNextMonth(DateTime(2026, 10),
      now: DateTime(2026, 11, 1)), isTrue);
    expect(TransactionDateRules.isFutureMonth(DateTime(2026, 12),
      now: DateTime(2026, 11, 1)), isTrue);
  });

  test('previous days are valid', () {
    expect(TransactionDateRules.isValid(DateTime(2024, 3, 1),
      now: DateTime(2026, 10, 13)), isTrue);
  });
}
