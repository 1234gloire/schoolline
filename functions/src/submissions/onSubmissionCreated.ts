import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import * as admin from 'firebase-admin';
import { logger } from 'firebase-functions/v2';
import { collections } from '../lib/firestore';
import { SubjectData, SubmissionData } from '../lib/types';

const EXAM_LATE_TOLERANCE_MINUTES = 5;

export const onSubmissionCreated = onDocumentCreated(
  'submissions/{submissionId}',
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const submissionId = event.params.submissionId;
    const data = snap.data() as SubmissionData;

    logger.info(`Nouvelle soumission: ${submissionId}`, {
      userId: data.userId,
      subjectId: data.subjectId,
    });

    try {
      const submittedAt = readSubmissionDate(data.submittedAt, snap.createTime);

      // ─── 1. Récupérer l'épreuve pour valider l'horaire ───
      const subjectSnap = await collections
        .subject(data.sessionId, data.subjectId)
        .get();

      if (!subjectSnap.exists) {
        logger.error(`Épreuve introuvable: ${data.subjectId}`);
        await snap.ref.update({ status: 'error', errorReason: 'subject_not_found' });
        return;
      }

      const subject = subjectSnap.data() as SubjectData;
      const endTime = subject.endTime.toDate();
      const startTime = subject.startTime.toDate();
      const toleranceStart = new Date(startTime.getTime() - EXAM_LATE_TOLERANCE_MINUTES * 60_000);
      const toleranceEnd = new Date(endTime.getTime() + EXAM_LATE_TOLERANCE_MINUTES * 60_000);

      // ─── 2. Validation horaire ───
      if (submittedAt < toleranceStart || submittedAt > toleranceEnd) {
        logger.warn(`Soumission hors délai: ${submissionId}`);
        await snap.ref.update({
          status: 'rejected',
          errorReason: 'out_of_time_window',
          rejectedAt: admin.firestore.FieldValue.serverTimestamp(),
          statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      // ─── 3. Anti-doublon ───
      const existing = await collections
        .submissions()
        .where('userId', '==', data.userId)
        .where('subjectId', '==', data.subjectId)
        .get();

      const activeSubmissions = existing.docs.filter((doc) => {
        if (doc.id === submissionId) {
          return true;
        }
        const status = doc.data()['status'] as string | undefined;
        return status !== 'rejected';
      });

      if (activeSubmissions.length > 1) {
        await snap.ref.update({
          status: 'rejected',
          errorReason: 'duplicate_submission',
          statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      // ─── 4. Déclencher pipeline OCR ───
      await snap.ref.update({
        submittedAt: admin.firestore.Timestamp.fromDate(submittedAt),
        status: 'submitted',
        statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        subjectName: subject.name,
        subjectCoefficient: subject.coefficient,
        subjectMaxScore: subject.maxScore,
        subjectBareme: subject.bareme,
        subjectCorrige: subject.corrigeText ?? '',
        ocrTrigger: true,
      });

      logger.info(`Soumission ${submissionId} validée`, {
        submittedAt: submittedAt.toISOString(),
      });
    } catch (error) {
      logger.error(`Erreur: ${submissionId}`, error);
      await snap.ref.update({
        status: 'error',
        errorReason: error instanceof Error ? error.message : String(error),
        statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }
);

function readSubmissionDate(
  submittedAt: unknown,
  createTime?: admin.firestore.Timestamp
): Date {
  if (
    submittedAt &&
    typeof submittedAt === 'object' &&
    'toDate' in submittedAt &&
    typeof submittedAt.toDate === 'function'
  ) {
    return submittedAt.toDate() as Date;
  }

  if (createTime) {
    return createTime.toDate();
  }

  return new Date();
}
