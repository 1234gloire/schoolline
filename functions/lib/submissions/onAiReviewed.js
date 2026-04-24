"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onAiReviewed = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const v2_1 = require("firebase-functions/v2");
exports.onAiReviewed = (0, firestore_1.onDocumentUpdated)('submissions/{submissionId}', async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after)
        return;
    if (before.status !== 'pendingHuman' && after.status === 'pendingHuman') {
        v2_1.logger.info(`Copie en attente correcteur: ${event.params.submissionId}`, {
            correctorId: after.correctorId,
            aiConfidence: after.aiConfidence,
        });
    }
});
//# sourceMappingURL=onAiReviewed.js.map