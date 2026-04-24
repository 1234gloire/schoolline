import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_constants.dart';
import '../models/payment_model.dart';

// Paiements de l'élève courant (stream temps réel)
final myPaymentsProvider = StreamProvider.family<List<PaymentModel>, String>((ref, userId) {
  return FirebaseFirestore.instance
      .collection(AppConstants.paymentsCollection)
      .where('userId', isEqualTo: userId)
      .orderBy('submittedAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map(PaymentModel.fromFirestore).toList());
});

// Paiement actif pour une session donnée
final paymentForSessionProvider = StreamProvider.autoDispose.family<
  PaymentModel?,
  ({String userId, String sessionId})
>((ref, params) {
  return FirebaseFirestore.instance
      .collection(AppConstants.paymentsCollection)
      .where('userId', isEqualTo: params.userId)
      .where('sessionId', isEqualTo: params.sessionId)
      .orderBy('submittedAt', descending: true)
      .limit(1)
      .snapshots()
      .map((snap) {
        if (snap.docs.isEmpty) return null;
        return PaymentModel.fromFirestore(snap.docs.first);
      });
});

// Notifier pour soumettre une preuve de paiement
class PaymentNotifier extends StateNotifier<AsyncValue<void>> {
  PaymentNotifier() : super(const AsyncValue.data(null));

  Future<void> submitProof({
    required String sessionId,
    required String proofFileRef,
  }) async {
    state = const AsyncValue.loading();
    try {
      final callable = FirebaseFunctions.instanceFor(region: AppConstants.functionsRegion)
          .httpsCallable('submitPaymentProof');
      await callable.call({
        'sessionId': sessionId,
        'proofFileRef': proofFileRef,
      });
      state = const AsyncValue.data(null);
    } on FirebaseFunctionsException catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  void reset() => state = const AsyncValue.data(null);
}

final paymentNotifierProvider =
    StateNotifierProvider.autoDispose<PaymentNotifier, AsyncValue<void>>(
  (_) => PaymentNotifier(),
);

// Message d'erreur lisible pour les erreurs de paiement
String paymentErrorMessage(Object error) {
  if (error is FirebaseFunctionsException) {
    switch (error.code) {
      case 'already-exists':
        return error.message ?? 'Une demande est déjà en cours pour cette session.';
      case 'not-found':
        return error.message ?? 'Session introuvable ou service indisponible.';
      case 'unauthenticated':
        return 'Session expirée. Reconnecte-toi et réessaie.';
      case 'permission-denied':
        return 'Cette opération n’est pas autorisée pour ton compte.';
      case 'unavailable':
        return 'Service temporairement indisponible. Réessaie dans un instant.';
      default:
        return error.message ?? 'Impossible d’envoyer la preuve pour le moment.';
    }
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'Impossible d’envoyer le fichier pour le moment.';
      case 'unauthorized':
        return 'Non autorisé. Reconnecte-toi et réessaie.';
      case 'object-not-found':
        return 'Fichier introuvable après l\'envoi.';
      case 'unavailable':
        return 'Service temporairement indisponible. Réessaie dans un instant.';
      default:
        return 'Impossible de traiter ce paiement pour le moment.';
    }
  }
  return 'Une erreur inattendue est survenue. Réessaie.';
}
