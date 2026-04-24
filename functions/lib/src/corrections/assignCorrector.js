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
exports.assignCorrector = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("../lib/firestore");
exports.assignCorrector = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'Authentification requise.');
    }
    const callerSnap = await firestore_1.collections.user(request.auth.uid).get();
    if (callerSnap.data()?.['role'] !== 'admin') {
        throw new https_1.HttpsError('permission-denied', 'Réservé aux admins.');
    }
    const { submissionId, correctorId: manualId } = request.data;
    if (!submissionId)
        throw new https_1.HttpsError('invalid-argument', 'submissionId requis.');
    const submissionRef = firestore_1.collections.submission(submissionId);
    const submissionSnap = await submissionRef.get();
    if (!submissionSnap.exists)
        throw new https_1.HttpsError('not-found', 'Soumission introuvable.');
    const correctorId = manualId ?? (await (0, firestore_1.getAvailableCorrector)());
    if (!correctorId)
        throw new https_1.HttpsError('failed-precondition', 'Aucun correcteur disponible.');
    await submissionRef.update({
        correctorId,
        status: 'pendingHuman',
        statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await (0, firestore_1.incrementCorrectorLoad)(correctorId);
    return { success: true, correctorId };
});
//# sourceMappingURL=assignCorrector.js.map