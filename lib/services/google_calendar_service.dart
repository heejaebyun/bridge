import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../models/external_event.dart';

/// GoogleCalendarService
/// - Google OAuth (google_sign_in)로 Access Token 획득
/// - Google Calendar API (REST)로 캘린더/이벤트 읽어오기
///
/// v0 범위: read-in only (write-back 없음)
class GoogleCalendarService {
  static final GoogleCalendarService _instance =
      GoogleCalendarService._internal();
  factory GoogleCalendarService() => _instance;
  GoogleCalendarService._internal();

  // 최소 권한: 읽기
  static const List<String> _scopes = <String>[
    'https://www.googleapis.com/auth/calendar.readonly',
  ];

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: _scopes,
  );

  GoogleSignInAccount? _currentAccount;

  Future<GoogleSignInAccount?> signInSilently() async {
    try {
      _currentAccount = await _googleSignIn.signInSilently();
      return _currentAccount;
    } catch (_) {
      return null;
    }
  }

  Future<GoogleSignInAccount?> signInInteractive() async {
    _currentAccount = await _googleSignIn.signIn();
    return _currentAccount;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentAccount = null;
  }

  Future<String?> _getAccessToken() async {
    final account = _currentAccount ?? await signInSilently();
    if (account == null) return null;
    final auth = await account.authentication;
    return auth.accessToken;
  }

  Future<List<Map<String, dynamic>>> listCalendars() async {
    final token = await _getAccessToken();
    if (token == null) return [];

    final uri = Uri.parse(
        'https://www.googleapis.com/calendar/v3/users/me/calendarList');
    final res = await http.get(uri, headers: {
      'Authorization': 'Bearer $token',
    });
    if (res.statusCode != 200) return [];

    final jsonBody = json.decode(res.body) as Map<String, dynamic>;
    final items = (jsonBody['items'] as List? ?? const []).cast<Map>();
    return items.map((m) => m.cast<String, dynamic>()).toList();
  }

  /// 기본: primary 캘린더 이벤트를 기간 기반으로 읽어옴
  Future<List<ExternalEvent>> listEvents({
    String calendarId = 'primary',
    required DateTime timeMin,
    required DateTime timeMax,
  }) async {
    final token = await _getAccessToken();
    if (token == null) return [];

    final uri = Uri.https(
      'www.googleapis.com',
      '/calendar/v3/calendars/${Uri.encodeComponent(calendarId)}/events',
      {
        'timeMin': timeMin.toUtc().toIso8601String(),
        'timeMax': timeMax.toUtc().toIso8601String(),
        'singleEvents': 'true',
        'orderBy': 'startTime',
        'maxResults': '2500',
      },
    );

    final res = await http.get(uri, headers: {
      'Authorization': 'Bearer $token',
    });
    if (res.statusCode != 200) return [];

    final body = json.decode(res.body) as Map<String, dynamic>;
    final items = (body['items'] as List? ?? const []).cast<Map>();

    final events = <ExternalEvent>[];
    for (final raw in items) {
      final m = raw.cast<String, dynamic>();
      final id = (m['id'] as String?) ?? '';
      if (id.isEmpty) continue;

      final summary = (m['summary'] as String?) ?? '(제목 없음)';
      final location = m['location'] as String?;
      final description = m['description'] as String?;
      final updated = m['updated'] as String?;

      final start = m['start'] as Map<String, dynamic>?;
      final end = m['end'] as Map<String, dynamic>?;
      if (start == null || end == null) continue;

      final isAllDay =
          start.containsKey('date') && !start.containsKey('dateTime');
      final startStr =
          (start['dateTime'] as String?) ?? (start['date'] as String?);
      final endStr = (end['dateTime'] as String?) ?? (end['date'] as String?);
      if (startStr == null || endStr == null) continue;

      // Google은 UTC/타임존 포함 ISO8601을 줌
      final startTime = DateTime.parse(startStr).toLocal();
      final endTime = DateTime.parse(endStr).toLocal();

      events.add(
        ExternalEvent(
          source: 'GOOGLE',
          sourceEventId: id,
          calendarId: calendarId,
          title: summary,
          startTime: startTime,
          endTime: endTime,
          isAllDay: isAllDay,
          location: location,
          description: description,
          updatedAt: updated != null ? DateTime.parse(updated).toLocal() : null,
        ),
      );
    }

    return events;
  }
}
