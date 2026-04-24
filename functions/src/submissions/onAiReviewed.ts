import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';
import { SubmissionData } from '../lib/types';

export const onAiReviewed = onDocumentUpdated(
  'submissions/{submissionId}',
  async (event) => {
    const before = event.data?.before.data() as SubmissionData | undefined;
    const after = event.data?.after.data() as SubmissionData | undefined;
    if (!before || !after) return;

    if (before.status !== 'pendingHuman' && after.status === 'pendingHuman') {
      logger.info(`Copie en attente correcteur: ${event.params.submissionId}`, {
        correctorId: after.correctorId,
        aiConfidence: after.aiConfidence,
      });
    }
  }
);
