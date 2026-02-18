import 'package:flutter/material.dart';

import 'flappy_calendar.dart';

/// ------------------------------
/// Public widget
/// ------------------------------
class MonthCalendarView extends StatelessWidget {
  const MonthCalendarView({
    super.key,
    required this.month,
    required this.events,
    this.selectedDay,
    this.onDayTap,
    this.onEventTap,
    this.maxEventLanesPerWeek = 2,
    this.weekStartsOn = DateTime.monday,
    this.dayCellMinHeight = 92,
    this.laneHeight = 18,
    this.laneSpacing = 3,
    this.eventTextStyle,
    this.overflowTextStyle,
    this.dayIndicatorBuilder,
  });

  final DateTime month; // any day inside the target month
  final List<CalendarEvent> events;

  final DateTime? selectedDay;
  final ValueChanged<DateTime>? onDayTap;
  final ValueChanged<CalendarEvent>? onEventTap;

  final int maxEventLanesPerWeek; // <= 2 here, but generic
  final int weekStartsOn;

  final double dayCellMinHeight;
  final double laneHeight;
  final double laneSpacing;

  /// Returns a [TextStyle] merged on top of [TextTheme.labelSmall] for a given
  /// event bar. Useful for changing color, weight, etc. per event.
  final TextStyle? eventTextStyle;

  /// Override the text style of the "+N" overflow badge.
  /// Merged on top of [TextTheme.labelSmall] via [TextStyle.merge].
  final TextStyle? overflowTextStyle;

  /// Optional builder for the day-number indicator inside each cell.
  ///
  /// When provided it replaces only the day-number [Text] widget; the cell
  /// border, padding, selection background, and overflow badge are unchanged.
  ///
  /// Parameters:
  /// - [day]        The date represented by this cell.
  /// - [isInMonth]  Whether [day] belongs to the displayed month.
  /// - [isSelected] Whether [day] equals [selectedDay].
  final Widget Function(DateTime day, bool isInMonth, bool isSelected)? dayIndicatorBuilder;

  @override
  Widget build(BuildContext context) {
    final grid = buildMonthGrid(month, weekStartsOn: weekStartsOn);
    final segments = buildWeekSegments(events: events, grid: grid, month: month);

    final byWeek = <int, List<WeekSegment>>{};
    for (final s in segments) {
      byWeek.putIfAbsent(s.weekIndex, () => []).add(s);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(grid.weeks.length, (weekIndex) {
          final weekDays = grid.weeks[weekIndex];
          final weekSegments = byWeek[weekIndex] ?? const <WeekSegment>[];

          return _WeekRow(
            weekDays: weekDays,
            weekIndex: weekIndex,
            month: month,
            selectedDay: selectedDay,
            onDayTap: onDayTap,
            weekSegments: weekSegments,
            maxLanes: maxEventLanesPerWeek,
            dayCellMinHeight: dayCellMinHeight,
            laneHeight: laneHeight,
            laneSpacing: laneSpacing,
            onEventTap: onEventTap,
            eventTextStyle: eventTextStyle,
            overflowTextStyle: overflowTextStyle,
            dayIndicatorBuilder: dayIndicatorBuilder,
          );
        }),
      ],
    );
  }
}

/// ------------------------------
/// One week row (days grid + overlay events)
/// ------------------------------
class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.weekDays,
    required this.weekIndex,
    required this.month,
    required this.selectedDay,
    required this.onDayTap,
    required this.weekSegments,
    required this.maxLanes,
    required this.dayCellMinHeight,
    required this.laneHeight,
    required this.laneSpacing,
    required this.onEventTap,
    this.eventTextStyle,
    this.overflowTextStyle,
    this.dayIndicatorBuilder,
  });

  final int weekIndex; // index of this week row in the month grid (0 = first row)
  final List<DateTime> weekDays; // len 7
  final DateTime month;
  final DateTime? selectedDay;
  final ValueChanged<DateTime>? onDayTap;

  final List<WeekSegment> weekSegments; // now raw segments, layout computed here
  final int maxLanes;

  final double dayCellMinHeight;
  final double laneHeight;
  final double laneSpacing;

  final ValueChanged<CalendarEvent>? onEventTap;
  final TextStyle? eventTextStyle;
  final TextStyle? overflowTextStyle;
  final Widget Function(DateTime day, bool isInMonth, bool isSelected)? dayIndicatorBuilder;

  // Pixel height reserved for the day number at the top of each cell.
  static const double _dayHeaderHeight = 26.0;

  @override
  Widget build(BuildContext context) {
    final border = BorderSide(color: Theme.of(context).dividerColor.withAlpha((0.6 * 255).round()));
    final addTopBorder = weekIndex == 0;

    // Layout is computed inside LayoutBuilder because text measurement
    // (TextPainter) requires a known cell width.
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = constraints.maxWidth / 7;

        // --- Measure which single-day segments overflow on one line ----------
        // We use TextPainter so we can decide whether to give a segment 2 lanes
        // of height (improving readability) before the layout algorithm runs.
        final textStyle =
            eventTextStyle ??
            Theme.of(context).textTheme.labelSmall?.copyWith(height: 1.1) ??
            const TextStyle(fontSize: 12);

        final needsTwoLines = <WeekSegment>{};
        for (final seg in weekSegments) {
          final isSingleDay = isSameDay(seg.event.start, seg.event.end) && seg.startCol == seg.endCol;
          if (!isSingleDay) continue;

          final availableWidth = (seg.endCol - seg.startCol + 1) * cellWidth - 12;
          final tp = TextPainter(
            text: TextSpan(text: seg.event.title, style: textStyle),
            maxLines: 1,
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: availableWidth);

          // If the title overflows, only request two lines when it can be wrapped
          // at a word boundary. If every single word is longer than the available
          // width, forcing two lines would still break a word mid-word — avoid that.
          if (tp.didExceedMaxLines || tp.width > availableWidth) {
            final words = seg.event.title.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
            var anyWordFits = false;
            for (final w in words) {
              final wtp = TextPainter(
                text: TextSpan(text: w, style: textStyle),
                textDirection: TextDirection.ltr,
              )..layout();
              if (wtp.width <= availableWidth) {
                anyWordFits = true;
                break;
              }
            }
            if (anyWordFits) needsTwoLines.add(seg);
          }
        }

        // --- Compute lane assignment and row height --------------------------
        final layout = computeWeekRowLayout(
          segments: weekSegments,
          maxLanes: maxLanes,
          needsTwoLines: needsTwoLines,
          dayHeaderHeight: _dayHeaderHeight,
          laneHeight: laneHeight,
          laneSpacing: laneSpacing,
          dayCellMinHeight: dayCellMinHeight,
        );

        // --- Render ----------------------------------------------------------
        return SizedBox(
          height: layout.totalHeight,
          child: Stack(
            children: [
              // Background: 7 tappable day cells laid out as a row.
              Positioned.fill(
                child: Row(
                  children: List.generate(7, (col) {
                    final day = weekDays[col];
                    final isInMonth = day.month == month.month && day.year == month.year;
                    final isSelected = selectedDay != null && isSameDay(selectedDay!, day);

                    return Expanded(
                      child: InkWell(
                        onTap: onDayTap == null ? null : () => onDayTap!(day),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: col == 0 ? border : BorderSide.none,
                              top: addTopBorder ? border : BorderSide.none,
                              right: border,
                              bottom: border,
                            ),
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary.withAlpha((0.10 * 255).round())
                                : null,
                          ),
                          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Day-number indicator (custom builder or default Text).
                              Align(
                                alignment: Alignment.center,
                                child: dayIndicatorBuilder != null
                                    ? dayIndicatorBuilder!(day, isInMonth, isSelected)
                                    : Text(
                                        '${day.day}',
                                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurface,
                                        ),
                                      ),
                              ),
                              const Spacer(),
                              // "+N" overflow badge shown when some events are hidden.
                              if (layout.hiddenCountPerCol[col] > 0)
                                Align(
                                  alignment: Alignment.topRight,
                                  child: Text(
                                    '+${layout.hiddenCountPerCol[col]}',
                                    style:
                                        (Theme.of(context).textTheme.labelSmall?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface.withAlpha((0.65 * 255).round()),
                                        ))?.merge(overflowTextStyle) ??
                                        overflowTextStyle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),

              // Foreground: absolutely-positioned event bars (visible lanes only).
              ...layout.positioned.where((ps) => ps.lane < maxLanes).map((ps) {
                final seg = ps.segment;
                final left = seg.startCol * cellWidth + 2;
                final width = constraints.maxWidth - left - (6 - seg.endCol) * cellWidth - 2;
                final top = _dayHeaderHeight + ps.lane * (laneHeight + laneSpacing);
                final height = ps.laneSpan * laneHeight + (ps.laneSpan - 1) * laneSpacing;

                return Positioned(
                  left: left,
                  top: top,
                  width: width,
                  height: height,
                  child: _EventBar(
                    title: seg.event.title,
                    color: seg.event.color,
                    continuesLeft: seg.continuesLeft,
                    continuesRight: seg.continuesRight,
                    onTap: onEventTap == null ? null : () => onEventTap!(seg.event),
                    maxLines: ps.laneSpan,
                    textStyle: eventTextStyle,
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

/// ------------------------------
/// Small bar widget
/// ------------------------------
class _EventBar extends StatelessWidget {
  const _EventBar({
    required this.title,
    required this.color,
    required this.continuesLeft,
    required this.continuesRight,
    this.onTap,
    this.maxLines = 1,
    this.textStyle,
  });

  final String title;
  final Color? color;
  final bool continuesLeft;
  final bool continuesRight;
  final VoidCallback? onTap;
  final int maxLines;

  /// Override merged on top of [TextTheme.labelSmall] via [TextStyle.merge].
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? Theme.of(context).colorScheme.primary.withAlpha((0.18 * 255).round());
    final fg = Theme.of(context).colorScheme.onSurface;

    // Segments that continue across a week boundary get a flat edge on that side
    // to signal they are clipped; otherwise both sides are rounded.
    const rounded = Radius.circular(4);
    const flat = Radius.circular(0);
    final borderRadius = BorderRadius.only(
      topLeft: continuesLeft ? flat : rounded,
      bottomLeft: continuesLeft ? flat : rounded,
      topRight: continuesRight ? flat : rounded,
      bottomRight: continuesRight ? flat : rounded,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(color: bg, borderRadius: borderRadius),
          alignment: Alignment.center,
          child: Text(
            title,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style:
                textStyle ??
                (Theme.of(context).textTheme.labelSmall?.copyWith(
                  height: 1.1,
                  color: fg.withAlpha((0.85 * 255).round()),
                ))?.merge(textStyle),
          ),
        ),
      ),
    );
  }
}
