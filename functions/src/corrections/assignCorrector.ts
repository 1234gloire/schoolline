import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { logger } from 'firebase-functions/v2';
import {
  collections,
  decrementCorrectorLoad,
  getAvailableCorrector,
  incrementCorrectorLoad,
} from '../lib/firestore';

interface AssignCorrectorPayload {
  submissionId: string;
  correctorId?: string;
}

export const assignCorrector = onCall<AssignCorrectorPayload>({ invoker: 'public' }, async (request) => {
  try {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Authentification requise.');
    }

    const callerSnap = await collections.user(request.auth.uid).get();
    if (callerSnap.data()?.['role'] !== 'admin') {
      throw new HttpsError('permission-denied', 'Réservé aux admins.');
    }

    const { submissionId, correctorId: manualId } = request.data;
    if (!submissionId) throw new HttpsError('invalid-argument', 'submissionId requis.');

    const submissionRef = collections.submission(submissionId);
    const submissionSnap = await submissionRef.get();
    if (!submissionSnap.exists) throw new HttpsError('not-found', 'Soumission introuvable.');

    const submission = submissionSnap.data()!;
    const allowedStatuses = ['aiReviewed', 'pendingHuman'];
    if (!allowedStatuses.includes(submission['status'])) {
      throw new HttpsError(
        'failed-precondition',
        `Affectation impossible au statut: ${submission['status']}`
      );
    }

    const correctorId = manualId ?? (await getAvailableCorrector());
    if (!correctorId) {
      throw new HttpsError('failed-precondition', 'Aucun correcteur disponible.');
    }

    const correctorSnap = await collections.user(correctorId).get();
    if (!correctorSnap.exists || correctorSnap.data()?.['role'] !== 'corrector') {
      throw new HttpsError('failed-precondition', 'Correcteur invalide.');
    }

    const previousCorrectorId = submission['correctorId'] as string | undefined;

    await submissionRef.update({
      correctorId,
      status: 'pendingHuman',
      statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    if (previousCorrectorId && previousCorrectorId !== correctorId) {
      try {
        await decrementCorrectorLoad(previousCorrectorId);
      } catch (_) {
        // Ajustement de charge best-effort.
      }
    }

    if (previousCorrectorId !== correctorId) {
      await incrementCorrectorLoad(correctorId);
    }

    return { success: true, correctorId };
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }

    logger.error('assignCorrector failed', {
      error,
      submissionId: request.data?.submissionId,
      requestedCorrectorId: request.data?.correctorId,
      callerId: request.auth?.uid ?? null,
    });
    throw new HttpsError(
      'internal',
      'Affectation impossible.',
      {
        message:
          error instanceof Error ? error.message : 'Erreur interne inconnue.',
      }
    );
  }
});
