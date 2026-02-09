/// ShareService: 카드 공유 기능 (바이럴 루프)
///
/// "민수랑 밥" → 카드 생성 → "민수에게 공유" → 카카오톡 전송
/// 민수가 Bridge 링크 열면 → 앱 설치 유도 or 웹으로 응답
///
/// 핵심: 내가 Bridge를 쓰면 주변 사람도 자연스럽게 접한다

import 'package:flutter/services.dart';
import '../models/bridge_card.dart';
import 'database_service.dart';

class ShareService {
  static final ShareService _instance = ShareService._internal();
  factory ShareService() => _instance;
  ShareService._internal();

  final DatabaseService _db = DatabaseService();

  // System share sheet
  static const _channel = MethodChannel('com.bridge.share');

  /// 카드를 공유 텍스트로 변환
  String generateShareText(BridgeCard card) {
    final buffer = StringBuffer();

    buffer.writeln('📌 ${card.title}');
    buffer.writeln('');

    if (card.hasDate) {
      buffer.write('📅 ${card.dateString}');
      if (card.hasTime) {
        buffer.write(' ${card.timeString}');
      }
      buffer.writeln('');
    }

    if (card.location != null) {
      buffer.writeln('📍 ${card.location}');
    }

    buffer.writeln('');
    buffer.writeln('Bridge에서 보냄');
    // 딥링크 (앱 설치 시 카드 확인 가능)
    buffer.writeln('https://bridge.app/card/${card.id}');

    return buffer.toString();
  }

  /// 약속 제안 텍스트 생성
  String generateProposalText(BridgeCard card, List<String> timeOptions) {
    final buffer = StringBuffer();

    buffer.writeln('📌 ${card.title}');
    buffer.writeln('');

    if (timeOptions.isNotEmpty) {
      buffer.writeln('언제가 좋아요?');
      for (int i = 0; i < timeOptions.length; i++) {
        buffer.writeln('${i + 1}. ${timeOptions[i]}');
      }
    } else if (card.hasDate) {
      buffer.writeln('📅 ${card.dateString} ${card.hasTime ? card.timeString : ""} 어때요?');
    } else {
      buffer.writeln('언제가 좋아요?');
    }

    buffer.writeln('');
    buffer.writeln('Bridge에서 보냄 ✨');

    return buffer.toString();
  }

  /// 시스템 공유 시트 열기
  Future<bool> shareCard(BridgeCard card) async {
    final text = generateShareText(card);
    return await _shareText(text);
  }

  /// 약속 제안 공유
  Future<bool> shareProposal(BridgeCard card, {List<String>? timeOptions}) async {
    final text = generateProposalText(card, timeOptions ?? []);
    return await _shareText(text);
  }

  /// 하루 일정 공유 (Timeline 공유)
  Future<bool> shareDaySchedule(List<BridgeCard> cards, DateTime date) async {
    final buffer = StringBuffer();
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final wd = weekdays[date.weekday - 1];

    buffer.writeln('📋 ${date.month}/${date.day}(${wd}) 일정');
    buffer.writeln('');

    for (final card in cards) {
      final time = card.hasTime ? card.timeString : '--:--';
      buffer.writeln('$time  ${card.categoryEmoji} ${card.title}');
    }

    buffer.writeln('');
    buffer.writeln('Bridge에서 보냄');

    return await _shareText(buffer.toString());
  }

  /// 텍스트 공유 (네이티브)
  Future<bool> _shareText(String text) async {
    try {
      await _channel.invokeMethod('shareText', {'text': text});

      // 공유 행동 로그
      await _db.logAction('card_share', metadata: '{"length": ${text.length}}');

      return true;
    } catch (e) {
      // 폴백: 클립보드 복사
      await Clipboard.setData(ClipboardData(text: text));
      return false;
    }
  }

  /// 공유 카드에서 빈 시간 제안 생성
  List<String> suggestTimeOptions(BridgeCard card, List<BridgeCard> existingCards) {
    final suggestions = <String>[];

    // 향후 7일 중 빈 시간 찾기
    final now = DateTime.now();
    for (int d = 1; d <= 7; d++) {
      final date = DateTime(now.year, now.month, now.day + d);
      final dayCards = existingCards.where((c) =>
          c.startTime != null &&
          c.startTime!.year == date.year &&
          c.startTime!.month == date.month &&
          c.startTime!.day == date.day).toList();

      // 저녁 시간 (18:00~21:00) 비어있으면 제안
      final hasEvening = dayCards.any((c) =>
          c.startTime!.hour >= 18 && c.startTime!.hour <= 21);

      if (!hasEvening) {
        final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
        final wd = weekdays[date.weekday - 1];
        suggestions.add('${date.month}/${date.day}(${wd}) 저녁 7시');
      }

      if (suggestions.length >= 3) break;
    }

    return suggestions;
  }
}
