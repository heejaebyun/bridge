/// RepeatPatternSheet: 반복 일정 감지 결과 표시
///
/// Timeline이나 대시보드에서 표시
/// "매주 화요일 10시 팀미팅 — 반복할까요?"

import 'package:flutter/material.dart';
import '../services/repeat_detection_service.dart';

class RepeatPatternSheet extends StatefulWidget {
  const RepeatPatternSheet({super.key});

  @override
  State<RepeatPatternSheet> createState() => _RepeatPatternSheetState();
}

class _RepeatPatternSheetState extends State<RepeatPatternSheet> {
  final RepeatDetectionService _detector = RepeatDetectionService();

  List<RepeatPattern> _patterns = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final patterns = await _detector.detectPatterns();
    if (mounted) setState(() { _patterns = patterns; _isLoading = false; });
  }

  Future<void> _accept(RepeatPattern pattern, int index) async {
    final card = await _detector.acceptPattern(pattern);
    if (mounted) {
      setState(() => _patterns.removeAt(index));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🔁 ${pattern.description} 반복 일정 등록!'),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (_patterns.isEmpty) Navigator.pop(context, true);
    }
  }

  Future<void> _reject(RepeatPattern pattern, int index) async {
    await _detector.rejectPattern(pattern);
    if (mounted) {
      setState(() => _patterns.removeAt(index));
      if (_patterns.isEmpty) Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0A0F1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF334155),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.repeat, color: Color(0xFF22D3EE), size: 22),
                const SizedBox(width: 8),
                const Text('반복 일정 발견!',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
          ),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: Color(0xFF22D3EE), strokeWidth: 2),
            )
          else if (_patterns.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('감지된 반복 패턴이 없어요', style: TextStyle(color: Colors.white38)),
            )
          else
            ...List.generate(_patterns.length, (i) {
              final p = _patterns[i];
              return _buildPatternTile(p, i);
            }),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  Widget _buildPatternTile(RepeatPattern pattern, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22D3EE).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.repeat, color: Color(0xFF22D3EE), size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pattern.title,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                      const SizedBox(height: 2),
                      Text(
                        '${pattern.weekdayLabel} ${pattern.timeLabel} · ${pattern.weekCount}주 연속',
                        style: const TextStyle(fontSize: 12, color: Colors.white38),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (pattern.location != null || pattern.person != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (pattern.location != null)
                    _tag('📍 ${pattern.location}'),
                  if (pattern.person != null) ...[
                    const SizedBox(width: 6),
                    _tag('👤 ${pattern.person}'),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                const Spacer(),
                GestureDetector(
                  onTap: () => _reject(pattern, index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('아니야', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _accept(pattern, index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22D3EE),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('매주 반복 🔁',
                        style: TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF334155),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11, color: Colors.white54)),
    );
  }
}
