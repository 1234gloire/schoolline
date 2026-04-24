import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { logger } from 'firebase-functions/v2';
import { collections, decrementCorrectorLoad } from '../lib/firestore';

interface SubmitCorrectionPayload {
  submissionId: string;
  finalScore: number;
  correctorNotes?: string;
}

export const submitCorrection = onCall<SubmitCorrectionPayload>({ invoker: 'public' },
  async (request) => {
    try {
      if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Authentification requise.');
      }

      const callerId = request.auth.uid;
      const callerSnap = await collections.user(callerId).get();
      const callerRole = callerSnap.data()?.['role'];

      if (callerRole !== 'corrector' && callerRole !== 'admin') {
        throw new HttpsError('permission-denied', 'Réservé aux correcteurs.');
      }

      const { submissionId, finalScore, correctorNotes } = request.data;

      if (!submissionId || typeof finalScore !== 'number') {
        throw new HttpsError('invalid-argument', 'submissionId et finalScore requis.');
      }

      const submissionRef = collections.submission(submissionId);
      const submissionSnap = await submissionRef.get();

      if (!submissionSnap.exists) {
        throw new HttpsError('not-found', 'Soumission introuvable.');
      }

      const submission = submissionSnap.data()!;
      const assignedCorrectorId = submission['correctorId'] as string | undefined;

      if (callerRole !== 'admin' && assignedCorrectorId !== callerId) {
        throw new HttpsError('permission-denied', 'Cette copie ne vous est pas assignée.');
      }

      const allowedStatuses = ['pendingHuman', 'aiReviewed'];
      if (!allowedStatuses.includes(submission['status'])) {
        throw new HttpsError(
          'failed-precondition',
          `Impossible de corriger une copie au statut: ${submission['status']}`
        );
      }

      const maxScore = (submission['subjectMaxScore'] as number) ?? 20;
      if (finalScore < 0 || finalScore > maxScore) {
        throw new HttpsError('invalid-argument', `Note entre 0 et ${maxScore}.`);
      }

      const resolvedCorrectorId =
        callerRole === 'admin' && assignedCorrectorId
          ? assignedCorrectorId
          : callerId;

      await submissionRef.update({
        status: 'humanReviewed',
        finalScore,
        correctorId: resolvedCorrectorId,
        correctorNotes: correctorNotes ?? '',
        errorReason: admin.firestore.FieldValue.delete(),
        humanReviewedAt: admin.firestore.FieldValue.serverTimestamp(),
        statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      const loadOwnerId =
        callerRole === 'admin' ? assignedCorrectorId : callerId;
      if (loadOwnerId) {
        try {
          await decrementCorrectorLoad(loadOwnerId);
        } catch (_) {
          // Ajustement de charge best-effort.
        }
      }

      return { success: true, submissionId, finalScore };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }

      logger.error('submitCorrection failed', {
        error,
        submissionId: request.data?.submissionId,
        callerId: request.auth?.uid ?? null,
      });
      throw new HttpsError(
        'internal',
        'Correction impossible.',
        {
          message:
            error instanceof Error ? error.message : 'Erreur interne inconnue.',
        }
      );
    }
  }
);
