import 'external_event.dart';

class CalendarConflict {
  final int? id;
  final String conflictType; // DUPLICATE | TIME_OVERLAP
  final String status; // OPEN | RESOLVED
  final String? resolution; // MERGE | KEEP_BOTH | HIDE_A | HIDE_B
  final DateTime createdAt;
  final DateTime? resolvedAt;

  // References
  final String eventASource;
  final String eventAId;
  final String eventBSource;
  final String eventBId;

  // Optional hydrated
  final ExternalEvent? eventA;
  final ExternalEvent? eventB;

  CalendarConflict({
    this.id,
    required this.conflictType,
    required this.status,
    this.resolution,
    required this.createdAt,
    this.resolvedAt,
    required this.eventASource,
    required this.eventAId,
    required this.eventBSource,
    required this.eventBId,
    this.eventA,
    this.eventB,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'conflict_type': conflictType,
      'status': status,
      'resolution': resolution,
      'created_at': createdAt.toIso8601String(),
      'resolved_at': resolvedAt?.toIso8601String(),
      'event_a_source': eventASource,
      'event_a_id': eventAId,
      'event_b_source': eventBSource,
      'event_b_id': eventBId,
    };
  }

  static CalendarConflict fromMap(Map<String, dynamic> map,
      {ExternalEvent? eventA, ExternalEvent? eventB}) {
    return CalendarConflict(
      id: map['id'] as int?,
      conflictType: map['conflict_type'] as String,
      status: map['status'] as String,
      resolution: map['resolution'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      resolvedAt: map['resolved_at'] != null
          ? DateTime.parse(map['resolved_at'] as String)
          : null,
      eventASource: map['event_a_source'] as String,
      eventAId: map['event_a_id'] as String,
      eventBSource: map['event_b_source'] as String,
      eventBId: map['event_b_id'] as String,
      eventA: eventA,
      eventB: eventB,
    );
  }
}
