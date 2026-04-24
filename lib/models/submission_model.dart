import 'package:cloud_firestore/cloud_firestore.dart';

enum SubmissionStatus {
  submitted,
  ocrDone,
  aiReviewed,
  pendingHuman,
  humanReviewed,
  published,
  rejected,
  error,
}

class SubmissionModel {
  final String id;
  final String userId;
  final String sessionId;
  final String subjectId;
  final String subjectName;
  final DateTime submittedAt;
  final String fileRef;
  final String ocrText;
  final SubmissionStatus status;
  final double? aiScore;
  final double? aiConfidence;
  final Map<String, double> aiDetails;
  final String? aiFeedback;
  final List<String> aiStrengths;
  final List<String> aiImprovements;
  final double? finalScore;
  final String? correctorId;
  final String? correctorNotes;
  final String? errorReason;
  final DateTime? ocrCompletedAt;
  final DateTime? aiReviewedAt;
  final DateTime? humanReviewedAt;
  final DateTime? publishedAt;
  final DateTime? statusUpdatedAt;

  const SubmissionModel({
    required this.id,
    required this.userId,
    required this.sessionId,
    required this.subjectId,
    required this.subjectName,
    required this.submittedAt,
    required this.fileRef,
    required this.ocrText,
    required this.status,
    this.aiScore,
    this.aiConfidence,
    required this.aiDetails,
    this.aiFeedback,
    required this.aiStrengths,
    required this.aiImprovements,
    this.finalScore,
    this.correctorId,
    this.correctorNotes,
    this.errorReason,
    this.ocrCompletedAt,
    this.aiReviewedAt,
    this.humanReviewedAt,
    this.publishedAt,
    this.statusUpdatedAt,
  });

  factory SubmissionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    DateTime? readTimestamp(String key) {
      return (data[key] as Timestamp?)?.toDate();
    }

    return SubmissionModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      sessionId: data['sessionId'] ?? '',
      subjectId: data['subjectId'] ?? '',
      subjectName: data['subjectName'] ?? '',
      submittedAt:
          (data['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      fileRef: data['fileRef'] ?? '',
      ocrText: data['ocrText'] ?? '',
      status: SubmissionStatus.values.firstWhere(
        (s) => s.name == (data['status'] ?? 'submitted'),
        orElse: () => SubmissionStatus.submitted,
      ),
      aiScore: (data['aiScore'] as num?)?.toDouble(),
      aiConfidence: (data['aiConfidence'] as num?)?.toDouble(),
      aiDetails: Map<String, double>.from(
        (data['aiDetails'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        ),
      ),
      aiFeedback: data['aiFeedback'],
      aiStrengths: List<String>.from(data['aiStrengths'] ?? []),
      aiImprovements: List<String>.from(data['aiImprovements'] ?? []),
      finalScore: (data['finalScore'] as num?)?.toDouble(),
      correctorId: data['correctorId'],
      correctorNotes: data['correctorNotes'],
      errorReason: data['errorReason'],
      ocrCompletedAt: readTimestamp('ocrCompletedAt'),
      aiReviewedAt: readTimestamp('aiReviewedAt'),
      humanReviewedAt: readTimestamp('humanReviewedAt'),
      publishedAt: readTimestamp('publishedAt'),
      statusUpdatedAt: readTimestamp('statusUpdatedAt'),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'sessionId': sessionId,
      'subjectId': subjectId,
      'subjectName': subjectName,
      'submittedAt': Timestamp.fromDate(submittedAt),
      'fileRef': fileRef,
      'ocrText': ocrText,
      'status': status.name,
      'aiScore': aiScore,
      'aiConfidence': aiConfidence,
      'aiDetails': aiDetails,
      'aiFeedback': aiFeedback,
      'aiStrengths': aiStrengths,
      'aiImprovements': aiImprovements,
      'finalScore': finalScore,
      'correctorId': correctorId,
      'correctorNotes': correctorNotes,
      'errorReason': errorReason,
      'ocrCompletedAt':
          ocrCompletedAt == null ? null : Timestamp.fromDate(ocrCompletedAt!),
      'aiReviewedAt':
          aiReviewedAt == null ? null : Timestamp.fromDate(aiReviewedAt!),
      'humanReviewedAt':
          humanReviewedAt == null ? null : Timestamp.fromDate(humanReviewedAt!),
      'publishedAt':
          publishedAt == null ? null : Timestamp.fromDate(publishedAt!),
      'statusUpdatedAt':
          statusUpdatedAt == null ? null : Timestamp.fromDate(statusUpdatedAt!),
    };
  }

  String get statusLabel {
    switch (status) {
      case SubmissionStatus.submitted:
        return 'Soumise';
      case SubmissionStatus.ocrDone:
        return 'OCR terminé';
      case SubmissionStatus.aiReviewed:
        return 'Évaluée par IA';
      case SubmissionStatus.pendingHuman:
        return 'En attente correcteur';
      case SubmissionStatus.humanReviewed:
        return 'Corrigée';
      case SubmissionStatus.published:
        return 'Note publiée';
      case SubmissionStatus.rejected:
        return 'Copie rejetée';
      case SubmissionStatus.error:
        return 'Traitement en erreur';
    }
  }

  bool get isPublished => status == SubmissionStatus.published;
  bool get isCorrecting =>
      status == SubmissionStatus.submitted ||
      status == SubmissionStatus.ocrDone ||
      status == SubmissionStatus.aiReviewed ||
      status == SubmissionStatus.pendingHuman ||
      status == SubmissionStatus.humanReviewed;
  bool get shouldShowStudentErrorReason =>
      (status == SubmissionStatus.rejected ||
          status == SubmissionStatus.error) &&
      errorReasonLabel.isNotEmpty;

  bool get canAccessResultDetail => isPublished;

  double? get displayScore => finalScore ?? aiScore;
  double? get studentVisibleScore => isPublished ? displayScore : null;

  DateTime? get workflowUpdatedAt =>
      publishedAt ??
      humanReviewedAt ??
      aiReviewedAt ??
      ocrCompletedAt ??
      statusUpdatedAt ??
      submittedAt;

  String get workflowDescription {
    switch (status) {
      case SubmissionStatus.submitted:
      case SubmissionStatus.ocrDone:
      case SubmissionStatus.aiReviewed:
        return 'Ta copie a bien été reçue. Elle est en cours de traitement, patiente quelques instants.';
      case SubmissionStatus.pendingHuman:
      case SubmissionStatus.humanReviewed:
        return 'Ta copie est entre les mains du correcteur. La note sera publiée dès que la correction sera terminée.';
      case SubmissionStatus.published:
        return 'La correction est terminée. Tu peux consulter ta note et les remarques du correcteur.';
      case SubmissionStatus.rejected:
        return 'Ta copie n\'a pas pu être traitée. ${errorReasonLabel.isNotEmpty ? errorReasonLabel : 'Contacte le support pour plus d\'informations.'}';
      case SubmissionStatus.error:
        return 'Un problème est survenu lors du traitement de ta copie. ${errorReasonLabel.isNotEmpty ? errorReasonLabel : 'Contacte le support pour qu\'il relance le traitement.'}';
    }
  }

  String get studentResultLabel {
    switch (status) {
      case SubmissionStatus.submitted:
      case SubmissionStatus.ocrDone:
      case SubmissionStatus.aiReviewed:
        return 'Traitement en cours…';
      case SubmissionStatus.pendingHuman:
      case SubmissionStatus.humanReviewed:
        return 'Correction en cours…';
      case SubmissionStatus.published:
        return 'Résultat disponible';
      case SubmissionStatus.rejected:
        return 'Copie rejetée';
      case SubmissionStatus.error:
        return 'Problème de traitement';
    }
  }

  String get errorReasonLabel {
    final rawReason = (errorReason ?? '').trim();
    if (rawReason.isEmpty) {
      return '';
    }

    switch (rawReason) {
      case 'subject_not_found':
        return 'Le sujet associé est introuvable.';
      case 'out_of_time_window':
        return 'La copie a été soumise hors de la fenêtre autorisée.';
      case 'duplicate_submission':
        return 'Une autre copie existe déjà pour cette matière.';
      case 'file_not_found':
        return 'Le fichier de la copie est introuvable.';
    }

    final normalizedReason = rawReason.toLowerCase();

    if (normalizedReason.contains('cloud vision api') ||
        normalizedReason.contains('vision api has not been used') ||
        normalizedReason.contains('service disabled') ||
        normalizedReason.contains('permission_denied') ||
        normalizedReason.contains('billing')) {
      return 'Le service d’analyse automatique est temporairement indisponible.';
    }

    if (normalizedReason.contains('object-not-found') ||
        normalizedReason.contains('file not found')) {
      return 'Le fichier de la copie est introuvable.';
    }

    if (normalizedReason.contains('deadline exceeded') ||
        normalizedReason.contains('timeout')) {
      return 'Le traitement a pris trop de temps.';
    }

    if (normalizedReason.contains('unauthenticated') ||
        normalizedReason.contains('not authenticated')) {
      return 'Une vérification d’accès a échoué pendant le traitement.';
    }

    if (normalizedReason.contains('internal')) {
      return 'Une erreur interne est survenue pendant le traitement.';
    }

    return 'Le traitement automatique de la copie a rencontré un problème.';
  }

  String get mention {
    final s = studentVisibleScore;
    if (s == null) return '';
    if (s >= 16) return 'Très Bien';
    if (s >= 14) return 'Bien';
    if (s >= 12) return 'Assez Bien';
    if (s >= 10) return 'Passable';
    return 'Insuffisant';
  }
}
