import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show immutable;

@immutable
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.color,
    this.isAllDay = false,
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final Color? color;
  final bool isAllDay;
}

// ---------------------------------------------------------------------------
// Date helpers
// ---------------------------------------------------------------------------

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

// ---------------------------------------------------------------------------
// Grid model
// ---------------------------------------------------------------------------

class MonthGrid {
  MonthGrid({required this.visibleStart, required this.visibleEnd, required this.weeks});

  /// First day shown in the grid (may be in the previous month).
  final DateTime visibleStart; // inclusive

  /// Last day shown in the grid (may be in the next month).
  final DateTime visibleEnd; // inclusive

  /// weeks[w][c] => DateTime for week w, column c (0=first day of week).
  final List<List<DateTime>> weeks;
}

/// Builds the full visible grid for [month].
///
/// [weekStartsOn] uses [DateTime] weekday constants (Monday = 1, Sunday = 7).
MonthGrid buildMonthGrid(DateTime month, {int weekStartsOn = DateTime.monday}) {
  final firstOfMonth = DateTime(month.year, month.month, 1);
  final firstDayWeekday = firstOfMonth.weekday; // 1..7

  int delta = firstDayWeekday - weekStartsOn;
  if (delta < 0) delta += 7;

  // Use DateTime(y, m, d) arithmetic to avoid DST pitfalls: adding/subtracting
  // Duration(days: N) to a local midnight can land at 23:00 on DST transition days.
  final visibleStart = DateTime(month.year, month.month, 1 - delta);

  final lastOfMonth = DateTime(month.year, month.month + 1, 0); // day 0 = last of previous month

  int endDelta = (weekStartsOn + 6) - lastOfMonth.weekday;
  if (endDelta < 0) endDelta += 7;

  final visibleEnd = DateTime(lastOfMonth.year, lastOfMonth.month, lastOfMonth.day + endDelta);

  // Compute week count from integer deltas — avoids calling difference() on local
  // DateTimes, which is unreliable across DST transitions.
  final daysCount = delta + lastOfMonth.day + endDelta;
  final weeksCount = daysCount ~/ 7; // always a whole number of weeks

  final weeks = <List<DateTime>>[];
  for (int w = 0; w < weeksCount; w++) {
    final week = <DateTime>[];
    for (int c = 0; c < 7; c++) {
      week.add(DateTime(visibleStart.year, visibleStart.month, visibleStart.day + w * 7 + c));
    }
    weeks.add(week);
  }

  return MonthGrid(visibleStart: visibleStart, visibleEnd: visibleEnd, weeks: weeks);
}

// ---------------------------------------------------------------------------
// Segment model (one slice of an event per week row)
// ---------------------------------------------------------------------------

class WeekSegment {
  WeekSegment({
    required this.event,
    required this.weekIndex,
    required this.startCol,
    required this.endCol,
    required this.continuesLeft,
    required this.continuesRight,
  });

  final CalendarEvent event;
  final int weekIndex; // 0..weeks-1
  final int startCol; // 0..6
  final int endCol; // 0..6

  /// True when the event started before this week's first day.
  final bool continuesLeft;

  /// True when the event ends after this week's last day.
  final bool continuesRight;
}

/// Splits [events] into per-week segments relative to [grid].
///
/// If [month] is provided, events are additionally clamped to that month so
/// that they do not render in adjacent-month padding cells.
List<WeekSegment> buildWeekSegments({required List<CalendarEvent> events, required MonthGrid grid, DateTime? month}) {
  final visibleStart = grid.visibleStart;
  final visibleEnd = grid.visibleEnd;

  DateTime? monthStart;
  DateTime? monthEnd;
  if (month != null) {
    monthStart = DateTime(month.year, month.month, 1);
    monthEnd = DateTime(month.year, month.month + 1, 0); // day 0 = last day of month
  }

  // Use UTC-based difference to count calendar days without DST interference.
  // visibleStart is always a local midnight produced by DateTime(y,m,d) arithmetic,
  // so converting both sides to UTC gives an exact multiple of 86400 seconds.
  final visibleStartUtc = DateTime.utc(visibleStart.year, visibleStart.month, visibleStart.day);

  int weekIndexForDay(DateTime d) => DateTime.utc(d.year, d.month, d.day).difference(visibleStartUtc).inDays ~/ 7;

  int colIndexForDay(DateTime d) => DateTime.utc(d.year, d.month, d.day).difference(visibleStartUtc).inDays % 7;

  final segments = <WeekSegment>[];

  for (final e in events) {
    final startDay = dayOnly(e.start);
    final endDay = dayOnly(e.end);
    if (endDay.isBefore(visibleStart) || startDay.isAfter(visibleEnd)) {
      continue;
    }

    // Clamp to the visible grid.
    DateTime effectiveStart = startDay.isBefore(visibleStart) ? visibleStart : startDay;
    DateTime effectiveEnd = endDay.isAfter(visibleEnd) ? visibleEnd : endDay;

    // Additionally clamp to the target month when provided.
    if (monthStart != null && monthEnd != null) {
      if (effectiveEnd.isBefore(monthStart) || effectiveStart.isAfter(monthEnd)) continue;
      if (effectiveStart.isBefore(monthStart)) effectiveStart = monthStart;
      if (effectiveEnd.isAfter(monthEnd)) effectiveEnd = monthEnd;
    }

    final startWeek = weekIndexForDay(effectiveStart);
    final endWeek = weekIndexForDay(effectiveEnd);

    for (int w = startWeek; w <= endWeek; w++) {
      final weekStartDay = DateTime(visibleStart.year, visibleStart.month, visibleStart.day + w * 7);
      final weekEndDay = DateTime(visibleStart.year, visibleStart.month, visibleStart.day + w * 7 + 6);

      final segStartDay = effectiveStart.isAfter(weekStartDay) ? effectiveStart : weekStartDay;
      final segEndDay = effectiveEnd.isBefore(weekEndDay) ? effectiveEnd : weekEndDay;

      if (segEndDay.isBefore(segStartDay)) continue;

      segments.add(
        WeekSegment(
          event: e,
          weekIndex: w,
          startCol: colIndexForDay(segStartDay),
          endCol: colIndexForDay(segEndDay),
          continuesLeft: startDay.isBefore(segStartDay),
          continuesRight: endDay.isAfter(segEndDay),
        ),
      );
    }
  }

  return segments;
}

// ---------------------------------------------------------------------------
// Lane-assignment model
// ---------------------------------------------------------------------------

class PositionedSegment {
  PositionedSegment({required this.segment, required this.lane, required this.laneSpan});

  final WeekSegment segment;

  /// First lane index (0-based).
  final int lane;

  /// How many lanes this segment occupies vertically.
  final int laneSpan;
}

bool overlapsColumns(WeekSegment a, WeekSegment b) {
  return !(a.endCol < b.startCol || b.endCol < a.startCol);
}

/// Greedy lane assignment for a single week row.
///
/// Multi-day segments are prioritised, then ordered by start time.
/// Each segment occupies exactly 1 lane.
///
/// Note: the adaptive 2-line promotion used by the real [_WeekRow] widget is
/// NOT replicated here — it requires text measurement which needs Flutter.
/// This function is kept as the testable, Flutter-free baseline.
List<PositionedSegment> layoutWeek(List<WeekSegment> weekSegments) {
  final sorted = [...weekSegments]
    ..sort((x, y) {
      final xMulti =
          x.startCol != x.endCol || x.continuesLeft || x.continuesRight || !isSameDay(x.event.start, x.event.end);
      final yMulti =
          y.startCol != y.endCol || y.continuesLeft || y.continuesRight || !isSameDay(y.event.start, y.event.end);
      if (xMulti != yMulti) return xMulti ? -1 : 1;

      final startCmp = x.event.start.compareTo(y.event.start);
      if (startCmp != 0) return startCmp;

      final c0 = x.startCol.compareTo(y.startCol);
      if (c0 != 0) return c0;
      final c1 = y.endCol.compareTo(x.endCol);
      if (c1 != 0) return c1;
      return x.event.title.compareTo(y.event.title);
    });

  final lanes = <List<WeekSegment>>[];
  final positioned = <PositionedSegment>[];

  for (final seg in sorted) {
    int laneIndex = -1;

    for (int l = 0; l < lanes.length; l++) {
      if (!lanes[l].any((s) => overlapsColumns(s, seg))) {
        laneIndex = l;
        break;
      }
    }

    if (laneIndex == -1) {
      lanes.add([seg]);
      laneIndex = lanes.length - 1;
    } else {
      lanes[laneIndex].add(seg);
    }

    positioned.add(PositionedSegment(segment: seg, lane: laneIndex, laneSpan: 1));
  }

  return positioned;
}

// ---------------------------------------------------------------------------
// Week-row layout result
// ---------------------------------------------------------------------------

/// Sorting priority used when assigning lanes within a week row.
///
/// Multi-day segments are sorted before single-day ones so they claim the top
/// lanes, matching Google Calendar / Apple Calendar conventions.
bool _isMultiDay(WeekSegment s) =>
    s.startCol != s.endCol || s.continuesLeft || s.continuesRight || !isSameDay(s.event.start, s.event.end);

/// Comparator that puts multi-day segments first, then sorts by start time,
/// then by column, span length, and title as tiebreakers.
int compareSegments(WeekSegment x, WeekSegment y) {
  final xMulti = _isMultiDay(x);
  final yMulti = _isMultiDay(y);
  if (xMulti != yMulti) return xMulti ? -1 : 1;

  final startCmp = x.event.start.compareTo(y.event.start);
  if (startCmp != 0) return startCmp;

  final c0 = x.startCol.compareTo(y.startCol);
  if (c0 != 0) return c0;
  final c1 = y.endCol.compareTo(x.endCol); // longer span first
  if (c1 != 0) return c1;
  return x.event.title.compareTo(y.event.title);
}

/// Fully computed layout for one week row, ready for the widget to render.
///
/// Produced by [computeWeekRowLayout]; requires text measurements supplied
/// by the caller (because [TextPainter] lives in Flutter, not pure Dart).
class WeekRowLayout {
  WeekRowLayout({required this.positioned, required this.hiddenCountPerCol, required this.totalHeight});

  /// All segments with their lane assignment. Segments with [PositionedSegment.lane]
  /// >= [maxLanes] are hidden and should not be rendered as bars.
  final List<PositionedSegment> positioned;

  /// For each of the 7 columns: how many segments are hidden due to the lane cap.
  /// Used to render the "+N" overflow badge.
  final List<int> hiddenCountPerCol;

  /// Pixel height the week row should occupy.
  final double totalHeight;
}

/// Computes the full lane layout for one week row.
///
/// Parameters:
/// - [segments]         Raw segments for this week, unsorted.
/// - [maxLanes]         Maximum number of visible event lanes.
/// - [needsTwoLines]    Set of segments that require 2-lane height (text wraps).
///                      Determined by the caller via [TextPainter].
/// - [dayHeaderHeight]  Pixel height reserved for the day number at the top.
/// - [laneHeight]       Pixel height of a single event lane.
/// - [laneSpacing]      Pixel gap between consecutive lanes.
/// - [dayCellMinHeight] Minimum height for the whole row.
///
/// Returns a [WeekRowLayout] the widget can use directly.
WeekRowLayout computeWeekRowLayout({
  required List<WeekSegment> segments,
  required int maxLanes,
  required Set<WeekSegment> needsTwoLines,
  required double dayHeaderHeight,
  required double laneHeight,
  required double laneSpacing,
  required double dayCellMinHeight,
}) {
  // --- Step 1: sort (multi-day first, then by start time) -------------------
  final sorted = [...segments]..sort(compareSegments);

  // --- Step 2: decide which overflow-text segments to promote to 2-lane -----
  // A segment may be promoted only when it is the sole occupant of its column
  // and there is spare lane capacity (i.e. the column has fewer events than
  // maxLanes). This prevents 2-line events from crowding out other events.
  final candidatesByDay = List<List<WeekSegment>>.generate(7, (_) => []);
  final totalEventsByDay = List<Set<String>>.generate(7, (_) => <String>{});

  for (final seg in sorted) {
    for (int c = seg.startCol; c <= seg.endCol; c++) {
      totalEventsByDay[c].add(seg.event.id);
      if (needsTwoLines.contains(seg) && seg.startCol == c && seg.endCol == c) {
        candidatesByDay[c].add(seg);
      }
    }
  }

  final promoted = <WeekSegment>{};
  for (int c = 0; c < 7; c++) {
    final spare = maxLanes - totalEventsByDay[c].length;
    if (spare <= 0) continue;
    final candidates = [...candidatesByDay[c]]..sort((a, b) => a.event.start.compareTo(b.event.start));
    for (int i = 0; i < candidates.length && i < spare; i++) {
      promoted.add(candidates[i]);
    }
  }

  // --- Step 3: greedy lane assignment (supports variable-height segments) ---
  // lanes[i] holds the segments currently occupying lane i.
  // A promoted segment needs 2 consecutive free lanes.
  final lanes = <List<WeekSegment>>[];
  final positioned = <PositionedSegment>[];

  for (final seg in sorted) {
    final requiredLanes = promoted.contains(seg) ? 2 : 1;

    int laneIndex = maxLanes; // default: hidden

    outer:
    for (int l = 0; l <= lanes.length; l++) {
      if (l + requiredLanes > maxLanes) break; // would exceed cap → hidden

      // Grow the lanes list lazily.
      while (lanes.length < l + requiredLanes) {
        lanes.add([]);
      }

      // Check that all required consecutive lanes are free for this segment.
      for (int check = l; check < l + requiredLanes; check++) {
        if (lanes[check].any((s) => overlapsColumns(s, seg))) continue outer;
      }

      laneIndex = l;
      break;
    }

    if (laneIndex < maxLanes) {
      for (int place = laneIndex; place < laneIndex + requiredLanes; place++) {
        lanes[place].add(seg);
      }
    }

    positioned.add(PositionedSegment(segment: seg, lane: laneIndex, laneSpan: requiredLanes));
  }

  // --- Step 4: per-column hidden-event count (drives the "+N" badge) --------
  final hiddenCountPerCol = List<int>.filled(7, 0);
  for (final ps in positioned) {
    if (ps.lane < maxLanes) continue;
    for (int c = ps.segment.startCol; c <= ps.segment.endCol; c++) {
      hiddenCountPerCol[c]++;
    }
  }

  // --- Step 5: row height ---------------------------------------------------
  // The row must be tall enough for:
  //   • the day-number header
  //   • the lanes actually used by visible segments
  //   • a consistent minimum (maxLanes reserved) so weeks without events
  //     have the same height as weeks with events
  //   • space for the "+N" badge when overflow exists
  final usedLaneCount = positioned
      .where((ps) => ps.lane < maxLanes)
      .fold(0, (acc, ps) => acc > ps.lane + ps.laneSpan ? acc : ps.lane + ps.laneSpan);

  double lanesHeight(int count) => count > 0 ? count * laneHeight + (count - 1) * laneSpacing : 0;

  final plusBadgeReserve = laneHeight.clamp(18.0, double.infinity);
  final minForUsed = dayHeaderHeight + lanesHeight(usedLaneCount) + 6;
  final minForMax = dayHeaderHeight + lanesHeight(maxLanes) + plusBadgeReserve + 6;
  final totalHeight = [dayCellMinHeight, minForUsed, minForMax].reduce((a, b) => a > b ? a : b);

  return WeekRowLayout(positioned: positioned, hiddenCountPerCol: hiddenCountPerCol, totalHeight: totalHeight);
}
