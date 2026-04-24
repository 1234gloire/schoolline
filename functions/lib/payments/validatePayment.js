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
exports.validatePayment = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("../lib/firestore");
exports.validatePayment = (0, https_1.onCall)({ invoker: 'public' }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'Authentification requise.');
    }
    const callerSnap = await firestore_1.collections.user(request.auth.uid).get();
    if (callerSnap.data()?.['role'] !== 'admin') {
        throw new https_1.HttpsError('permission-denied', 'Réservé aux admins.');
    }
    const { paymentId, approved, rejectionReason } = request.data;
    if (!paymentId) {
        throw new https_1.HttpsError('invalid-argument', 'paymentId requis.');
    }
    const paymentRef = firestore_1.collections.payment(paymentId);
    const paymentSnap = await paymentRef.get();
    if (!paymentSnap.exists) {
        throw new https_1.HttpsError('not-found', 'Paiement introuvable.');
    }
    const payment = paymentSnap.data();
    if (payment['status'] !== 'pending') {
        throw new https_1.HttpsError('failed-precondition', `Paiement déjà traité : ${payment['status']}`);
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    if (approved) {
        await paymentRef.update({
            status: 'approved',
            reviewedAt: now,
            reviewedBy: request.auth.uid,
        });
        // Débloquer la session pour l'élève
        await firestore_1.collections.user(payment['userId']).update({
            subscriptions: admin.firestore.FieldValue.arrayUnion(payment['sessionId']),
        });
        await notifyStudent(payment['userId'], '✅ Paiement validé', `Ton accès à "${payment['sessionTitle']}" est maintenant actif. Bonne session !`, 'payment_approved');
    }
    else {
        await paymentRef.update({
            status: 'rejected',
            reviewedAt: now,
            reviewedBy: request.auth.uid,
            rejectionReason: rejectionReason?.trim() ?? '',
        });
        await notifyStudent(payment['userId'], 'Paiement non validé', rejectionReason?.trim() || `Ton paiement pour "${payment['sessionTitle']}" n'a pas pu être validé. Réessaie.`, 'payment_rejected');
    }
    return { success: true };
});
async function notifyStudent(userId, title, body, type) {
    try {
        const snap = await firestore_1.collections.user(userId).get();
        const token = snap.data()?.['fcmToken'];
        if (!token)
            return;
        await admin.messaging().send({
            token,
            notification: { title, body },
            data: { type },
            android: { priority: 'high' },
            apns: { payload: { aps: { badge: 1 } } },
        });
    }
    catch (_) {
        // Non bloquant
    }
}
//# sourceMappingURL=validatePayment.js.map