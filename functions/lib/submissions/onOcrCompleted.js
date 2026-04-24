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
exports.onOcrCompleted = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const admin = __importStar(require("firebase-admin"));
const v2_1 = require("firebase-functions/v2");
const ocr_1 = require("../lib/ocr");
const ai_1 = require("../lib/ai");
const firestore_2 = require("../lib/firestore");
exports.onOcrCompleted = (0, firestore_1.onDocumentUpdated)('submissions/{submissionId}', async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after)
        return;
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();
    const triggerJustSet = !beforeData['ocrTrigger'] &&
        afterData['ocrTrigger'] === true &&
        after.status === 'submitted';
    if (!triggerJustSet)
        return;
    const submissionId = event.params.submissionId;
    const ref = event.data.after.ref;
    v2_1.logger.info(`Pipeline OCR→IA: ${submissionId}`);
    try {
        // ─── OCR ───
        let ocrText = '';
        if (after.fileRef) {
            ocrText = await (0, ocr_1.extractTextFromStorage)(after.fileRef);
        }
        await ref.update({
            status: 'ocrDone',
            ocrText,
            ocrCompletedAt: admin.firestore.FieldValue.serverTimestamp(),
            statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            ocrTrigger: admin.firestore.FieldValue.delete(),
        });
        // ─── Évaluation IA ───
        const bareme = afterData['subjectBareme'] ?? {};
        const maxScore = afterData['subjectMaxScore'] ?? 20;
        const corrigeText = afterData['subjectCorrige'] ?? '';
        const aiResult = await (0, ai_1.evaluateCopy)({
            subjectName: after.subjectName,
            ocrText,
            bareme,
            maxScore,
            corrigeText,
        });
        v2_1.logger.info(`IA terminée: ${submissionId}`, {
            score: aiResult.score,
            confidence: aiResult.confidence,
        });
        // ─── Routage ───
        if (aiResult.confidence >= ai_1.AI_CONFIDENCE_THRESHOLD) {
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
        }
        else {
            const correctorId = await (0, firestore_2.getAvailableCorrector)();
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
            if (correctorId)
                await (0, firestore_2.incrementCorrectorLoad)(correctorId);
        }
    }
    catch (error) {
        v2_1.logger.error(`Erreur pipeline: ${submissionId}`, error);
        await ref.update({
            status: 'pendingHuman',
            errorReason: String(error),
            statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
});
async function notifyStudent(userId, subjectName, score, maxScore) {
    try {
        const snap = await firestore_2.collections.user(userId).get();
        const token = snap.data()?.['fcmToken'];
        if (!token)
            return;
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
    }
    catch (_) { /* non bloquant */ }
}
//# sourceMappingURL=onOcrCompleted.js.map