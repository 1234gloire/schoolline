import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_constants.dart';

// Notifier pour envoyer une demande de session à la demande
class OnDemandSessionNotifier extends StateNotifier<AsyncValue<String?>> {
  OnDemandSessionNotifier() : super(const AsyncValue.data(null));

  Future<String> requestSession({
    required DateTime startDate,
    required DateTime endDate,
    required bool isPublic,
  }) async {
    state = const AsyncValue.loading();
    try {
      final callable = FirebaseFunctions.instanceFor(region: AppConstants.functionsRegion)
          .httpsCallable('requestOnDemandSession');
      final result = await callable.call({
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'visibility': isPublic ? 'public' : 'private',
      });
      final sessionId = result.data['sessionId'] as String;
      state = AsyncValue.data(sessionId);
      return sessionId;
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

final onDemandSessionNotifierProvider =
    StateNotifierProvider.autoDispose<OnDemandSessionNotifier, AsyncValue<String?>>(
  (_) => OnDemandSessionNotifier(),
);

// Message d'erreur lisible pour les erreurs de demande de session
String onDemandSessionErrorMessage(Object error) {
  if (error is FirebaseFunctionsException) {
    switch (error.code) {
      case 'failed-precondition':
        return error.message ?? 'Conditions non remplies pour cette demande.';
      case 'already-exists':
        return error.message ?? 'Tu as déjà une session à la demande en attente ou active.';
      case 'invalid-argument':
        return error.message ?? 'Dates invalides.';
      case 'permission-denied':
        return 'Cette opération n’est pas autorisée pour ton compte.';
      case 'unauthenticated':
        return 'Session expirée. Reconnecte-toi et réessaie.';
      case 'unavailable':
        return 'Service temporairement indisponible. Réessaie dans un instant.';
      default:
        return error.message ?? 'Impossible d’envoyer la demande pour le moment.';
    }
  }
  return 'Une erreur inattendue est survenue. Réessaie.';
}
