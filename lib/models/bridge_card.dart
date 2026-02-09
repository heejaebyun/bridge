/// BridgeCard: Bridge 앱의 핵심 데이터 단위
/// 모든 사용자 입력은 카드로 변환된다.

enum CardStatus {
  newCard,    // 새로 생성됨 (미처리)
  deferred,   // 나중에 처리 (저녁 브리핑으로 미룸)
  confirmed,  // 일정 확정 (캘린더 반영)
  editing,    // 수정 중
  deleted,    // 삭제됨
}

enum CardCategory {
  work,       // 업무
  meeting,    // 약속/미팅
  health,     // 건강/병원/운동
  errand,     // 가사/심부름/장보기
  leisure,    // 여가/취미
  travel,     // 이동
  meal,       // 식사
  study,      // 학습/공부
  social,     // 사교/모임
  other,      // 기타
}

enum EnergyLevel {
  low,        // 회복형 (낮잠, 산책)
  medium,     // 중립 (식사, 이동)
  high,       // 활성형 (운동, 회의)
}

enum ParseConfidence {
  full,       // 날짜 + 시간 + 제목 모두 파싱 성공
  partial,    // 일부만 파싱됨
  corrected,  // 오타 보정 후 파싱됨
  failed,     // 파싱 실패 → 메모 카드로 저장
}

class BridgeCard {
  final int? id;
  final String rawText;           // 사용자 원문 (절대 수정 안 함)
  final String title;             // 파싱된 제목
  final DateTime? startTime;      // 시작 시간
  final DateTime? endTime;        // 종료 시간
  final int? durationMinutes;     // 예상 소요 시간
  final String? location;         // 장소
  final String? person;           // 동반자
  final String? memo;             // 메모
  final CardStatus status;
  final CardCategory category;
  final EnergyLevel energyLevel;
  final ParseConfidence parseConfidence;
  final bool isRepeating;         // 반복 여부
  final DateTime createdAt;
  final DateTime updatedAt;

  // 메타데이터 (추천 엔진용)
  final String inputMethod;       // 'text', 'voice', 'widget'
  final String? correctedText;    // 오타 보정된 텍스트 (있는 경우)
  final int triageActionCount;    // Triage에서 처리된 횟수
  final bool hasDateUncertainty;  // "쯤", "정도" 등 불확실성 마커

  BridgeCard({
    this.id,
    required this.rawText,
    required this.title,
    this.startTime,
    this.endTime,
    this.durationMinutes,
    this.location,
    this.person,
    this.memo,
    this.status = CardStatus.newCard,
    this.category = CardCategory.other,
    this.energyLevel = EnergyLevel.medium,
    this.parseConfidence = ParseConfidence.failed,
    this.isRepeating = false,
    required this.createdAt,
    DateTime? updatedAt,
    this.inputMethod = 'text',
    this.correctedText,
    this.triageActionCount = 0,
    this.hasDateUncertainty = false,
  }) : updatedAt = updatedAt ?? createdAt;

  /// 날짜가 확정되었는지
  bool get hasDate => startTime != null;

  /// 시간이 확정되었는지
  bool get hasTime =>
      startTime != null &&
      (startTime!.hour != 0 || startTime!.minute != 0);

  /// 완전한 일정인지 (제목 + 날짜 + 시간)
  bool get isComplete => title.isNotEmpty && hasDate && hasTime;

  /// 부분 파싱인지 (제목은 있지만 날짜/시간 미정)
  bool get isPartial => title.isNotEmpty && !isComplete;

  /// 미결정 카드인지 (Triage 대상)
  bool get needsTriage =>
      status == CardStatus.newCard || status == CardStatus.deferred;

  /// 오늘 일정인지
  bool get isToday {
    if (startTime == null) return false;
    final now = DateTime.now();
    return startTime!.year == now.year &&
        startTime!.month == now.month &&
        startTime!.day == now.day;
  }

  /// 내일 일정인지
  bool get isTomorrow {
    if (startTime == null) return false;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return startTime!.year == tomorrow.year &&
        startTime!.month == tomorrow.month &&
        startTime!.day == tomorrow.day;
  }

  /// 카테고리 한글 라벨
  String get categoryLabel {
    switch (category) {
      case CardCategory.work: return '업무';
      case CardCategory.meeting: return '약속';
      case CardCategory.health: return '건강';
      case CardCategory.errand: return '심부름';
      case CardCategory.leisure: return '여가';
      case CardCategory.travel: return '이동';
      case CardCategory.meal: return '식사';
      case CardCategory.study: return '학습';
      case CardCategory.social: return '모임';
      case CardCategory.other: return '기타';
    }
  }

  /// 카테고리 이모지
  String get categoryEmoji {
    switch (category) {
      case CardCategory.work: return '💼';
      case CardCategory.meeting: return '🤝';
      case CardCategory.health: return '🏥';
      case CardCategory.errand: return '🛒';
      case CardCategory.leisure: return '🎮';
      case CardCategory.travel: return '🚗';
      case CardCategory.meal: return '🍽';
      case CardCategory.study: return '📚';
      case CardCategory.social: return '👥';
      case CardCategory.other: return '📌';
    }
  }

  /// 시간 포맷 (HH:MM)
  String get timeString {
    if (startTime == null) return '시간 미정';
    final h = startTime!.hour.toString().padLeft(2, '0');
    final m = startTime!.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// 날짜 포맷
  String get dateString {
    if (startTime == null) return '날짜 미정';
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));

    if (isToday) return '오늘';
    if (isTomorrow) return '내일';

    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final wd = weekdays[startTime!.weekday - 1];
    return '${startTime!.month}/${startTime!.day} ($wd)';
  }

  BridgeCard copyWith({
    int? id,
    String? rawText,
    String? title,
    DateTime? startTime,
    DateTime? endTime,
    int? durationMinutes,
    String? location,
    String? person,
    String? memo,
    CardStatus? status,
    CardCategory? category,
    EnergyLevel? energyLevel,
    ParseConfidence? parseConfidence,
    bool? isRepeating,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? inputMethod,
    String? correctedText,
    int? triageActionCount,
    bool? hasDateUncertainty,
  }) {
    return BridgeCard(
      id: id ?? this.id,
      rawText: rawText ?? this.rawText,
      title: title ?? this.title,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      location: location ?? this.location,
      person: person ?? this.person,
      memo: memo ?? this.memo,
      status: status ?? this.status,
      category: category ?? this.category,
      energyLevel: energyLevel ?? this.energyLevel,
      parseConfidence: parseConfidence ?? this.parseConfidence,
      isRepeating: isRepeating ?? this.isRepeating,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      inputMethod: inputMethod ?? this.inputMethod,
      correctedText: correctedText ?? this.correctedText,
      triageActionCount: triageActionCount ?? this.triageActionCount,
      hasDateUncertainty: hasDateUncertainty ?? this.hasDateUncertainty,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'raw_text': rawText,
      'title': title,
      'start_time': startTime?.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'duration_minutes': durationMinutes,
      'location': location,
      'person': person,
      'memo': memo,
      'status': status.index,
      'category': category.index,
      'energy_level': energyLevel.index,
      'parse_confidence': parseConfidence.index,
      'is_repeating': isRepeating ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'input_method': inputMethod,
      'corrected_text': correctedText,
      'triage_action_count': triageActionCount,
      'has_date_uncertainty': hasDateUncertainty ? 1 : 0,
    };
  }

  factory BridgeCard.fromMap(Map<String, dynamic> map) {
    return BridgeCard(
      id: map['id'] as int?,
      rawText: map['raw_text'] as String,
      title: map['title'] as String,
      startTime: map['start_time'] != null
          ? DateTime.parse(map['start_time'] as String)
          : null,
      endTime: map['end_time'] != null
          ? DateTime.parse(map['end_time'] as String)
          : null,
      durationMinutes: map['duration_minutes'] as int?,
      location: map['location'] as String?,
      person: map['person'] as String?,
      memo: map['memo'] as String?,
      status: CardStatus.values[map['status'] as int],
      category: CardCategory.values[map['category'] as int],
      energyLevel: EnergyLevel.values[map['energy_level'] as int],
      parseConfidence:
          ParseConfidence.values[map['parse_confidence'] as int],
      isRepeating: (map['is_repeating'] as int) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      inputMethod: map['input_method'] as String? ?? 'text',
      correctedText: map['corrected_text'] as String?,
      triageActionCount: map['triage_action_count'] as int? ?? 0,
      hasDateUncertainty: (map['has_date_uncertainty'] as int?) == 1,
    );
  }
}
