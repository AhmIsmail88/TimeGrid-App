import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timegrid/app/localization/gen/app_localizations.dart';
import 'package:timegrid/app/theme.dart';
import 'package:timegrid/core/widgets/week_strip.dart';

/// The week strip is pure UI: it needs no database, so these tests drive it
/// directly and check the dates it hands back rather than pixels.
void main() {
  DateTime? tapped;

  Widget wrap({
    required DateTime? selected,
    Locale locale = const Locale('en'),
    ThemeData? theme,
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: theme,
      home: Scaffold(
        body: WeekStrip(
          selectedDate: selected,
          onDaySelected: (day) => tapped = day,
        ),
      ),
    );
  }

  Finder dayCells() => find.byWidgetPredicate((widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('week-day-'));

  setUp(() => tapped = null);

  testWidgets('shows the seven days of the selected date week', (tester) async {
    // The en locale starts the week on Sunday, so the week of Wednesday
    // 30 Sep 2026 runs from 27 Sep to 3 Oct.
    await tester.pumpWidget(wrap(selected: DateTime(2026, 9, 30)));

    for (final day in ['27', '28', '29', '30', '1', '2', '3']) {
      expect(find.text(day), findsOneWidget, reason: 'day $day missing');
    }
    expect(dayCells(), findsNWidgets(7));
  });

  testWidgets('tapping a day reports that exact date', (tester) async {
    await tester.pumpWidget(wrap(selected: DateTime(2026, 9, 30)));

    await tester.tap(find.text('1'));
    await tester.pump();

    expect(tapped, DateTime(2026, 10, 1));
  });

  testWidgets('the arrows move a full week at a time', (tester) async {
    await tester.pumpWidget(wrap(selected: DateTime(2026, 9, 30)));

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(find.text('27'), findsNothing);
    expect(find.text('4'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();

    expect(find.text('4'), findsNothing);
    expect(find.text('20'), findsOneWidget);
    expect(find.text('26'), findsOneWidget);
  });

  testWidgets('follows a date picked outside the week on screen',
      (tester) async {
    await tester.pumpWidget(wrap(selected: DateTime(2026, 9, 30)));
    expect(find.text('30'), findsOneWidget);

    await tester.pumpWidget(wrap(selected: DateTime(2026, 11, 10)));
    await tester.pump();

    expect(find.text('30'), findsNothing);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
  });

  testWidgets('lays out right-to-left for Arabic and still returns dates',
      (tester) async {
    await tester.pumpWidget(wrap(
      selected: DateTime(2026, 9, 30),
      locale: const Locale('ar'),
    ));

    expect(
      Directionality.of(tester.element(find.byType(WeekStrip))),
      TextDirection.rtl,
    );
    expect(dayCells(), findsNWidgets(7));

    // In RTL the first cell of the Row sits on the right, so the right-most
    // cell has to be the locale's first day of the week.
    DateTime? rightmostDay;
    double rightmostX = -1;
    for (final element in dayCells().evaluate()) {
      final key = element.widget.key! as ValueKey<String>;
      final rect = tester.getRect(find.byKey(key));
      if (rect.left > rightmostX) {
        rightmostX = rect.left;
        rightmostDay = DateTime.parse(key.value.substring('week-day-'.length));
      }
    }
    final localizations =
        MaterialLocalizations.of(tester.element(find.byType(WeekStrip)));
    final firstDay = rightmostDay ?? DateTime(2000);
    expect(firstDay.weekday % 7, localizations.firstDayOfWeekIndex);
    expect(firstDay.weekday, DateTime.saturday);

    await tester.tap(find.text('27'));
    await tester.pump();
    expect(tapped, DateTime(2026, 9, 27));
  });

  testWidgets('renders on the dark theme too', (tester) async {
    await tester.pumpWidget(wrap(
      selected: DateTime(2026, 9, 30),
      theme: AppTheme.dark(),
    ));

    expect(dayCells(), findsNWidgets(7));
    expect(find.text('30'), findsOneWidget);
  });
}
