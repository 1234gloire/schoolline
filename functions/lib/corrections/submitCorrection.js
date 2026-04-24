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
exports.submitCorrection = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const v2_1 = require("firebase-functions/v2");
const firestore_1 = require("../lib/firestore");
exports.submitCorrection = (0, https_1.onCall)({ invoker: 'public' }, async (request) => {
    try {
        if (!request.auth) {
            throw new https_1.HttpsError('unauthenticated', 'Authentification requise.');
        }
        const callerId = request.auth.uid;
        const callerSnap = await firestore_1.collections.user(callerId).get();
        const callerRole = callerSnap.data()?.['role'];
        if (callerRole !== 'corrector' && callerRole !== 'admin') {
            throw new https_1.HttpsError('permission-denied', 'Réservé aux correcteurs.');
        }
        const { submissionId, finalScore, correctorNotes } = request.data;
        if (!submissionId || typeof finalScore !== 'number') {
            throw new https_1.HttpsError('invalid-argument', 'submissionId et finalScore requis.');
        }
        const submissionRef = firestore_1.collections.submission(submissionId);
        const submissionSnap = await submissionRef.get();
        if (!submissionSnap.exists) {
            throw new https_1.HttpsError('not-found', 'Soumission introuvable.');
        }
        const submission = submissionSnap.data();
        const assignedCorrectorId = submission['correctorId'];
        if (callerRole !== 'admin' && assignedCorrectorId !== callerId) {
            throw new https_1.HttpsError('permission-denied', 'Cette copie ne vous est pas assignée.');
        }
        const allowedStatuses = ['pendingHuman', 'aiReviewed'];
        if (!allowedStatuses.includes(submission['status'])) {
            throw new https_1.HttpsError('failed-precondition', `Impossible de corriger une copie au statut: ${submission['status']}`);
        }
        const maxScore = submission['subjectMaxScore'] ?? 20;
        if (finalScore < 0 || finalScore > maxScore) {
            throw new https_1.HttpsError('invalid-argument', `Note entre 0 et ${maxScore}.`);
        }
        const resolvedCorrectorId = callerRole === 'admin' && assignedCorrectorId
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
        const loadOwnerId = callerRole === 'admin' ? assignedCorrectorId : callerId;
        if (loadOwnerId) {
            try {
                await (0, firestore_1.decrementCorrectorLoad)(loadOwnerId);
            }
            catch (_) {
                // Ajustement de charge best-effort.
            }
        }
        return { success: true, submissionId, finalScore };
    }
    catch (error) {
        if (error instanceof https_1.HttpsError) {
            throw error;
        }
        v2_1.logger.error('submitCorrection failed', {
            error,
            submissionId: request.data?.submissionId,
            callerId: request.auth?.uid ?? null,
        });
        throw new https_1.HttpsError('internal', 'Correction impossible.', {
            message: error instanceof Error ? error.message : 'Erreur interne inconnue.',
        });
    }
});
//# sourceMappingURL=submitCorrection.js.map