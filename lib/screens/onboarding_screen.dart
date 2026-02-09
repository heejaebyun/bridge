/// OnboardingScreen: 첫 실행 경험
///
/// 1. 환영 → 2. 캘린더 임포트 (선택) → 3. 완료
/// 최대한 빨리 Chat으로 보내는 게 목표

import 'package:flutter/material.dart';
import '../services/calendar_import_service.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0; // 0: welcome, 1: import, 2: importing, 3: done
  final CalendarImportService _importService = CalendarImportService();
  List<CalendarAccount> _calendars = [];
  int _importedCount = 0;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _buildStep(),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _buildWelcome();
      case 1:
        return _buildImportChoice();
      case 2:
        return _buildImporting();
      case 3:
        return _buildDone();
      default:
        return _buildWelcome();
    }
  }

  Widget _buildWelcome() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 2),
        // 로고 영역
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF22D3EE).withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF22D3EE).withOpacity(0.3),
            ),
          ),
          child: const Center(
            child: Text('B', style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Color(0xFF22D3EE),
            )),
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          'Bridge',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '말 한마디로 일정 관리',
          style: TextStyle(
            fontSize: 18,
            color: Colors.white54,
          ),
        ),
        const SizedBox(height: 48),
        // 3줄 설명
        _buildFeatureRow('💬', '아무거나 말하면 일정이 돼요'),
        const SizedBox(height: 16),
        _buildFeatureRow('🃏', '저녁에 카드 한 장씩 정리해요'),
        const SizedBox(height: 16),
        _buildFeatureRow('📋', '아침에 오늘 하루가 세팅돼요'),
        const Spacer(flex: 3),
        // 시작 버튼
        GestureDetector(
          onTap: () => setState(() => _step = 1),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF22D3EE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text(
                '시작하기',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureRow(String emoji, String text) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white70,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImportChoice() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 2),
        const Icon(Icons.calendar_today, size: 56, color: Color(0xFF22D3EE)),
        const SizedBox(height: 24),
        const Text(
          '기존 일정 가져올까요?',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '구글 캘린더 등 기기에 등록된\n일정을 한 번에 가져올 수 있어요',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: Colors.white54,
            height: 1.5,
          ),
        ),
        const Spacer(flex: 3),
        // 가져오기 버튼
        GestureDetector(
          onTap: _startImport,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF22D3EE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isLoading)
                  const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.black, strokeWidth: 2),
                  )
                else
                  const Icon(Icons.download, color: Colors.black),
                const SizedBox(width: 8),
                Text(
                  _isLoading ? '가져오는 중...' : '캘린더에서 가져오기',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 건너뛰기
        GestureDetector(
          onTap: () => setState(() => _step = 3),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: const Center(
              child: Text(
                '나중에 할게요',
                style: TextStyle(fontSize: 15, color: Colors.white54),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _startImport() async {
    setState(() => _isLoading = true);

    try {
      _calendars = await _importService.getCalendars();

      if (_calendars.isEmpty) {
        // 캘린더 없거나 권한 거부
        setState(() {
          _isLoading = false;
          _step = 3;
        });
        return;
      }

      // 모든 캘린더에서 이벤트 가져오기
      int total = 0;
      for (final cal in _calendars) {
        final events = await _importService.getEvents(cal.id, days: 30);
        if (events.isNotEmpty) {
          total += await _importService.importEvents(events);
        }
      }

      setState(() {
        _isLoading = false;
        _importedCount = total;
        _step = total > 0 ? 3 : 3;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _step = 3;
      });
    }
  }

  Widget _buildImporting() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Color(0xFF22D3EE)),
          SizedBox(height: 24),
          Text('일정 가져오는 중...', style: TextStyle(color: Colors.white70, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildDone() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 2),
        const Icon(Icons.celebration, size: 64, color: Color(0xFF22D3EE)),
        const SizedBox(height: 24),
        const Text(
          '준비 완료!',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        if (_importedCount > 0) ...[
          Text(
            '$_importedCount개 일정을 가져왔어요 ✨',
            style: const TextStyle(fontSize: 16, color: Color(0xFF22D3EE)),
          ),
          const SizedBox(height: 8),
        ],
        const Text(
          '이제 아무거나 말해보세요',
          style: TextStyle(fontSize: 16, color: Colors.white54),
        ),
        const SizedBox(height: 8),
        // 코인 안내
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.toll, color: Color(0xFFF59E0B)),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'AI 기능 체험용 200원을 드렸어요!',
                  style: TextStyle(color: Color(0xFFF59E0B), fontSize: 14),
                ),
              ),
            ],
          ),
        ),
        const Spacer(flex: 3),
        GestureDetector(
          onTap: widget.onComplete,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF22D3EE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text(
                'Bridge 시작하기 →',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
