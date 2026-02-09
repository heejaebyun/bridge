import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/database_service.dart';
import 'services/card_service.dart';
import 'screens/chat_tab.dart';
import 'screens/timeline_tab.dart';
import 'screens/triage_tab.dart';
import 'screens/calendar_tab.dart';
import 'screens/dashboard_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/smart_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 상태바 투명
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  runApp(const BridgeApp());
}

class BridgeApp extends StatelessWidget {
  const BridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bridge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0F1A),
        primaryColor: const Color(0xFF22D3EE),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF22D3EE),
          secondary: Color(0xFF818CF8),
          surface: Color(0xFF1E293B),
          onPrimary: Colors.black,
          onSecondary: Colors.white,
          onSurface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E293B),
          elevation: 0,
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF1E293B),
          elevation: 0,
        ),
      ),
      home: const BridgeRoot(),
    );
  }
}

/// 앱 루트: 온보딩 여부 확인 후 분기
class BridgeRoot extends StatefulWidget {
  const BridgeRoot({super.key});

  @override
  State<BridgeRoot> createState() => _BridgeRootState();
}

class _BridgeRootState extends State<BridgeRoot> {
  bool _isLoading = true;
  bool _showOnboarding = false;
  final DatabaseService _db = DatabaseService();

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final isFirst = await _db.isFirstLaunch();
    setState(() {
      _showOnboarding = isFirst;
      _isLoading = false;
    });
  }

  void _onOnboardingComplete() async {
    await _db.setFirstLaunchDone();
    setState(() => _showOnboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0F1A),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF22D3EE)),
        ),
      );
    }

    if (_showOnboarding) {
      return OnboardingScreen(onComplete: _onOnboardingComplete);
    }

    return const BridgeHome();
  }
}

class BridgeHome extends StatefulWidget {
  const BridgeHome({super.key});

  @override
  State<BridgeHome> createState() => _BridgeHomeState();
}

class _BridgeHomeState extends State<BridgeHome> {
  int _currentIndex = 0;
  final DatabaseService _db = DatabaseService();
  final CardService _cardService = CardService();

  // Triage 배지 카운트
  int _triageCount = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _checkFirstLaunch();
    await _updateTriageCount();
    // Phase 1: 스마트 알림 초기화
    final notif = SmartNotificationService();
    await notif.initialize();
    await notif.recordAppOpen();
    await notif.scheduleNextDayNotifications();
    await notif.checkPendingNotifications();
  }

  Future<void> _checkFirstLaunch() async {
    final isFirst = await _db.isFirstLaunch();
    if (isFirst) {
      await _db.setFirstLaunchDone();
      // 첫 실행: Chat 탭에서 환영 메시지가 자동으로 나옴
    }
  }

  Future<void> _updateTriageCount() async {
    final cards = await _cardService.getTriageCards();
    if (mounted) {
      setState(() {
        _triageCount = cards.length;
      });
    }
  }

  void _onTabChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
    // 탭 변경 시 Triage 카운트 갱신
    _updateTriageCount();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ChatTab(
            onCardCreated: () => _updateTriageCount(),
          ),
          TimelineTab(),
          TriageTab(
            onTriageChanged: () => _updateTriageCount(),
          ),
          const CalendarTab(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E293B),
          border: Border(
            top: BorderSide(color: Color(0xFF334155), width: 0.5),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.chat_bubble_outline, Icons.chat_bubble, 'Chat'),
                _buildNavItem(1, Icons.timeline_outlined, Icons.timeline, 'Timeline'),
                _buildTriageNavItem(),
                _buildNavItem(3, Icons.calendar_today_outlined, Icons.calendar_today, 'Calendar'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon, String label) {
    final isActive = _currentIndex == index;
    return GestureDetector(
      onTap: () => _onTabChanged(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              size: 24,
              color: isActive
                  ? const Color(0xFF22D3EE)
                  : Colors.white38,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isActive
                    ? const Color(0xFF22D3EE)
                    : Colors.white38,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTriageNavItem() {
    final isActive = _currentIndex == 2;
    return GestureDetector(
      onTap: () => _onTabChanged(2),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isActive ? Icons.style : Icons.style_outlined,
                  size: 24,
                  color: isActive
                      ? const Color(0xFF22D3EE)
                      : Colors.white38,
                ),
                // 배지
                if (_triageCount > 0)
                  Positioned(
                    right: -8,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_triageCount',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Triage',
              style: TextStyle(
                fontSize: 11,
                color: isActive
                    ? const Color(0xFF22D3EE)
                    : Colors.white38,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
