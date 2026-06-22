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
exports.requestOnDemandSession = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("../lib/firestore");
const MIN_LEAD_TIME_MS = 48 * 60 * 60 * 1000;
exports.requestOnDemandSession = (0, https_1.onCall)({ invoker: 'public', region: 'europe-west1' }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'Authentification requise.');
    }
    const { startDate: rawStart, endDate: rawEnd, visibility } = request.data;
    if (!rawStart || !rawEnd) {
        throw new https_1.HttpsError('invalid-argument', 'startDate et endDate sont requis.');
    }
    if (visibility !== 'public' && visibility !== 'private') {
        throw new https_1.HttpsError('invalid-argument', "visibility doit être 'public' ou 'private'.");
    }
    const startDate = new Date(rawStart);
    const endDate = new Date(rawEnd);
    if (Number.isNaN(startDate.getTime()) || Number.isNaN(endDate.getTime())) {
        throw new https_1.HttpsError('invalid-argument', 'Dates invalides.');
    }
    if (endDate.getTime() <= startDate.getTime()) {
        throw new https_1.HttpsError('invalid-argument', 'La date de fin doit être après la date de début.');
    }
    const uid = request.auth.uid;
    const userSnap = await firestore_1.collections.user(uid).get();
    const userData = userSnap.data();
    if (!userSnap.exists || !userData) {
        throw new https_1.HttpsError('not-found', 'Profil utilisateur introuvable.');
    }
    if (userData['role'] !== 'student') {
        throw new https_1.HttpsError('permission-denied', 'Réservé aux élèves.');
    }
    const displayName = userData['displayName']?.trim() ?? '';
    const phone = userData['phone']?.trim() ?? '';
    const school = userData['school']?.trim() ?? '';
    const studentClass = userData['class'];
    const series = userData['series']?.trim() ?? '';
    const missing = [];
    if (!displayName)
        missing.push('nom complet');
    if (!phone)
        missing.push('téléphone');
    if (!school)
        missing.push('établissement');
    if (!studentClass)
        missing.push('classe');
    if (studentClass === 'terminale' && !series)
        missing.push('série');
    if (missing.length > 0) {
        throw new https_1.HttpsError('failed-precondition', `Profil incomplet : ${missing.join(', ')}.`);
    }
    // Temps serveur uniquement — ne jamais faire confiance à l'horloge du client.
    if (startDate.getTime() - Date.now() < MIN_LEAD_TIME_MS) {
        throw new https_1.HttpsError('failed-precondition', 'La date de début doit être au moins 48h après la demande.');
    }
    const pendingSnap = await firestore_1.collections
        .sessions()
        .where('requestedBy', '==', uid)
        .where('status', 'in', ['draft', 'open'])
        .limit(1)
        .get();
    if (!pendingSnap.empty) {
        throw new https_1.HttpsError('already-exists', "Tu as déjà une session à la demande en attente ou active.");
    }
    const sessionData = {
        title: `Session à la demande — ${displayName}`,
        class: studentClass,
        series: studentClass === 'terminale' ? [series] : [],
        status: 'draft',
        startDate: admin.firestore.Timestamp.fromDate(startDate),
        endDate: admin.firestore.Timestamp.fromDate(endDate),
        price: 1500,
        createdBy: 'system',
        isOnDemand: true,
        visibility,
        requestedBy: uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    const ref = await firestore_1.collections.sessions().add(sessionData);
    return { sessionId: ref.id };
});
//# sourceMappingURL=requestOnDemandSession.js.map