/// ChatMessage: Chat 탭의 메시지 모델

class ChatMessage {
  final int? id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final String? linkedCardId;     // 연결된 카드 ID
  final MessageType type;
  final List<QuickAction>? quickActions;

  ChatMessage({
    this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.linkedCardId,
    this.type = MessageType.text,
    this.quickActions,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'content': content,
      'is_user': isUser ? 1 : 0,
      'timestamp': timestamp.toIso8601String(),
      'linked_card_id': linkedCardId,
      'type': type.index,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as int?,
      content: map['content'] as String,
      isUser: (map['is_user'] as int) == 1,
      timestamp: DateTime.parse(map['timestamp'] as String),
      linkedCardId: map['linked_card_id'] as String?,
      type: MessageType.values[map['type'] as int? ?? 0],
    );
  }
}

enum MessageType {
  text,           // 일반 텍스트
  cardCreated,    // 카드 생성됨 (카드 UI 포함)
  cardConfirmed,  // 카드 확정됨
  briefing,       // 브리핑 메시지
  recommendation, // 추천 메시지
  coinPrompt,     // 코인 충전 유도
  system,         // 시스템 안내
}

/// 빠른 액션 버튼 (Chat 메시지 하단)
class QuickAction {
  final String label;
  final String action;    // 'confirm', 'edit', 'defer', 'input'
  final String? payload;  // 추가 데이터

  QuickAction({
    required this.label,
    required this.action,
    this.payload,
  });
}

/// CoinInfo: 코인(크레딧) 시스템
class CoinInfo {
  final int balance;          // 현재 잔액 (원 단위)
  final int totalUsed;        // 총 사용량
  final int totalPurchased;   // 총 충전량
  final DateTime? lastUsedAt;
  final DateTime? lastPurchasedAt;

  CoinInfo({
    required this.balance,
    this.totalUsed = 0,
    this.totalPurchased = 0,
    this.lastUsedAt,
    this.lastPurchasedAt,
  });

  /// 초기 무료 지급: 200원
  static const int initialGrant = 200;

  /// 충전 단위: 1,000원
  static const int purchaseUnit = 1000;

  /// LLM 기본 호출 비용: 50원
  static const int llmBasicCost = 50;

  /// LLM 복잡한 호출 비용: 100원
  static const int llmComplexCost = 100;

  /// LLM 사용 가능 여부
  bool get canUseLLM => balance >= llmBasicCost;

  /// 기본 호출 몇 번 가능한지
  int get remainingBasicCalls => balance ~/ llmBasicCost;
}

/// UserAction: 사용자 행동 메타데이터 (추천 엔진용)
class UserAction {
  final int? id;
  final DateTime timestamp;
  final String actionType;    // 'card_create', 'card_confirm', 'card_defer',
                              // 'card_delete', 'card_edit', 'triage_complete',
                              // 'recommendation_accept', 'recommendation_reject',
                              // 'briefing_view', 'coin_purchase', 'llm_call'
  final int? cardId;
  final String? metadata;     // JSON string for extra data

  UserAction({
    this.id,
    required this.timestamp,
    required this.actionType,
    this.cardId,
    this.metadata,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'action_type': actionType,
      'card_id': cardId,
      'metadata': metadata,
    };
  }

  factory UserAction.fromMap(Map<String, dynamic> map) {
    return UserAction(
      id: map['id'] as int?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      actionType: map['action_type'] as String,
      cardId: map['card_id'] as int?,
      metadata: map['metadata'] as String?,
    );
  }
}
