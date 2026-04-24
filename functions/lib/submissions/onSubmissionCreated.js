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
        const submittedAt = readSubmissionDate(data.submittedAt, snap.createTime);
        // ─── 1. Récupérer l'épreuve pour valider l'horaire ───
        const subjectSnap = await firestore_2.collections
            .subject(data.sessionId, data.subjectId)
            .get();
        if (!subjectSnap.exists) {
            v2_1.logger.error(`Épreuve introuvable: ${data.subjectId}`);
            await snap.ref.update({ status: 'error', errorReason: 'subject_not_found' });
            return;
        }
        const subject = subjectSnap.data();
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
                statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return;
        }
        // ─── 3. Anti-doublon ───
        const existing = await firestore_2.collections
            .submissions()
            .where('userId', '==', data.userId)
            .where('subjectId', '==', data.subjectId)
            .get();
        const activeSubmissions = existing.docs.filter((doc) => {
            if (doc.id === submissionId) {
                return true;
            }
            const status = doc.data()['status'];
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
        v2_1.logger.info(`Soumission ${submissionId} validée`, {
            submittedAt: submittedAt.toISOString(),
        });
    }
    catch (error) {
        v2_1.logger.error(`Erreur: ${submissionId}`, error);
        await snap.ref.update({
            status: 'error',
            errorReason: error instanceof Error ? error.message : String(error),
            statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
});
function readSubmissionDate(submittedAt, createTime) {
    if (submittedAt &&
        typeof submittedAt === 'object' &&
        'toDate' in submittedAt &&
        typeof submittedAt.toDate === 'function') {
        return submittedAt.toDate();
    }
    if (createTime) {
        return createTime.toDate();
    }
    return new Date();
}
//# sourceMappingURL=onSubmissionCreated.js.map