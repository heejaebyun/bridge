import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:home_widget/home_widget.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 위젯 초기화
  await HomeWidget.setAppGroupId('group.bridge.app');

  runApp(const BridgeApp());
}

class BridgeApp extends StatelessWidget {
  const BridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bridge',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0F1A),
        primaryColor: const Color(0xFF22D3EE),
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _controller = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isListening = false;
  String _statusText = '무엇을 도와드릴까요?';
  List<Contact> _contacts = [];
  StreamSubscription? _widgetClickSubscription;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _listenToWidgetClicks();
    _updateWidget();
  }

  // 위젯 클릭 이벤트 리스닝
  void _listenToWidgetClicks() {
    _widgetClickSubscription = HomeWidget.widgetClicked.listen((uri) {
      // 위젯에서 앱을 열면 바로 음성 입력 시작
      if (uri != null) {
        Future.delayed(const Duration(milliseconds: 300), () {
          _startListening();
        });
      }
    });
  }

  // 위젯 업데이트
  Future<void> _updateWidget() async {
    await HomeWidget.saveWidgetData<String>('app_name', 'BRIDGE');
    await HomeWidget.saveWidgetData<String>('status', _statusText);
    await HomeWidget.updateWidget(
      name: 'BridgeWidgetProvider',
      androidName: 'BridgeWidgetProvider',
    );
  }

  Future<void> _requestPermissions() async {
    await Permission.contacts.request();
    await Permission.microphone.request();
    await _loadContacts();
  }

  Future<void> _loadContacts() async {
    if (await FlutterContacts.requestPermission()) {
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      setState(() {
        _contacts = contacts;
      });
    }
  }

  Future<void> _startListening() async {
    bool available = await _speech.initialize();
    if (available) {
      setState(() {
        _isListening = true;
        _statusText = '듣고 있어요...';
      });
      _updateWidget();

      _speech.listen(
        onResult: (result) {
          if (result.finalResult) {
            _controller.text = result.recognizedWords;
            _processCommand(result.recognizedWords);
          }
        },
        localeId: 'ko_KR',
      );
    }
  }

  void _stopListening() {
    _speech.stop();
    setState(() {
      _isListening = false;
      _statusText = '무엇을 도와드릴까요?';
    });
    _updateWidget();
  }

  Future<void> _processCommand(String command) async {
    setState(() {
      _statusText = '처리 중...';
    });
    _updateWidget();

    // 카카오톡 패턴
    final kakaoPattern = RegExp(r'(.+?)(?:한테|에게|께)\s*(?:카톡|카카오톡|메시지)');
    final match = kakaoPattern.firstMatch(command);

    if (match != null) {
      final name = match.group(1)?.trim() ?? '';
      await _openKakaoChat(name);
    } else if (command.contains('카톡') || command.contains('카카오톡')) {
      await _launchKakao();
    }
    // 유튜브 뮤직
    else if (command.contains('유튜브 뮤직') || command.contains('유튜브뮤직')) {
      final query = command
          .replaceAll('유튜브 뮤직에서', '')
          .replaceAll('유튜브뮤직에서', '')
          .replaceAll('유튜브 뮤직', '')
          .replaceAll('유튜브뮤직', '')
          .replaceAll('틀어', '')
          .replaceAll('재생', '')
          .replaceAll('줘', '')
          .trim();
      await _launchYoutubeMusic(query);
    }
    // 유튜브
    else if (command.contains('유튜브') || command.contains('유투브')) {
      final query = command
          .replaceAll('유튜브에서', '')
          .replaceAll('유투브에서', '')
          .replaceAll('유튜브', '')
          .replaceAll('유투브', '')
          .replaceAll('검색', '')
          .replaceAll('틀어', '')
          .replaceAll('찾아', '')
          .replaceAll('줘', '')
          .trim();
      await _launchYoutube(query);
    }
    // 스포티파이
    else if (command.contains('스포티파이') || command.contains('스포')) {
      final query = command
          .replaceAll('스포티파이에서', '')
          .replaceAll('스포티파이', '')
          .replaceAll('스포에서', '')
          .replaceAll('스포', '')
          .replaceAll('틀어', '')
          .replaceAll('재생', '')
          .replaceAll('줘', '')
          .trim();
      await _launchSpotify(query);
    }
    // 멜론
    else if (command.contains('멜론')) {
      final query = command
          .replaceAll('멜론에서', '')
          .replaceAll('멜론', '')
          .replaceAll('틀어', '')
          .replaceAll('재생', '')
          .replaceAll('줘', '')
          .trim();
      await _launchMelon(query);
    }
    // 배민
    else if (command.contains('배민') || command.contains('배달의민족')) {
      final query = command
          .replaceAll('배민에서', '')
          .replaceAll('배달의민족에서', '')
          .replaceAll('배민', '')
          .replaceAll('배달의민족', '')
          .replaceAll('시켜', '')
          .replaceAll('검색', '')
          .replaceAll('줘', '')
          .trim();
      await _launchBaemin(query);
    }
    // 토스
    else if (command.contains('토스')) {
      await _launchToss();
    }
    // 네이버
    else if (command.contains('네이버')) {
      final query = command
          .replaceAll('네이버에서', '')
          .replaceAll('네이버', '')
          .replaceAll('검색', '')
          .replaceAll('찾아', '')
          .replaceAll('줘', '')
          .trim();
      await _launchNaver(query);
    }
    // 쿠팡이츠
    else if (command.contains('쿠팡이츠') || command.contains('쿠팡 이츠')) {
      final query = command
          .replaceAll('쿠팡이츠에서', '')
          .replaceAll('쿠팡 이츠에서', '')
          .replaceAll('쿠팡이츠', '')
          .replaceAll('쿠팡 이츠', '')
          .replaceAll('시켜', '')
          .replaceAll('검색', '')
          .replaceAll('줘', '')
          .trim();
      await _launchCoupangEats(query);
    }
    // 쿠팡
    else if (command.contains('쿠팡')) {
      final query = command
          .replaceAll('쿠팡에서', '')
          .replaceAll('쿠팡', '')
          .replaceAll('검색', '')
          .replaceAll('찾아', '')
          .replaceAll('줘', '')
          .trim();
      await _launchCoupang(query);
    } else {
      setState(() {
        _statusText = '카톡, 유튜브, 쿠팡, 네이버, 배민, 토스, 멜론, 스포티파이';
      });
      _updateWidget();
    }
  }

  Future<void> _openKakaoChat(String name) async {
    Contact? found;
    for (var contact in _contacts) {
      if (contact.displayName.contains(name)) {
        found = contact;
        break;
      }
    }

    if (found != null) {
      final Uri kakaoUri = Uri.parse('kakaotalk://launch');

      if (await canLaunchUrl(kakaoUri)) {
        await launchUrl(kakaoUri, mode: LaunchMode.externalApplication);
        setState(() {
          _statusText = '${found!.displayName}님 찾았어요. 카카오톡을 열었어요.';
        });
        _updateWidget();
      } else {
        setState(() {
          _statusText = '카카오톡이 설치되어 있지 않아요.';
        });
        _updateWidget();
      }
    } else {
      setState(() {
        _statusText = '"$name"님을 연락처에서 찾지 못했어요.';
      });
      _updateWidget();
    }
  }

  Future<void> _launchKakao() async {
    final Uri kakaoUri = Uri.parse('kakaotalk://launch');
    if (await canLaunchUrl(kakaoUri)) {
      await launchUrl(kakaoUri, mode: LaunchMode.externalApplication);
      setState(() {
        _statusText = '카카오톡을 열었어요.';
      });
      _updateWidget();
    }
  }

  Future<void> _launchYoutube(String query) async {
    Uri uri;
    if (query.isNotEmpty) {
      uri = Uri.parse(
        'https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}',
      );
    } else {
      uri = Uri.parse('https://www.youtube.com');
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
    setState(() {
      _statusText = query.isNotEmpty ? '유튜브에서 "$query" 검색' : '유튜브 열었어요';
    });
    _updateWidget();
  }

  Future<void> _launchCoupang(String query) async {
    Uri uri;
    if (query.isNotEmpty) {
      uri = Uri.parse('coupang://search?query=${Uri.encodeComponent(query)}');
    } else {
      uri = Uri.parse('coupang://');
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      setState(() {
        _statusText = query.isNotEmpty ? '쿠팡에서 "$query" 검색' : '쿠팡 열었어요';
      });
      _updateWidget();
    } else {
      // 쿠팡 앱 없으면 웹으로
      final webUri = Uri.parse(
        'https://www.coupang.com/np/search?q=${Uri.encodeComponent(query)}',
      );
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launchYoutubeMusic(String query) async {
    Uri uri;
    if (query.isNotEmpty) {
      uri = Uri.parse(
        'https://music.youtube.com/search?q=${Uri.encodeComponent(query)}',
      );
    } else {
      uri = Uri.parse('https://music.youtube.com');
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    setState(() {
      _statusText = query.isNotEmpty ? '유튜브 뮤직에서 "$query" 검색' : '유튜브 뮤직 열었어요';
    });
    _updateWidget();
  }

  Future<void> _launchSpotify(String query) async {
    final appUri = Uri.parse('spotify://search/${Uri.encodeComponent(query)}');

    if (await canLaunchUrl(appUri)) {
      await launchUrl(appUri, mode: LaunchMode.externalApplication);
      setState(() {
        _statusText = query.isNotEmpty ? '스포티파이에서 "$query" 검색' : '스포티파이 열었어요';
      });
      _updateWidget();
    } else {
      setState(() {
        _statusText = '스포티파이 앱이 필요해요';
      });
      _updateWidget();
      // 플레이스토어로 보내기
      final storeUri = Uri.parse(
        'https://play.google.com/store/apps/details?id=com.spotify.music',
      );
      await launchUrl(storeUri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launchMelon(String query) async {
    final appUri = Uri.parse(
      'melonapp://search?query=${Uri.encodeComponent(query)}',
    );

    if (await canLaunchUrl(appUri)) {
      await launchUrl(appUri, mode: LaunchMode.externalApplication);
      setState(() {
        _statusText = query.isNotEmpty ? '멜론에서 "$query" 검색' : '멜론 열었어요';
      });
      _updateWidget();
    } else {
      setState(() {
        _statusText = '멜론 앱이 필요해요';
      });
      _updateWidget();
      final storeUri = Uri.parse(
        'https://play.google.com/store/apps/details?id=com.iloen.melon',
      );
      await launchUrl(storeUri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launchBaemin(String query) async {
    Uri uri;
    if (query.isNotEmpty) {
      uri = Uri.parse(
        'https://www.baemin.com/search?keyword=${Uri.encodeComponent(query)}',
      );
    } else {
      uri = Uri.parse('https://www.baemin.com');
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    setState(() {
      _statusText = query.isNotEmpty ? '배민에서 "$query" 검색' : '배민 열었어요';
    });
    _updateWidget();
  }

  Future<void> _launchToss() async {
    final uri = Uri.parse('https://toss.im');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    setState(() {
      _statusText = '토스 열었어요';
    });
    _updateWidget();
  }

  Future<void> _launchNaver(String query) async {
    Uri uri;
    if (query.isNotEmpty) {
      uri = Uri.parse(
        'https://search.naver.com/search.naver?query=${Uri.encodeComponent(query)}',
      );
    } else {
      uri = Uri.parse('https://www.naver.com');
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    setState(() {
      _statusText = query.isNotEmpty ? '네이버에서 "$query" 검색' : '네이버 열었어요';
    });
    _updateWidget();
  }

  Future<void> _launchCoupangEats(String query) async {
    final appUri = Uri.parse('coupangeats://');

    if (await canLaunchUrl(appUri)) {
      await launchUrl(appUri, mode: LaunchMode.externalApplication);
      setState(() {
        _statusText = '쿠팡이츠 열었어요';
      });
      _updateWidget();
    } else {
      setState(() {
        _statusText = '쿠팡이츠 앱이 필요해요';
      });
      _updateWidget();
      final storeUri = Uri.parse(
        'https://play.google.com/store/apps/details?id=com.coupang.mobile.eats',
      );
      await launchUrl(storeUri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const SizedBox(height: 40),

              const Text(
                'BRIDGE',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF22D3EE),
                  letterSpacing: 8,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                _statusText,
                style: const TextStyle(fontSize: 16, color: Colors.white70),
                textAlign: TextAlign.center,
              ),

              const Spacer(),

              GestureDetector(
                onTapDown: (_) => _startListening(),
                onTapUp: (_) => _stopListening(),
                onTapCancel: () => _stopListening(),
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isListening
                        ? const Color(0xFF22D3EE)
                        : const Color(0xFF1E293B),
                    border: Border.all(
                      color: const Color(0xFF22D3EE),
                      width: 2,
                    ),
                    boxShadow: _isListening
                        ? [
                            BoxShadow(
                              color: const Color(0xFF22D3EE).withOpacity(0.5),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ]
                        : [],
                  ),
                  child: Icon(
                    _isListening ? Icons.mic : Icons.mic_none,
                    size: 48,
                    color: _isListening
                        ? Colors.black
                        : const Color(0xFF22D3EE),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              const Text(
                '길게 눌러서 말하기',
                style: TextStyle(fontSize: 14, color: Colors.white38),
              ),

              const Spacer(),

              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: '또는 여기에 입력...',
                          hintStyle: TextStyle(color: Colors.white38),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                        ),
                        onSubmitted: _processCommand,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: Color(0xFF22D3EE)),
                      onPressed: () => _processCommand(_controller.text),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _widgetClickSubscription?.cancel();
    super.dispose();
  }
}
