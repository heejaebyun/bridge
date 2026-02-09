/// SmartNotificationService: 사용자 패턴 학습 기반 스마트 알림
///
/// Phase 1 핵심:
/// - 사용자가 앱을 여는 시간대 학습 (최근 4주)
/// - 요일별 최적 알림 시간 계산
/// - 반응률 낮은 요일은 알림 줄임
/// - 30분 전 일정 리마인더
/// - 주간 리포트 푸시

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';
import 'card_service.dart';

class SmartNotificationService {
  static final SmartNotificationService _instance =
      SmartNotificationService._internal();
  factory SmartNotificationService() => _instance;
  SmartNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final DatabaseService _db = DatabaseService();
  final CardService _cardService = CardService();

  bool _isInitialized = false;

  // ============================================
  // 초기화
  // ============================================

  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings =
        InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
    _isInitialized = true;
  }

  void _onNotificationTap(NotificationResponse response) {
    _db.logAction('notification_tap',
        metadata: '{"payload": "${response.payload}"}');
  }

  // ============================================
  // 앱 사용 패턴 학습
  // ============================================

  /// 앱 열림 기록 (main.dart didChangeAppLifecycleState에서 호출)
  Future<void> recordAppOpen() async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();

    // 요일별 앱 오픈 시간 기록
    final key = 'app_opens_${now.weekday}';
    final existing = prefs.getStringList(key) ?? [];
    existing.add(now.toIso8601String());

    // 최근 28일만 유지
    final cutoff = now.subtract(const Duration(days: 28));
    final filtered = existing.where((s) {
      try { return DateTime.parse(s).isAfter(cutoff); }
      catch (_) { return false; }
    }).toList();

    await prefs.setStringList(key, filtered);
    await _db.logAction('app_open',
        metadata: '{"weekday": ${now.weekday}, "hour": ${now.hour}}');
  }

  /// 알림 반응 기록
  Future<void> recordNotificationResponse(bool didOpen) async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();

    final key = 'notif_response_${now.weekday}';
    final existing = prefs.getStringList(key) ?? [];
    existing.add('${didOpen ? 1 : 0}:${now.toIso8601String()}');

    // 최근 28일
    final cutoff = now.subtract(const Duration(days: 28));
    final filtered = existing.where((s) {
      try {
        final ts = s.split(':').sublist(1).join(':');
        return DateTime.parse(ts).isAfter(cutoff);
      } catch (_) { return false; }
    }).toList();

    await prefs.setStringList(key, filtered);
  }

  // ============================================
  // 최적 알림 시간 계산
  // ============================================

  /// 요일별 최적 아침 알림 시간
  Future<NotificationSchedule> getOptimalMorningTime(int weekday) async {
    final prefs = await SharedPreferences.getInstance();
    final opens = prefs.getStringList('app_opens_$weekday') ?? [];

    if (opens.length < 3) {
      return NotificationSchedule(hour: 8, minute: 0, shouldSend: true, confidence: 'default');
    }

    // 아침 시간대 (6~12시) 오픈만 필터
    final morningMinutes = <int>[];
    for (final s in opens) {
      try {
        final dt = DateTime.parse(s);
        if (dt.hour >= 6 && dt.hour <= 12) {
          morningMinutes.add(dt.hour * 60 + dt.minute);
        }
      } catch (_) {}
    }

    if (morningMinutes.isEmpty) {
      return NotificationSchedule(hour: 8, minute: 0, shouldSend: true, confidence: 'default');
    }

    // 평균 - 10분 (약간 먼저)
    final avg = morningMinutes.reduce((a, b) => a + b) ~/ morningMinutes.length;
    final target = (avg - 10).clamp(360, 720);

    return NotificationSchedule(
      hour: target ~/ 60,
      minute: target % 60,
      shouldSend: true,
      confidence: morningMinutes.length >= 7 ? 'high' : 'learning',
    );
  }

  /// 요일별 최적 저녁 알림 시간
  Future<NotificationSchedule> getOptimalEveningTime(int weekday) async {
    final prefs = await SharedPreferences.getInstance();
    final opens = prefs.getStringList('app_opens_$weekday') ?? [];

    if (opens.length < 3) {
      return NotificationSchedule(hour: 19, minute: 0, shouldSend: true, confidence: 'default');
    }

    final eveningMinutes = <int>[];
    for (final s in opens) {
      try {
        final dt = DateTime.parse(s);
        if (dt.hour >= 18 && dt.hour <= 23) {
          eveningMinutes.add(dt.hour * 60 + dt.minute);
        }
      } catch (_) {}
    }

    if (eveningMinutes.isEmpty) {
      return NotificationSchedule(hour: 19, minute: 0, shouldSend: true, confidence: 'default');
    }

    final avg = eveningMinutes.reduce((a, b) => a + b) ~/ eveningMinutes.length;
    final target = (avg - 5).clamp(1080, 1380);

    return NotificationSchedule(
      hour: target ~/ 60,
      minute: target % 60,
      shouldSend: true,
      confidence: eveningMinutes.length >= 7 ? 'high' : 'learning',
    );
  }

  /// 이 요일에 알림 보낼 가치가 있는지
  Future<bool> shouldSendOnWeekday(int weekday) async {
    final prefs = await SharedPreferences.getInstance();
    final responses = prefs.getStringList('notif_response_$weekday') ?? [];

    if (responses.length < 4) return true;

    int total = 0, opened = 0;
    for (final r in responses) {
      total++;
      if (r.startsWith('1:')) opened++;
    }
    return (opened / total) > 0.1; // 10% 이하면 스킵
  }

  // ============================================
  // 알림 스케줄링
  // ============================================

  /// 내일 알림 세팅 (매일 자정 or 앱 종료 시 호출)
  Future<void> scheduleNextDayNotifications() async {
    await initialize();

    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final wd = tomorrow.weekday;

    if (!await shouldSendOnWeekday(wd)) return;

    // 아침 브리핑
    final morning = await getOptimalMorningTime(wd);
    if (morning.shouldSend) {
      await _scheduleMorningBriefing(tomorrow, morning);
    }

    // 저녁 Triage
    final evening = await getOptimalEveningTime(wd);
    if (evening.shouldSend) {
      await _scheduleEveningTriage(tomorrow, evening);
    }
  }

  Future<void> _scheduleMorningBriefing(
      DateTime date, NotificationSchedule schedule) async {
    final timeline = await _cardService.getTodayTimeline();
    final count = timeline.confirmedCards.length;
    final triage = timeline.triageCardCount;

    String title, body;
    if (count == 0 && triage == 0) {
      title = '☀️ 좋은 아침!';
      body = '오늘은 한가해요. 뭐 할 계획 있어요?';
    } else if (count == 0 && triage > 0) {
      title = '📌 정리할 거 $triage개';
      body = '어제 입력한 카드부터 정리해요';
    } else {
      final totalFree = timeline.freeSlots
          .fold<int>(0, (sum, s) => sum + s.durationMinutes);
      title = '📋 오늘 일정 ${count}개';
      body = totalFree > 60
          ? '빈 시간 ${(totalFree / 60).toStringAsFixed(1)}시간 있어요'
          : '빡빡한 하루! 화이팅 💪';
    }

    await _showScheduledNotification(
      id: 100,
      title: title,
      body: body,
      payload: 'morning_briefing',
      when: DateTime(date.year, date.month, date.day, schedule.hour, schedule.minute),
    );
  }

  Future<void> _scheduleEveningTriage(
      DateTime date, NotificationSchedule schedule) async {
    await _showScheduledNotification(
      id: 200,
      title: '🌙 하루 정리할 시간',
      body: '오늘 입력한 것들 같이 정리할까요?',
      payload: 'evening_triage',
      when: DateTime(date.year, date.month, date.day, schedule.hour, schedule.minute),
    );
  }

  /// 다음 일정 30분 전 리마인더
  Future<void> checkUpcomingEvents() async {
    await initialize();
    final cards = await _db.getTodayConfirmedCards();
    final now = DateTime.now();

    for (final card in cards) {
      if (card.startTime == null) continue;
      final diff = card.startTime!.difference(now).inMinutes;
      if (diff > 25 && diff <= 35) {
        await _showNotification(
          id: 1000 + (card.id ?? 0),
          title: '⏰ 30분 후',
          body: '${card.categoryEmoji} ${card.title}'
              '${card.location != null ? ' @ ${card.location}' : ''}',
          payload: 'upcoming_${card.id}',
        );
      }
    }
  }

  /// 주간 리포트 푸시 (일요일 저녁)
  Future<void> sendWeeklyReportNotification() async {
    await initialize();
    final now = DateTime.now();
    if (now.weekday != DateTime.sunday) return;

    final stats = await _db.getActionStats(7);
    final avgDaily = await _db.getAverageDailyCards(7);
    final confirmed = stats['card_confirm'] ?? 0;

    final body = confirmed == 0
        ? '이번 주는 조용했네요. 다음 주 화이팅!'
        : '이번 주: 일정 $confirmed개 완료, 하루 평균 ${avgDaily.toStringAsFixed(1)}개';

    await _showNotification(
      id: 300,
      title: '📊 이번 주 리포트',
      body: body,
      payload: 'weekly_report',
    );
  }

  /// 빈 시간 추천 알림 (Phase 2 연동)
  Future<void> sendRecommendationNotification(String text, int freeMinutes) async {
    await initialize();
    await _showNotification(
      id: 400,
      title: '💡 빈 시간 ${freeMinutes}분',
      body: text,
      payload: 'recommendation',
    );
  }

  // ============================================
  // 내부 유틸
  // ============================================

  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'bridge_smart', 'Bridge 스마트 알림',
        channelDescription: '개인화된 일정 알림',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _notifications.show(id, title, body, details, payload: payload);
  }

  Future<void> _showScheduledNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    required DateTime when,
  }) async {
    // 미래 시간이면 예약, 아니면 즉시 표시
    // (실제 프로덕션에서는 flutter_timezone + zonedSchedule 사용)
    if (when.isAfter(DateTime.now())) {
      // 간이 구현: SharedPreferences에 저장 후 앱 포그라운드 시 체크
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getStringList('pending_notifications') ?? [];
      pending.add('$id|$title|$body|${payload ?? ''}|${when.toIso8601String()}');
      await prefs.setStringList('pending_notifications', pending);
    } else {
      await _showNotification(id: id, title: title, body: body, payload: payload);
    }
  }

  /// 대기 중인 예약 알림 체크 (앱 포그라운드 시 호출)
  Future<void> checkPendingNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList('pending_notifications') ?? [];
    final now = DateTime.now();
    final remaining = <String>[];

    for (final p in pending) {
      final parts = p.split('|');
      if (parts.length < 5) continue;

      final when = DateTime.tryParse(parts[4]);
      if (when == null) continue;

      if (when.isBefore(now)) {
        await _showNotification(
          id: int.tryParse(parts[0]) ?? 0,
          title: parts[1],
          body: parts[2],
          payload: parts[3].isEmpty ? null : parts[3],
        );
      } else {
        remaining.add(p);
      }
    }

    await prefs.setStringList('pending_notifications', remaining);
  }

  /// 학습된 패턴 조회 (디버그/대시보드용)
  Future<Map<String, dynamic>> getLearnedPatterns() async {
    final patterns = <String, dynamic>{};
    final names = ['', '월', '화', '수', '목', '금', '토', '일'];

    for (int wd = 1; wd <= 7; wd++) {
      final morning = await getOptimalMorningTime(wd);
      final evening = await getOptimalEveningTime(wd);
      final send = await shouldSendOnWeekday(wd);

      patterns['${names[wd]}요일'] = {
        'morning': '${morning.hour}:${morning.minute.toString().padLeft(2, '0')}',
        'evening': '${evening.hour}:${evening.minute.toString().padLeft(2, '0')}',
        'shouldSend': send,
        'confidence': morning.confidence,
      };
    }
    return patterns;
  }
}

class NotificationSchedule {
  final int hour;
  final int minute;
  final bool shouldSend;
  final String confidence;

  NotificationSchedule({
    required this.hour,
    required this.minute,
    required this.shouldSend,
    required this.confidence,
  });
}
