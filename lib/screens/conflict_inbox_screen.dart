import 'package:flutter/material.dart';

import '../models/calendar_conflict.dart';
import '../services/database_service.dart';

class ConflictInboxScreen extends StatefulWidget {
  const ConflictInboxScreen({super.key});

  @override
  State<ConflictInboxScreen> createState() => _ConflictInboxScreenState();
}

class _ConflictInboxScreenState extends State<ConflictInboxScreen> {
  final DatabaseService _db = DatabaseService();
  bool _loading = true;
  List<CalendarConflict> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _db.getOpenConflicts();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _resolve(CalendarConflict c, String resolution) async {
    // v0: 원본 캘린더 삭제/수정 없음
    // resolution 예: KEEP_BOTH / HIDE_A / HIDE_B / MERGE
    if (resolution == 'HIDE_A') {
      await _db.hideExternalEvent(c.eventASource, c.eventAId);
    } else if (resolution == 'HIDE_B') {
      await _db.hideExternalEvent(c.eventBSource, c.eventBId);
    } else if (resolution == 'MERGE') {
      // v0에서는 “병합=둘 중 하나 숨김”으로 처리 (정책 고정)
      // 우선 DEVICE를 남기고 GOOGLE 숨김 (원하면 룰 바꿔도 됨)
      if (c.eventASource == 'DEVICE') {
        await _db.hideExternalEvent(c.eventBSource, c.eventBId);
      } else if (c.eventBSource == 'DEVICE') {
        await _db.hideExternalEvent(c.eventASource, c.eventAId);
      } else {
        // 둘 다 DEVICE가 아닐 때는 B 숨김
        await _db.hideExternalEvent(c.eventBSource, c.eventBId);
      }
    }

    await _db.resolveConflict(c.id!, resolution);
    await _db.logAction('conflict_resolve',
        metadata: '{"id": ${c.id}, "resolution": "$resolution"}');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0F1A),
        foregroundColor: Colors.white,
        title: const Text('충돌 확인'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(
                  child: Text('확인할 충돌이 없어요',
                      style: TextStyle(color: Colors.white54)))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _tile(_items[i]),
                ),
    );
  }

  Widget _tile(CalendarConflict c) {
    final a = c.eventA;
    final b = c.eventB;
    if (a == null || b == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.conflictType == 'DUPLICATE' ? '중복 후보' : '시간 충돌',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          _row('A', a),
          const SizedBox(height: 8),
          _row('B', b),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _btn('병합', () => _resolve(c, 'MERGE'))),
              const SizedBox(width: 8),
              Expanded(child: _btn('둘 다 유지', () => _resolve(c, 'KEEP_BOTH'))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _btn('A 숨김', () => _resolve(c, 'HIDE_A'))),
              const SizedBox(width: 8),
              Expanded(child: _btn('B 숨김', () => _resolve(c, 'HIDE_B'))),
            ],
          ),
          const SizedBox(height: 6),
          const Text('v0: 숨김은 Bridge 내부에서만 처리(원본 삭제/수정 아님).',
              style: TextStyle(color: Colors.white30, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _row(String tag, dynamic e) {
    final start = e.startTime as DateTime;
    final end = e.endTime as DateTime;

    final time = '${_t(start)}-${_t(end)}';
    return Row(
      children: [
        SizedBox(
          width: 20,
          child: Text(tag,
              style: const TextStyle(
                  color: Colors.white70, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.title as String,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('$time · ${e.source}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  String _t(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  Widget _btn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
      ),
    );
  }
}
