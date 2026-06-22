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
exports.createPawapayPayment = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const node_crypto_1 = require("node:crypto");
const firestore_1 = require("../lib/firestore");
const pawapayShared_1 = require("./pawapayShared");
const PAWAPAY_BASE_URL = 'https://api.pawapay.io/v2';
exports.createPawapayPayment = (0, https_1.onCall)({ invoker: 'public', region: 'europe-west1' }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'Authentification requise.');
    }
    const { sessionId, phoneNumber: rawPhone } = request.data;
    const uid = request.auth.uid;
    if (!sessionId || !rawPhone) {
        throw new https_1.HttpsError('invalid-argument', 'sessionId et phoneNumber requis.');
    }
    const userSnap = await firestore_1.collections.user(uid).get();
    const userData = userSnap.data() ?? {};
    const subscriptions = userData['subscriptions'] ?? [];
    if (subscriptions.includes(sessionId)) {
        throw new https_1.HttpsError('already-exists', 'Tu as déjà accès à cette session.');
    }
    const sessionSnap = await firestore_1.collections.session(sessionId).get();
    if (!sessionSnap.exists) {
        throw new https_1.HttpsError('not-found', 'Session introuvable.');
    }
    const session = sessionSnap.data();
    const startDate = session['startDate'];
    if (startDate && startDate.toMillis() <= Date.now()) {
        throw new https_1.HttpsError('failed-precondition', 'Les inscriptions sont closes : cette session a déjà commencé.');
    }
    const amount = Math.round(Number(session['price']) || 0);
    if (amount < 1) {
        throw new https_1.HttpsError('failed-precondition', 'Montant invalide.');
    }
    const apiToken = process.env.PAWAPAY_API_TOKEN;
    if (!apiToken) {
        throw new https_1.HttpsError('internal', 'Paiement Mobile Money indisponible pour le moment.');
    }
    // Normalisation minimale (indicatif Congo) puis validation/détection de
    // l'opérateur via predict-provider, recommandé par pawaPay pour éviter
    // les rejets liés au format du numéro.
    const digits = rawPhone.replace(/\D/g, '');
    const local = digits.startsWith('242') ? digits.slice(3) : digits;
    const withoutLeadingZero = local.startsWith('0') ? local.slice(1) : local;
    const candidate = `242${withoutLeadingZero}`;
    let predictResponse;
    try {
        predictResponse = await fetch(`${PAWAPAY_BASE_URL}/predict-provider`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                Authorization: `Bearer ${apiToken}`,
            },
            body: JSON.stringify({ phoneNumber: candidate }),
        });
    }
    catch (_) {
        throw new https_1.HttpsError('unavailable', 'Impossible de contacter le service de paiement.');
    }
    const predicted = (await predictResponse.json().catch(() => null));
    if (!predictResponse.ok ||
        !predicted?.provider ||
        !predicted?.phoneNumber ||
        predicted.country !== 'COG') {
        throw new https_1.HttpsError('invalid-argument', 'Numéro Mobile Money invalide pour le Congo. Vérifie ton numéro.');
    }
    const depositId = (0, node_crypto_1.randomUUID)();
    let response;
    try {
        response = await fetch(`${PAWAPAY_BASE_URL}/deposits`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                Authorization: `Bearer ${apiToken}`,
            },
            body: JSON.stringify({
                depositId,
                payer: {
                    type: 'MMO',
                    accountDetails: {
                        phoneNumber: predicted.phoneNumber,
                        provider: predicted.provider,
                    },
                },
                amount: String(amount),
                currency: 'XAF',
                customerMessage: 'Paiement ExamSim',
            }),
        });
    }
    catch (_) {
        throw new https_1.HttpsError('unavailable', 'Impossible de contacter le service de paiement.');
    }
    const data = (await response.json().catch(() => null));
    if (!response.ok || data?.status !== 'ACCEPTED') {
        throw new https_1.HttpsError('unavailable', data?.failureReason?.failureCode
            ? (0, pawapayShared_1.mapFailureReason)(data.failureReason.failureCode)
            : 'Le paiement a été refusé. Vérifie ton numéro et réessaie.');
    }
    // Réutilise le document pending existant pour cette session, sinon en crée un.
    const existingSnap = await firestore_1.collections
        .payments()
        .where('userId', '==', uid)
        .where('sessionId', '==', sessionId)
        .where('provider', '==', 'pawapay')
        .where('status', '==', 'pending')
        .limit(1)
        .get();
    const paymentData = {
        userId: uid,
        sessionId,
        sessionTitle: session['title'] ?? '',
        amount,
        provider: 'pawapay',
        transKey: depositId,
        proofFileRef: '',
        status: 'pending',
        submittedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    let paymentId;
    if (!existingSnap.empty) {
        paymentId = existingSnap.docs[0].id;
        await existingSnap.docs[0].ref.set(paymentData, { merge: true });
    }
    else {
        const ref = await firestore_1.collections.payments().add(paymentData);
        paymentId = ref.id;
    }
    return { paymentId, depositId, amount };
});
//# sourceMappingURL=createPawapayPayment.js.map