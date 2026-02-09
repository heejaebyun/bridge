/// KoreanParser: 한국어 자연어 → 일정 데이터 파싱
/// 
/// 4단계 폴백:
/// 1단계: 완전 파싱 (날짜 + 시간 + 제목)
/// 2단계: 부분 파싱 (일부만 추출)
/// 3단계: 오타 보정 후 재시도
/// 4단계: 원문 그대로 메모 카드 저장

import '../models/bridge_card.dart';

class ParseResult {
  final String title;
  final DateTime? startTime;
  final DateTime? endTime;
  final int? durationMinutes;
  final String? location;
  final String? person;
  final CardCategory category;
  final ParseConfidence confidence;
  final String? correctedText;
  final bool hasDateUncertainty;
  final String systemMessage;     // Chat에 표시할 메시지

  ParseResult({
    required this.title,
    this.startTime,
    this.endTime,
    this.durationMinutes,
    this.location,
    this.person,
    this.category = CardCategory.other,
    this.confidence = ParseConfidence.failed,
    this.correctedText,
    this.hasDateUncertainty = false,
    required this.systemMessage,
  });
}

class KoreanParser {
  static final KoreanParser _instance = KoreanParser._internal();
  factory KoreanParser() => _instance;
  KoreanParser._internal();

  /// 메인 파싱 함수
  ParseResult parse(String input) {
    if (input.trim().isEmpty) {
      return ParseResult(
        title: '',
        systemMessage: '뭐든 말해주세요!',
      );
    }

    String text = input.trim();

    // 1단계: 그대로 파싱 시도
    var result = _tryParse(text);
    if (result.confidence == ParseConfidence.full) {
      return result;
    }

    // 부분 파싱 성공
    if (result.confidence == ParseConfidence.partial) {
      return result;
    }

    // 3단계: 오타 보정 후 재시도
    final corrected = _correctTypos(text);
    if (corrected != text) {
      var correctedResult = _tryParse(corrected);
      if (correctedResult.confidence == ParseConfidence.full ||
          correctedResult.confidence == ParseConfidence.partial) {
        return ParseResult(
          title: correctedResult.title,
          startTime: correctedResult.startTime,
          endTime: correctedResult.endTime,
          durationMinutes: correctedResult.durationMinutes,
          location: correctedResult.location,
          person: correctedResult.person,
          category: correctedResult.category,
          confidence: ParseConfidence.corrected,
          correctedText: corrected,
          hasDateUncertainty: correctedResult.hasDateUncertainty,
          systemMessage: correctedResult.systemMessage,
        );
      }
    }

    // 4단계: 파싱 실패 → 메모 카드
    final title = _extractBestTitle(text);
    final category = _inferCategory(text);
    return ParseResult(
      title: title,
      category: category,
      confidence: ParseConfidence.failed,
      systemMessage: '일단 저장했어요! 저녁에 같이 정리해요 ✌️',
    );
  }

  /// 파싱 시도
  ParseResult _tryParse(String text) {
    DateTime? date;
    int? hour;
    int? minute;
    bool hasUncertainty = false;
    String remaining = text;

    // 불확실성 마커 체크
    if (_uncertaintyPattern.hasMatch(text)) {
      hasUncertainty = true;
    }

    // 날짜 추출
    final dateResult = _extractDate(remaining);
    if (dateResult != null) {
      date = dateResult.date;
      remaining = dateResult.remaining;
    }

    // 시간 추출
    final timeResult = _extractTime(remaining);
    if (timeResult != null) {
      hour = timeResult.hour;
      minute = timeResult.minute;
      remaining = timeResult.remaining;
    }

    // 장소 추출
    final locationResult = _extractLocation(remaining);
    String? location;
    if (locationResult != null) {
      location = locationResult.location;
      remaining = locationResult.remaining;
    }

    // 사람 추출
    final personResult = _extractPerson(remaining);
    String? person;
    if (personResult != null) {
      person = personResult.person;
      remaining = personResult.remaining;
    }

    // 제목 추출 (남은 텍스트에서)
    final title = _cleanTitle(remaining);
    final category = _inferCategory(text);

    // DateTime 조합
    DateTime? startTime;
    if (date != null && hour != null) {
      startTime = DateTime(
        date.year, date.month, date.day,
        hour, minute ?? 0,
      );
    } else if (date != null) {
      startTime = date;
    }

    // Confidence 판단
    ParseConfidence confidence;
    String systemMessage;

    if (title.isNotEmpty && date != null && hour != null) {
      // 완전 파싱
      confidence = ParseConfidence.full;
      final timeStr = '${hour.toString().padLeft(2, '0')}:${(minute ?? 0).toString().padLeft(2, '0')}';
      final dateStr = _formatDateKorean(date);
      systemMessage = '$dateStr $timeStr \'$title\' 일정 맞나요?';
    } else if (title.isNotEmpty && (date != null || hour != null)) {
      // 부분 파싱
      confidence = ParseConfidence.partial;
      if (date == null) {
        systemMessage = '\'$title\' — 언제인지 모르겠지만 일단 저장했어요!';
      } else {
        final dateStr = _formatDateKorean(date);
        systemMessage = '$dateStr \'$title\' — 시간은요?';
      }
    } else if (title.isNotEmpty) {
      // 제목만 있음
      confidence = ParseConfidence.partial;
      systemMessage = '\'$title\' — 일단 저장했어요! 저녁에 같이 정리해요 ✌️';
    } else {
      // 파싱 실패
      confidence = ParseConfidence.failed;
      systemMessage = '일단 메모로 저장했어요! 저녁에 같이 정리해요 ✌️';
    }

    // 소요 시간 추정
    int? duration = _estimateDuration(category);

    return ParseResult(
      title: title.isEmpty ? text : title,
      startTime: startTime,
      durationMinutes: duration,
      location: location,
      person: person,
      category: category,
      confidence: confidence,
      hasDateUncertainty: hasUncertainty,
      systemMessage: systemMessage,
    );
  }

  // ========== 날짜 추출 ==========

  static final _uncertaintyPattern =
      RegExp(r'쯤|정도|인가|인지|같은데|것\s*같|아마|대충');

  _DateResult? _extractDate(String text) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // "오늘"
    final todayMatch = RegExp(r'오늘').firstMatch(text);
    if (todayMatch != null) {
      return _DateResult(
        date: today,
        remaining: text.replaceFirst('오늘', '').trim(),
      );
    }

    // "내일"
    final tomorrowMatch = RegExp(r'내일').firstMatch(text);
    if (tomorrowMatch != null) {
      return _DateResult(
        date: today.add(const Duration(days: 1)),
        remaining: text.replaceFirst('내일', '').trim(),
      );
    }

    // "모레" / "모래"
    final dayAfterMatch = RegExp(r'모[레래]').firstMatch(text);
    if (dayAfterMatch != null) {
      return _DateResult(
        date: today.add(const Duration(days: 2)),
        remaining: text.replaceFirst(dayAfterMatch.group(0)!, '').trim(),
      );
    }

    // "이번주 N요일" / "다음주 N요일"
    final weekdayMatch =
        RegExp(r'(이번\s*주|다음\s*주|담\s*주)\s*([월화수목금토일])요?일?')
            .firstMatch(text);
    if (weekdayMatch != null) {
      final isNext = weekdayMatch.group(1)!.contains('다음') ||
          weekdayMatch.group(1)!.contains('담');
      final dayStr = weekdayMatch.group(2)!;
      final targetDay = _weekdayFromKorean(dayStr);
      if (targetDay != null) {
        var date = _getNextWeekday(today, targetDay, isNext);
        return _DateResult(
          date: date,
          remaining: text.replaceFirst(weekdayMatch.group(0)!, '').trim(),
        );
      }
    }

    // "N요일" (단독)
    final singleWeekday =
        RegExp(r'([월화수목금토일])요일').firstMatch(text);
    if (singleWeekday != null) {
      final dayStr = singleWeekday.group(1)!;
      final targetDay = _weekdayFromKorean(dayStr);
      if (targetDay != null) {
        var date = _getNextWeekday(today, targetDay, false);
        return _DateResult(
          date: date,
          remaining: text.replaceFirst(singleWeekday.group(0)!, '').trim(),
        );
      }
    }

    // "N월 N일" / "N/N"
    final dateMatch =
        RegExp(r'(\d{1,2})\s*[월/]\s*(\d{1,2})일?').firstMatch(text);
    if (dateMatch != null) {
      final month = int.parse(dateMatch.group(1)!);
      final day = int.parse(dateMatch.group(2)!);
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        var year = now.year;
        var date = DateTime(year, month, day);
        if (date.isBefore(today)) {
          date = DateTime(year + 1, month, day);
        }
        return _DateResult(
          date: date,
          remaining: text.replaceFirst(dateMatch.group(0)!, '').trim(),
        );
      }
    }

    // "N일 뒤" / "N일 후"
    final daysLater =
        RegExp(r'(\d{1,3})\s*일\s*[뒤후]').firstMatch(text);
    if (daysLater != null) {
      final days = int.parse(daysLater.group(1)!);
      return _DateResult(
        date: today.add(Duration(days: days)),
        remaining: text.replaceFirst(daysLater.group(0)!, '').trim(),
      );
    }

    // "다음주" (요일 없이)
    final nextWeekMatch = RegExp(r'다음\s*주|담\s*주').firstMatch(text);
    if (nextWeekMatch != null) {
      // 다음주 월요일로 설정
      final daysUntilMonday = (8 - now.weekday) % 7;
      final nextMonday = today.add(Duration(
          days: daysUntilMonday == 0 ? 7 : daysUntilMonday));
      return _DateResult(
        date: nextMonday,
        remaining: text.replaceFirst(nextWeekMatch.group(0)!, '').trim(),
      );
    }

    return null;
  }

  // ========== 시간 추출 ==========

  _TimeResult? _extractTime(String text) {
    // "N시 N분" / "N시반"
    final timeMatch =
        RegExp(r'(\d{1,2})\s*시\s*((\d{1,2})\s*분|반)?').firstMatch(text);
    if (timeMatch != null) {
      var hour = int.parse(timeMatch.group(1)!);
      int minute = 0;
      if (timeMatch.group(3) != null) {
        minute = int.parse(timeMatch.group(3)!);
      } else if (timeMatch.group(2) != null &&
          timeMatch.group(2)!.contains('반')) {
        minute = 30;
      }
      return _TimeResult(
        hour: hour,
        minute: minute,
        remaining: text.replaceFirst(timeMatch.group(0)!, '').trim(),
      );
    }

    // "HH:MM" / "HH시"
    final colonTime =
        RegExp(r'(\d{1,2}):(\d{2})').firstMatch(text);
    if (colonTime != null) {
      final hour = int.parse(colonTime.group(1)!);
      final minute = int.parse(colonTime.group(2)!);
      if (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
        return _TimeResult(
          hour: hour,
          minute: minute,
          remaining: text.replaceFirst(colonTime.group(0)!, '').trim(),
        );
      }
    }

    // "오전/오후 N시"
    final ampmMatch =
        RegExp(r'(오전|오후|아침|저녁|낮|밤)\s*(\d{1,2})\s*시?').firstMatch(text);
    if (ampmMatch != null) {
      final period = ampmMatch.group(1)!;
      var hour = int.parse(ampmMatch.group(2)!);
      if ((period == '오후' || period == '저녁' || period == '밤') &&
          hour < 12) {
        hour += 12;
      }
      if (period == '아침' && hour > 12) {
        hour -= 12;
      }
      return _TimeResult(
        hour: hour,
        minute: 0,
        remaining: text.replaceFirst(ampmMatch.group(0)!, '').trim(),
      );
    }

    // "아침" / "점심" / "저녁" / "밤" (시간 없이 단독)
    final periodOnly =
        RegExp(r'^(아침|점심|저녁|밤|새벽)$|(?<=\s)(아침|점심|저녁|밤|새벽)(?=\s|$)')
            .firstMatch(text);
    if (periodOnly != null) {
      final period = periodOnly.group(0)!.trim();
      int hour;
      switch (period) {
        case '새벽': hour = 5; break;
        case '아침': hour = 8; break;
        case '점심': hour = 12; break;
        case '저녁': hour = 18; break;
        case '밤': hour = 21; break;
        default: hour = 9;
      }
      return _TimeResult(
        hour: hour,
        minute: 0,
        remaining: text.replaceFirst(period, '').trim(),
      );
    }

    return null;
  }

  // ========== 장소 추출 ==========

  _LocationResult? _extractLocation(String text) {
    // "~에서" 패턴
    final locationMatch =
        RegExp(r'(\S+(?:역|카페|병원|학교|회사|집|마트|공원|센터|관|점|동|구|시))\s*에서?')
            .firstMatch(text);
    if (locationMatch != null) {
      return _LocationResult(
        location: locationMatch.group(1)!,
        remaining: text.replaceFirst(locationMatch.group(0)!, '').trim(),
      );
    }

    // "강남역", "홍대", "신촌" 등 지명
    final placeMatch =
        RegExp(r'(강남역?|홍대입구?|신촌|여의도|판교|잠실|명동|이태원|성수|합정|건대입구?)')
            .firstMatch(text);
    if (placeMatch != null) {
      return _LocationResult(
        location: placeMatch.group(1)!,
        remaining: text.replaceFirst(placeMatch.group(0)!, '').trim(),
      );
    }

    return null;
  }

  // ========== 사람 추출 ==========

  _PersonResult? _extractPerson(String text) {
    // "~이랑" / "~한테" / "~랑" / "~하고"
    final personMatch =
        RegExp(r'(\S{1,10}?)(이?랑|한테|하고|씨|님|형|누나|언니|오빠)')
            .firstMatch(text);
    if (personMatch != null) {
      final person = personMatch.group(1)!;
      // 너무 짧거나 기능어는 제외
      if (person.length >= 1 && !_isFunctionWord(person)) {
        return _PersonResult(
          person: person + (personMatch.group(2) ?? ''),
          remaining: text.replaceFirst(personMatch.group(0)!, '').trim(),
        );
      }
    }

    return null;
  }

  bool _isFunctionWord(String word) {
    const functionWords = {
      '그', '이', '저', '뭐', '왜', '어디', '나', '너', '우리',
      '내', '네', '그냥', '좀', '다', '또', '안',
    };
    return functionWords.contains(word);
  }

  // ========== 카테고리 추론 ==========

  CardCategory _inferCategory(String text) {
    final lower = text.toLowerCase();

    if (_matchesAny(lower, ['회의', '미팅', '보고', '발표', '출근', '업무', '프로젝트', '코드', '개발', '기획'])) {
      return CardCategory.work;
    }
    if (_matchesAny(lower, ['병원', '의사', '치과', '약', '건강검진', '운동', '헬스', '필라테스', '요가', '스트레칭'])) {
      return CardCategory.health;
    }
    if (_matchesAny(lower, ['밥', '점심', '저녁', '식사', '카페', '커피', '맛집', '브런치', '치킨', '피자'])) {
      return CardCategory.meal;
    }
    if (_matchesAny(lower, ['만나', '약속', '데이트', '모임', '동창', '친구'])) {
      return CardCategory.meeting;
    }
    if (_matchesAny(lower, ['장보기', '마트', '세탁', '청소', '빨래', '택배', '은행', '우체국', '사야'])) {
      return CardCategory.errand;
    }
    if (_matchesAny(lower, ['영화', '게임', '넷플릭스', '유튜브', '드라마', '여행', '놀'])) {
      return CardCategory.leisure;
    }
    if (_matchesAny(lower, ['공부', '시험', '강의', '수업', '과제', '독서', '책'])) {
      return CardCategory.study;
    }
    if (_matchesAny(lower, ['이동', '출발', '도착', '비행기', 'KTX', '버스'])) {
      return CardCategory.travel;
    }

    return CardCategory.other;
  }

  bool _matchesAny(String text, List<String> keywords) {
    return keywords.any((k) => text.contains(k));
  }

  // ========== 소요 시간 추정 ==========

  int? _estimateDuration(CardCategory category) {
    switch (category) {
      case CardCategory.work: return 60;
      case CardCategory.meeting: return 90;
      case CardCategory.health: return 60;
      case CardCategory.errand: return 30;
      case CardCategory.leisure: return 120;
      case CardCategory.travel: return 60;
      case CardCategory.meal: return 60;
      case CardCategory.study: return 90;
      case CardCategory.social: return 120;
      case CardCategory.other: return null;
    }
  }

  // ========== 한글 오타 보정 ==========

  String _correctTypos(String text) {
    String result = text;

    // 한글 자모 분리 상태 복원 (ㄴㅐ일 → 내일)
    result = _reassembleJamo(result);

    // 흔한 오타 사전
    const typoMap = {
      '벼원': '병원',
      '베원': '병원',
      '볍원': '병원',
      '내이': '내일',
      '네일': '내일',
      '모래': '모레',
      '회의': '회의',
      '미팅': '미팅',
      '겅남': '강남',
      '홍데': '홍대',
      '신촌': '신촌',
      '얃속': '약속',
      '악속': '약속',
      '야속': '약속',
      '저녁': '저녁',
      '저넉': '저녁',
      '점싱': '점심',
      '점시': '점심',
      '아추': '아침',
    };

    typoMap.forEach((typo, correct) {
      result = result.replaceAll(typo, correct);
    });

    return result;
  }

  /// 한글 자모 재조합 (ㄴㅐ일 → 내일)
  String _reassembleJamo(String text) {
    // 한글 자모 유니코드 범위
    // 초성: ㄱ(0x3131) ~ ㅎ(0x314E)
    // 중성: ㅏ(0x314F) ~ ㅣ(0x3163)

    const chosung = [
      'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ',
      'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
    ];
    const jungsung = [
      'ㅏ', 'ㅐ', 'ㅑ', 'ㅒ', 'ㅓ', 'ㅔ', 'ㅕ', 'ㅖ', 'ㅗ', 'ㅘ',
      'ㅙ', 'ㅚ', 'ㅛ', 'ㅜ', 'ㅝ', 'ㅞ', 'ㅟ', 'ㅠ', 'ㅡ', 'ㅢ', 'ㅣ',
    ];

    final buffer = StringBuffer();
    final chars = text.runes.toList();

    int i = 0;
    while (i < chars.length) {
      final c = String.fromCharCode(chars[i]);

      // 초성 + 중성 조합 시도
      if (i + 1 < chars.length) {
        final next = String.fromCharCode(chars[i + 1]);
        final choIdx = chosung.indexOf(c);
        final jungIdx = jungsung.indexOf(next);

        if (choIdx >= 0 && jungIdx >= 0) {
          // 조합: 0xAC00 + (초성 * 21 + 중성) * 28
          final code = 0xAC00 + (choIdx * 21 + jungIdx) * 28;
          buffer.writeCharCode(code);
          i += 2;
          continue;
        }
      }

      buffer.write(c);
      i++;
    }

    return buffer.toString();
  }

  // ========== 유틸리티 ==========

  String _cleanTitle(String text) {
    // 불필요한 조사/어미 제거
    String cleaned = text
        .replaceAll(RegExp(r'[을를이가은는에서에게도의로]$'), '')
        .replaceAll(RegExp(r'^(그|그리고|아|음|어)\s+'), '')
        .replaceAll(RegExp(r'\s+(해야|해야됨|해야함|할것|하기|가야|가기)$'), '')
        .replaceAll(RegExp(r'\s+(있어|있음|있다|예약)$'), '')
        .trim();

    // 빈 결과면 원문 반환
    if (cleaned.isEmpty) return text.trim();
    return cleaned;
  }

  String _extractBestTitle(String text) {
    // 최소한의 정리만 해서 제목 생성
    String title = text
        .replaceAll(RegExp(r'ㅋ+|ㅎ+|ㅠ+|ㅜ+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (title.length > 30) {
      title = '${title.substring(0, 30)}...';
    }

    return title.isEmpty ? text.trim() : title;
  }

  int? _weekdayFromKorean(String day) {
    const map = {
      '월': DateTime.monday,
      '화': DateTime.tuesday,
      '수': DateTime.wednesday,
      '목': DateTime.thursday,
      '금': DateTime.friday,
      '토': DateTime.saturday,
      '일': DateTime.sunday,
    };
    return map[day];
  }

  DateTime _getNextWeekday(DateTime from, int targetWeekday, bool isNextWeek) {
    int daysAhead = targetWeekday - from.weekday;
    if (daysAhead <= 0) daysAhead += 7;
    if (isNextWeek && daysAhead <= 7) daysAhead += 7;
    return from.add(Duration(days: daysAhead));
  }

  String _formatDateKorean(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = date.difference(today).inDays;

    if (diff == 0) return '오늘';
    if (diff == 1) return '내일';
    if (diff == 2) return '모레';

    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final wd = weekdays[date.weekday - 1];
    return '${date.month}/${date.day}($wd)';
  }
}

// ========== 내부 결과 클래스들 ==========

class _DateResult {
  final DateTime date;
  final String remaining;
  _DateResult({required this.date, required this.remaining});
}

class _TimeResult {
  final int hour;
  final int minute;
  final String remaining;
  _TimeResult({required this.hour, this.minute = 0, required this.remaining});
}

class _LocationResult {
  final String location;
  final String remaining;
  _LocationResult({required this.location, required this.remaining});
}

class _PersonResult {
  final String person;
  final String remaining;
  _PersonResult({required this.person, required this.remaining});
}
