/// RepeatDetectionService: 반복 일정 자동 감지
///
/// Phase 1 핵심:
/// 3주 연속 같은 요일+비슷한 시간에 유사 제목의 카드 →
/// "이거 매주 반복할까요?" 제안
///
/// 예: 매주 화요일 10시 "팀미팅" → 반복 일정 제안
/// 예: 매주 월/수/금 19시 "헬스장" → 반복 일정 제안

import '../models/bridge_card.dart';
import 'database_service.dart';

class RepeatDetectionService {
  static final RepeatDetectionService _instance =
      RepeatDetectionService._internal();
  factory RepeatDetectionService() => _instance;
  RepeatDetectionService._internal();

  final DatabaseService _db = DatabaseService();

  /// 반복 패턴 감지 (주 1회 호출 권장)
  Future<List<RepeatPattern>> detectPatterns() async {
    final db = await _db.database;

    // 최근 4주간 확정 카드 중 시간 있는 것들
    final since =
        DateTime.now().subtract(const Duration(days: 28)).toIso8601String();

    final cards = await db.rawQuery('''
      SELECT * FROM cards
      WHERE status = ? AND start_time IS NOT NULL AND created_at >= ?
      ORDER BY start_time ASC
    ''', [CardStatus.confirmed.index, since]);

    final allCards = cards.map((m) => BridgeCard.fromMap(m)).toList();

    // 요일 + 시간대 + 유사 제목으로 그룹핑
    final groups = <String, List<BridgeCard>>{};

    for (final card in allCards) {
      if (card.startTime == null) continue;

      final weekday = card.startTime!.weekday;
      final hourBucket = (card.startTime!.hour ~/ 2) * 2; // 2시간 단위
      final titleKey = _normalizeTitle(card.title);

      final key = '$weekday:$hourBucket:$titleKey';
      groups.putIfAbsent(key, () => []).add(card);
    }

    // 3주 이상 반복된 그룹 → 패턴
    final patterns = <RepeatPattern>[];

    for (final entry in groups.entries) {
      if (entry.value.length < 3) continue;

      // 서로 다른 주에 속하는지 확인
      final weeks = <int>{};
      for (final card in entry.value) {
        final weekNum = _weekNumber(card.startTime!);
        weeks.add(weekNum);
      }

      if (weeks.length < 3) continue;

      // 이미 반복으로 표시된 카드면 스킵
      if (entry.value.every((c) => c.isRepeating)) continue;

      final parts = entry.key.split(':');
      final weekday = int.parse(parts[0]);
      final hourBucket = int.parse(parts[1]);

      // 평균 시간 계산
      final avgMinute = entry.value
              .map((c) => c.startTime!.hour * 60 + c.startTime!.minute)
              .reduce((a, b) => a + b) ~/
          entry.value.length;

      // 대표 제목 (가장 빈번한 것)
      final titleCounts = <String, int>{};
      for (final c in entry.value) {
        titleCounts[c.title] = (titleCounts[c.title] ?? 0) + 1;
      }
      final bestTitle = titleCounts.entries
          .reduce((a, b) => a.value > b.value ? a : b)
          .key;

      // 대표 카테고리
      final catCounts = <CardCategory, int>{};
      for (final c in entry.value) {
        catCounts[c.category] = (catCounts[c.category] ?? 0) + 1;
      }
      final bestCat = catCounts.entries
          .reduce((a, b) => a.value > b.value ? a : b)
          .key;

      patterns.add(RepeatPattern(
        weekday: weekday,
        hour: avgMinute ~/ 60,
        minute: avgMinute % 60,
        title: bestTitle,
        category: bestCat,
        occurrences: entry.value.length,
        weekCount: weeks.length,
        relatedCardIds: entry.value.map((c) => c.id!).toList(),
        location: entry.value
            .map((c) => c.location)
            .whereType<String>()
            .isEmpty
            ? null
            : entry.value
                .map((c) => c.location)
                .whereType<String>()
                .first,
        person: entry.value
            .map((c) => c.person)
            .whereType<String>()
            .isEmpty
            ? null
            : entry.value
                .map((c) => c.person)
                .whereType<String>()
                .first,
      ));
    }

    // 신뢰도순 정렬
    patterns.sort((a, b) => b.weekCount.compareTo(a.weekCount));

    return patterns;
  }

  /// 반복 패턴 수락 → 관련 카드에 isRepeating 표시 + 다음 주 카드 자동 생성
  Future<BridgeCard?> acceptPattern(RepeatPattern pattern) async {
    final db = await _db.database;

    // 관련 카드 반복 표시
    for (final cardId in pattern.relatedCardIds) {
      await db.update('cards', {'is_repeating': 1},
          where: 'id = ?', whereArgs: [cardId]);
    }

    // 다음 주 동일 시간에 카드 자동 생성
    final now = DateTime.now();
    final daysUntil = ((pattern.weekday - now.weekday) % 7);
    final nextDate = DateTime(
      now.year,
      now.month,
      now.day + (daysUntil == 0 ? 7 : daysUntil),
      pattern.hour,
      pattern.minute,
    );

    final newCard = BridgeCard(
      rawText: '[반복] ${pattern.title}',
      title: pattern.title,
      startTime: nextDate,
      durationMinutes: 60,
      location: pattern.location,
      person: pattern.person,
      status: CardStatus.confirmed,
      category: pattern.category,
      parseConfidence: ParseConfidence.full,
      isRepeating: true,
      inputMethod: 'auto_repeat',
      createdAt: DateTime.now(),
    );

    final id = await _db.insertCard(newCard);
    await _db.logAction('repeat_accept',
        cardId: id,
        metadata: '{"pattern_title": "${pattern.title}", '
            '"weekday": ${pattern.weekday}, '
            '"occurrences": ${pattern.occurrences}}');

    return newCard.copyWith(id: id);
  }

  /// 반복 패턴 거절
  Future<void> rejectPattern(RepeatPattern pattern) async {
    await _db.logAction('repeat_reject',
        metadata: '{"pattern_title": "${pattern.title}", '
            '"weekday": ${pattern.weekday}}');
  }

  /// 다음 주 반복 일정 자동 생성 (일요일 저녁 호출)
  Future<List<BridgeCard>> generateNextWeekRepeats() async {
    final db = await _db.database;
    final generated = <BridgeCard>[];

    // is_repeating = 1인 카드들의 패턴 추출
    final repeating = await db.rawQuery('''
      SELECT DISTINCT 
        title, 
        CAST(strftime('%w', start_time) AS INTEGER) as weekday,
        CAST(strftime('%H', start_time) AS INTEGER) as hour,
        CAST(strftime('%M', start_time) AS INTEGER) as minute,
        category, location, person, duration_minutes
      FROM cards
      WHERE is_repeating = 1 AND status = ?
      GROUP BY title, weekday
    ''', [CardStatus.confirmed.index]);

    final now = DateTime.now();
    final nextMonday = now.add(Duration(days: (8 - now.weekday) % 7));

    for (final row in repeating) {
      final weekday = row['weekday'] as int;
      final hour = row['hour'] as int;
      final minute = row['minute'] as int;

      // 다음 주 해당 요일 계산
      final daysFromMonday = (weekday - 1 + 7) % 7;
      final targetDate = nextMonday.add(Duration(days: daysFromMonday));

      // 이미 해당 날짜에 같은 제목의 카드가 있는지 체크
      final existing = await db.rawQuery('''
        SELECT COUNT(*) as count FROM cards
        WHERE title = ? AND start_time >= ? AND start_time < ? AND status != ?
      ''', [
        row['title'],
        DateTime(targetDate.year, targetDate.month, targetDate.day).toIso8601String(),
        DateTime(targetDate.year, targetDate.month, targetDate.day + 1).toIso8601String(),
        CardStatus.deleted.index,
      ]);

      if ((existing.first['count'] as int) > 0) continue;

      final card = BridgeCard(
        rawText: '[반복] ${row['title']}',
        title: row['title'] as String,
        startTime: DateTime(
          targetDate.year, targetDate.month, targetDate.day, hour, minute),
        durationMinutes: (row['duration_minutes'] as int?) ?? 60,
        location: row['location'] as String?,
        person: row['person'] as String?,
        status: CardStatus.confirmed,
        category: CardCategory.values[(row['category'] as int).clamp(0, 9)],
        parseConfidence: ParseConfidence.full,
        isRepeating: true,
        inputMethod: 'auto_repeat',
        createdAt: DateTime.now(),
      );

      final id = await _db.insertCard(card);
      generated.add(card.copyWith(id: id));
    }

    if (generated.isNotEmpty) {
      await _db.logAction('repeat_generate',
          metadata: '{"count": ${generated.length}}');
    }

    return generated;
  }

  /// 제목 정규화 (유사 제목 묶기)
  String _normalizeTitle(String title) {
    return title
        .replaceAll(RegExp(r'[^\w가-힣]'), '')
        .toLowerCase()
        .trim();
  }

  /// 주차 번호 계산
  int _weekNumber(DateTime dt) {
    final firstDay = DateTime(dt.year, 1, 1);
    return ((dt.difference(firstDay).inDays + firstDay.weekday) / 7).ceil();
  }
}

/// 감지된 반복 패턴
class RepeatPattern {
  final int weekday;           // 1=월 ~ 7=일
  final int hour;
  final int minute;
  final String title;
  final CardCategory category;
  final int occurrences;       // 발생 횟수
  final int weekCount;         // 서로 다른 주 수
  final List<int> relatedCardIds;
  final String? location;
  final String? person;

  RepeatPattern({
    required this.weekday,
    required this.hour,
    required this.minute,
    required this.title,
    required this.category,
    required this.occurrences,
    required this.weekCount,
    required this.relatedCardIds,
    this.location,
    this.person,
  });

  String get weekdayLabel {
    const names = ['', '월', '화', '수', '목', '금', '토', '일'];
    return '${names[weekday]}요일';
  }

  String get timeLabel {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  String get description {
    return '매주 $weekdayLabel $timeLabel $title';
  }
}
