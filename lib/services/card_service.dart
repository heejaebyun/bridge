/// CardService: 카드 생성/관리의 핵심 비즈니스 로직
/// Parser → Card → DB → ChatMessage 전체 흐름을 관리

import '../models/bridge_card.dart';
import '../models/chat_message.dart';
import 'database_service.dart';
import 'korean_parser.dart';

class CardService {
  static final CardService _instance = CardService._internal();
  factory CardService() => _instance;
  CardService._internal();

  final DatabaseService _db = DatabaseService();
  final KoreanParser _parser = KoreanParser();

  /// 사용자 입력 → 카드 생성 + 시스템 메시지 반환
  /// 이 함수가 "3초의 경험"의 핵심
  Future<CardCreateResult> processInput(String input, {String inputMethod = 'text'}) async {
    // 1. 파싱
    final parseResult = _parser.parse(input);

    // 2. 카드 생성
    final card = BridgeCard(
      rawText: input,
      title: parseResult.title,
      startTime: parseResult.startTime,
      durationMinutes: parseResult.durationMinutes,
      location: parseResult.location,
      person: parseResult.person,
      category: parseResult.category,
      parseConfidence: parseResult.confidence,
      correctedText: parseResult.correctedText,
      hasDateUncertainty: parseResult.hasDateUncertainty,
      inputMethod: inputMethod,
      createdAt: DateTime.now(),
    );

    // 3. DB 저장
    final cardId = await _db.insertCard(card);
    final savedCard = card.copyWith(id: cardId);

    // 4. 행동 로그
    await _db.logAction(
      'card_create',
      cardId: cardId,
      metadata: '{"confidence": "${parseResult.confidence.name}", '
          '"category": "${parseResult.category.name}", '
          '"input_method": "$inputMethod"}',
    );

    // 5. 시스템 메시지 + Quick Actions 생성
    final quickActions = _buildQuickActions(savedCard, parseResult);
    final systemMessage = parseResult.systemMessage;

    return CardCreateResult(
      card: savedCard,
      systemMessage: systemMessage,
      quickActions: quickActions,
      parseConfidence: parseResult.confidence,
    );
  }

  /// Quick Actions 생성 (파싱 결과에 따라 다름)
  List<QuickAction> _buildQuickActions(BridgeCard card, ParseResult parseResult) {
    switch (parseResult.confidence) {
      case ParseConfidence.full:
        // 완전 파싱: 확정/수정/나중에 (+ 사람 있으면 공유)
        final actions = [
          QuickAction(label: '확정 ✓', action: 'confirm', payload: '${card.id}'),
          QuickAction(label: '수정', action: 'edit', payload: '${card.id}'),
          QuickAction(label: '나중에', action: 'defer', payload: '${card.id}'),
        ];
        if (card.person != null) {
          actions.insert(1, QuickAction(
              label: '📤 공유', action: 'share', payload: '${card.id}'));
        }
        return actions;

      case ParseConfidence.partial:
      case ParseConfidence.corrected:
        if (card.hasDate && !card.hasTime) {
          // 날짜만 있고 시간 없음
          return [
            QuickAction(label: '오전', action: 'set_time', payload: 'morning'),
            QuickAction(label: '오후', action: 'set_time', payload: 'afternoon'),
            QuickAction(label: '저녁', action: 'set_time', payload: 'evening'),
            QuickAction(label: '나중에', action: 'defer', payload: '${card.id}'),
          ];
        } else if (!card.hasDate) {
          // 날짜 없음
          return [
            QuickAction(label: '오늘', action: 'set_date', payload: 'today'),
            QuickAction(label: '내일', action: 'set_date', payload: 'tomorrow'),
            QuickAction(label: '다음주', action: 'set_date', payload: 'next_week'),
            QuickAction(label: '나중에', action: 'defer', payload: '${card.id}'),
          ];
        }
        return [
          QuickAction(label: '수정', action: 'edit', payload: '${card.id}'),
          QuickAction(label: '나중에', action: 'defer', payload: '${card.id}'),
        ];

      case ParseConfidence.failed:
        // 파싱 실패: 나중에 정리
        return [
          QuickAction(label: '날짜 정하기', action: 'edit', payload: '${card.id}'),
          QuickAction(label: '그냥 메모로', action: 'memo', payload: '${card.id}'),
        ];
    }
  }

  /// 카드 확정
  Future<BridgeCard> confirmCard(int cardId) async {
    await _db.updateCardStatus(cardId, CardStatus.confirmed);
    await _db.logAction('card_confirm', cardId: cardId);
    final card = await _db.getCard(cardId);
    return card!;
  }

  /// 카드 미루기 (Triage → 저녁 브리핑)
  Future<void> deferCard(int cardId) async {
    await _db.updateCardStatus(cardId, CardStatus.deferred);
    await _db.logAction('card_defer', cardId: cardId);
  }

  /// 카드 삭제
  Future<void> deleteCard(int cardId) async {
    await _db.updateCardStatus(cardId, CardStatus.deleted);
    await _db.logAction('card_delete', cardId: cardId);
  }

  /// 카드 수정
  Future<BridgeCard> editCard(int cardId, {
    String? title,
    DateTime? startTime,
    DateTime? endTime,
    int? durationMinutes,
    String? location,
    String? person,
    String? memo,
  }) async {
    final card = await _db.getCard(cardId);
    if (card == null) throw Exception('Card not found');

    final updated = card.copyWith(
      title: title,
      startTime: startTime,
      endTime: endTime,
      durationMinutes: durationMinutes,
      location: location,
      person: person,
      memo: memo,
      status: CardStatus.editing,
      triageActionCount: card.triageActionCount + 1,
    );

    await _db.updateCard(updated);
    await _db.logAction('card_edit', cardId: cardId);
    return updated;
  }

  /// 카드에 날짜 설정 (Quick Action 처리)
  Future<BridgeCard> setCardDate(int cardId, String datePayload) async {
    final card = await _db.getCard(cardId);
    if (card == null) throw Exception('Card not found');

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime targetDate;

    switch (datePayload) {
      case 'today':
        targetDate = today;
        break;
      case 'tomorrow':
        targetDate = today.add(const Duration(days: 1));
        break;
      case 'next_week':
        final daysUntilMonday = (8 - now.weekday) % 7;
        targetDate = today.add(Duration(
            days: daysUntilMonday == 0 ? 7 : daysUntilMonday));
        break;
      default:
        targetDate = today.add(const Duration(days: 1));
    }

    // 기존 시간이 있으면 유지, 없으면 날짜만 설정
    DateTime startTime;
    if (card.hasTime) {
      startTime = DateTime(
        targetDate.year, targetDate.month, targetDate.day,
        card.startTime!.hour, card.startTime!.minute,
      );
    } else {
      startTime = targetDate;
    }

    final updated = card.copyWith(startTime: startTime);
    await _db.updateCard(updated);
    return updated;
  }

  /// 카드에 시간 설정 (Quick Action 처리)
  Future<BridgeCard> setCardTime(int cardId, String timePayload) async {
    final card = await _db.getCard(cardId);
    if (card == null) throw Exception('Card not found');

    int hour;
    switch (timePayload) {
      case 'morning': hour = 9; break;
      case 'afternoon': hour = 14; break;
      case 'evening': hour = 18; break;
      default: hour = 12;
    }

    DateTime startTime;
    if (card.hasDate) {
      startTime = DateTime(
        card.startTime!.year, card.startTime!.month, card.startTime!.day,
        hour, 0,
      );
    } else {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      startTime = DateTime(
        tomorrow.year, tomorrow.month, tomorrow.day,
        hour, 0,
      );
    }

    final updated = card.copyWith(startTime: startTime);
    await _db.updateCard(updated);
    return updated;
  }

  /// Triage 대상 카드 목록
  Future<List<BridgeCard>> getTriageCards() async {
    return await _db.getTriageCards();
  }

  /// 오늘 타임라인 데이터
  Future<TimelineData> getTodayTimeline() async {
    final confirmed = await _db.getTodayConfirmedCards();
    final triage = await _db.getTriageCards();
    final todayCount = await _db.getTodayCardCount();

    // 빈 시간 계산
    final freeSlots = _calculateFreeSlots(confirmed);

    return TimelineData(
      confirmedCards: confirmed,
      triageCardCount: triage.length,
      totalTodayCards: todayCount,
      freeSlots: freeSlots,
    );
  }

  /// 빈 시간 계산
  List<FreeSlot> _calculateFreeSlots(List<BridgeCard> cards) {
    if (cards.isEmpty) return [];

    final slots = <FreeSlot>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 활동 시간: 08:00 ~ 22:00
    final dayStart = today.add(const Duration(hours: 8));
    final dayEnd = today.add(const Duration(hours: 22));

    // 시간이 있는 카드만 정렬
    final timed = cards
        .where((c) => c.hasTime)
        .toList()
      ..sort((a, b) => a.startTime!.compareTo(b.startTime!));

    if (timed.isEmpty) {
      slots.add(FreeSlot(start: dayStart, end: dayEnd));
      return slots;
    }

    // 첫 일정 전
    if (timed.first.startTime!.isAfter(dayStart)) {
      final gap = timed.first.startTime!.difference(dayStart).inMinutes;
      if (gap >= 30) {
        slots.add(FreeSlot(start: dayStart, end: timed.first.startTime!));
      }
    }

    // 일정 사이
    for (int i = 0; i < timed.length - 1; i++) {
      final currentEnd = timed[i].endTime ??
          timed[i].startTime!.add(Duration(
              minutes: timed[i].durationMinutes ?? 60));
      final nextStart = timed[i + 1].startTime!;

      final gap = nextStart.difference(currentEnd).inMinutes;
      if (gap >= 30) {
        slots.add(FreeSlot(start: currentEnd, end: nextStart));
      }
    }

    // 마지막 일정 후
    final lastEnd = timed.last.endTime ??
        timed.last.startTime!.add(Duration(
            minutes: timed.last.durationMinutes ?? 60));
    if (lastEnd.isBefore(dayEnd)) {
      final gap = dayEnd.difference(lastEnd).inMinutes;
      if (gap >= 30) {
        slots.add(FreeSlot(start: lastEnd, end: dayEnd));
      }
    }

    return slots;
  }

  /// 아침 브리핑 메시지 생성
  Future<String> generateMorningBriefing() async {
    final timeline = await getTodayTimeline();
    final buffer = StringBuffer();

    final now = DateTime.now();
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final wd = weekdays[now.weekday - 1];

    buffer.writeln('☀️ ${now.month}월 ${now.day}일 (${wd}요일)');
    buffer.writeln('');

    if (timeline.confirmedCards.isEmpty) {
      buffer.writeln('오늘은 일정이 없어요.');
      buffer.writeln('편하게 보내세요!');
    } else {
      buffer.writeln('오늘 일정 ${timeline.confirmedCards.length}개:');
      buffer.writeln('');

      for (final card in timeline.confirmedCards) {
        if (card.hasTime) {
          buffer.writeln('${card.timeString}  ${card.categoryEmoji} ${card.title}');
        } else {
          buffer.writeln('⏰ 미정  ${card.categoryEmoji} ${card.title}');
        }
      }

      if (timeline.freeSlots.isNotEmpty) {
        buffer.writeln('');
        final totalFree = timeline.freeSlots
            .fold<int>(0, (sum, s) => sum + s.durationMinutes);
        buffer.writeln('빈 시간: ${totalFree}분');
      }
    }

    if (timeline.triageCardCount > 0) {
      buffer.writeln('');
      buffer.writeln('📌 미결정 카드 ${timeline.triageCardCount}개');
    }

    return buffer.toString();
  }

  /// 저녁 브리핑 시작 가능 여부
  Future<bool> canStartEveningTriage() async {
    final cards = await getTriageCards();
    return cards.isNotEmpty;
  }

  /// Triage 완료 체크
  Future<void> completeTriageSession() async {
    await _db.logAction('triage_complete');
    if (!await _db.hasCompletedFirstTriage()) {
      await _db.setFirstTriageDone();
    }
  }
}

/// 카드 생성 결과
class CardCreateResult {
  final BridgeCard card;
  final String systemMessage;
  final List<QuickAction> quickActions;
  final ParseConfidence parseConfidence;

  CardCreateResult({
    required this.card,
    required this.systemMessage,
    required this.quickActions,
    required this.parseConfidence,
  });
}

/// 타임라인 데이터
class TimelineData {
  final List<BridgeCard> confirmedCards;
  final int triageCardCount;
  final int totalTodayCards;
  final List<FreeSlot> freeSlots;

  TimelineData({
    required this.confirmedCards,
    required this.triageCardCount,
    required this.totalTodayCards,
    required this.freeSlots,
  });
}

/// 빈 시간 슬롯
class FreeSlot {
  final DateTime start;
  final DateTime end;

  FreeSlot({required this.start, required this.end});

  int get durationMinutes => end.difference(start).inMinutes;

  String get timeRange {
    final sh = start.hour.toString().padLeft(2, '0');
    final sm = start.minute.toString().padLeft(2, '0');
    final eh = end.hour.toString().padLeft(2, '0');
    final em = end.minute.toString().padLeft(2, '0');
    return '$sh:$sm ~ $eh:$em';
  }
}
