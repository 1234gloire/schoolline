"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.checkPawapayPaymentStatus = void 0;
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("../lib/firestore");
const pawapayShared_1 = require("./pawapayShared");
const PAWAPAY_BASE_URL = 'https://api.pawapay.io/v2';
exports.checkPawapayPaymentStatus = (0, https_1.onCall)({ invoker: 'public', region: 'europe-west1' }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'Authentification requise.');
    }
    const { paymentId } = request.data;
    if (!paymentId) {
        throw new https_1.HttpsError('invalid-argument', 'paymentId requis.');
    }
    const paymentRef = firestore_1.collections.payment(paymentId);
    const snap = await paymentRef.get();
    if (!snap.exists) {
        throw new https_1.HttpsError('not-found', 'Paiement introuvable.');
    }
    const payment = snap.data();
    if (payment['userId'] !== request.auth.uid) {
        throw new https_1.HttpsError('permission-denied', "Ce paiement ne t'appartient pas.");
    }
    if (payment['status'] === 'approved') {
        return { status: 'approved' };
    }
    if (payment['status'] === 'rejected') {
        return { status: 'rejected', reason: payment['rejectionReason'] ?? null };
    }
    const apiToken = process.env.PAWAPAY_API_TOKEN;
    const depositId = payment['transKey'];
    if (!apiToken || !depositId) {
        return { status: 'pending' };
    }
    let response;
    try {
        response = await fetch(`${PAWAPAY_BASE_URL}/deposits/${depositId}`, {
            headers: { Authorization: `Bearer ${apiToken}` },
        });
    }
    catch (_) {
        return { status: 'pending' };
    }
    const body = (await response.json().catch(() => null));
    if (body?.status !== 'FOUND' || !body.data) {
        return { status: 'pending' };
    }
    if (body.data.status === 'COMPLETED') {
        return (0, pawapayShared_1.finalizeApproved)(paymentRef, payment, depositId);
    }
    if (body.data.status === 'FAILED') {
        const reason = (0, pawapayShared_1.mapFailureReason)(body.data.failureReason?.failureCode);
        return (0, pawapayShared_1.finalizeRejected)(paymentRef, payment, depositId, reason);
    }
    return { status: 'pending' };
});
//# sourceMappingURL=checkPawapayPaymentStatus.js.map