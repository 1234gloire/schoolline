import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/session_model.dart';
import '../models/payment_model.dart';
import '../models/subject_model.dart';
import '../models/submission_model.dart';
import '../models/user_model.dart';
import '../models/student_result_model.dart';
import '../core/constants/app_constants.dart';
import 'auth_provider.dart';

// ─── Sessions actives uniquement (open + active) — pour le carousel dashboard ───
final activeSessionsProvider = StreamProvider<List<SessionModel>>((ref) {
  final currentUser = ref.watch(currentUserProvider);
  if (currentUser == null) {
    return Stream.value(const <SessionModel>[]);
  }

  return FirebaseFirestore.instance
      .collection(AppConstants.sessionsCollection)
      .where('status', whereIn: ['open', 'active'])
      .orderBy('startDate', descending: true)
      .snapshots()
      .map(
        (snap) =>
            snap.docs
                .map(SessionModel.fromFirestore)
                .where((session) => sessionMatchesStudent(session, currentUser))
                .toList(),
      );
});

// ─── Sessions historique (résultats publiés) — pour la section Historique du profil ───
final historicSessionsProvider = StreamProvider<List<SessionModel>>((ref) {
  final currentUser = ref.watch(currentUserProvider);
  if (currentUser == null) {
    return Stream.value(const <SessionModel>[]);
  }

  // Utilise startDate (même index composite que sessionsProvider — évite un index manquant)
  return FirebaseFirestore.instance
      .collection(AppConstants.sessionsCollection)
      .where('status', isEqualTo: 'resultsPublished')
      .orderBy('startDate', descending: true)
      .snapshots()
      .map(
        (snap) =>
            snap.docs
                .map(SessionModel.fromFirestore)
                .where((session) => sessionMatchesStudent(session, currentUser))
                .toList(),
      );
});

// ─── Sessions disponibles (toutes : open, active, closed, resultsPublished) ───
final sessionsProvider = StreamProvider<List<SessionModel>>((ref) {
  final currentUser = ref.watch(currentUserProvider);
  if (currentUser == null) {
    return Stream.value(const <SessionModel>[]);
  }

  return FirebaseFirestore.instance
      .collection(AppConstants.sessionsCollection)
      .where(
        'status',
        whereIn: ['open', 'active', 'closed', 'resultsPublished'],
      )
      .orderBy('startDate', descending: true)
      .snapshots()
      .map(
        (snap) =>
            snap.docs
                .map(SessionModel.fromFirestore)
                .where((session) => sessionMatchesStudent(session, currentUser))
                .toList(),
      );
});

final sessionByIdProvider = FutureProvider.family<SessionModel?, String>((
  ref,
  sessionId,
) async {
  final doc =
      await FirebaseFirestore.instance
          .collection(AppConstants.sessionsCollection)
          .doc(sessionId)
          .get();

  if (!doc.exists) return null;
  return SessionModel.fromFirestore(doc);
});

// ─── Matières d'une session ───
final subjectsProvider = StreamProvider.family<List<SubjectModel>, String>((
  ref,
  sessionId,
) {
  final currentUser = ref.watch(currentUserProvider);
  if (currentUser == null) {
    return Stream.value(const <SubjectModel>[]);
  }

  return FirebaseFirestore.instance
      .collection(AppConstants.sessionsCollection)
      .doc(sessionId)
      .collection(AppConstants.subjectsSubcollection)
      .orderBy('startTime')
      .snapshots()
      .map(
        (snap) =>
            snap.docs
                .map((doc) => SubjectModel.fromFirestore(doc, sessionId))
                .where((subject) => subjectMatchesStudent(subject, currentUser))
                .toList(),
      );
});

final subjectByIdProvider = FutureProvider.family<
  SubjectModel?,
  ({String sessionId, String subjectId})
>((
  ref,
  params,
) async {
  final subjectDoc =
      await FirebaseFirestore.instance
          .collection(AppConstants.sessionsCollection)
          .doc(params.sessionId)
          .collection(AppConstants.subjectsSubcollection)
          .doc(params.subjectId)
          .get();

  if (!subjectDoc.exists) return null;
  return SubjectModel.fromFirestore(subjectDoc, params.sessionId);
});

// ─── Soumissions de l'élève ───
final mySubmissionsProvider =
    StreamProvider.family<List<SubmissionModel>, String>((ref, userId) {
      return FirebaseFirestore.instance
          .collection(AppConstants.submissionsCollection)
          .where('userId', isEqualTo: userId)
          .orderBy('submittedAt', descending: true)
          .snapshots()
          .map((snap) => snap.docs.map(SubmissionModel.fromFirestore).toList());
    });

// ─── Soumission d'une épreuve spécifique ───
final submissionForSubjectProvider = StreamProvider.autoDispose.family<
  SubmissionModel?,
  ({String userId, String subjectId})
>((ref, params) {
  return FirebaseFirestore.instance
      .collection(AppConstants.submissionsCollection)
      .where('userId', isEqualTo: params.userId)
      .where('subjectId', isEqualTo: params.subjectId)
      .snapshots()
      .map((snap) {
        if (snap.docs.isEmpty) return null;
        final submissions =
            snap.docs.map(SubmissionModel.fromFirestore).toList()
              ..sort(
                (a, b) => b.workflowUpdatedAt!.compareTo(a.workflowUpdatedAt!),
              );
        return submissions.first;
      });
});

final submissionByIdProvider = FutureProvider.family<
  SubmissionModel?,
  ({String userId, String submissionId})
>((ref, params) async {
  final doc =
      await FirebaseFirestore.instance
          .collection(AppConstants.submissionsCollection)
          .doc(params.submissionId)
          .get();
  if (!doc.exists) return null;

  final submission = SubmissionModel.fromFirestore(doc);
  if (submission.userId != params.userId) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'Accès refusé à cette copie.',
    );
  }

  return submission;
});

// ─── Classement d'un élève dans une session ───
final studentRankingProvider = FutureProvider.autoDispose.family<
  ({int rank, int total})?,
  ({String sessionId, String userId})
>((ref, params) async {
  final snap = await FirebaseFirestore.instance
      .collection(AppConstants.sessionsCollection)
      .doc(params.sessionId)
      .collection(AppConstants.studentResultsSubcollection)
      .get();

  if (snap.docs.isEmpty) return null;

  final sorted = snap.docs.map(StudentResultModel.fromFirestore).toList()
    ..sort((a, b) {
      final cmp = b.moyenneGenerale.compareTo(a.moyenneGenerale);
      return cmp != 0 ? cmp : a.lastSubmittedAt.compareTo(b.lastSubmittedAt);
    });

  final total = sorted.length;
  final rank = sorted.indexWhere((r) => r.userId == params.userId) + 1;
  if (rank == 0) return null;
  return (rank: rank, total: total);
});

// ─── Classement complet d'une session (tous les participants triés) ───
final fullRankingProvider = StreamProvider.autoDispose.family<
  List<({int rank, String userId, String displayName, double moyenneGenerale})>,
  String
>((ref, sessionId) {
  return FirebaseFirestore.instance
      .collection(AppConstants.sessionsCollection)
      .doc(sessionId)
      .collection(AppConstants.studentResultsSubcollection)
      .snapshots()
      .asyncMap((snap) async {
        final results = snap.docs.map(StudentResultModel.fromFirestore).toList()
          ..sort((a, b) {
            final cmp = b.moyenneGenerale.compareTo(a.moyenneGenerale);
            return cmp != 0 ? cmp : a.lastSubmittedAt.compareTo(b.lastSubmittedAt);
          });

        final userDocs = await Future.wait(
          results.map(
            (r) => FirebaseFirestore.instance
                .collection(AppConstants.usersCollection)
                .doc(r.userId)
                .get(),
          ),
        );
        final displayNames = {
          for (final doc in userDocs)
            doc.id: (doc.data()?['displayName'] as String?) ?? 'Élève',
        };

        return List.generate(results.length, (i) {
          final r = results[i];
          return (
            rank: i + 1,
            userId: r.userId,
            displayName: displayNames[r.userId] ?? 'Élève',
            moyenneGenerale: r.moyenneGenerale,
          );
        });
      });
});

// ─── Bulletin de résultats d'un élève pour une session ───
final studentResultProvider = StreamProvider.autoDispose.family<
  StudentResultModel?,
  ({String sessionId, String userId})
>((ref, params) {
  return FirebaseFirestore.instance
      .collection(AppConstants.sessionsCollection)
      .doc(params.sessionId)
      .collection(AppConstants.studentResultsSubcollection)
      .doc(params.userId)
      .snapshots()
      .map((snap) => snap.exists ? StudentResultModel.fromFirestore(snap) : null);
});

// ─── Tous les bulletins publiés de l'élève (collectionGroup) ───────────────
final myStudentResultsProvider =
    StreamProvider.autoDispose.family<List<StudentResultModel>, String>((
      ref,
      userId,
    ) {
      return FirebaseFirestore.instance
          .collectionGroup(AppConstants.studentResultsSubcollection)
          .where('userId', isEqualTo: userId)
          .snapshots()
          .map(
            (snap) => snap.docs
                .map(StudentResultModel.fromFirestore)
                .toList()
              ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt)),
          );
    });

// ─── Soumission Notifier (pour upload) ───
class SubmissionNotifier extends StateNotifier<AsyncValue<SubmissionModel?>> {
  SubmissionNotifier() : super(const AsyncValue.data(null));

  Future<SubmissionModel?> _findExistingSubmission({
    required String userId,
    required String subjectId,
  }) async {
    final snap =
        await FirebaseFirestore.instance
            .collection(AppConstants.submissionsCollection)
            .where('userId', isEqualTo: userId)
            .where('subjectId', isEqualTo: subjectId)
            .limit(1)
            .get();

    if (snap.docs.isEmpty) return null;
    return SubmissionModel.fromFirestore(snap.docs.first);
  }

  Future<void> submitCopy({
    required String userId,
    required String sessionId,
    required String subjectId,
    required String subjectName,
    required String fileRef,
  }) async {
    state = const AsyncValue.loading();
    try {
      final existingSubmission = await _findExistingSubmission(
        userId: userId,
        subjectId: subjectId,
      );
      if (existingSubmission != null) {
        state = AsyncValue.data(existingSubmission);
        throw DuplicateSubmissionException(existingSubmission);
      }

      final submittedAt = DateTime.now();

      // Utiliser FieldValue.serverTimestamp() pour éviter la fraude d'horloge
      final data = {
        'userId': userId,
        'sessionId': sessionId,
        'subjectId': subjectId,
        'subjectName': subjectName,
        'submittedAt': FieldValue.serverTimestamp(),
        'fileRef': fileRef,
        'ocrText': '',
        'status': SubmissionStatus.submitted.name,
        'aiDetails': {},
        'aiStrengths': [],
        'aiImprovements': [],
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      };

      final docRef = await FirebaseFirestore.instance
          .collection(AppConstants.submissionsCollection)
          .add(data);

      final created = SubmissionModel(
        id: docRef.id,
        userId: userId,
        sessionId: sessionId,
        subjectId: subjectId,
        subjectName: subjectName,
        submittedAt: submittedAt,
        fileRef: fileRef,
        ocrText: '',
        status: SubmissionStatus.submitted,
        aiDetails: {},
        aiStrengths: [],
        aiImprovements: [],
        statusUpdatedAt: submittedAt,
      );

      state = AsyncValue.data(created);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  void reset() => state = const AsyncValue.data(null);
}

final submissionNotifierProvider =
    StateNotifierProvider<SubmissionNotifier, AsyncValue<SubmissionModel?>>((
      ref,
    ) {
      return SubmissionNotifier();
    });

class DuplicateSubmissionException implements Exception {
  final SubmissionModel existingSubmission;

  const DuplicateSubmissionException(this.existingSubmission);

  @override
  String toString() => 'Une copie a déjà été soumise pour cette matière.';
}

String submissionDataErrorMessage(Object error) {
  if (error is DuplicateSubmissionException) {
    return 'Une copie existe déjà pour cette matière.';
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'Ces informations ne sont pas accessibles pour le moment.';
      case 'unavailable':
        return 'Service temporairement indisponible. Réessaie dans un instant.';
      case 'failed-precondition':
        return 'Les données ne sont pas encore prêtes. Réessaie dans un instant.';
      default:
        return 'Impossible de charger les résultats pour le moment.';
    }
  }
  return 'Impossible de charger les résultats pour le moment.';
}

String firestoreDataErrorMessage(
  Object error, {
  String fallback = 'Impossible de charger les données pour le moment.',
}) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'Ces données ne sont pas accessibles pour le moment.';
      case 'failed-precondition':
        return 'Les données demandées ne sont pas encore prêtes.';
      case 'unavailable':
        return 'Service temporairement indisponible. Réessaie dans un instant.';
      default:
        return fallback;
    }
  }

  return fallback;
}

bool sessionMatchesStudent(SessionModel session, UserModel user) {
  final studentClass = user.studentClass?.name ?? 'terminale';
  if (session.studentClass != studentClass) {
    return false;
  }

  // Sessions à la demande privées : visibles uniquement par leur demandeur.
  if (session.visibility == SessionVisibility.private &&
      session.requestedBy != user.uid) {
    return false;
  }

  if (studentClass == 'troisieme') {
    return true;
  }

  final studentSeries = user.series.trim().toUpperCase();
  if (studentSeries.isEmpty) {
    return false;
  }

  final sessionSeries =
      session.series.map((series) => series.trim().toUpperCase()).toList();
  return sessionSeries.isEmpty || sessionSeries.contains(studentSeries);
}

bool subjectMatchesStudent(SubjectModel subject, UserModel user) {
  final studentClass = user.studentClass?.name ?? 'terminale';
  if (studentClass == 'troisieme') {
    return true;
  }

  final studentSeries = user.series.trim().toUpperCase();
  if (studentSeries.isEmpty) {
    return false;
  }

  final subjectSeries =
      subject.series.map((series) => series.trim().toUpperCase()).toList();
  return subjectSeries.isEmpty || subjectSeries.contains(studentSeries);
}

bool studentHasSessionAccess({
  required SessionModel session,
  required UserModel user,
  PaymentModel? payment,
}) {
  if (session.price <= 0) {
    return true;
  }

  if (user.subscriptions.contains(session.id)) {
    return true;
  }

  return payment?.isApproved ?? false;
}
