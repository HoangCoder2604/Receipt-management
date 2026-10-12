/// Business rules for actual spending: no dates later than the local day.
/// Read the clock on every operation so tomorrow is allowed once it arrives.
class TransactionDateRules {
  static DateTime today({DateTime? now}) {
    final time = now ?? DateTime.now();
    return DateTime(time.year, time.month, time.day);
  }

  static DateTime currentMonth({DateTime? now}) {
    final time = now ?? DateTime.now();
    return DateTime(time.year, time.month);
  }

  static bool isFuture(DateTime date, {DateTime? now}) {
    final localDay = DateTime(date.year, date.month, date.day);
    return localDay.isAfter(today(now: now));
  }

  static bool isValid(DateTime date, {DateTime? now}) {
    return !isFuture(date, now: now) &&
        !DateTime(date.year, date.month, date.day).isBefore(DateTime(2000));
  }

  static bool isFutureMonth(DateTime month, {DateTime? now}) {
    return DateTime(month.year, month.month).isAfter(currentMonth(now: now));
  }

  static bool canGoToNextMonth(DateTime month, {DateTime? now}) {
    return !isFutureMonth(DateTime(month.year, month.month + 1), now: now);
  }
}
