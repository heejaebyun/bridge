/// TimelineTab: 오늘 하루 타임라인
/// 아침 브리핑의 시각적 표현
///
/// 규칙:
/// - 확정된 일정만 표시
/// - 빈 시간 명시적으로 표시
/// - 여기서 생성/수정 불가 (읽기 전용)
/// - 추천 트리거 없음

import 'package:flutter/material.dart';
import '../models/bridge_card.dart';
import '../services/card_service.dart';
import '../services/repeat_detection_service.dart';
import 'dashboard_screen.dart';
import 'repeat_pattern_sheet.dart';

class TimelineTab extends StatefulWidget {
  const TimelineTab({super.key});

  @override
  State<TimelineTab> createState() => _TimelineTabState();
}

class _TimelineTabState extends State<TimelineTab> {
  final CardService _cardService = CardService();
  final RepeatDetectionService _repeatDetector = RepeatDetectionService();
  TimelineData? _data;
  bool _isLoading = true;
  bool _hasRepeatPatterns = false;

  @override
  void initState() {
    super.initState();
    _loadTimeline();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadTimeline();
  }

  Future<void> _loadTimeline() async {
    final data = await _cardService.getTodayTimeline();
    // 반복 패턴 체크 (백그라운드)
    _repeatDetector.detectPatterns().then((patterns) {
      if (mounted && patterns.isNotEmpty) {
        setState(() => _hasRepeatPatterns = true);
      }
    });
    if (mounted) {
      setState(() {
        _data = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1A),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF22D3EE)))
            : RefreshIndicator(
                onRefresh: _loadTimeline,
                color: const Color(0xFF22D3EE),
                child: CustomScrollView(
                  slivers: [
                    // 헤더
                    SliverToBoxAdapter(child: _buildHeader()),
                    // 타임라인
                    SliverToBoxAdapter(child: _buildTimeline()),
                    // 반복 패턴 감지 알림
                    if (_hasRepeatPatterns)
                      SliverToBoxAdapter(child: _buildRepeatPatternNotice()),
                    // 미결정 카드 알림
                    if (_data != null && _data!.triageCardCount > 0)
                      SliverToBoxAdapter(child: _buildTriageNotice()),
                    // 하단 여백
                    const SliverToBoxAdapter(
                        child: SizedBox(height: 100)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeader() {
    final now = DateTime.now();
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final wd = weekdays[now.weekday - 1];

    final greeting = _getGreeting(now.hour);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$greeting',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DashboardScreen()),
                ),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.bar_chart_rounded,
                      color: Color(0xFF22D3EE), size: 22),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${now.month}월 ${now.day}일 (${wd}요일)',
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 16),
          // 요약 카드
          _buildSummaryCard(),
        ],
      ),
    );
  }

  String _getGreeting(int hour) {
    if (hour < 6) return '🌙 좋은 새벽이에요';
    if (hour < 12) return '☀️ 좋은 아침이에요';
    if (hour < 18) return '🌤 오후도 힘내요';
    return '🌙 오늘 하루 수고했어요';
  }

  Widget _buildSummaryCard() {
    if (_data == null) return const SizedBox();

    final totalFreeMinutes = _data!.freeSlots
        .fold<int>(0, (sum, s) => sum + s.durationMinutes);
    final freeHours = totalFreeMinutes ~/ 60;
    final freeMinutes = totalFreeMinutes % 60;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF22D3EE).withOpacity(0.15),
            const Color(0xFF818CF8).withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF22D3EE).withOpacity(0.2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            '${_data!.confirmedCards.length}',
            '일정',
            const Color(0xFF22D3EE),
          ),
          Container(
            width: 1,
            height: 32,
            color: const Color(0xFF334155),
          ),
          _buildStatItem(
            freeHours > 0 ? '${freeHours}h ${freeMinutes}m' : '${freeMinutes}m',
            '빈 시간',
            const Color(0xFF818CF8),
          ),
          Container(
            width: 1,
            height: 32,
            color: const Color(0xFF334155),
          ),
          _buildStatItem(
            '${_data!.triageCardCount}',
            '미결정',
            const Color(0xFFF59E0B),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white54),
        ),
      ],
    );
  }

  Widget _buildTimeline() {
    if (_data == null || _data!.confirmedCards.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            children: [
              const SizedBox(height: 40),
              Icon(Icons.wb_sunny_outlined,
                  size: 64, color: Colors.white.withOpacity(0.1)),
              const SizedBox(height: 16),
              const Text(
                '오늘은 일정이 없어요',
                style: TextStyle(fontSize: 18, color: Colors.white38),
              ),
              const SizedBox(height: 8),
              const Text(
                'Chat에서 일정을 추가해보세요',
                style: TextStyle(fontSize: 14, color: Colors.white24),
              ),
            ],
          ),
        ),
      );
    }

    // 타임라인 아이템 구성 (일정 + 빈 시간)
    final items = _buildTimelineItems();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: items.map((item) => _buildTimelineRow(item)).toList(),
      ),
    );
  }

  List<_TimelineItem> _buildTimelineItems() {
    final items = <_TimelineItem>[];
    final cards = _data!.confirmedCards;
    final freeSlots = _data!.freeSlots;

    // 일정과 빈 시간을 시간순으로 합치기
    int cardIdx = 0;
    int slotIdx = 0;

    while (cardIdx < cards.length || slotIdx < freeSlots.length) {
      DateTime? cardTime = cardIdx < cards.length
          ? cards[cardIdx].startTime
          : null;
      DateTime? slotTime = slotIdx < freeSlots.length
          ? freeSlots[slotIdx].start
          : null;

      if (cardTime != null &&
          (slotTime == null || cardTime.isBefore(slotTime))) {
        items.add(_TimelineItem.schedule(cards[cardIdx]));
        cardIdx++;
      } else if (slotTime != null) {
        items.add(_TimelineItem.freeTime(freeSlots[slotIdx]));
        slotIdx++;
      } else {
        break;
      }
    }

    return items;
  }

  Widget _buildTimelineRow(_TimelineItem item) {
    if (item.isSchedule) {
      return _buildScheduleItem(item.card!);
    } else {
      return _buildFreeSlotItem(item.freeSlot!);
    }
  }

  Widget _buildScheduleItem(BridgeCard card) {
    final now = DateTime.now();
    final isNow = card.hasTime &&
        card.startTime!.isBefore(now) &&
        (card.endTime ?? card.startTime!.add(
            Duration(minutes: card.durationMinutes ?? 60))).isAfter(now);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 시간
          SizedBox(
            width: 56,
            child: Text(
              card.hasTime ? card.timeString : '--:--',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isNow
                    ? const Color(0xFF22D3EE)
                    : Colors.white54,
              ),
            ),
          ),
          // 타임라인 도트
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isNow
                      ? const Color(0xFF22D3EE)
                      : const Color(0xFF334155),
                  border: Border.all(
                    color: isNow
                        ? const Color(0xFF22D3EE)
                        : const Color(0xFF475569),
                    width: 2,
                  ),
                ),
              ),
              Container(
                width: 2,
                height: 60,
                color: const Color(0xFF334155),
              ),
            ],
          ),
          const SizedBox(width: 12),
          // 카드 내용
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isNow
                    ? const Color(0xFF22D3EE).withOpacity(0.1)
                    : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isNow
                      ? const Color(0xFF22D3EE).withOpacity(0.3)
                      : const Color(0xFF334155),
                ),
              ),
              child: Row(
                children: [
                  Text(card.categoryEmoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        if (card.location != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            card.location!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white38,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isNow)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22D3EE),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'NOW',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
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

  Widget _buildFreeSlotItem(FreeSlot slot) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              '${slot.start.hour.toString().padLeft(2, '0')}:${slot.start.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white24,
              ),
            ),
          ),
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF334155),
                    width: 1,
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 40,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFF334155),
                    width: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF334155).withOpacity(0.5),
                  style: BorderStyle.solid,
                ),
              ),
              child: Text(
                '빈 시간 ${slot.durationMinutes}분',
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white24,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRepeatPatternNotice() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: GestureDetector(
        onTap: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            builder: (_) => const RepeatPatternSheet(),
          ).then((_) {
            _loadTimeline();
            setState(() => _hasRepeatPatterns = false);
          });
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF22D3EE).withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF22D3EE).withOpacity(0.25)),
          ),
          child: const Row(
            children: [
              Icon(Icons.repeat, color: Color(0xFF22D3EE), size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text('반복 패턴을 발견했어요! 확인할까요?',
                    style: TextStyle(color: Color(0xFF22D3EE), fontSize: 13)),
              ),
              Icon(Icons.chevron_right, color: Color(0xFF22D3EE), size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTriageNotice() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B).withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFF59E0B).withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.style, color: Color(0xFFF59E0B), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '미결정 카드 ${_data!.triageCardCount}개가 있어요',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

class _TimelineItem {
  final BridgeCard? card;
  final FreeSlot? freeSlot;

  bool get isSchedule => card != null;

  _TimelineItem._({this.card, this.freeSlot});

  factory _TimelineItem.schedule(BridgeCard card) =>
      _TimelineItem._(card: card);

  factory _TimelineItem.freeTime(FreeSlot slot) =>
      _TimelineItem._(freeSlot: slot);
}
