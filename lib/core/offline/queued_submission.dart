import 'dart:convert';

class QueuedSubmission {
  final String id;
  final String sessionId;
  final String subjectId;
  final String subjectName;
  final List<String> pagePaths;
  final DateTime queuedAt;
  final int retryCount;

  const QueuedSubmission({
    required this.id,
    required this.sessionId,
    required this.subjectId,
    required this.subjectName,
    required this.pagePaths,
    required this.queuedAt,
    this.retryCount = 0,
  });

  QueuedSubmission copyWith({int? retryCount}) => QueuedSubmission(
    id: id,
    sessionId: sessionId,
    subjectId: subjectId,
    subjectName: subjectName,
    pagePaths: pagePaths,
    queuedAt: queuedAt,
    retryCount: retryCount ?? this.retryCount,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'subjectId': subjectId,
    'subjectName': subjectName,
    'pagePaths': pagePaths,
    'queuedAt': queuedAt.toIso8601String(),
    'retryCount': retryCount,
  };

  factory QueuedSubmission.fromJson(Map<String, dynamic> json) =>
      QueuedSubmission(
        id: json['id'] as String,
        sessionId: json['sessionId'] as String,
        subjectId: json['subjectId'] as String,
        subjectName: json['subjectName'] as String,
        pagePaths: List<String>.from(json['pagePaths'] as List),
        queuedAt: DateTime.parse(json['queuedAt'] as String),
        retryCount: json['retryCount'] as int? ?? 0,
      );

  String toJsonString() => jsonEncode(toJson());

  factory QueuedSubmission.fromJsonString(String value) =>
      QueuedSubmission.fromJson(jsonDecode(value) as Map<String, dynamic>);
}
