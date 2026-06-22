"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.pawapayWebhook = void 0;
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("../lib/firestore");
const pawapayShared_1 = require("./pawapayShared");
exports.pawapayWebhook = (0, https_1.onRequest)({ region: 'europe-west1', invoker: 'public' }, async (req, res) => {
    if (req.method !== 'POST') {
        res.status(405).send('Method Not Allowed');
        return;
    }
    const body = req.body;
    const depositId = body.depositId;
    if (!depositId) {
        res.status(400).json({ error: 'depositId manquant' });
        return;
    }
    const snap = await firestore_1.collections
        .payments()
        .where('transKey', '==', depositId)
        .where('provider', '==', 'pawapay')
        .limit(1)
        .get();
    if (snap.empty) {
        res.status(200).json({ ok: true, note: 'transaction inconnue' });
        return;
    }
    const paymentDoc = snap.docs[0];
    const payment = paymentDoc.data();
    if (payment['status'] === 'approved' || payment['status'] === 'rejected') {
        res.status(200).json({ ok: true, note: 'déjà traité' });
        return;
    }
    if (body.status === 'COMPLETED') {
        await (0, pawapayShared_1.finalizeApproved)(paymentDoc.ref, payment, depositId);
    }
    else if (body.status === 'FAILED') {
        await (0, pawapayShared_1.finalizeRejected)(paymentDoc.ref, payment, depositId, (0, pawapayShared_1.mapFailureReason)(body.failureReason?.failureCode));
    }
    res.status(200).json({ ok: true });
});
//# sourceMappingURL=pawapayWebhook.js.map