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
exports.paydunyaWebhook = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("../lib/firestore");
const baseUrl = () => process.env['PAYDUNYA_MODE'] === 'sandbox'
    ? 'https://app.paydunya.com/sandbox-api/v1'
    : 'https://app.paydunya.com/api/v1';
const headers = () => ({
    'PAYDUNYA-MASTER-KEY': process.env['PAYDUNYA_MASTER_KEY'] ?? '',
    'PAYDUNYA-PRIVATE-KEY': process.env['PAYDUNYA_PRIVATE_KEY'] ?? '',
    'PAYDUNYA-TOKEN': process.env['PAYDUNYA_TOKEN'] ?? '',
});
function paydunyaAmount(data) {
    const rawAmount = data['total_amount'] ??
        data['amount'] ??
        data['invoice']?.['total_amount'];
    const amount = Number(rawAmount);
    return Number.isFinite(amount) ? Math.round(amount) : null;
}
/**
 * IPN PayDunya — appelé automatiquement quand un paiement est confirmé.
 * URL à configurer dans le dashboard PayDunya :
 *   https://europe-west1-vdfapp-7c806.cloudfunctions.net/paydunyaWebhook
 */
exports.paydunyaWebhook = (0, https_1.onRequest)({ region: 'europe-west1', invoker: 'public' }, async (req, res) => {
    if (req.method !== 'POST') {
        res.status(405).send('Method Not Allowed');
        return;
    }
    const body = req.body;
    // PayDunya envoie le token de facture dans plusieurs formats possibles
    const invoiceToken = body['token'] ??
        body['hash'] ??
        body['data']?.['invoice']?.['token'] ??
        body['invoice']?.['token'];
    if (!invoiceToken) {
        // Certains IPN PayDunya n'ont pas de token mais juste un hash dans les headers
        res.status(200).json({ ok: true, note: 'token absent, ignoré' });
        return;
    }
    // Confirmer le paiement auprès de PayDunya
    let confirmData;
    try {
        const resp = await fetch(`${baseUrl()}/checkout-invoice/confirm/${invoiceToken}`, { headers: headers() });
        confirmData = (await resp.json());
    }
    catch {
        res.status(500).json({ error: 'Impossible de confirmer avec PayDunya' });
        return;
    }
    const status = confirmData['status']?.toLowerCase();
    const customData = confirmData['custom_data'];
    const paymentId = customData?.['payment_id'];
    const userId = customData?.['user_id'];
    const sessionId = customData?.['session_id'];
    if (!paymentId) {
        res.status(200).json({ ok: true, note: 'payment_id absent dans custom_data' });
        return;
    }
    const paymentRef = firestore_1.collections.payment(paymentId);
    const paymentSnap = await paymentRef.get();
    if (!paymentSnap.exists) {
        res.status(200).json({ ok: true, note: 'paiement introuvable' });
        return;
    }
    const payment = paymentSnap.data();
    const expectedAmount = Math.round(Number(payment['amount']) || 0);
    const confirmedAmount = paydunyaAmount(confirmData);
    const tokenMatches = payment['paydunyaToken'] === invoiceToken;
    const customDataMatches = payment['userId'] === userId &&
        payment['sessionId'] === sessionId &&
        (confirmedAmount === null || confirmedAmount === expectedAmount);
    if (!tokenMatches || !customDataMatches) {
        console.error('PayDunya confirmation mismatch', {
            paymentId,
            tokenMatches,
            customDataMatches,
            expectedAmount,
            confirmedAmount,
        });
        res.status(200).json({ ok: true, note: 'confirmation ignorée' });
        return;
    }
    // Idempotence
    if (payment['status'] === 'approved' || payment['status'] === 'rejected') {
        res.status(200).json({ ok: true, note: 'déjà traité' });
        return;
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    if (status === 'completed') {
        await paymentRef.update({
            status: 'approved',
            reviewedAt: now,
            paydunyaToken: invoiceToken,
        });
        await firestore_1.collections.user(payment['userId']).update({
            subscriptions: admin.firestore.FieldValue.arrayUnion(payment['sessionId']),
        });
        await notifyStudent(payment['userId'], '✅ Paiement confirmé', `Ton accès à "${payment['sessionTitle']}" est maintenant actif !`, 'payment_approved');
    }
    else if (status === 'cancelled' || status === 'failed') {
        await paymentRef.update({ status: 'rejected', reviewedAt: now });
    }
    res.status(200).json({ ok: true });
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
    catch (_) { /* non bloquant */ }
}
//# sourceMappingURL=paydunyaWebhook.js.map