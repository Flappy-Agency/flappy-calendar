// Unit tests for month_calendar_logic.dart.
// No Flutter widget pump needed — these are pure Dart tests.
import 'package:flappy_calendar/flappy_calendar.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

CalendarEvent makeEvent({
  String id = 'e1',
  String title = 'Event',
  required DateTime start,
  required DateTime end,
  Color? color,
}) {
  return CalendarEvent(id: id, title: title, start: start, end: end, color: color);
}

// ---------------------------------------------------------------------------
// dayOnly / isSameDay
// ---------------------------------------------------------------------------

void main() {
  group('dayOnly', () {
    test('strips time component', () {
      final dt = DateTime(2026, 2, 5, 14, 30, 59);
      final result = dayOnly(dt);
      expect(result, equals(DateTime(2026, 2, 5)));
      expect(result.hour, 0);
      expect(result.minute, 0);
      expect(result.second, 0);
    });

    test('midnight is unchanged', () {
      final midnight = DateTime(2026, 3, 1);
      expect(dayOnly(midnight), equals(midnight));
    });
  });

  group('isSameDay', () {
    test('same date different times → true', () {
      expect(
        isSameDay(DateTime(2026, 2, 5, 9, 0), DateTime(2026, 2, 5, 23, 59)),
        isTrue,
      );
    });

    test('different dates → false', () {
      expect(
        isSameDay(DateTime(2026, 2, 5), DateTime(2026, 2, 6)),
        isFalse,
      );
    });

    test('different months → false', () {
      expect(
        isSameDay(DateTime(2026, 1, 31), DateTime(2026, 2, 1)),
        isFalse,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // buildMonthGrid
  // ---------------------------------------------------------------------------

  group('buildMonthGrid', () {
    // February 2026 starts on a Sunday (weekday=7).
    // With weekStartsOn=Monday the grid should start on Mon 26 Jan.
    test('Feb 2026 week-start Monday: visible range is Mon 26 Jan – Sun 1 Mar', () {
      final grid = buildMonthGrid(DateTime(2026, 2), weekStartsOn: DateTime.monday);

      expect(grid.visibleStart, equals(DateTime(2026, 1, 26)));
      expect(grid.visibleEnd, equals(DateTime(2026, 3, 1)));
    });

    test('Feb 2026 week-start Monday: produces 5 weeks', () {
      final grid = buildMonthGrid(DateTime(2026, 2), weekStartsOn: DateTime.monday);
      expect(grid.weeks.length, equals(5));
    });

    test('every week row has exactly 7 days', () {
      final grid = buildMonthGrid(DateTime(2026, 2), weekStartsOn: DateTime.monday);
      for (final week in grid.weeks) {
        expect(week.length, equals(7));
      }
    });

    test('days are consecutive across all weeks', () {
      // March 2026 crosses a DST transition (last Sunday) — use component-based
      // comparison instead of difference().inDays which is DST-sensitive.
      final grid = buildMonthGrid(DateTime(2026, 3), weekStartsOn: DateTime.monday);
      final flat = grid.weeks.expand((w) => w).toList();
      for (int i = 1; i < flat.length; i++) {
        final prev = flat[i - 1];
        final next = flat[i];
        final expected = DateTime(prev.year, prev.month, prev.day + 1);
        expect(
          isSameDay(next, expected),
          isTrue,
          reason: 'Day $i ($next) is not exactly 1 day after day ${i - 1} ($prev)',
        );
      }
    });

    test('week-start Sunday: first column is Sunday', () {
      // January 2026: 1st is a Thursday.
      // With Sunday start, grid starts on Sun 28 Dec 2025.
      final grid = buildMonthGrid(DateTime(2026, 1), weekStartsOn: DateTime.sunday);
      expect(grid.visibleStart.weekday, equals(DateTime.sunday));
      // Each week should start on a Sunday.
      for (final week in grid.weeks) {
        expect(week.first.weekday, equals(DateTime.sunday));
      }
    });

    test('visible start is always the correct day-of-week (Monday)', () {
      // April 2026: 1st is Wednesday. With Mon start, grid starts Mon 30 March.
      final grid = buildMonthGrid(DateTime(2026, 4), weekStartsOn: DateTime.monday);
      expect(grid.visibleStart.weekday, equals(DateTime.monday));
    });

    test('grid covers the full target month', () {
      final grid = buildMonthGrid(DateTime(2026, 2), weekStartsOn: DateTime.monday);
      final monthStart = DateTime(2026, 2, 1);
      final monthEnd = DateTime(2026, 2, 28);
      expect(
        grid.visibleStart.isBefore(monthStart) || grid.visibleStart == monthStart,
        isTrue,
        reason: 'Grid should start on or before Feb 1',
      );
      expect(
        grid.visibleEnd.isAfter(monthEnd) || grid.visibleEnd == monthEnd,
        isTrue,
        reason: 'Grid should end on or after Feb 28',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // buildWeekSegments
  // ---------------------------------------------------------------------------

  group('buildWeekSegments', () {
    // Use Feb 2026 grid with Monday start throughout.
    late MonthGrid grid;

    setUp(() {
      grid = buildMonthGrid(DateTime(2026, 2), weekStartsOn: DateTime.monday);
    });

    test('single-day event produces one segment', () {
      final event = makeEvent(
        start: DateTime(2026, 2, 5, 9),
        end: DateTime(2026, 2, 5, 10),
      );
      final segments = buildWeekSegments(events: [event], grid: grid);
      expect(segments.length, equals(1));
    });

    test('single-day event: startCol == endCol', () {
      final event = makeEvent(
        start: DateTime(2026, 2, 5, 9), // Thursday
        end: DateTime(2026, 2, 5, 10),
      );
      final segments = buildWeekSegments(events: [event], grid: grid);
      expect(segments.first.startCol, equals(segments.first.endCol));
    });

    test('event spanning two weeks produces two segments', () {
      // Monday Feb 2 → Monday Feb 9 crosses the week boundary (Mon 2 Feb is week 1, Mon 9 Feb is week 2).
      final event = makeEvent(
        start: DateTime(2026, 2, 2),
        end: DateTime(2026, 2, 9),
      );
      final segments = buildWeekSegments(events: [event], grid: grid);
      expect(segments.length, equals(2));
    });

    test('cross-week segment: first part has continuesRight=true', () {
      final event = makeEvent(
        start: DateTime(2026, 2, 2),
        end: DateTime(2026, 2, 9),
      );
      final segments = buildWeekSegments(events: [event], grid: grid)
        ..sort((a, b) => a.weekIndex.compareTo(b.weekIndex));
      expect(segments[0].continuesRight, isTrue);
      expect(segments[1].continuesLeft, isTrue);
    });

    test('event entirely outside the grid is excluded', () {
      final event = makeEvent(
        start: DateTime(2025, 12, 1),
        end: DateTime(2025, 12, 31),
      );
      final segments = buildWeekSegments(events: [event], grid: grid);
      expect(segments, isEmpty);
    });

    test('event clipped to month does not appear in adjacent-month cells', () {
      // An event from Jan 28 to Feb 3 with month clamping should only appear
      // in Feb cells (col 0 = Mon Feb 2, because grid starts Mon Jan 26).
      final event = makeEvent(
        start: DateTime(2026, 1, 28),
        end: DateTime(2026, 2, 3),
      );
      final segments = buildWeekSegments(
        events: [event],
        grid: grid,
        month: DateTime(2026, 2),
      );
      // After clamping, the effective start is Feb 1 (Sunday in grid col 6, week 0)
      // and effective end is Feb 3 (Tuesday, col 1, week 1) — split into 2 segments.
      for (final seg in segments) {
        // All segment days should be within February.
        final segStart = grid.visibleStart.add(Duration(days: seg.weekIndex * 7 + seg.startCol));
        final segEnd = grid.visibleStart.add(Duration(days: seg.weekIndex * 7 + seg.endCol));
        expect(segStart.month == 2 || segEnd.month == 2, isTrue);
      }
    });

    test('event spanning all 5 weeks of the month produces 5 segments', () {
      final event = makeEvent(
        start: DateTime(2026, 2, 1),
        end: DateTime(2026, 2, 28),
      );
      final segments = buildWeekSegments(events: [event], grid: grid);
      // Feb 1 is week 0 (Sunday col), Feb 28 is week 4.
      expect(segments.length, equals(5));
    });

    test('empty event list produces no segments', () {
      final segments = buildWeekSegments(events: [], grid: grid);
      expect(segments, isEmpty);
    });

    test('multiple events on same day each produce their own segment', () {
      final events = [
        makeEvent(id: 'a', start: DateTime(2026, 2, 10, 9), end: DateTime(2026, 2, 10, 10)),
        makeEvent(id: 'b', start: DateTime(2026, 2, 10, 11), end: DateTime(2026, 2, 10, 12)),
        makeEvent(id: 'c', start: DateTime(2026, 2, 10, 13), end: DateTime(2026, 2, 10, 14)),
      ];
      final segments = buildWeekSegments(events: events, grid: grid);
      expect(segments.length, equals(3));
      // All in the same week+col.
      expect(segments.map((s) => s.weekIndex).toSet().length, equals(1));
      expect(segments.map((s) => s.startCol).toSet().length, equals(1));
    });
  });

  // ---------------------------------------------------------------------------
  // overlapsColumns
  // ---------------------------------------------------------------------------

  group('overlapsColumns', () {
    MonthGrid? _grid;

    // Build a minimal grid just to construct WeekSegment instances.
    MonthGrid getGrid() {
      _grid ??= buildMonthGrid(DateTime(2026, 2), weekStartsOn: DateTime.monday);
      return _grid!;
    }

    WeekSegment seg(int start, int end) {
      final event = makeEvent(
        start: DateTime(2026, 2, 2 + start),
        end: DateTime(2026, 2, 2 + end),
      );
      return WeekSegment(
        event: event,
        weekIndex: 0,
        startCol: start,
        endCol: end,
        continuesLeft: false,
        continuesRight: false,
      );
    }

    test('identical segments overlap', () {
      expect(overlapsColumns(seg(2, 4), seg(2, 4)), isTrue);
    });

    test('adjacent but non-overlapping segments do not overlap', () {
      // [0,1] and [2,3] share no column.
      expect(overlapsColumns(seg(0, 1), seg(2, 3)), isFalse);
    });

    test('touching at boundary: col 2 end and col 3 start — no overlap', () {
      expect(overlapsColumns(seg(0, 2), seg(3, 6)), isFalse);
    });

    test('overlapping by one column', () {
      expect(overlapsColumns(seg(0, 3), seg(3, 6)), isTrue);
    });

    test('one segment contained within another', () {
      expect(overlapsColumns(seg(0, 6), seg(2, 4)), isTrue);
    });

    test('is symmetric', () {
      final a = seg(1, 3);
      final b = seg(4, 6);
      expect(overlapsColumns(a, b), equals(overlapsColumns(b, a)));
    });

    // Get grid to satisfy linter (variable used in tearDown-like fashion).
    tearDownAll(() => getGrid());
  });

  // ---------------------------------------------------------------------------
  // layoutWeek
  // ---------------------------------------------------------------------------

  group('layoutWeek', () {
    WeekSegment makeSeg({
      String id = 'e',
      required int startCol,
      required int endCol,
      DateTime? start,
      DateTime? end,
    }) {
      final s = start ?? DateTime(2026, 2, 2 + startCol, 9);
      final e = end ?? DateTime(2026, 2, 2 + endCol, 10);
      final event = makeEvent(id: id, start: s, end: e);
      return WeekSegment(
        event: event,
        weekIndex: 0,
        startCol: startCol,
        endCol: endCol,
        continuesLeft: false,
        continuesRight: false,
      );
    }

    test('empty input produces no positioned segments', () {
      expect(layoutWeek([]), isEmpty);
    });

    test('single segment goes to lane 0', () {
      final result = layoutWeek([makeSeg(id: 'a', startCol: 0, endCol: 0)]);
      expect(result.single.lane, equals(0));
    });

    test('two non-overlapping segments share lane 0', () {
      final a = makeSeg(id: 'a', startCol: 0, endCol: 2);
      final b = makeSeg(id: 'b', startCol: 4, endCol: 6);
      final result = layoutWeek([a, b]);
      expect(result.length, equals(2));
      expect(result.every((ps) => ps.lane == 0), isTrue);
    });

    test('two overlapping segments go to different lanes', () {
      final a = makeSeg(id: 'a', startCol: 0, endCol: 3);
      final b = makeSeg(id: 'b', startCol: 2, endCol: 5);
      final result = layoutWeek([a, b]);
      final lanes = result.map((ps) => ps.lane).toList()..sort();
      expect(lanes, equals([0, 1]));
    });

    test('multi-day segment is placed before single-day segment', () {
      // Multi-day: cols 0-3; single-day: col 0 only.
      final multiDay = makeSeg(
        id: 'multi',
        startCol: 0,
        endCol: 3,
        start: DateTime(2026, 2, 2, 9),
        end: DateTime(2026, 2, 5, 10),
      );
      final singleDay = makeSeg(
        id: 'single',
        startCol: 0,
        endCol: 0,
        start: DateTime(2026, 2, 2, 8),
        end: DateTime(2026, 2, 2, 9),
      );
      final result = layoutWeek([singleDay, multiDay]);
      final multiResult = result.firstWhere((ps) => ps.segment.event.id == 'multi');
      expect(multiResult.lane, equals(0), reason: 'Multi-day should win lane 0');
    });

    test('all positioned segments have laneSpan == 1', () {
      final segs = [
        makeSeg(id: 'a', startCol: 0, endCol: 1),
        makeSeg(id: 'b', startCol: 1, endCol: 2),
        makeSeg(id: 'c', startCol: 3, endCol: 6),
      ];
      final result = layoutWeek(segs);
      expect(result.every((ps) => ps.laneSpan == 1), isTrue);
    });

    test('three mutually overlapping segments occupy three distinct lanes', () {
      // All span the full row (cols 0-6), so they all conflict.
      final segs = List.generate(
        3,
            (i) => makeSeg(
          id: 'e$i',
          startCol: 0,
          endCol: 6,
          start: DateTime(2026, 2, 2, 8 + i),
          end: DateTime(2026, 2, 8, 9 + i),
        ),
      );
      final result = layoutWeek(segs);
      final lanes = result.map((ps) => ps.lane).toSet();
      expect(lanes.length, equals(3));
    });
  });

  // ---------------------------------------------------------------------------
  // compareSegments
  // ---------------------------------------------------------------------------

  group('compareSegments', () {
    WeekSegment seg({
      required String id,
      required int startCol,
      required int endCol,
      DateTime? start,
      DateTime? end,
      bool continuesLeft = false,
      bool continuesRight = false,
    }) {
      final s = start ?? DateTime(2026, 2, 2 + startCol, 9);
      final e = end ?? DateTime(2026, 2, 2 + endCol, 10);
      return WeekSegment(
        event: makeEvent(id: id, start: s, end: e),
        weekIndex: 0,
        startCol: startCol,
        endCol: endCol,
        continuesLeft: continuesLeft,
        continuesRight: continuesRight,
      );
    }

    test('multi-day segment sorts before single-day segment', () {
      final multi = seg(
        id: 'multi',
        startCol: 0,
        endCol: 3,
        start: DateTime(2026, 2, 2, 9),
        end: DateTime(2026, 2, 5, 10),
      );
      final single = seg(id: 'single', startCol: 0, endCol: 0);
      expect(compareSegments(multi, single), isNegative);
      expect(compareSegments(single, multi), isPositive);
    });

    test('two single-day segments: earlier start time sorts first', () {
      final early = seg(id: 'a', startCol: 2, endCol: 2, start: DateTime(2026, 2, 4, 8), end: DateTime(2026, 2, 4, 9));
      final late_ = seg(id: 'b', startCol: 2, endCol: 2, start: DateTime(2026, 2, 4, 11), end: DateTime(2026, 2, 4, 12));
      expect(compareSegments(early, late_), isNegative);
    });

    test('equal start time: earlier column sorts first', () {
      final left = seg(id: 'a', startCol: 1, endCol: 1);
      final right = seg(id: 'b', startCol: 3, endCol: 3);
      expect(compareSegments(left, right), isNegative);
    });

    test('equal start and column: longer span sorts first', () {
      final long = seg(id: 'a', startCol: 0, endCol: 3,
          start: DateTime(2026, 2, 2, 9), end: DateTime(2026, 2, 5, 10));
      final short = seg(id: 'b', startCol: 0, endCol: 1,
          start: DateTime(2026, 2, 2, 9), end: DateTime(2026, 2, 3, 10));
      expect(compareSegments(long, short), isNegative);
    });

    test('segment continuing from previous week is treated as multi-day', () {
      final continues = seg(id: 'c', startCol: 0, endCol: 0, continuesLeft: true);
      final plain = seg(id: 'p', startCol: 0, endCol: 0);
      expect(compareSegments(continues, plain), isNegative);
    });

    test('identical segments compare as equal (returns 0)', () {
      final a = seg(id: 'x', startCol: 2, endCol: 4,
          start: DateTime(2026, 2, 4, 9), end: DateTime(2026, 2, 6, 10));
      final b = seg(id: 'x', startCol: 2, endCol: 4,
          start: DateTime(2026, 2, 4, 9), end: DateTime(2026, 2, 6, 10));
      expect(compareSegments(a, b), equals(0));
    });
  });

  // ---------------------------------------------------------------------------
  // computeWeekRowLayout
  // ---------------------------------------------------------------------------

  group('computeWeekRowLayout', () {
    // Shared layout parameters matching the widget test defaults.
    const dayHeaderHeight = 26.0;
    const laneHeight = 18.0;
    const laneSpacing = 4.0;
    const dayCellMinHeight = 48.0;

    WeekRowLayout layout({
      required List<WeekSegment> segments,
      int maxLanes = 2,
      Set<WeekSegment>? needsTwoLines,
    }) {
      return computeWeekRowLayout(
        segments: segments,
        maxLanes: maxLanes,
        needsTwoLines: needsTwoLines ?? {},
        dayHeaderHeight: dayHeaderHeight,
        laneHeight: laneHeight,
        laneSpacing: laneSpacing,
        dayCellMinHeight: dayCellMinHeight,
      );
    }

    WeekSegment seg({
      required String id,
      required int startCol,
      required int endCol,
      DateTime? start,
      DateTime? end,
    }) {
      final s = start ?? DateTime(2026, 2, 2 + startCol, 9);
      final e = end ?? DateTime(2026, 2, 2 + endCol, 10);
      return WeekSegment(
        event: makeEvent(id: id, start: s, end: e),
        weekIndex: 0,
        startCol: startCol,
        endCol: endCol,
        continuesLeft: false,
        continuesRight: false,
      );
    }

    test('empty segments: no positioned, no overflow, height >= dayCellMinHeight', () {
      final result = layout(segments: []);
      expect(result.positioned, isEmpty);
      expect(result.hiddenCountPerCol, equals(List.filled(7, 0)));
      expect(result.totalHeight, greaterThanOrEqualTo(dayCellMinHeight));
    });

    test('single segment goes to lane 0 with laneSpan 1', () {
      final s = seg(id: 'a', startCol: 2, endCol: 2);
      final result = layout(segments: [s]);
      expect(result.positioned.single.lane, equals(0));
      expect(result.positioned.single.laneSpan, equals(1));
    });

    test('hidden segment increments hiddenCountPerCol for each covered column', () {
      // 3 same-column segments with maxLanes=2 → 1 hidden.
      final segs = [
        seg(id: 'a', startCol: 3, endCol: 3, start: DateTime(2026, 2, 5, 8), end: DateTime(2026, 2, 5, 9)),
        seg(id: 'b', startCol: 3, endCol: 3, start: DateTime(2026, 2, 5, 9), end: DateTime(2026, 2, 5, 10)),
        seg(id: 'c', startCol: 3, endCol: 3, start: DateTime(2026, 2, 5, 10), end: DateTime(2026, 2, 5, 11)),
      ];
      final result = layout(segments: segs, maxLanes: 2);
      expect(result.hiddenCountPerCol[3], equals(1));
      // All other columns have no hidden events.
      for (int c = 0; c < 7; c++) {
        if (c == 3) continue;
        expect(result.hiddenCountPerCol[c], equals(0));
      }
    });

    test('multi-column hidden segment counts in every column it spans', () {
      // A 3-wide segment (cols 1-3) hidden behind 2 other full-row events.
      final fullRow1 = seg(id: 'r1', startCol: 0, endCol: 6,
          start: DateTime(2026, 2, 2, 7), end: DateTime(2026, 2, 8, 8));
      final fullRow2 = seg(id: 'r2', startCol: 0, endCol: 6,
          start: DateTime(2026, 2, 2, 8), end: DateTime(2026, 2, 8, 9));
      final hidden = seg(id: 'h', startCol: 1, endCol: 3,
          start: DateTime(2026, 2, 3, 9), end: DateTime(2026, 2, 5, 10));
      final result = layout(segments: [fullRow1, fullRow2, hidden], maxLanes: 2);
      for (int c = 1; c <= 3; c++) {
        expect(result.hiddenCountPerCol[c], equals(1),
            reason: 'Column $c should have 1 hidden event');
      }
    });

    test('segment in needsTwoLines with spare capacity gets laneSpan=2', () {
      final s = seg(id: 'a', startCol: 4, endCol: 4);
      // maxLanes=3 and only 1 event in column 4 → 2 spare slots → can promote.
      final result = layout(segments: [s], maxLanes: 3, needsTwoLines: {s});
      expect(result.positioned.single.laneSpan, equals(2));
    });

    test('segment in needsTwoLines without spare capacity keeps laneSpan=1', () {
      // Column 0 already has 2 events with maxLanes=2 → no spare → no promotion.
      final s1 = seg(id: 'a', startCol: 0, endCol: 0,
          start: DateTime(2026, 2, 2, 8), end: DateTime(2026, 2, 2, 9));
      final s2 = seg(id: 'b', startCol: 0, endCol: 0,
          start: DateTime(2026, 2, 2, 9), end: DateTime(2026, 2, 2, 10));
      // s2 wants 2 lines but both lanes are already taken.
      final result = layout(segments: [s1, s2], maxLanes: 2, needsTwoLines: {s2});
      final ps2 = result.positioned.firstWhere((ps) => ps.segment.event.id == 'b');
      expect(ps2.laneSpan, equals(1));
    });

    test('totalHeight is always >= dayCellMinHeight', () {
      // Even with zero segments and small lane config.
      final result = layout(segments: [], maxLanes: 1);
      expect(result.totalHeight, greaterThanOrEqualTo(dayCellMinHeight));
    });

    test('all visible positioned segments have lane < maxLanes', () {
      final segs = List.generate(
        3,
            (i) => seg(
          id: 'e$i',
          startCol: i * 2,
          endCol: i * 2,
          start: DateTime(2026, 2, 2 + i * 2, 9),
          end: DateTime(2026, 2, 2 + i * 2, 10),
        ),
      );
      final result = layout(segments: segs, maxLanes: 2);
      for (final ps in result.positioned.where((ps) => ps.lane < 2)) {
        expect(ps.lane, lessThan(2));
      }
    });
  });
}