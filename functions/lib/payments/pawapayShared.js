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
exports.finalizeApproved = finalizeApproved;
exports.finalizeRejected = finalizeRejected;
exports.mapFailureReason = mapFailureReason;
exports.notifyStudent = notifyStudent;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("../lib/firestore");
async function finalizeApproved(paymentRef, payment, providerRef) {
    await paymentRef.update({
        status: 'approved',
        reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
        providerRef,
    });
    await firestore_1.collections.user(payment['userId']).update({
        subscriptions: admin.firestore.FieldValue.arrayUnion(payment['sessionId']),
    });
    await notifyStudent(payment['userId'], '✅ Paiement confirmé', `Ton accès à "${payment['sessionTitle']}" est maintenant actif !`, 'payment_approved');
    return { status: 'approved' };
}
async function finalizeRejected(paymentRef, payment, providerRef, reason) {
    await paymentRef.update({
        status: 'rejected',
        reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
        providerRef,
        rejectionReason: reason,
    });
    await notifyStudent(payment['userId'], 'Paiement non abouti', `Le paiement pour "${payment['sessionTitle']}" a échoué. Réessaie.`, 'payment_rejected');
    return { status: 'rejected', reason };
}
function mapFailureReason(code) {
    switch (code) {
        case 'PAYER_NOT_FOUND':
            return 'Numéro introuvable. Vérifie ton numéro Mobile Money.';
        case 'PAYMENT_NOT_APPROVED':
            return "Tu n'as pas validé la demande de paiement à temps.";
        case 'PAYER_LIMIT_REACHED':
        case 'WALLET_LIMIT_REACHED':
            return 'Limite de transaction atteinte sur ton compte Mobile Money.';
        case 'INSUFFICIENT_BALANCE':
            return 'Solde insuffisant. Recharge ton compte Mobile Money et réessaie.';
        default:
            return 'La transaction a échoué. Réessaie.';
    }
}
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
//# sourceMappingURL=pawapayShared.js.map