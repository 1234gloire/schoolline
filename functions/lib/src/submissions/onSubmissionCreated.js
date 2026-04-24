"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.onSubmissionCreated = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const admin = __importStar(require("firebase-admin"));
const v2_1 = require("firebase-functions/v2");
const firestore_2 = require("../lib/firestore");
const EXAM_LATE_TOLERANCE_MINUTES = 5;
exports.onSubmissionCreated = (0, firestore_1.onDocumentCreated)('submissions/{submissionId}', async (event) => {
    const snap = event.data;
    if (!snap)
        return;
    const submissionId = event.params.submissionId;
    const data = snap.data();
    v2_1.logger.info(`Nouvelle soumission: ${submissionId}`, {
        userId: data.userId,
        subjectId: data.subjectId,
    });
    try {
        // ─── 1. Récupérer l'épreuve pour valider l'horaire ───
        const subjectSnap = await admin
            .firestore()
            .collectionGroup('subjects')
            .where(admin.firestore.FieldPath.documentId(), '==', data.subjectId)
            .limit(1)
            .get();
        if (subjectSnap.empty) {
            v2_1.logger.error(`Épreuve introuvable: ${data.subjectId}`);
            await snap.ref.update({ status: 'error', errorReason: 'subject_not_found' });
            return;
        }
        const subject = subjectSnap.docs[0].data();
        const submittedAt = data.submittedAt.toDate();
        const endTime = subject.endTime.toDate();
        const startTime = subject.startTime.toDate();
        const toleranceStart = new Date(startTime.getTime() - EXAM_LATE_TOLERANCE_MINUTES * 60000);
        const toleranceEnd = new Date(endTime.getTime() + EXAM_LATE_TOLERANCE_MINUTES * 60000);
        // ─── 2. Validation horaire ───
        if (submittedAt < toleranceStart || submittedAt > toleranceEnd) {
            v2_1.logger.warn(`Soumission hors délai: ${submissionId}`);
            await snap.ref.update({
                status: 'rejected',
                errorReason: 'out_of_time_window',
                rejectedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return;
        }
        // ─── 3. Anti-doublon ───
        const existing = await firestore_2.collections
            .submissions()
            .where('userId', '==', data.userId)
            .where('subjectId', '==', data.subjectId)
            .where('status', '!=', 'rejected')
            .limit(2)
            .get();
        if (existing.docs.length > 1) {
            await snap.ref.update({ status: 'rejected', errorReason: 'duplicate_submission' });
            return;
        }
        // ─── 4. URL signée pour la copie ───
        let signedUrl;
        if (data.fileRef) {
            try {
                const [url] = await admin.storage().bucket()
                    .file(data.fileRef)
                    .getSignedUrl({
                    action: 'read',
                    expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
                });
                signedUrl = url;
            }
            catch (_) { /* non bloquant */ }
        }
        // ─── 5. Déclencher pipeline OCR ───
        await snap.ref.update({
            status: 'submitted',
            statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            subjectName: subject.name,
            subjectCoefficient: subject.coefficient,
            subjectMaxScore: subject.maxScore,
            subjectBareme: subject.bareme,
            ...(signedUrl ? { signedUrl } : {}),
            ocrTrigger: true,
        });
        v2_1.logger.info(`Soumission ${submissionId} validée`);
    }
    catch (error) {
        v2_1.logger.error(`Erreur: ${submissionId}`, error);
        await snap.ref.update({ status: 'error', errorReason: String(error) });
    }
});
//# sourceMappingURL=onSubmissionCreated.js.map