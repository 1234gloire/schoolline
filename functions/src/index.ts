import * as admin from 'firebase-admin';
import { setGlobalOptions } from 'firebase-functions/v2';

admin.initializeApp();

setGlobalOptions({
  region: 'europe-west1',
  maxInstances: 10,
});

export { onSubmissionCreated } from './submissions/onSubmissionCreated';
export { onOcrCompleted } from './submissions/onOcrCompleted';
export { onAiReviewed } from './submissions/onAiReviewed';
export { retrySubmissionProcessing } from './submissions/retrySubmissionProcessing';
export { publishResults, publishSingleResult } from './results/publishResults';
export { assignCorrector } from './corrections/assignCorrector';
export { submitCorrection } from './corrections/submitCorrection';
export { getSubmissionAssets } from './corrections/getSubmissionAssets';
export { onUserCreated } from './users/onUserCreated';
export { createStaffUser } from './users/createStaffUser';
export { onUserBlocked } from './users/onUserBlocked';
export { submitPaymentProof } from './payments/submitPaymentProof';
export { validatePayment } from './payments/validatePayment';
export { autoCloseSessions } from './sessions/autoCloseSessions';
export { scheduleExamReminders } from './notifications/scheduleExamReminders';
