/// ChatTab: 모든 입력의 입구
/// "대충 써도 받아주는" 경험의 핵심
///
/// 규칙:
/// - 항상 답변함 (잘 모르겠어요 금지)
/// - 카드 생성 시 즉시 시각적 피드백
/// - Quick Actions로 다음 행동 유도
/// - "또 뭐 있어요?" 로 연속 입력 유도

import 'package:flutter/material.dart';
import '../models/bridge_card.dart';
import '../models/chat_message.dart';
import '../services/card_service.dart';
import '../services/database_service.dart';
import '../services/share_service.dart';

class ChatTab extends StatefulWidget {
  final VoidCallback? onCardCreated;

  const ChatTab({super.key, this.onCardCreated});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final CardService _cardService = CardService();
  final DatabaseService _db = DatabaseService();
  final ShareService _shareService = ShareService();

  List<_ChatItem> _items = [];
  bool _isProcessing = false;
  int _coinBalance = 200;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadCoinBalance();
    await _addWelcomeMessage();
  }

  Future<void> _loadCoinBalance() async {
    final balance = await _db.getCoinBalance();
    setState(() => _coinBalance = balance);
  }

  Future<void> _addWelcomeMessage() async {
    final isFirst = await _db.isFirstLaunch();

    if (_items.isEmpty) {
      setState(() {
        _items.add(_ChatItem.system(
          '안녕하세요! 내일 뭐 하세요?\n아무거나 말해주세요. 대충 써도 돼요 😊',
          quickActions: [
            QuickAction(label: '내일 일정 입력하기', action: 'focus_input'),
            QuickAction(label: '그냥 둘러볼게', action: 'tour'),
          ],
        ));
      });
    }
  }

  Future<void> _handleInput(String text) async {
    if (text.trim().isEmpty) return;
    _controller.clear();

    setState(() {
      _items.add(_ChatItem.user(text));
      _isProcessing = true;
    });
    _scrollToBottom();

    // 특수 명령어 처리
    if (_isSpecialCommand(text)) {
      await _handleSpecialCommand(text);
      return;
    }

    // 카드 생성
    try {
      final result = await _cardService.processInput(text);

      setState(() {
        _isProcessing = false;
        _items.add(_ChatItem.card(
          result.card,
          result.systemMessage,
          result.quickActions,
        ));

        // 카드 3개 이하면 "또 뭐 있어요?" 유도
        // 여기서 DB count를 하진 않고 현재 세션 기준
        final cardCount = _items.where((i) => i.type == _ChatItemType.card).length;
        if (cardCount <= 3) {
          _items.add(_ChatItem.system(
            _getNextPrompt(cardCount),
          ));
        }
      });

      widget.onCardCreated?.call();
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _items.add(_ChatItem.system(
          '일단 메모로 저장했어요! 저녁에 같이 정리해요 ✌️',
        ));
      });
    }

    _scrollToBottom();
  }

  String _getNextPrompt(int cardCount) {
    switch (cardCount) {
      case 1: return '잘 받았어요! 다른 것도 있으면 알려주세요 ✍️';
      case 2: return '또 뭐 있어요?';
      case 3: return '좋아요! 저녁에 같이 정리해요 🌙';
      default: return '';
    }
  }

  bool _isSpecialCommand(String text) {
    final lower = text.toLowerCase().trim();
    return lower == '브리핑' ||
        lower == '브리핑해줘' ||
        lower == '오늘 일정' ||
        lower.contains('코인') ||
        lower.contains('충전') ||
        lower.contains('크레딧');
  }

  Future<void> _handleSpecialCommand(String text) async {
    final lower = text.toLowerCase().trim();

    if (lower.contains('브리핑') || lower.contains('오늘 일정')) {
      final briefing = await _cardService.generateMorningBriefing();
      setState(() {
        _isProcessing = false;
        _items.add(_ChatItem.system(briefing));
      });
    } else if (lower.contains('코인') || lower.contains('충전') || lower.contains('크레딧')) {
      setState(() {
        _isProcessing = false;
        _items.add(_ChatItem.system(
          '💰 코인 잔액: ${_coinBalance}원\n\n'
          'AI 기능은 Phase 2에서 만나요!\n'
          '간단한 일정 입력은 무료예요!',
        ));
      });
    }

    _scrollToBottom();
  }

  /// Quick Action 처리
  Future<void> _handleQuickAction(QuickAction action) async {
    switch (action.action) {
      case 'confirm':
        if (action.payload != null) {
          final cardId = int.parse(action.payload!);
          final card = await _cardService.confirmCard(cardId);
          setState(() {
            _items.add(_ChatItem.system(
              '✅ ${card.dateString} ${card.hasTime ? card.timeString : ""} '
              '\'${card.title}\' 확정!',
            ));
          });
          widget.onCardCreated?.call();
        }
        break;

      case 'defer':
        if (action.payload != null) {
          final cardId = int.parse(action.payload!);
          await _cardService.deferCard(cardId);
          setState(() {
            _items.add(_ChatItem.system(
              '📌 저녁에 같이 정리해요!',
            ));
          });
        }
        break;

      case 'edit':
        if (action.payload != null) {
          // TODO: 수정 다이얼로그 열기
          setState(() {
            _items.add(_ChatItem.system(
              '수정할 내용을 말해주세요.\n예: "시간 3시로 변경" / "장소 강남역"',
            ));
          });
        }
        break;

      case 'set_date':
        if (action.payload != null) {
          // 마지막 카드의 ID를 찾아서 날짜 설정
          final lastCard = _findLastCard();
          if (lastCard != null) {
            final updated = await _cardService.setCardDate(
                lastCard.id!, action.payload!);
            setState(() {
              _items.add(_ChatItem.system(
                '📅 ${updated.dateString}로 설정했어요!',
                quickActions: updated.isComplete
                    ? [
                        QuickAction(
                            label: '확정 ✓',
                            action: 'confirm',
                            payload: '${updated.id}'),
                        QuickAction(
                            label: '시간 수정',
                            action: 'edit',
                            payload: '${updated.id}'),
                      ]
                    : [
                        QuickAction(
                            label: '오전',
                            action: 'set_time',
                            payload: 'morning'),
                        QuickAction(
                            label: '오후',
                            action: 'set_time',
                            payload: 'afternoon'),
                        QuickAction(
                            label: '저녁',
                            action: 'set_time',
                            payload: 'evening'),
                      ],
              ));
            });
            widget.onCardCreated?.call();
          }
        }
        break;

      case 'set_time':
        if (action.payload != null) {
          final lastCard = _findLastCard();
          if (lastCard != null) {
            final updated = await _cardService.setCardTime(
                lastCard.id!, action.payload!);
            setState(() {
              _items.add(_ChatItem.system(
                '⏰ ${updated.timeString}으로 설정했어요!',
                quickActions: [
                  QuickAction(
                      label: '확정 ✓',
                      action: 'confirm',
                      payload: '${updated.id}'),
                  QuickAction(
                      label: '수정',
                      action: 'edit',
                      payload: '${updated.id}'),
                ],
              ));
            });
            widget.onCardCreated?.call();
          }
        }
        break;

      case 'memo':
        if (action.payload != null) {
          setState(() {
            _items.add(_ChatItem.system('📝 메모로 저장했어요!'));
          });
        }
        break;

      case 'focus_input':
        _focusNode.requestFocus();
        break;

      case 'tour':
        setState(() {
          _items.add(_ChatItem.system(
            '둘러보세요!\n\n'
            '💬 Chat — 여기서 뭐든 입력\n'
            '📋 Timeline — 오늘 하루 일정\n'
            '🃏 Triage — 미결정 카드 정리\n'
            '📅 Calendar — 캘린더 뷰\n\n'
            '준비되면 언제든 말해주세요!',
          ));
        });
        break;

      case 'purchase':
        setState(() {
          _items.add(_ChatItem.system(
            '결제 기능은 Phase 2에서 만나요!\n곧 만나요 🙏',
          ));
        });
        break;

      case 'share':
        if (action.payload != null) {
          final card = _findLastCard();
          if (card != null) {
            await _shareService.shareCard(card);
            setState(() {
              _items.add(_ChatItem.system('📤 공유했어요!'));
            });
          }
        }
        break;
    }

    _scrollToBottom();
  }

  BridgeCard? _findLastCard() {
    for (int i = _items.length - 1; i >= 0; i--) {
      if (_items[i].card != null) {
        return _items[i].card;
      }
    }
    return null;
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0F1A),
        title: const Row(
          children: [
            Text(
              'Bridge',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          // 코인 잔액
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.toll, size: 16, color: Color(0xFFF59E0B)),
                const SizedBox(width: 4),
                Text(
                  '$_coinBalance',
                  style: const TextStyle(
                    color: Color(0xFFF59E0B),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 메시지 리스트
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _items.length + (_isProcessing ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _items.length && _isProcessing) {
                  return _buildTypingIndicator();
                }
                return _buildChatItem(_items[index]);
              },
            ),
          ),

          // 입력 영역
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildChatItem(_ChatItem item) {
    switch (item.type) {
      case _ChatItemType.user:
        return _buildUserBubble(item.text);
      case _ChatItemType.system:
        return _buildSystemBubble(item.text, item.quickActions);
      case _ChatItemType.card:
        return _buildCardBubble(item.card!, item.text, item.quickActions);
    }
  }

  Widget _buildUserBubble(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF22D3EE),
              borderRadius: BorderRadius.circular(20).copyWith(
                bottomRight: const Radius.circular(4),
              ),
            ),
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 15,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemBubble(String text, List<QuickAction>? quickActions) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20).copyWith(
                bottomLeft: const Radius.circular(4),
              ),
            ),
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ),
          if (quickActions != null && quickActions.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildQuickActions(quickActions),
          ],
        ],
      ),
    );
  }

  Widget _buildCardBubble(
      BridgeCard card, String message, List<QuickAction>? quickActions) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 카드 UI
          Container(
            width: MediaQuery.of(context).size.width * 0.72,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1E293B),
                  const Color(0xFF1E293B).withOpacity(0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: card.isComplete
                    ? const Color(0xFF22D3EE).withOpacity(0.5)
                    : const Color(0xFFF59E0B).withOpacity(0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 카테고리 + 상태
                Row(
                  children: [
                    Text(
                      card.categoryEmoji,
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        card.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // 날짜/시간
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: card.hasDate
                          ? const Color(0xFF22D3EE)
                          : Colors.white38,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      card.dateString,
                      style: TextStyle(
                        fontSize: 14,
                        color: card.hasDate
                            ? const Color(0xFF22D3EE)
                            : Colors.white38,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: card.hasTime
                          ? const Color(0xFF22D3EE)
                          : Colors.white38,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      card.hasTime ? card.timeString : '시간 미정',
                      style: TextStyle(
                        fontSize: 14,
                        color: card.hasTime
                            ? const Color(0xFF22D3EE)
                            : Colors.white38,
                      ),
                    ),
                  ],
                ),
                if (card.location != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.place, size: 14, color: Color(0xFF818CF8)),
                      const SizedBox(width: 6),
                      Text(
                        card.location!,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF818CF8),
                        ),
                      ),
                    ],
                  ),
                ],
                if (card.person != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.person, size: 14, color: Color(0xFF818CF8)),
                      const SizedBox(width: 6),
                      Text(
                        card.person!,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF818CF8),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 시스템 메시지
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white60,
              ),
            ),
          ),
          if (quickActions != null && quickActions.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildQuickActions(quickActions),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActions(List<QuickAction> actions) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: actions.map((action) {
        final isConfirm = action.action == 'confirm';
        return GestureDetector(
          onTap: () => _handleQuickAction(action),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isConfirm
                  ? const Color(0xFF22D3EE).withOpacity(0.15)
                  : const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isConfirm
                    ? const Color(0xFF22D3EE).withOpacity(0.5)
                    : const Color(0xFF334155),
              ),
            ),
            child: Text(
              action.label,
              style: TextStyle(
                fontSize: 13,
                color: isConfirm
                    ? const Color(0xFF22D3EE)
                    : Colors.white70,
                fontWeight: isConfirm ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                return Padding(
                  padding: EdgeInsets.only(left: i > 0 ? 4 : 0),
                  child: _AnimatedDot(delay: i * 200),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0F1A),
        border: Border(
          top: BorderSide(color: Color(0xFF1E293B)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // TODO: 음성 입력 버튼
            // GestureDetector(
            //   onTap: _startVoiceInput,
            //   child: Container(...)
            // ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: '아무거나 말해주세요...',
                    hintStyle: TextStyle(color: Colors.white30),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                  onSubmitted: _handleInput,
                  textInputAction: TextInputAction.send,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _handleInput(_controller.text),
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0xFF22D3EE),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_upward,
                    color: Colors.black, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}

// ========== 내부 모델 ==========

enum _ChatItemType { user, system, card }

class _ChatItem {
  final _ChatItemType type;
  final String text;
  final BridgeCard? card;
  final List<QuickAction>? quickActions;

  _ChatItem._({
    required this.type,
    required this.text,
    this.card,
    this.quickActions,
  });

  factory _ChatItem.user(String text) =>
      _ChatItem._(type: _ChatItemType.user, text: text);

  factory _ChatItem.system(String text, {List<QuickAction>? quickActions}) =>
      _ChatItem._(
          type: _ChatItemType.system, text: text, quickActions: quickActions);

  factory _ChatItem.card(
          BridgeCard card, String message, List<QuickAction>? quickActions) =>
      _ChatItem._(
        type: _ChatItemType.card,
        text: message,
        card: card,
        quickActions: quickActions,
      );
}

// ========== 애니메이션 ==========

class _AnimatedDot extends StatefulWidget {
  final int delay;
  const _AnimatedDot({required this.delay});

  @override
  State<_AnimatedDot> createState() => _AnimatedDotState();
}

class _AnimatedDotState extends State<_AnimatedDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.repeat();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Color.lerp(
              const Color(0xFF22D3EE).withOpacity(0.3),
              const Color(0xFF22D3EE),
              _controller.value,
            ),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
