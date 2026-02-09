import '../models/calendar_conflict.dart';
import '../models/external_event.dart';
import 'calendar_import_service.dart';
import 'database_service.dart';
import 'google_calendar_sync_service.dart';

class ExternalCalendarSyncService {
  static final ExternalCalendarSyncService _instance =
      ExternalCalendarSyncService._internal();
  factory ExternalCalendarSyncService() => _instance;
  ExternalCalendarSyncService._internal();

  final DatabaseService _db = DatabaseService();
  final CalendarImportService _device = CalendarImportService();
  final GoogleCalendarSyncService _google = GoogleCalendarSyncService();

  Future<void> syncAndBuildConflicts({
    String? deviceCalendarId, // ✅ optional로 변경 (호환 유지)
    int days = 30,
  }) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(Duration(days: days));

    // 1) DEVICE: 특정 캘린더만 or 전체 캘린더
    if (deviceCalendarId != null && deviceCalendarId.isNotEmpty) {
      await _device.importCalendar(deviceCalendarId, days: days);
    } else {
      final calendars = await _device.getCalendars();
      for (final cal in calendars) {
        await _device.importCalendar(cal.id, days: days);
      }
    }

    // 2) GOOGLE: primary
    await _google.syncPrimary(start: start, end: end);

    // 3) conflicts rebuild (event 기반)
    await _db.clearOpenConflicts();

    final events = await _db.getExternalEventsInRange(start, end);
    final conflicts = _detectConflicts(events);

    for (final c in conflicts) {
      await _db.createConflict(c);
    }

    await _db.logAction('conflicts_rebuild',
        metadata: '{"count": ${conflicts.length}}');
  }

  List<CalendarConflict> _detectConflicts(List<ExternalEvent> events) {
    final res = <CalendarConflict>[];
    final sorted = [...events]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    for (int i = 0; i < sorted.length; i++) {
      final a = sorted[i];

      for (int j = i + 1; j < sorted.length; j++) {
        final b = sorted[j];

        // 멀리 떨어지면 break
        if (b.startTime.isAfter(a.endTime.add(const Duration(minutes: 60))))
          break;

        // 다른 소스(DEVICE vs GOOGLE)만 비교
        if (a.source == b.source) continue;

        final isOverlap =
            a.startTime.isBefore(b.endTime) && b.startTime.isBefore(a.endTime);
        if (!isOverlap) continue;

        final isDuplicate = _looksDuplicate(a, b);

        res.add(CalendarConflict(
          conflictType: isDuplicate ? 'DUPLICATE' : 'TIME_OVERLAP',
          eventASource: a.source,
          eventAId: a.sourceEventId,
          eventBSource: b.source,
          eventBId: b.sourceEventId,
          status: 'OPEN',
          createdAt: DateTime.now(),
          eventA: a,
          eventB: b,
        ));
      }
    }
    return res;
  }

  bool _looksDuplicate(ExternalEvent a, ExternalEvent b) {
    final sd = (a.startTime.difference(b.startTime).inMinutes).abs();
    final ed = (a.endTime.difference(b.endTime).inMinutes).abs();
    if (sd > 10 || ed > 10) return false;

    final at = _norm(a.title);
    final bt = _norm(b.title);
    if (at.isEmpty || bt.isEmpty) return false;

    return at == bt || at.contains(bt) || bt.contains(at);
  }

  String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');
}
