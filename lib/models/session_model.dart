import 'package:cloud_firestore/cloud_firestore.dart';

enum SessionStatus { draft, open, active, closed, resultsPublished }

enum SessionVisibility { public, private }

class SessionModel {
  final String id;
  final String title;
  final String studentClass; // 'terminale' | 'troisieme'
  final List<String> series;
  final SessionStatus status;
  final DateTime startDate;
  final DateTime endDate;
  final double price; // FCFA
  final String createdBy;
  final bool isOnDemand;
  final SessionVisibility visibility;
  final String? requestedBy;

  const SessionModel({
    required this.id,
    required this.title,
    required this.studentClass,
    required this.series,
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.price,
    required this.createdBy,
    this.isOnDemand = false,
    this.visibility = SessionVisibility.public,
    this.requestedBy,
  });

  factory SessionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SessionModel(
      id: doc.id,
      title: data['title'] ?? '',
      studentClass: data['class'] ?? 'terminale',
      series: List<String>.from(data['series'] ?? []),
      status: SessionStatus.values.firstWhere(
        (s) => s.name == (data['status'] ?? 'draft'),
        orElse: () => SessionStatus.draft,
      ),
      startDate: (data['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate: (data['endDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      price: (data['price'] ?? 0).toDouble(),
      createdBy: data['createdBy'] ?? '',
      isOnDemand: data['isOnDemand'] ?? false,
      visibility: SessionVisibility.values.firstWhere(
        (v) => v.name == (data['visibility'] ?? 'public'),
        orElse: () => SessionVisibility.public,
      ),
      requestedBy: data['requestedBy'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'class': studentClass,
      'series': series,
      'status': status.name,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'price': price,
      'createdBy': createdBy,
      'isOnDemand': isOnDemand,
      'visibility': visibility.name,
      if (requestedBy != null) 'requestedBy': requestedBy,
    };
  }

  String get statusLabel {
    switch (status) {
      case SessionStatus.draft: return 'Brouillon';
      case SessionStatus.open: return 'Ouverte';
      case SessionStatus.active: return 'En cours';
      case SessionStatus.closed: return 'Terminée';
      case SessionStatus.resultsPublished: return 'Résultats publiés';
    }
  }

  String get classLabel {
    switch (studentClass) {
      case 'terminale':
        return 'Terminale';
      case 'troisieme':
        return '3ème';
      default:
        return studentClass;
    }
  }

  String get audienceLabel {
    if (studentClass == 'troisieme' || series.isEmpty) {
      return classLabel;
    }
    return '$classLabel • Séries : ${series.join(', ')}';
  }

  bool get isAccessible =>
      status == SessionStatus.open ||
      status == SessionStatus.active ||
      status == SessionStatus.resultsPublished;

  String get visibilityLabel =>
      visibility == SessionVisibility.private ? 'Privée' : 'Publique';
}
