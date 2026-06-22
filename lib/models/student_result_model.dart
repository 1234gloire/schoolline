import 'package:cloud_firestore/cloud_firestore.dart';

class SubjectResultEntry {
  final String subjectId;
  final String subjectName;
  final double finalScore; // sur 20
  final double maxScore;   // 20
  final double coefficient;
  final String submissionId;

  const SubjectResultEntry({
    required this.subjectId,
    required this.subjectName,
    required this.finalScore,
    required this.maxScore,
    required this.coefficient,
    required this.submissionId,
  });

  factory SubjectResultEntry.fromMap(Map<String, dynamic> data) {
    return SubjectResultEntry(
      subjectId: data['subjectId'] as String? ?? '',
      subjectName: data['subjectName'] as String? ?? '',
      finalScore: (data['finalScore'] as num?)?.toDouble() ?? 0,
      maxScore: (data['maxScore'] as num?)?.toDouble() ?? 20,
      coefficient: (data['coefficient'] as num?)?.toDouble() ?? 1,
      submissionId: data['submissionId'] as String? ?? '',
    );
  }

  double get points => finalScore * coefficient;
}

class StudentResultModel {
  final String userId;
  final String sessionId;
  final double moyenneGenerale;
  final double totalPoints;
  final double totalCoefficients;
  final bool isAdmis;
  final String mention;
  final List<SubjectResultEntry> subjects;
  final DateTime publishedAt;
  final DateTime lastSubmittedAt;

  const StudentResultModel({
    required this.userId,
    required this.sessionId,
    required this.moyenneGenerale,
    required this.totalPoints,
    required this.totalCoefficients,
    required this.isAdmis,
    required this.mention,
    required this.subjects,
    required this.publishedAt,
    required this.lastSubmittedAt,
  });

  factory StudentResultModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return StudentResultModel(
      userId: data['userId'] as String? ?? doc.id,
      sessionId: data['sessionId'] as String? ?? '',
      moyenneGenerale: (data['moyenneGenerale'] as num?)?.toDouble() ?? 0,
      totalPoints: (data['totalPoints'] as num?)?.toDouble() ?? 0,
      totalCoefficients: (data['totalCoefficients'] as num?)?.toDouble() ?? 1,
      isAdmis: data['isAdmis'] as bool? ?? false,
      mention: data['mention'] as String? ?? '',
      subjects: (data['subjects'] as List<dynamic>? ?? [])
          .map((e) => SubjectResultEntry.fromMap(e as Map<String, dynamic>))
          .toList(),
      publishedAt: (data['publishedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastSubmittedAt:
          (data['lastSubmittedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
