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
exports.createPaydunyaInvoice = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("../lib/firestore");
const baseUrl = () => process.env['PAYDUNYA_MODE'] === 'sandbox'
    ? 'https://app.paydunya.com/sandbox-api/v1'
    : 'https://app.paydunya.com/api/v1';
const payUrl = (token) => process.env['PAYDUNYA_MODE'] === 'sandbox'
    ? `https://paydunya.com/sandbox-checkout/invoice/${token}`
    : `https://paydunya.com/checkout/invoice/${token}`;
const PAYDUNYA_MIN_AMOUNT = 200;
const headers = () => ({
    'Content-Type': 'application/json',
    'PAYDUNYA-MASTER-KEY': process.env['PAYDUNYA_MASTER_KEY'] ?? '',
    'PAYDUNYA-PRIVATE-KEY': process.env['PAYDUNYA_PRIVATE_KEY'] ?? '',
    'PAYDUNYA-TOKEN': process.env['PAYDUNYA_TOKEN'] ?? '',
});
function assertPaydunyaConfig() {
    const missing = [
        'PAYDUNYA_MASTER_KEY',
        'PAYDUNYA_PRIVATE_KEY',
        'PAYDUNYA_TOKEN',
    ].filter((key) => !process.env[key]);
    if (missing.length > 0) {
        console.error('Missing PayDunya configuration:', missing.join(', '));
        throw new https_1.HttpsError('failed-precondition', 'Configuration PayDunya incomplète.');
    }
}
exports.createPaydunyaInvoice = (0, https_1.onCall)({ invoker: 'public', region: 'europe-west1' }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'Authentification requise.');
    }
    assertPaydunyaConfig();
    const { sessionId } = request.data;
    const uid = request.auth.uid;
    if (!sessionId) {
        throw new https_1.HttpsError('invalid-argument', 'sessionId requis.');
    }
    // Vérifier si déjà abonné
    const userSnap = await firestore_1.collections.user(uid).get();
    const subscriptions = userSnap.data()?.['subscriptions'] ?? [];
    if (subscriptions.includes(sessionId)) {
        throw new https_1.HttpsError('already-exists', 'Tu as déjà accès à cette session.');
    }
    // Récupérer la session
    const sessionSnap = await firestore_1.collections.session(sessionId).get();
    if (!sessionSnap.exists) {
        throw new https_1.HttpsError('not-found', 'Session introuvable.');
    }
    const session = sessionSnap.data();
    const amount = Math.round(Number(session['price']) || 0);
    if (amount <= 0) {
        throw new https_1.HttpsError('failed-precondition', 'Aucun paiement requis pour cette session.');
    }
    if (amount < PAYDUNYA_MIN_AMOUNT) {
        throw new https_1.HttpsError('failed-precondition', `Le montant minimum PayDunya est ${PAYDUNYA_MIN_AMOUNT} FCFA.`);
    }
    // Réutiliser une facture pending existante
    const existingSnap = await firestore_1.collections
        .payments()
        .where('userId', '==', uid)
        .where('sessionId', '==', sessionId)
        .where('provider', '==', 'paydunya')
        .where('status', '==', 'pending')
        .limit(1)
        .get();
    if (!existingSnap.empty) {
        const existing = existingSnap.docs[0].data();
        if (existing['invoiceUrl']) {
            const token = existing['paydunyaToken'];
            const existingUrl = existing['invoiceUrl'];
            const invoiceUrl = existingUrl.includes('app.paydunya.com') && token
                ? payUrl(token)
                : existingUrl;
            if (invoiceUrl !== existingUrl) {
                await existingSnap.docs[0].ref.update({ invoiceUrl });
            }
            console.log('Reusing existing invoiceUrl:', invoiceUrl);
            return { invoiceUrl, paymentId: existingSnap.docs[0].id };
        }
        // Doc exists but no URL yet — delete and recreate
        await existingSnap.docs[0].ref.delete();
    }
    // Créer le document Firestore avant d'appeler PayDunya
    const paymentRef = await firestore_1.collections.payments().add({
        userId: uid,
        sessionId,
        sessionTitle: session['title'] ?? '',
        amount,
        provider: 'paydunya',
        proofFileRef: '',
        status: 'pending',
        submittedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    // Créer la facture PayDunya
    const webhookUrl = `https://europe-west1-vdfapp-7c806.cloudfunctions.net/paydunyaWebhook`;
    const body = {
        invoice: {
            total_amount: amount,
            description: `DiakExam — ${session['title'] ?? 'Session'}`,
        },
        store: {
            name: 'DiakExam',
        },
        actions: {
            cancel_url: 'https://diakexam.app/payment/cancel',
            return_url: 'https://diakexam.app/payment/return',
            callback_url: webhookUrl,
        },
        custom_data: {
            payment_id: paymentRef.id,
            user_id: uid,
            session_id: sessionId,
        },
    };
    let result;
    try {
        const response = await fetch(`${baseUrl()}/checkout-invoice/create`, { method: 'POST', headers: headers(), body: JSON.stringify(body) });
        result = (await response.json());
        console.log('PayDunya API response:', JSON.stringify(result));
        console.log('PayDunya mode:', process.env['PAYDUNYA_MODE']);
    }
    catch (err) {
        await paymentRef.delete();
        throw new https_1.HttpsError('internal', 'Impossible de joindre PayDunya. Réessaie.');
    }
    if (result['response_code'] !== '00') {
        await paymentRef.delete();
        const msg = result['response_text']
            ?? 'Erreur lors de la création de la facture PayDunya.';
        console.error('PayDunya error:', result['response_code'], msg);
        throw new https_1.HttpsError('failed-precondition', msg);
    }
    const invoiceToken = result['token'];
    const responseText = result['response_text'];
    const invoiceUrl = typeof responseText === 'string' && responseText.startsWith('http')
        ? responseText
        : payUrl(invoiceToken);
    console.log('Invoice URL:', invoiceUrl);
    await paymentRef.update({ paydunyaToken: invoiceToken, invoiceUrl });
    return { invoiceUrl, paymentId: paymentRef.id };
});
//# sourceMappingURL=createPaydunyaInvoice.js.map