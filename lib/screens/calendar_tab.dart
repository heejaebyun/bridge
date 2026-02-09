/// CalendarTab: 내부 캘린더(통합) 뷰
///
/// 규칙:
/// - 읽기 전용
/// - 외부 캘린더(DEVICE/GOOGLE) read-in 결과 표시
/// - 날짜 탭하면 해당 날의 일정 리스트
/// - 충돌은 별도 인박스에서 사용자가 해결
library;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/external_event.dart';
import '../services/database_service.dart';
import '../services/external_calendar_sync_service.dart';
import 'conflict_inbox_screen.dart';

class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  final DatabaseService _db = DatabaseService();
  final ExternalCalendarSyncService _sync = ExternalCalendarSyncService();

  DateTime _focusedMonth = DateTime.now();
  DateTime _selectedDate = DateTime.now();
  final List<ExternalEvent> _selectedDateEvents = [];
  Map<DateTime, int> _eventCounts = {};
  int _openConflictCount = 0;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _loadMonth();
    _loadSelectedDate();
  }

  Future<void> _loadMonth() async {
    final counts = <DateTime, int>{};
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDay = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);

    for (var d = firstDay;
        d.isBefore(lastDay.add(const Duration(days: 1)));
        d = d.add(const Duration(days: 1))) {
      final events = await _db.getExternalEventsForDate(d);
      if (events.isNotEmpty) {
        counts[DateTime(d.year, d.month, d.day)] = events.length;
      }
    }

    if (mounted) {
      setState(() => _eventCounts = counts);
    }
  }

  Future<void> _loadSelectedDate() async {
    final cards = await _db.getConfirmedCardsForDate(_selectedDate);
    final open = await _db.getOpenConflictCount();
    if (mounted) {
      setState(() {
        _openConflictCount = open;
      });
    }
  }

  Future<void> _runSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);

    final cal = await Permission.calendar.request();
    if (!cal.isGranted) {
      if (mounted) setState(() => _syncing = false);
      return;
    }

    await _sync.syncAndBuildConflicts(days: 30);
    await _loadMonth();
    await _loadSelectedDate();

    if (mounted) setState(() => _syncing = false);
  }

  void _onDateSelected(DateTime date) {
    setState(() => _selectedDate = date);
    _loadSelectedDate();
  }

  void _changeMonth(int delta) {
    setState(() {
      _focusedMonth = DateTime(
        _focusedMonth.year,
        _focusedMonth.month + delta,
      );
    });
    _loadMonth();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1A),
      body: SafeArea(
        child: Column(
          children: [
            _buildMonthHeader(),
            _buildWeekdayHeader(),
            _buildCalendarGrid(),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              height: 1,
              color: const Color(0xFF1E293B),
            ),
            Expanded(child: _buildDaySchedule()),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => _changeMonth(-1),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.chevron_left, color: Colors.white54),
            ),
          ),
          Text(
            '${_focusedMonth.year}년 ${_focusedMonth.month}월',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Row(
            children: [
              GestureDetector(
                onTap: _syncing ? null : _runSync,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.sync_rounded,
                    color: _syncing ? Colors.white24 : const Color(0xFF22D3EE),
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ConflictInboxScreen()),
                ).then((_) => _loadSelectedDate()),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.warning_amber_rounded,
                          color: Color(0xFFF59E0B), size: 20),
                    ),
                    if (_openConflictCount > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$_openConflictCount',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _changeMonth(1),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.chevron_right, color: Colors.white54),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({required IconData icon, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFF22D3EE), size: 20),
      ),
    );
  }

  Widget _buildConflictButton() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ConflictInboxScreen()),
      ).then((_) => _loadSelectedDate()),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.warning_amber_rounded,
                color: Color(0xFFF59E0B), size: 20),
          ),
          if (_openConflictCount > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$_openConflictCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWeekdayHeader() {
    const weekdays = ['일', '월', '화', '수', '목', '금', '토'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: weekdays.map((day) {
          final isSun = day == '일';
          final isSat = day == '토';
          return Expanded(
            child: Center(
              child: Text(
                day,
                style: TextStyle(
                  fontSize: 13,
                  color: isSun
                      ? const Color(0xFFEF4444).withOpacity(0.7)
                      : isSat
                          ? const Color(0xFF3B82F6).withOpacity(0.7)
                          : Colors.white38,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final firstDayOfMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDayOfMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final firstWeekday = firstDayOfMonth.weekday % 7;

    final totalCells = firstWeekday + lastDayOfMonth.day;
    final rows = (totalCells / 7).ceil();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: List.generate(rows, (row) {
          return Row(
            children: List.generate(7, (col) {
              final index = row * 7 + col;
              final day = index - firstWeekday + 1;

              if (day < 1 || day > lastDayOfMonth.day) {
                return const Expanded(child: SizedBox(height: 44));
              }

              final date =
                  DateTime(_focusedMonth.year, _focusedMonth.month, day);
              final isToday = _isSameDay(date, DateTime.now());
              final isSelected = _isSameDay(date, _selectedDate);
              final eventCount =
                  _eventCounts[DateTime(date.year, date.month, date.day)] ?? 0;

              return Expanded(
                child: GestureDetector(
                  onTap: () => _onDateSelected(date),
                  child: Container(
                    height: 44,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF22D3EE).withOpacity(0.15)
                          : isToday
                              ? const Color(0xFF1E293B)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: isToday && !isSelected
                          ? Border.all(
                              color: const Color(0xFF22D3EE).withOpacity(0.3))
                          : isSelected
                              ? Border.all(color: const Color(0xFF22D3EE))
                              : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            fontSize: 14,
                            color: isSelected
                                ? const Color(0xFF22D3EE)
                                : col == 0
                                    ? const Color(0xFFEF4444).withOpacity(0.7)
                                    : col == 6
                                        ? const Color(0xFF3B82F6)
                                            .withOpacity(0.7)
                                        : Colors.white70,
                            fontWeight: isToday || isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        if (eventCount > 0) ...[
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              eventCount > 3 ? 3 : eventCount,
                              (_) => Container(
                                width: 4,
                                height: 4,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 1),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF22D3EE),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),
          );
        }),
      ),
    );
  }

  Widget _buildDaySchedule() {
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final wd = weekdays[_selectedDate.weekday - 1];
    final isToday = _isSameDay(_selectedDate, DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Text(
            isToday
                ? '오늘'
                : '${_selectedDate.month}/${_selectedDate.day} ($wd)',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        Expanded(
          child: _selectedDateEvents.isEmpty
              ? Center(
                  child: Text(
                    '일정이 없어요',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withOpacity(0.2),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: _selectedDateEvents.length,
                  itemBuilder: (context, index) {
                    return _buildScheduleCard(_selectedDateEvents[index]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildScheduleCard(ExternalEvent e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              _fmtTime(e.startTime),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF22D3EE),
              ),
            ),
          ),
          Container(
            width: 3,
            height: 36,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: e.source == 'GOOGLE'
                  ? const Color(0xFF3B82F6)
                  : const Color(0xFF22D3EE),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      e.source,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.35),
                      ),
                    ),
                  ],
                ),
                if ((e.location ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    e.location!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white38,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
