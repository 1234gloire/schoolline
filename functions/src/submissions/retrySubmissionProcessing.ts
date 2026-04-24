import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { collections } from '../lib/firestore';
import { SubjectData } from '../lib/types';

interface RetrySubmissionPayload {
  submissionId: string;
}

export const retrySubmissionProcessing = onCall<RetrySubmissionPayload>({ invoker: 'public' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Authentification requise.');
    }

    const callerSnap = await collections.user(request.auth.uid).get();
    if (callerSnap.data()?.['role'] !== 'admin') {
      throw new HttpsError('permission-denied', 'Réservé aux admins.');
    }

    const { submissionId } = request.data;
    if (!submissionId) {
      throw new HttpsError('invalid-argument', 'submissionId requis.');
    }

    const submissionRef = collections.submission(submissionId);
    const submissionSnap = await submissionRef.get();
    if (!submissionSnap.exists) {
      throw new HttpsError('not-found', 'Soumission introuvable.');
    }

    const submission = submissionSnap.data()!;
    const currentStatus = submission['status'] as string | undefined;
    if (currentStatus !== 'error') {
      throw new HttpsError(
        'failed-precondition',
        `Relance indisponible pour le statut: ${currentStatus}`
      );
    }

    const subjectSnap = await collections
      .subject(
        submission['sessionId'] as string,
        submission['subjectId'] as string
      )
      .get();

    if (!subjectSnap.exists) {
      throw new HttpsError('not-found', 'Épreuve introuvable.');
    }

    const subject = subjectSnap.data() as SubjectData;
    const now = admin.firestore.FieldValue.serverTimestamp();

    await submissionRef.update({
      status: 'submitted',
      statusUpdatedAt: now,
      submittedAt:
        submission['submittedAt'] ?? admin.firestore.Timestamp.now(),
      subjectName: subject.name,
      subjectCoefficient: subject.coefficient,
      subjectMaxScore: subject.maxScore,
      subjectBareme: subject.bareme,
      ocrText: '',
      aiScore: admin.firestore.FieldValue.delete(),
      aiConfidence: admin.firestore.FieldValue.delete(),
      aiDetails: admin.firestore.FieldValue.delete(),
      aiFeedback: admin.firestore.FieldValue.delete(),
      aiStrengths: admin.firestore.FieldValue.delete(),
      aiImprovements: admin.firestore.FieldValue.delete(),
      finalScore: admin.firestore.FieldValue.delete(),
      correctorId: admin.firestore.FieldValue.delete(),
      correctorNotes: admin.firestore.FieldValue.delete(),
      errorReason: admin.firestore.FieldValue.delete(),
      ocrCompletedAt: admin.firestore.FieldValue.delete(),
      aiReviewedAt: admin.firestore.FieldValue.delete(),
      humanReviewedAt: admin.firestore.FieldValue.delete(),
      publishedAt: admin.firestore.FieldValue.delete(),
      ocrTrigger: true,
    });

    return { success: true, submissionId };
  }
);
