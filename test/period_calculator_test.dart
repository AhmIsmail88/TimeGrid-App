import 'package:flutter_test/flutter_test.dart';
import 'package:timegrid/core/utils/period_calculator.dart';

void main() {
  group('PeriodCalculator', () {
    test('day 21 -> 21 Mar to 20 Apr for a March date', () {
      const calc = PeriodCalculator(21);
      final period = calc.periodContaining(DateTime(2026, 3, 25));
      expect(period.start, DateTime(2026, 3, 21));
      expect(period.end, DateTime(2026, 4, 20));
    });

    test('date before the cycle day belongs to the previous period', () {
      const calc = PeriodCalculator(21);
      final period = calc.periodContaining(DateTime(2026, 3, 5));
      expect(period.start, DateTime(2026, 2, 21));
      expect(period.end, DateTime(2026, 3, 20));
    });

    test('start and end are both inclusive', () {
      const calc = PeriodCalculator(21);
      final period = calc.periodContaining(DateTime(2026, 3, 21));
      expect(period.contains(DateTime(2026, 3, 21)), isTrue);
      expect(period.contains(DateTime(2026, 4, 20)), isTrue);
      expect(period.contains(DateTime(2026, 4, 21)), isFalse);
    });

    test('handles February and leap years for a day-28 cycle', () {
      const calc = PeriodCalculator(28);
      // 2028 is a leap year -> Feb has 29 days, so day 28 is a normal day.
      final period = calc.periodContaining(DateTime(2028, 2, 20));
      expect(period.start, DateTime(2028, 1, 28));
      expect(period.end, DateTime(2028, 2, 27));
    });

    test('next/previous period roll correctly across a year boundary', () {
      const calc = PeriodCalculator(21);
      final dec = calc.periodContaining(DateTime(2026, 12, 25));
      final next = calc.nextPeriod(dec);
      expect(next.start, DateTime(2027, 1, 21));
      final prev = calc.previousPeriod(next);
      expect(prev.start, dec.start);
    });
  });
}
