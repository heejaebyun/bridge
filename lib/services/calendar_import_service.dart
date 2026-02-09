import 'package:flutter/services.dart';
import '../models/external_event.dart';
import 'database_service.dart';

class CalendarImportService {
  static final CalendarImportService _instance =
      CalendarImportService._internal();
  factory CalendarImportService() => _instance;
  CalendarImportService._internal();

  final DatabaseService _db = DatabaseService();
  static const _channel = MethodChannel('com.bridge.calendar');

  Future<List<CalendarAccount>> getCalendars() async {
    try {
      final result = await _channel.invokeMethod('getCalendars');
      final list = (result as List).cast<Map>();
      return list
          .map((m) => CalendarAccount(
                id: m['id'] as String,
                name: m['name'] as String,
                accountName: m['accountName'] as String? ?? '',
                color: m['color'] as int? ?? 0,
                eventCount: m['eventCount'] as int? ?? 0,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<ImportedEvent>> getEvents(String calendarId,
      {int days = 30}) async {
    try {
      final now = DateTime.now();
      final result = await _channel.invokeMethod('getEvents', {
        'calendarId': calendarId,
        'startMillis': now.millisecondsSinceEpoch,
        'endMillis': now.add(Duration(days: days)).millisecondsSinceEpoch,
      });

      final list = (result as List).cast<Map>();
      return list
          .map((m) => ImportedEvent(
                eventId: (m['eventId'] as String?) ?? '',
                title: m['title'] as String? ?? '(제목 없음)',
                startTime:
                    DateTime.fromMillisecondsSinceEpoch(m['start'] as int),
                endTime: DateTime.fromMillisecondsSinceEpoch(m['end'] as int),
                location: m['location'] as String?,
                description: m['description'] as String?,
                isAllDay: m['allDay'] as bool? ?? false,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// OnboardingScreen 호환 유지:
  /// - 기존 코드가 importEvents(events)로 부르므로 calendarId는 optional/default로 둔다.
  Future<int> importEvents(
    List<ImportedEvent> events, {
    String calendarId = 'unknown',
  }) async {
    final now = DateTime.now();
    final list = events
        .where((e) => e.eventId.isNotEmpty)
        .map((e) => ExternalEvent(
              source: 'DEVICE',
              sourceEventId: e.eventId,
              calendarId: calendarId,
              title: e.title,
              startTime: e.startTime,
              endTime: e.endTime,
              isAllDay: e.isAllDay,
              location: e.location,
              description: e.description,
              updatedAt: null,
              createdAt: now,
            ))
        .toList();

    if (list.isNotEmpty) {
      await _db.upsertExternalEvents(list);
    }
    await _db.logAction('device_calendar_import',
        metadata: '{"count": ${list.length}, "calendarId": "$calendarId"}');
    return list.length; // int
  }

  /// convenience: 캘린더 하나를 읽어서 바로 import
  Future<int> importCalendar(String calendarId, {int days = 30}) async {
    final events = await getEvents(calendarId, days: days);
    return importEvents(events, calendarId: calendarId);
  }
}

class CalendarAccount {
  final String id;
  final String name;
  final String accountName;
  final int color;
  final int eventCount;

  CalendarAccount({
    required this.id,
    required this.name,
    required this.accountName,
    required this.color,
    required this.eventCount,
  });
}

class ImportedEvent {
  final String eventId;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final String? location;
  final String? description;
  final bool isAllDay;

  ImportedEvent({
    required this.eventId,
    required this.title,
    required this.startTime,
    required this.endTime,
    this.location,
    this.description,
    this.isAllDay = false,
  });
}
