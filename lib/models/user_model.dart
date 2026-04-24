import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { student, corrector, admin }

enum StudentClass { terminale, troisieme }

class UserModel {
  final String uid;
  final String displayName;
  final String email;
  final String phone;
  final UserRole role;
  final StudentClass? studentClass;
  final String series;
  final String school;
  final String avatarUrl;
  final DateTime createdAt;
  final List<String> subscriptions; // IDs sessions achetées
  final List<String>
  abandonedSubjectIds; // IDs des épreuves quittées sans soumission
  final bool blocked;

  const UserModel({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.phone,
    required this.role,
    this.studentClass,
    required this.series,
    required this.school,
    this.avatarUrl = '',
    required this.createdAt,
    required this.subscriptions,
    required this.abandonedSubjectIds,
    this.blocked = false,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      displayName: data['displayName'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      role: UserRole.values.firstWhere(
        (r) => r.name == (data['role'] ?? 'student'),
        orElse: () => UserRole.student,
      ),
      studentClass:
          data['class'] != null
              ? StudentClass.values.firstWhere(
                (c) => c.name == data['class'],
                orElse: () => StudentClass.terminale,
              )
              : null,
      series: data['series'] ?? '',
      school: data['school'] ?? '',
      avatarUrl: data['avatarUrl'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      subscriptions: List<String>.from(data['subscriptions'] ?? []),
      abandonedSubjectIds: List<String>.from(data['abandonedSubjectIds'] ?? []),
      blocked: data['blocked'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'displayName': displayName,
      'email': email,
      'phone': phone,
      'role': role.name,
      'class': studentClass?.name,
      'series': series,
      'school': school,
      'avatarUrl': avatarUrl,
      'createdAt': Timestamp.fromDate(createdAt),
      'subscriptions': subscriptions,
      'abandonedSubjectIds': abandonedSubjectIds,
      'blocked': blocked,
    };
  }

  UserModel copyWith({
    String? displayName,
    String? email,
    String? phone,
    UserRole? role,
    StudentClass? studentClass,
    String? series,
    String? school,
    String? avatarUrl,
    List<String>? subscriptions,
    List<String>? abandonedSubjectIds,
    bool? blocked,
  }) {
    return UserModel(
      uid: uid,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      studentClass: studentClass ?? this.studentClass,
      series: series ?? this.series,
      school: school ?? this.school,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt,
      subscriptions: subscriptions ?? this.subscriptions,
      abandonedSubjectIds: abandonedSubjectIds ?? this.abandonedSubjectIds,
      blocked: blocked ?? this.blocked,
    );
  }

  bool get isStudent => role == UserRole.student;
  bool get isCorrector => role == UserRole.corrector;
  bool get isAdmin => role == UserRole.admin;
  bool hasAbandonedSubject(String subjectId) =>
      abandonedSubjectIds.contains(subjectId);

  List<String> get missingRequiredFields {
    final missing = <String>[];

    if (displayName.trim().isEmpty) {
      missing.add('nom complet');
    }
    if (phone.trim().isEmpty) {
      missing.add('téléphone');
    }
    if (school.trim().isEmpty) {
      missing.add('établissement');
    }
    if (studentClass == null) {
      missing.add('classe');
    }
    if (studentClass == StudentClass.terminale && series.trim().isEmpty) {
      missing.add('série');
    }

    return missing;
  }

  bool get isProfileComplete => missingRequiredFields.isEmpty;

  double get profileCompletionRatio {
    final totalRequiredFields = studentClass == StudentClass.terminale ? 5 : 4;
    final completed = totalRequiredFields - missingRequiredFields.length;
    if (totalRequiredFields <= 0) return 1;
    return (completed.clamp(0, totalRequiredFields)) / totalRequiredFields;
  }

  String get classLabel {
    switch (studentClass) {
      case StudentClass.terminale:
        return 'Terminale';
      case StudentClass.troisieme:
        return '3ème';
      case null:
        return 'Classe non renseignée';
    }
  }
}
