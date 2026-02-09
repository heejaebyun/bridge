import '../models/external_event.dart';
import 'database_service.dart';
import 'google_calendar_service.dart';

class GoogleCalendarSyncService {
  static final GoogleCalendarSyncService _instance =
      GoogleCalendarSyncService._internal();
  factory GoogleCalendarSyncService() => _instance;
  GoogleCalendarSyncService._internal();

  final DatabaseService _db = DatabaseService();
  final GoogleCalendarService _google = GoogleCalendarService();

  Future<bool> signInSilently() async {
    final account = await _google.signInSilently();
    return account != null;
  }

  Future<void> signInInteractive() async {
    await _google.signInInteractive();
  }

  Future<int> syncPrimary({
    required DateTime start,
    required DateTime end,
  }) async {
    // 로그인(조용히)
    await _google.signInSilently();

    final events = await _google.listEvents(
      calendarId: 'primary',
      timeMin: start,
      timeMax: end,
    );

    if (events.isNotEmpty) {
      await _db.upsertExternalEvents(events);
    }

    await _db.logAction('google_calendar_sync',
        metadata: '{"count": ${events.length}}');
    return events.length;
  }
}
