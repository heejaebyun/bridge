/// TriageTab: 저녁 브리핑 — 미결정 카드를 한 장씩 처리
///
/// 규칙:
/// - NEW + DEFERRED 카드만 표시
/// - 한 번에 1개만 처리
/// - 카드 스택 UI (뒤에 겹쳐 보임)
/// - 처리: 확정 / 미룸 / 삭제 / 수정
/// - 텍스트 입력 없음
/// - 추천 UI 없음

import 'package:flutter/material.dart';
import '../models/bridge_card.dart';
import '../services/card_service.dart';
import '../services/database_service.dart';
import '../services/share_service.dart';

class TriageTab extends StatefulWidget {
  final VoidCallback? onTriageChanged;

  const TriageTab({super.key, this.onTriageChanged});

  @override
  State<TriageTab> createState() => _TriageTabState();
}

class _TriageTabState extends State<TriageTab> {
  final CardService _cardService = CardService();
  final DatabaseService _db = DatabaseService();
  final ShareService _shareService = ShareService();

  List<BridgeCard> _cards = [];
  bool _isLoading = true;
  bool _showComplete = false;

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadCards();
  }

  Future<void> _loadCards() async {
    final cards = await _cardService.getTriageCards();
    if (mounted) {
      setState(() {
        _cards = cards;
        _isLoading = false;
        _showComplete = false;
      });
    }
  }

  Future<void> _confirmCard(BridgeCard card) async {
    if (card.isComplete) {
      // 바로 확정
      await _cardService.confirmCard(card.id!);
      _removeTopCard();
    } else {
      // 정보 부족 → 수정 다이얼로그
      _showEditDialog(card);
    }
  }

  Future<void> _deferCard(BridgeCard card) async {
    await _cardService.deferCard(card.id!);
    _removeTopCard();
  }

  Future<void> _deleteCard(BridgeCard card) async {
    await _cardService.deleteCard(card.id!);
    _removeTopCard();
  }

  void _removeTopCard() {
    setState(() {
      if (_cards.isNotEmpty) {
        _cards.removeAt(0);
      }
      if (_cards.isEmpty) {
        _showComplete = true;
        _cardService.completeTriageSession();
      }
    });
    widget.onTriageChanged?.call();
  }

  void _showEditDialog(BridgeCard card) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _EditCardSheet(
        card: card,
        onSave: (updated) async {
          Navigator.pop(ctx);
          // 수정 후 확정
          await _cardService.editCard(
            card.id!,
            title: updated.title,
            startTime: updated.startTime,
            location: updated.location,
          );
          await _cardService.confirmCard(card.id!);
          _removeTopCard();
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1A),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF22D3EE)))
            : _showComplete
                ? _buildCompleteView()
                : _cards.isEmpty
                    ? _buildEmptyView()
                    : _buildTriageView(),
      ),
    );
  }

  Widget _buildTriageView() {
    return Column(
      children: [
        // 헤더
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Triage',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_cards.length}개 남음',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFFF59E0B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),

        // 카드 스택
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildCardStack(),
            ),
          ),
        ),

        // 액션 버튼
        _buildActionButtons(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildCardStack() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 뒤 카드들 (미리보기)
        for (int i = (_cards.length - 1 > 2 ? 2 : _cards.length - 1);
            i > 0;
            i--)
          Transform.translate(
            offset: Offset(0, -i * 8.0),
            child: Transform.scale(
              scale: 1 - (i * 0.05),
              child: Opacity(
                opacity: 1 - (i * 0.3),
                child: _buildCard(_cards[i], isBackground: true),
              ),
            ),
          ),

        // 최상단 카드 (인터랙티브)
        if (_cards.isNotEmpty)
          Dismissible(
            key: ValueKey(_cards[0].id),
            direction: DismissDirection.horizontal,
            onDismissed: (direction) {
              if (direction == DismissDirection.endToStart) {
                // 왼쪽 스와이프 → 삭제
                _deleteCard(_cards[0]);
              } else {
                // 오른쪽 스와이프 → 미루기
                _deferCard(_cards[0]);
              }
            },
            background: Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 32),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule, color: Color(0xFFF59E0B), size: 32),
                  SizedBox(height: 4),
                  Text('나중에', style: TextStyle(color: Color(0xFFF59E0B))),
                ],
              ),
            ),
            secondaryBackground: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 32),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 32),
                  SizedBox(height: 4),
                  Text('삭제', style: TextStyle(color: Color(0xFFEF4444))),
                ],
              ),
            ),
            child: _buildCard(_cards[0]),
          ),
      ],
    );
  }

  Widget _buildCard(BridgeCard card, {bool isBackground = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: card.isComplete
              ? const Color(0xFF22D3EE).withOpacity(0.3)
              : const Color(0xFFF59E0B).withOpacity(0.3),
          width: isBackground ? 1 : 1.5,
        ),
        boxShadow: isBackground
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 카테고리 태그
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF22D3EE).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${card.categoryEmoji} ${card.categoryLabel}',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF22D3EE),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 제목
          Text(
            card.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),

          // 날짜/시간
          _buildInfoRow(
            Icons.calendar_today,
            card.dateString,
            isSet: card.hasDate,
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            Icons.access_time,
            card.hasTime ? card.timeString : '시간 미정',
            isSet: card.hasTime,
          ),
          if (card.location != null) ...[
            const SizedBox(height: 8),
            _buildInfoRow(Icons.place, card.location!, isSet: true),
          ],
          if (card.person != null) ...[
            const SizedBox(height: 8),
            _buildInfoRow(Icons.person, card.person!, isSet: true),
          ],

          const SizedBox(height: 16),

          // 원문 (작은 글씨)
          if (card.rawText != card.title)
            Text(
              '"${card.rawText}"',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white24,
                fontStyle: FontStyle.italic,
              ),
            ),

          // 파싱 상태
          if (!card.isComplete)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outline,
                        size: 14, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 6),
                    Text(
                      card.hasDate
                          ? '시간을 정해주세요'
                          : '날짜와 시간을 정해주세요',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text, {bool isSet = false}) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: isSet ? const Color(0xFF22D3EE) : Colors.white24,
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: TextStyle(
            fontSize: 16,
            color: isSet ? Colors.white : Colors.white38,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    if (_cards.isEmpty) return const SizedBox();
    final card = _cards[0];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // 삭제
          _buildActionBtn(
            Icons.close,
            '삭제',
            const Color(0xFFEF4444),
            () => _deleteCard(card),
          ),
          const SizedBox(width: 12),
          // 나중에
          _buildActionBtn(
            Icons.schedule,
            '나중에',
            const Color(0xFFF59E0B),
            () => _deferCard(card),
          ),
          const SizedBox(width: 12),
          // 공유 (사람이 있는 카드만)
          if (card.person != null) ...[
            _buildActionBtn(
              Icons.share,
              '공유',
              const Color(0xFF10B981),
              () => _shareService.shareCard(card),
            ),
            const SizedBox(width: 12),
          ] else ...[
            // 수정
            _buildActionBtn(
              Icons.edit,
              '수정',
              const Color(0xFF818CF8),
              () => _showEditDialog(card),
            ),
            const SizedBox(width: 12),
          ],
          // 확정
          Expanded(
            child: GestureDetector(
              onTap: () => _confirmCard(card),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF22D3EE),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check, color: Colors.black, size: 20),
                    SizedBox(width: 6),
                    Text(
                      '확정',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBtn(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline,
              size: 64, color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 16),
          const Text(
            '처리할 카드가 없어요',
            style: TextStyle(fontSize: 18, color: Colors.white38),
          ),
          const SizedBox(height: 8),
          const Text(
            'Chat에서 일정을 추가해보세요',
            style: TextStyle(fontSize: 14, color: Colors.white24),
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.celebration,
              size: 64, color: Color(0xFF22D3EE)),
          const SizedBox(height: 16),
          const Text(
            '다 정리했어요! 🎉',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '편한 밤 보내세요 🌙',
            style: TextStyle(fontSize: 16, color: Colors.white54),
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: _loadCards,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: const Text(
                '다시 확인',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ========== 수정 시트 ==========

class _EditCardSheet extends StatefulWidget {
  final BridgeCard card;
  final Function(BridgeCard) onSave;
  final VoidCallback onCancel;

  const _EditCardSheet({
    required this.card,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<_EditCardSheet> createState() => _EditCardSheetState();
}

class _EditCardSheetState extends State<_EditCardSheet> {
  late TextEditingController _titleController;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.card.title);
    _selectedDate = widget.card.startTime;
    if (widget.card.hasTime) {
      _selectedTime = TimeOfDay(
        hour: widget.card.startTime!.hour,
        minute: widget.card.startTime!.minute,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '카드 수정',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),

            // 제목
            TextField(
              controller: _titleController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: '제목',
                labelStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF0A0F1A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 날짜 선택
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0F1A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today,
                        size: 18, color: Color(0xFF22D3EE)),
                    const SizedBox(width: 12),
                    Text(
                      _selectedDate != null
                          ? '${_selectedDate!.month}/${_selectedDate!.day}'
                          : '날짜 선택',
                      style: TextStyle(
                        color: _selectedDate != null
                            ? Colors.white
                            : Colors.white38,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 시간 선택
            GestureDetector(
              onTap: _pickTime,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0F1A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time,
                        size: 18, color: Color(0xFF22D3EE)),
                    const SizedBox(width: 12),
                    Text(
                      _selectedTime != null
                          ? '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}'
                          : '시간 선택',
                      style: TextStyle(
                        color: _selectedTime != null
                            ? Colors.white
                            : Colors.white38,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 버튼
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: widget.onCancel,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0F1A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text('취소',
                            style: TextStyle(color: Colors.white54)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      DateTime? startTime;
                      if (_selectedDate != null) {
                        startTime = DateTime(
                          _selectedDate!.year,
                          _selectedDate!.month,
                          _selectedDate!.day,
                          _selectedTime?.hour ?? 0,
                          _selectedTime?.minute ?? 0,
                        );
                      }

                      widget.onSave(widget.card.copyWith(
                        title: _titleController.text,
                        startTime: startTime,
                      ));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22D3EE),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          '확정',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF22D3EE),
              surface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? const TimeOfDay(hour: 12, minute: 0),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF22D3EE),
              surface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );
    if (time != null) {
      setState(() => _selectedTime = time);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }
}
