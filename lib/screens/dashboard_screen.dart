/// DashboardScreen: 나의 생활 리포트
/// 메타데이터 축적 → 시각화 → 락인
///
/// 투자자에게 보여주는 핵심:
/// "쓸수록 데이터가 쌓이고, 데이터가 쌓일수록 떠나기 어려움"

import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/card_service.dart';
import '../models/bridge_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DatabaseService _db = DatabaseService();
  final CardService _cardService = CardService();

  bool _isLoading = true;
  _DashboardData? _data;
  int _selectedPeriod = 7; // 7일 / 14일 / 30일

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final db = await _db.database;

    // 기간 내 확정된 카드
    final since = DateTime.now()
        .subtract(Duration(days: _selectedPeriod))
        .toIso8601String();

    final allCards = await db.rawQuery('''
      SELECT * FROM cards 
      WHERE created_at >= ? AND status != ?
      ORDER BY created_at DESC
    ''', [since, CardStatus.deleted.index]);

    final confirmedCards = await db.rawQuery('''
      SELECT * FROM cards 
      WHERE created_at >= ? AND status = ?
      ORDER BY start_time ASC
    ''', [since, CardStatus.confirmed.index]);

    // 카테고리별 통계
    final categoryStats = await db.rawQuery('''
      SELECT category, COUNT(*) as count 
      FROM cards 
      WHERE created_at >= ? AND status = ?
      GROUP BY category 
      ORDER BY count DESC
    ''', [since, CardStatus.confirmed.index]);

    // 요일별 통계
    final weekdayStats = await db.rawQuery('''
      SELECT CAST(strftime('%w', start_time) AS INTEGER) as weekday,
             COUNT(*) as count
      FROM cards
      WHERE created_at >= ? AND status = ? AND start_time IS NOT NULL
      GROUP BY weekday
      ORDER BY weekday
    ''', [since, CardStatus.confirmed.index]);

    // 시간대별 통계
    final hourStats = await db.rawQuery('''
      SELECT CAST(strftime('%H', start_time) AS INTEGER) as hour,
             COUNT(*) as count
      FROM cards
      WHERE created_at >= ? AND status = ? AND start_time IS NOT NULL
      GROUP BY hour
      ORDER BY hour
    ''', [since, CardStatus.confirmed.index]);

    // 행동 통계
    final actionStats = await _db.getActionStats(_selectedPeriod);

    // 파싱 성공률
    final parseStats = await db.rawQuery('''
      SELECT parse_confidence, COUNT(*) as count
      FROM cards
      WHERE created_at >= ?
      GROUP BY parse_confidence
    ''', [since]);

    // 평균 하루 일정
    final avgDaily = await _db.getAverageDailyCards(_selectedPeriod);

    // 가장 바쁜 요일
    String busiestDay = '없음';
    int busiestCount = 0;
    final weekdayNames = ['일', '월', '화', '수', '목', '금', '토'];
    for (final row in weekdayStats) {
      final count = row['count'] as int;
      if (count > busiestCount) {
        busiestCount = count;
        busiestDay = '${weekdayNames[row['weekday'] as int]}요일';
      }
    }

    // 가장 많이 미루는 카테고리
    final deferredStats = await db.rawQuery('''
      SELECT c.category, COUNT(*) as count
      FROM user_actions ua
      JOIN cards c ON ua.card_id = c.id
      WHERE ua.action_type = 'card_defer' AND ua.timestamp >= ?
      GROUP BY c.category
      ORDER BY count DESC
      LIMIT 1
    ''', [since]);

    String mostDeferred = '없음';
    if (deferredStats.isNotEmpty) {
      final catIdx = deferredStats.first['category'] as int;
      if (catIdx < CardCategory.values.length) {
        mostDeferred = _categoryLabel(CardCategory.values[catIdx]);
      }
    }

    // 가장 활동적인 시간대
    String peakHour = '없음';
    int peakCount = 0;
    for (final row in hourStats) {
      final count = row['count'] as int;
      if (count > peakCount) {
        peakCount = count;
        final h = row['hour'] as int;
        peakHour = '$h시~${h + 1}시';
      }
    }

    // 파싱 성공률 계산
    int totalParsed = 0;
    int successParsed = 0;
    for (final row in parseStats) {
      final count = row['count'] as int;
      totalParsed += count;
      final conf = row['parse_confidence'] as int;
      if (conf <= 2) successParsed += count; // full, partial, corrected
    }
    final parseRate = totalParsed > 0
        ? (successParsed / totalParsed * 100).round()
        : 0;

    // 카테고리별 시간 합산
    final categoryHours = <CardCategory, double>{};
    for (final row in confirmedCards) {
      final card = BridgeCard.fromMap(row);
      final duration = card.durationMinutes ?? 60;
      categoryHours[card.category] =
          (categoryHours[card.category] ?? 0) + duration / 60.0;
    }

    if (mounted) {
      setState(() {
        _data = _DashboardData(
          totalCards: allCards.length,
          confirmedCount: confirmedCards.length,
          avgDailyCards: avgDaily,
          busiestDay: busiestDay,
          busiestDayCount: busiestCount,
          mostDeferredCategory: mostDeferred,
          peakHour: peakHour,
          parseSuccessRate: parseRate,
          categoryStats: {
            for (final row in categoryStats)
              if (row['category'] as int < CardCategory.values.length)
                CardCategory.values[row['category'] as int]:
                    row['count'] as int,
          },
          weekdayStats: {
            for (final row in weekdayStats)
              row['weekday'] as int: row['count'] as int,
          },
          hourStats: {
            for (final row in hourStats)
              row['hour'] as int: row['count'] as int,
          },
          categoryHours: categoryHours,
          triageCount: actionStats['triage_complete'] ?? 0,
          totalActions: actionStats.values.fold(0, (a, b) => a + b),
        );
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0F1A),
        title: const Text(
          '나의 리포트',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF22D3EE)))
          : _data == null
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  color: const Color(0xFF22D3EE),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _buildPeriodSelector(),
                      const SizedBox(height: 20),
                      _buildOverviewCard(),
                      const SizedBox(height: 16),
                      _buildInsightsCard(),
                      const SizedBox(height: 16),
                      _buildCategoryBreakdown(),
                      const SizedBox(height: 16),
                      _buildWeekdayChart(),
                      const SizedBox(height: 16),
                      _buildHourChart(),
                      const SizedBox(height: 16),
                      _buildParseStats(),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.analytics_outlined, size: 64, color: Colors.white12),
          SizedBox(height: 16),
          Text('아직 데이터가 부족해요', style: TextStyle(color: Colors.white38, fontSize: 18)),
          SizedBox(height: 8),
          Text('일정을 추가하면 리포트가 생겨요', style: TextStyle(color: Colors.white24, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Row(
      children: [7, 14, 30].map((days) {
        final isSelected = _selectedPeriod == days;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () {
              setState(() => _selectedPeriod = days);
              _loadData();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF22D3EE).withOpacity(0.15)
                    : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF22D3EE)
                      : const Color(0xFF334155),
                ),
              ),
              child: Text(
                '$days일',
                style: TextStyle(
                  color: isSelected ? const Color(0xFF22D3EE) : Colors.white54,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildOverviewCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF22D3EE).withOpacity(0.12),
            const Color(0xFF818CF8).withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF22D3EE).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '최근 $_selectedPeriod일 요약',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatPill('${_data!.confirmedCount}', '완료 일정', const Color(0xFF22D3EE)),
              _buildStatPill('${_data!.avgDailyCards.toStringAsFixed(1)}', '하루 평균', const Color(0xFF818CF8)),
              _buildStatPill('${_data!.triageCount}', 'Triage 완료', const Color(0xFFF59E0B)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill(String value, String label, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white54)),
      ],
    );
  }

  Widget _buildInsightsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb_outline, color: Color(0xFFF59E0B), size: 20),
              SizedBox(width: 8),
              Text('인사이트', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 16),
          _buildInsightRow('📅', '가장 바쁜 요일', _data!.busiestDay, '${_data!.busiestDayCount}건'),
          const SizedBox(height: 12),
          _buildInsightRow('⏰', '가장 활동적인 시간', _data!.peakHour, ''),
          const SizedBox(height: 12),
          _buildInsightRow('🔄', '자주 미루는 카테고리', _data!.mostDeferredCategory, ''),
          const SizedBox(height: 12),
          _buildInsightRow('🎯', '입력 인식률', '${_data!.parseSuccessRate}%', ''),
        ],
      ),
    );
  }

  Widget _buildInsightRow(String emoji, String label, String value, String sub) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 14, color: Colors.white54)),
        ),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
        if (sub.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(sub, style: const TextStyle(fontSize: 12, color: Colors.white38)),
        ],
      ],
    );
  }

  Widget _buildCategoryBreakdown() {
    if (_data!.categoryStats.isEmpty) return const SizedBox();

    final total = _data!.categoryStats.values.fold(0, (a, b) => a + b);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('카테고리별 일정', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 16),
          ..._data!.categoryStats.entries.map((entry) {
            final pct = total > 0 ? entry.value / total : 0.0;
            final hours = _data!.categoryHours[entry.key] ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(_categoryEmoji(entry.key), style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_categoryLabel(entry.key), style: const TextStyle(color: Colors.white70)),
                      ),
                      Text('${entry.value}건', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                      const SizedBox(width: 8),
                      Text('${hours.toStringAsFixed(1)}h', style: const TextStyle(color: Color(0xFF22D3EE), fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: const Color(0xFF334155),
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF22D3EE)),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildWeekdayChart() {
    final weekdayNames = ['일', '월', '화', '수', '목', '금', '토'];
    final maxCount = _data!.weekdayStats.values.isEmpty
        ? 1
        : _data!.weekdayStats.values.reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('요일별 일정', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final count = _data!.weekdayStats[i] ?? 0;
                final height = maxCount > 0 ? (count / maxCount) * 80 : 0.0;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '$count',
                      style: const TextStyle(fontSize: 11, color: Colors.white38),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 28,
                      height: height + 4,
                      decoration: BoxDecoration(
                        color: count == maxCount
                            ? const Color(0xFF22D3EE)
                            : const Color(0xFF22D3EE).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      weekdayNames[i],
                      style: TextStyle(
                        fontSize: 12,
                        color: i == 0
                            ? const Color(0xFFEF4444).withOpacity(0.7)
                            : i == 6
                                ? const Color(0xFF3B82F6).withOpacity(0.7)
                                : Colors.white54,
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHourChart() {
    // 6시~23시만 표시
    final hours = List.generate(18, (i) => i + 6);
    final maxCount = _data!.hourStats.values.isEmpty
        ? 1
        : _data!.hourStats.values.reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('시간대별 활동', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 16),
          SizedBox(
            height: 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: hours.map((h) {
                final count = _data!.hourStats[h] ?? 0;
                final height = maxCount > 0 ? (count / maxCount) * 60 : 0.0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Container(
                      height: height + 2,
                      decoration: BoxDecoration(
                        color: count == maxCount
                            ? const Color(0xFF818CF8)
                            : const Color(0xFF818CF8).withOpacity(0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('6시', style: TextStyle(fontSize: 10, color: Colors.white24)),
              const Text('12시', style: TextStyle(fontSize: 10, color: Colors.white24)),
              const Text('18시', style: TextStyle(fontSize: 10, color: Colors.white24)),
              const Text('23시', style: TextStyle(fontSize: 10, color: Colors.white24)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildParseStats() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Bridge 성능', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  '${_data!.parseSuccessRate}%',
                  '입력 인식률',
                  const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  '${_data!.totalCards}',
                  '총 입력',
                  const Color(0xFF22D3EE),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  '${_data!.totalActions}',
                  '총 행동',
                  const Color(0xFF818CF8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ],
      ),
    );
  }

  String _categoryLabel(CardCategory cat) {
    const labels = {
      CardCategory.work: '업무',
      CardCategory.meeting: '약속',
      CardCategory.health: '건강',
      CardCategory.errand: '심부름',
      CardCategory.leisure: '여가',
      CardCategory.travel: '이동',
      CardCategory.meal: '식사',
      CardCategory.study: '학습',
      CardCategory.social: '모임',
      CardCategory.other: '기타',
    };
    return labels[cat] ?? '기타';
  }

  String _categoryEmoji(CardCategory cat) {
    const emojis = {
      CardCategory.work: '💼',
      CardCategory.meeting: '🤝',
      CardCategory.health: '🏥',
      CardCategory.errand: '🛒',
      CardCategory.leisure: '🎮',
      CardCategory.travel: '🚗',
      CardCategory.meal: '🍽',
      CardCategory.study: '📚',
      CardCategory.social: '👥',
      CardCategory.other: '📌',
    };
    return emojis[cat] ?? '📌';
  }
}

class _DashboardData {
  final int totalCards;
  final int confirmedCount;
  final double avgDailyCards;
  final String busiestDay;
  final int busiestDayCount;
  final String mostDeferredCategory;
  final String peakHour;
  final int parseSuccessRate;
  final Map<CardCategory, int> categoryStats;
  final Map<int, int> weekdayStats;
  final Map<int, int> hourStats;
  final Map<CardCategory, double> categoryHours;
  final int triageCount;
  final int totalActions;

  _DashboardData({
    required this.totalCards,
    required this.confirmedCount,
    required this.avgDailyCards,
    required this.busiestDay,
    required this.busiestDayCount,
    required this.mostDeferredCategory,
    required this.peakHour,
    required this.parseSuccessRate,
    required this.categoryStats,
    required this.weekdayStats,
    required this.hourStats,
    required this.categoryHours,
    required this.triageCount,
    required this.totalActions,
  });
}
