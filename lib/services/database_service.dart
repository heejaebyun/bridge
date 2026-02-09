/// DatabaseService: 로컬 SQLite 데이터베이스
/// 모든 데이터는 기기에만 저장됨 (서버 전송 없음)
library;

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/bridge_card.dart';
import '../models/chat_message.dart';
import '../models/external_event.dart';
import '../models/calendar_conflict.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'bridge_v2.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // external_events
      await db.execute('''
        CREATE TABLE IF NOT EXISTS external_events (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          source TEXT NOT NULL,
          source_event_id TEXT NOT NULL,
          calendar_id TEXT NOT NULL,
          title TEXT NOT NULL,
          start_time TEXT NOT NULL,
          end_time TEXT NOT NULL,
          is_all_day INTEGER NOT NULL DEFAULT 0,
          location TEXT,
          description TEXT,
          updated_at TEXT,
          created_at TEXT NOT NULL,
          UNIQUE(source, source_event_id)
        )
      ''');

      // conflicts (event 기반으로 통일)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS conflicts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          conflict_type TEXT NOT NULL,
          event_a_source TEXT NOT NULL,
          event_a_id TEXT NOT NULL,
          event_b_source TEXT NOT NULL,
          event_b_id TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'OPEN',
          resolution TEXT,
          created_at TEXT NOT NULL,
          resolved_at TEXT
        )
      ''');

      // hidden_events
      await db.execute('''
        CREATE TABLE IF NOT EXISTS hidden_events (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          source TEXT NOT NULL,
          source_event_id TEXT NOT NULL,
          hidden_at TEXT NOT NULL,
          UNIQUE(source, source_event_id)
        )
      ''');

      // indexes
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_external_events_time ON external_events(start_time)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_conflicts_status ON conflicts(status)');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // ===== 카드 테이블 =====
    await db.execute('''
      CREATE TABLE cards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        raw_text TEXT NOT NULL,
        title TEXT NOT NULL,
        start_time TEXT,
        end_time TEXT,
        duration_minutes INTEGER,
        location TEXT,
        person TEXT,
        memo TEXT,
        status INTEGER NOT NULL DEFAULT 0,
        category INTEGER NOT NULL DEFAULT 9,
        energy_level INTEGER NOT NULL DEFAULT 1,
        parse_confidence INTEGER NOT NULL DEFAULT 3,
        is_repeating INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        input_method TEXT DEFAULT 'text',
        corrected_text TEXT,
        triage_action_count INTEGER DEFAULT 0,
        has_date_uncertainty INTEGER DEFAULT 0
      )
    ''');

    // ===== 채팅 메시지 테이블 =====
    await db.execute('''
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        is_user INTEGER NOT NULL,
        timestamp TEXT NOT NULL,
        linked_card_id TEXT,
        type INTEGER DEFAULT 0
      )
    ''');

    // ===== 사용자 행동 로그 (메타데이터 핵심) =====
    await db.execute('''
      CREATE TABLE user_actions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        action_type TEXT NOT NULL,
        card_id INTEGER,
        metadata TEXT
      )
    ''');

    // ===== 코인 =====
    await db.execute('''
      CREATE TABLE coins (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        balance INTEGER NOT NULL DEFAULT 200,
        total_used INTEGER DEFAULT 0,
        total_purchased INTEGER DEFAULT 0,
        last_used_at TEXT,
        last_purchased_at TEXT
      )
    ''');

    // ===== 설정 =====
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    // ===== 외부 캘린더 이벤트 (디바이스/구글) =====
    await db.execute('''
      CREATE TABLE external_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source TEXT NOT NULL,
        source_event_id TEXT NOT NULL,
        calendar_id TEXT NOT NULL,
        title TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        is_all_day INTEGER NOT NULL DEFAULT 0,
        location TEXT,
        description TEXT,
        updated_at TEXT,
        created_at TEXT NOT NULL,
        UNIQUE(source, source_event_id)
      )
    ''');

    // ===== 충돌/중복 해결 인박스 (event 기반) =====
    await db.execute('''
      CREATE TABLE conflicts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conflict_type TEXT NOT NULL,
        event_a_source TEXT NOT NULL,
        event_a_id TEXT NOT NULL,
        event_b_source TEXT NOT NULL,
        event_b_id TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'OPEN',
        resolution TEXT,
        created_at TEXT NOT NULL,
        resolved_at TEXT
      )
    ''');

    // ===== Bridge에서 숨김 처리한 외부 이벤트 =====
    await db.execute('''
      CREATE TABLE hidden_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source TEXT NOT NULL,
        source_event_id TEXT NOT NULL,
        hidden_at TEXT NOT NULL,
        UNIQUE(source, source_event_id)
      )
    ''');

    // ===== 인덱스 (성능) =====
    await db.execute('CREATE INDEX idx_cards_status ON cards(status)');
    await db.execute('CREATE INDEX idx_cards_start_time ON cards(start_time)');
    await db.execute('CREATE INDEX idx_cards_created_at ON cards(created_at)');
    await db
        .execute('CREATE INDEX idx_actions_type ON user_actions(action_type)');
    await db.execute(
        'CREATE INDEX idx_actions_timestamp ON user_actions(timestamp)');
    await db.execute(
        'CREATE INDEX idx_external_events_time ON external_events(start_time)');
    await db.execute('CREATE INDEX idx_conflicts_status ON conflicts(status)');

    // 초기 코인 지급 (200)
    await db.insert('coins', {
      'balance': 200,
      'total_used': 0,
      'total_purchased': 0,
    });
  }

  // =============================================
  // 카드 CRUD
  // =============================================

  Future<int> insertCard(BridgeCard card) async {
    final db = await database;
    final map = card.toMap();
    map.remove('id');
    return db.insert('cards', map);
  }

  Future<void> updateCard(BridgeCard card) async {
    final db = await database;
    await db
        .update('cards', card.toMap(), where: 'id = ?', whereArgs: [card.id]);
  }

  Future<void> updateCardStatus(int cardId, CardStatus status) async {
    final db = await database;
    await db.update(
      'cards',
      {
        'status': status.index,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [cardId],
    );
  }

  Future<BridgeCard?> getCard(int id) async {
    final db = await database;
    final maps = await db.query('cards', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return BridgeCard.fromMap(maps.first);
  }

  Future<List<BridgeCard>> getTriageCards() async {
    final db = await database;
    final maps = await db.query(
      'cards',
      where: 'status IN (?, ?)',
      whereArgs: [CardStatus.newCard.index, CardStatus.deferred.index],
      orderBy: 'created_at ASC',
    );
    return maps.map((m) => BridgeCard.fromMap(m)).toList();
  }

  Future<List<BridgeCard>> getTodayConfirmedCards() async {
    final db = await database;
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final maps = await db.query(
      'cards',
      where: 'status = ? AND start_time >= ? AND start_time < ?',
      whereArgs: [
        CardStatus.confirmed.index,
        startOfDay.toIso8601String(),
        endOfDay.toIso8601String(),
      ],
      orderBy: 'start_time ASC',
    );
    return maps.map((m) => BridgeCard.fromMap(m)).toList();
  }

  Future<List<BridgeCard>> getConfirmedCardsForDate(DateTime date) async {
    final db = await database;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final maps = await db.query(
      'cards',
      where: 'status = ? AND start_time >= ? AND start_time < ?',
      whereArgs: [
        CardStatus.confirmed.index,
        startOfDay.toIso8601String(),
        endOfDay.toIso8601String(),
      ],
      orderBy: 'start_time ASC',
    );
    return maps.map((m) => BridgeCard.fromMap(m)).toList();
  }

  Future<List<BridgeCard>> getConfirmedCardsByDate(DateTime date) async {
    final db = await database;
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));

    final maps = await db.query(
      'cards',
      where:
          'status = ? AND ((start_time >= ? AND start_time < ?) OR start_time IS NULL)',
      whereArgs: [
        CardStatus.confirmed.index,
        start.toIso8601String(),
        end.toIso8601String(),
      ],
      orderBy: 'start_time ASC',
    );
    return maps.map((m) => BridgeCard.fromMap(m)).toList();
  }

  Future<int> getTodayCardCount() async {
    final db = await database;
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM cards WHERE created_at >= ?',
      [startOfDay.toIso8601String()],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  // =============================================
  // 외부 캘린더 이벤트 (DEVICE/GOOGLE)
  // =============================================

  Future<void> upsertExternalEvent(ExternalEvent event) async {
    final db = await database;
    final map = event.toMap();
    map.remove('id');
    await db.insert(
      'external_events',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertExternalEvents(List<ExternalEvent> events) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final e in events) {
        final map = e.toMap();
        map.remove('id');
        await txn.insert(
          'external_events',
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<ExternalEvent>> getExternalEventsForDate(DateTime date) async {
    final db = await database;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final maps = await db.rawQuery('''
      SELECT e.*
      FROM external_events e
      LEFT JOIN hidden_events h
        ON e.source = h.source AND e.source_event_id = h.source_event_id
      WHERE h.id IS NULL
        AND e.start_time >= ? AND e.start_time < ?
      ORDER BY e.start_time ASC
    ''', [startOfDay.toIso8601String(), endOfDay.toIso8601String()]);

    return maps
        .map((m) => ExternalEvent.fromMap(m.cast<String, dynamic>()))
        .toList();
  }

  Future<List<ExternalEvent>> getExternalEventsInRange(
      DateTime start, DateTime end) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT e.*
      FROM external_events e
      LEFT JOIN hidden_events h
        ON e.source = h.source AND e.source_event_id = h.source_event_id
      WHERE h.id IS NULL
        AND e.start_time >= ? AND e.start_time < ?
      ORDER BY e.start_time ASC
    ''', [start.toIso8601String(), end.toIso8601String()]);
    return maps
        .map((m) => ExternalEvent.fromMap(m.cast<String, dynamic>()))
        .toList();
  }

  Future<ExternalEvent?> getExternalEvent(
      String source, String sourceEventId) async {
    final db = await database;
    final maps = await db.query(
      'external_events',
      where: 'source = ? AND source_event_id = ?',
      whereArgs: [source, sourceEventId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return ExternalEvent.fromMap(maps.first.cast<String, dynamic>());
  }

  Future<void> hideExternalEvent(String source, String sourceEventId) async {
    final db = await database;
    await db.insert(
      'hidden_events',
      {
        'source': source,
        'source_event_id': sourceEventId,
        'hidden_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> unhideExternalEvent(String source, String sourceEventId) async {
    final db = await database;
    await db.delete(
      'hidden_events',
      where: 'source = ? AND source_event_id = ?',
      whereArgs: [source, sourceEventId],
    );
  }

  // =============================================
  // 충돌 인박스
  // =============================================

  Future<int> createConflict(CalendarConflict conflict) async {
    final db = await database;
    final map = conflict.toMap();
    map.remove('id');
    return db.insert('conflicts', map);
  }

  Future<void> clearOpenConflicts() async {
    final db = await database;
    await db.delete('conflicts', where: "status = 'OPEN'");
  }

  Future<List<CalendarConflict>> getOpenConflicts() async {
    final db = await database;
    final rows = await db.query(
      'conflicts',
      where: "status = 'OPEN'",
      orderBy: 'created_at ASC',
    );

    final conflicts = <CalendarConflict>[];
    for (final r in rows) {
      final map = r.cast<String, dynamic>();
      final a = await getExternalEvent(
          map['event_a_source'] as String, map['event_a_id'] as String);
      final b = await getExternalEvent(
          map['event_b_source'] as String, map['event_b_id'] as String);
      conflicts.add(CalendarConflict.fromMap(map, eventA: a, eventB: b));
    }
    return conflicts;
  }

  Future<int> getOpenConflictCount() async {
    final db = await database;
    final result = await db.rawQuery(
        "SELECT COUNT(*) as count FROM conflicts WHERE status = 'OPEN'");
    return (result.first['count'] as int?) ?? 0;
  }

  Future<void> resolveConflict(int conflictId, String resolution) async {
    final db = await database;
    await db.update(
      'conflicts',
      {
        'status': 'RESOLVED',
        'resolution': resolution,
        'resolved_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [conflictId],
    );
  }

  // =============================================
  // 채팅 메시지
  // =============================================

  Future<int> insertMessage(ChatMessage message) async {
    final db = await database;
    return db.insert('messages', message.toMap());
  }

  Future<List<ChatMessage>> getRecentMessages(int limit) async {
    final db = await database;
    final maps = await db.query(
      'messages',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return maps.map((m) => ChatMessage.fromMap(m)).toList().reversed.toList();
  }

  Future<List<ChatMessage>> getTodayMessages() async {
    final db = await database;
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    final maps = await db.query(
      'messages',
      where: 'timestamp >= ?',
      whereArgs: [startOfDay.toIso8601String()],
      orderBy: 'timestamp ASC',
    );
    return maps.map((m) => ChatMessage.fromMap(m)).toList();
  }

  // =============================================
  // 사용자 행동 로그 (메타데이터)
  // =============================================

  Future<void> logAction(String actionType,
      {int? cardId, String? metadata}) async {
    final db = await database;
    await db.insert('user_actions', {
      'timestamp': DateTime.now().toIso8601String(),
      'action_type': actionType,
      'card_id': cardId,
      'metadata': metadata,
    });
  }

  Future<Map<String, int>> getActionStats(int days) async {
    final db = await database;
    final since =
        DateTime.now().subtract(Duration(days: days)).toIso8601String();

    final result = await db.rawQuery('''
      SELECT action_type, COUNT(*) as count
      FROM user_actions
      WHERE timestamp >= ?
      GROUP BY action_type
    ''', [since]);

    return {
      for (var r in result) r['action_type'] as String: r['count'] as int
    };
  }

  Future<List<Map<String, dynamic>>> getCardCreationPattern() async {
    final db = await database;
    return db.rawQuery('''
      SELECT 
        CAST(strftime('%w', created_at) AS INTEGER) as weekday,
        CAST(strftime('%H', created_at) AS INTEGER) as hour,
        category,
        COUNT(*) as count
      FROM cards
      GROUP BY weekday, hour, category
      ORDER BY count DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getTriagePattern() async {
    final db = await database;
    return db.rawQuery('''
      SELECT 
        ua.action_type,
        c.category,
        COUNT(*) as count
      FROM user_actions ua
      JOIN cards c ON ua.card_id = c.id
      WHERE ua.action_type IN ('card_confirm', 'card_defer', 'card_delete')
      GROUP BY ua.action_type, c.category
      ORDER BY count DESC
    ''');
  }

  Future<double> getAverageDailyCards(int days) async {
    final db = await database;
    final since =
        DateTime.now().subtract(Duration(days: days)).toIso8601String();

    final result = await db.rawQuery('''
      SELECT COUNT(*) as total FROM cards
      WHERE status = ? AND created_at >= ?
    ''', [CardStatus.confirmed.index, since]);

    final total = (result.first['total'] as int?) ?? 0;
    return total / days;
  }

  // =============================================
  // 코인
  // =============================================

  Future<int> getCoinBalance() async {
    final db = await database;
    final maps = await db.query('coins', limit: 1);
    if (maps.isEmpty) return 0;
    return maps.first['balance'] as int;
  }

  Future<bool> useCoins(int amount) async {
    final db = await database;
    final balance = await getCoinBalance();
    if (balance < amount) return false;

    await db.rawUpdate('''
      UPDATE coins SET 
        balance = balance - ?,
        total_used = total_used + ?,
        last_used_at = ?
      WHERE id = 1
    ''', [amount, amount, DateTime.now().toIso8601String()]);

    await logAction('coin_use', metadata: '{"amount": $amount}');
    return true;
  }

  Future<void> addCoins(int amount) async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE coins SET 
        balance = balance + ?,
        total_purchased = total_purchased + ?,
        last_purchased_at = ?
      WHERE id = 1
    ''', [amount, amount, DateTime.now().toIso8601String()]);

    await logAction('coin_purchase', metadata: '{"amount": $amount}');
  }

  // =============================================
  // 설정
  // =============================================

  Future<String?> getSetting(String key) async {
    final db = await database;
    final maps = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (maps.isEmpty) return null;
    return maps.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> isFirstLaunch() async {
    final value = await getSetting('first_launch_done');
    return value != 'true';
  }

  Future<void> setFirstLaunchDone() async {
    await setSetting('first_launch_done', 'true');
  }

  Future<bool> hasCompletedFirstTriage() async {
    final value = await getSetting('first_triage_done');
    return value == 'true';
  }

  Future<void> setFirstTriageDone() async {
    await setSetting('first_triage_done', 'true');
  }
}
