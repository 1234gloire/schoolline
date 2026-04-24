import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import * as admin from 'firebase-admin';
import { logger } from 'firebase-functions/v2';
import { extractTextFromStorage } from '../lib/ocr';
import { evaluateCopy, AI_CONFIDENCE_THRESHOLD } from '../lib/ai';
import { collections, getAvailableCorrector, incrementCorrectorLoad } from '../lib/firestore';
import { SubmissionData } from '../lib/types';

export const onOcrCompleted = onDocumentUpdated(
  'submissions/{submissionId}',
  async (event) => {
    const before = event.data?.before.data() as SubmissionData | undefined;
    const after = event.data?.after.data() as SubmissionData | undefined;
    if (!before || !after) return;

    const beforeData = event.data!.before.data() as Record<string, unknown>;
    const afterData = event.data!.after.data() as Record<string, unknown>;

    const triggerJustSet =
      !beforeData['ocrTrigger'] &&
      afterData['ocrTrigger'] === true &&
      after.status === 'submitted';

    if (!triggerJustSet) return;

    const submissionId = event.params.submissionId;
    const ref = event.data!.after.ref;

    logger.info(`Pipeline OCR→IA: ${submissionId}`);

    try {
      // ─── OCR ───
      let ocrText = '';
      if (after.fileRef) {
        ocrText = await extractTextFromStorage(after.fileRef);
      }

      await ref.update({
        status: 'ocrDone',
        ocrText,
        ocrCompletedAt: admin.firestore.FieldValue.serverTimestamp(),
        statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        ocrTrigger: admin.firestore.FieldValue.delete(),
      });

      // ─── Évaluation IA ───
      const bareme = (afterData['subjectBareme'] as Record<string, number>) ?? {};
      const maxScore = (afterData['subjectMaxScore'] as number) ?? 20;

      const corrigeText = (afterData['subjectCorrige'] as string | undefined) ?? '';

      const aiResult = await evaluateCopy({
        subjectName: after.subjectName,
        ocrText,
        bareme,
        maxScore,
        corrigeText,
      });

      logger.info(`IA terminée: ${submissionId}`, {
        score: aiResult.score,
        confidence: aiResult.confidence,
      });

      // ─── Routage ───
      if (aiResult.confidence >= AI_CONFIDENCE_THRESHOLD) {
        await ref.update({
          status: 'published',
          aiScore: aiResult.score,
          aiConfidence: aiResult.confidence,
          aiDetails: aiResult.details,
          aiFeedback: aiResult.feedback,
          aiStrengths: aiResult.strengths,
          aiImprovements: aiResult.improvements,
          finalScore: aiResult.score,
          aiReviewedAt: admin.firestore.FieldValue.serverTimestamp(),
          statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          publishedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await notifyStudent(after.userId, after.subjectName, aiResult.score, maxScore);
      } else {
        const correctorId = await getAvailableCorrector();
        await ref.update({
          status: 'pendingHuman',
          aiScore: aiResult.score,
          aiConfidence: aiResult.confidence,
          aiDetails: aiResult.details,
          aiFeedback: aiResult.feedback,
          aiStrengths: aiResult.strengths,
          aiImprovements: aiResult.improvements,
          aiReviewedAt: admin.firestore.FieldValue.serverTimestamp(),
          ...(correctorId ? { correctorId } : {}),
          statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        if (correctorId) await incrementCorrectorLoad(correctorId);
      }
    } catch (error) {
      logger.error(`Erreur pipeline: ${submissionId}`, error);
      await ref.update({
        status: 'pendingHuman',
        errorReason: String(error),
        statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }
);

async function notifyStudent(
  userId: string,
  subjectName: string,
  score: number,
  maxScore: number
): Promise<void> {
  try {
    const snap = await collections.user(userId).get();
    const token = snap.data()?.['fcmToken'] as string | undefined;
    if (!token) return;
    await admin.messaging().send({
      token,
      notification: {
        title: `Résultat — ${subjectName}`,
        body: `Ta note : ${score}/${maxScore}`,
      },
      data: { type: 'result_published', subjectName },
      android: { priority: 'high' },
      apns: { payload: { aps: { badge: 1 } } },
    });
  } catch (_) { /* non bloquant */ }
}
