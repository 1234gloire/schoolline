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
exports.submitPaymentProof = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("../lib/firestore");
exports.submitPaymentProof = (0, https_1.onCall)({ invoker: 'public' }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'Authentification requise.');
    }
    const { sessionId, proofFileRef } = request.data;
    if (!sessionId || !proofFileRef) {
        throw new https_1.HttpsError('invalid-argument', 'sessionId et proofFileRef sont requis.');
    }
    const userId = request.auth.uid;
    // Vérifier qu'il n'existe pas déjà un paiement pending ou approved
    const existingSnap = await firestore_1.collections
        .payments()
        .where('userId', '==', userId)
        .where('sessionId', '==', sessionId)
        .where('status', 'in', ['pending', 'approved'])
        .limit(1)
        .get();
    if (!existingSnap.empty) {
        const existing = existingSnap.docs[0].data();
        if (existing['status'] === 'approved') {
            throw new https_1.HttpsError('already-exists', 'Accès déjà accordé pour cette session.');
        }
        throw new https_1.HttpsError('already-exists', 'Une demande est déjà en attente de validation.');
    }
    // Récupérer le titre et le prix de la session
    const sessionSnap = await firestore_1.collections.session(sessionId).get();
    if (!sessionSnap.exists) {
        throw new https_1.HttpsError('not-found', 'Session introuvable.');
    }
    const sessionData = sessionSnap.data();
    await firestore_1.collections.payments().add({
        userId,
        sessionId,
        sessionTitle: sessionData['title'] ?? '',
        amount: sessionData['price'] ?? 0,
        proofFileRef,
        status: 'pending',
        submittedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { success: true };
});
//# sourceMappingURL=submitPaymentProof.js.map