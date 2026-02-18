import 'package:flappy_calendar/flappy_calendar.dart';
import 'package:flappy_calendar/month_calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  final kMonth = DateTime(2026, 2, 1); // February 2026, starts on a Sunday

  Widget buildTestWidget({
    required List<CalendarEvent> events,
    int maxLanes = 2,
    DateTime? selectedDay,
    ValueChanged<DateTime>? onDayTap,
    ValueChanged<CalendarEvent>? onEventTap,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 700,
            child: MonthCalendarView(
              month: kMonth,
              events: events,
              maxEventLanesPerWeek: maxLanes,
              weekStartsOn: DateTime.monday,
              dayCellMinHeight: 48,
              laneHeight: 18,
              laneSpacing: 4,
              selectedDay: selectedDay,
              onDayTap: onDayTap,
              onEventTap: onEventTap,
            ),
          ),
        ),
      ),
    );
  }

  CalendarEvent makeEvent({
    String id = 'e1',
    String title = 'Event',
    required DateTime start,
    required DateTime end,
    Color color = const Color(0xFFFF9900),
  }) {
    return CalendarEvent(id: id, title: title, start: start, end: end, color: color);
  }

  // ---------------------------------------------------------------------------
  // Overflow badge
  // ---------------------------------------------------------------------------

  group('overflow badge', () {
    List<CalendarEvent> sameDayEvents(int count) => List.generate(
      count,
          (i) => makeEvent(
        id: 'e$i',
        title: 'Event $i',
        start: DateTime(2026, 2, 5, 9 + i),
        end: DateTime(2026, 2, 5, 10 + i),
      ),
    );

    testWidgets('4 events same day with maxLanes=2 shows +2 and 2 visible', (tester) async {
      await tester.pumpWidget(buildTestWidget(events: sameDayEvents(4), maxLanes: 2));
      await tester.pumpAndSettle();

      expect(find.text('+2'), findsOneWidget);
      int visible = 0;
      for (int i = 0; i < 4; i++) {
        if (tester.any(find.text('Event $i'))) visible++;
      }
      expect(visible, equals(2));
    });

    testWidgets('4 events same day with maxLanes=3 shows +1 and 3 visible', (tester) async {
      await tester.pumpWidget(buildTestWidget(events: sameDayEvents(4), maxLanes: 3));
      await tester.pumpAndSettle();

      expect(find.text('+1'), findsOneWidget);
      int visible = 0;
      for (int i = 0; i < 4; i++) {
        if (tester.any(find.text('Event $i'))) visible++;
      }
      expect(visible, equals(3));
    });

    testWidgets('no events shows no overflow badge', (tester) async {
      await tester.pumpWidget(buildTestWidget(events: []));
      await tester.pumpAndSettle();

      expect(find.textContaining('+'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // onDayTap callback
  // ---------------------------------------------------------------------------

  group('onDayTap', () {
    testWidgets('tapping a day cell calls onDayTap with the correct date', (tester) async {
      DateTime? tapped;
      await tester.pumpWidget(buildTestWidget(
        events: [],
        onDayTap: (d) => tapped = d,
      ));
      await tester.pumpAndSettle();

      // Feb 5 is rendered as the text '5' inside its day cell.
      await tester.tap(find.text('5').first);
      await tester.pumpAndSettle();

      expect(tapped, isNotNull);
      expect(tapped!.year, equals(2026));
      expect(tapped!.month, equals(2));
      expect(tapped!.day, equals(5));
    });

    testWidgets('no onDayTap provided — tapping a cell does not throw', (tester) async {
      await tester.pumpWidget(buildTestWidget(events: [])); // onDayTap omitted
      await tester.pumpAndSettle();

      // Should not throw.
      await tester.tap(find.text('10').first);
      await tester.pumpAndSettle();
    });

    testWidgets('each tapped day delivers its own distinct date', (tester) async {
      final tapped = <DateTime>[];
      await tester.pumpWidget(buildTestWidget(
        events: [],
        onDayTap: tapped.add,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('3').first);
      await tester.tap(find.text('17').first);
      await tester.pumpAndSettle();

      expect(tapped, hasLength(2));
      expect(tapped[0].day, equals(3));
      expect(tapped[1].day, equals(17));
    });
  });

  // ---------------------------------------------------------------------------
  // onEventTap callback
  // ---------------------------------------------------------------------------

  group('onEventTap', () {
    testWidgets('tapping an event bar calls onEventTap with the correct event', (tester) async {
      final event = makeEvent(
        id: 'meeting',
        title: 'Team meeting',
        start: DateTime(2026, 2, 10, 10),
        end: DateTime(2026, 2, 10, 11),
      );
      CalendarEvent? tapped;
      await tester.pumpWidget(buildTestWidget(
        events: [event],
        onEventTap: (e) => tapped = e,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Team meeting'));
      await tester.pumpAndSettle();

      expect(tapped, isNotNull);
      expect(tapped!.id, equals('meeting'));
    });

    testWidgets('tapping different event bars delivers distinct events', (tester) async {
      final events = [
        makeEvent(id: 'a', title: 'Alpha', start: DateTime(2026, 2, 3, 9), end: DateTime(2026, 2, 3, 10)),
        makeEvent(id: 'b', title: 'Beta', start: DateTime(2026, 2, 4, 9), end: DateTime(2026, 2, 4, 10)),
      ];
      final tapped = <String>[];
      await tester.pumpWidget(buildTestWidget(
        events: events,
        maxLanes: 3,
        onEventTap: (e) => tapped.add(e.id),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alpha'));
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      expect(tapped, equals(['a', 'b']));
    });
  });

  // ---------------------------------------------------------------------------
  // Multi-week events
  // ---------------------------------------------------------------------------

  group('multi-week events', () {
    testWidgets('event spanning two week rows renders a bar in each row', (tester) async {
      // Feb 2 (Mon, week 1) → Feb 9 (Mon, week 2): crosses a week boundary.
      final event = makeEvent(
        id: 'span',
        title: 'Long event',
        start: DateTime(2026, 2, 2),
        end: DateTime(2026, 2, 9),
      );
      await tester.pumpWidget(buildTestWidget(events: [event], maxLanes: 3));
      await tester.pumpAndSettle();

      // The title should appear twice — once per week row segment.
      expect(find.text('Long event'), findsNWidgets(2));
    });

    testWidgets('single-day event renders exactly one bar', (tester) async {
      final event = makeEvent(
        title: 'Standup',
        start: DateTime(2026, 2, 11, 9),
        end: DateTime(2026, 2, 11, 10),
      );
      await tester.pumpWidget(buildTestWidget(events: [event]));
      await tester.pumpAndSettle();

      expect(find.text('Standup'), findsOneWidget);
    });
  });
}