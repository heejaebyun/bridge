class ExternalEvent {
  final int? id;
  final String source; // DEVICE | GOOGLE
  final String sourceEventId;
  final String calendarId;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final bool isAllDay;
  final String? location;
  final String? description;
  final DateTime createdAt;
  final DateTime? updatedAt;

  ExternalEvent({
    this.id,
    required this.source,
    required this.sourceEventId,
    required this.calendarId,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.isAllDay,
    this.location,
    this.description,
    DateTime? createdAt,
    this.updatedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'source': source,
      'source_event_id': sourceEventId,
      'calendar_id': calendarId,
      'title': title,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'is_all_day': isAllDay ? 1 : 0,
      'location': location,
      'description': description,
      'updated_at': updatedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  static ExternalEvent fromMap(Map<String, dynamic> map) {
    return ExternalEvent(
      id: map['id'] as int?,
      source: map['source'] as String,
      sourceEventId: map['source_event_id'] as String,
      calendarId: map['calendar_id'] as String,
      title: map['title'] as String,
      startTime: DateTime.parse(map['start_time'] as String),
      endTime: DateTime.parse(map['end_time'] as String),
      isAllDay: (map['is_all_day'] as int? ?? 0) == 1,
      location: map['location'] as String?,
      description: map['description'] as String?,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
