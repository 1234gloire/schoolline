import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_model.dart';

/// Annonce diffusée par l'administration (collection `announcements`).
class AnnouncementModel {
  final String id;
  final String title;
  final String body;

  /// 'all' | 'troisieme' | 'terminale'
  final String audience;

  /// Série ciblée (A, C, D…) si audience == 'terminale', sinon null.
  final String? series;

  final String sentByName;
  final DateTime? createdAt;

  const AnnouncementModel({
    required this.id,
    required this.title,
    required this.body,
    required this.audience,
    required this.series,
    required this.sentByName,
    required this.createdAt,
  });

  factory AnnouncementModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};
    final created = data['createdAt'];
    return AnnouncementModel(
      id: doc.id,
      title: (data['title'] ?? '') as String,
      body: (data['body'] ?? '') as String,
      audience: (data['audience'] ?? 'all') as String,
      series: data['series'] as String?,
      sentByName: (data['sentByName'] ?? '') as String,
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }

  /// L'annonce concerne-t-elle cet élève (selon classe + série) ?
  bool matchesStudent(UserModel user) {
    switch (audience) {
      case 'troisieme':
        return user.studentClass == StudentClass.troisieme;
      case 'terminale':
        if (user.studentClass != StudentClass.terminale) return false;
        final s = series?.trim().toUpperCase() ?? '';
        if (s.isEmpty) return true;
        return user.series.trim().toUpperCase() == s;
      case 'all':
      default:
        return true;
    }
  }
}
