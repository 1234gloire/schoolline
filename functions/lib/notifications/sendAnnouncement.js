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
exports.sendAnnouncement = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const v2_1 = require("firebase-functions/v2");
const firestore_1 = require("../lib/firestore");
// sendEachForMulticast accepte au maximum 500 tokens par appel.
const FCM_BATCH_SIZE = 500;
exports.sendAnnouncement = (0, https_1.onCall)({ invoker: 'public', region: 'europe-west1' }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'Authentification requise.');
    }
    const callerSnap = await firestore_1.collections.user(request.auth.uid).get();
    const callerData = callerSnap.data();
    if (callerData?.['role'] !== 'admin') {
        throw new https_1.HttpsError('permission-denied', 'Réservé aux admins.');
    }
    const title = request.data.title?.trim();
    const body = request.data.body?.trim();
    const audience = request.data.audience ?? 'all';
    const series = request.data.series?.trim().toUpperCase();
    if (!title || !body) {
        throw new https_1.HttpsError('invalid-argument', 'Le titre et le message sont requis.');
    }
    if (title.length > 80) {
        throw new https_1.HttpsError('invalid-argument', 'Le titre ne doit pas dépasser 80 caractères.');
    }
    if (body.length > 500) {
        throw new https_1.HttpsError('invalid-argument', 'Le message ne doit pas dépasser 500 caractères.');
    }
    // ── Sélection des destinataires (élèves uniquement) ──
    let query = firestore_1.collections.users().where('role', '==', 'student');
    if (audience === 'troisieme' || audience === 'terminale') {
        query = query.where('class', '==', audience);
    }
    const usersSnap = await query.get();
    const recipientDocs = usersSnap.docs.filter((doc) => {
        const d = doc.data();
        if (!d['fcmToken'])
            return false;
        // Filtre série uniquement pour la Terminale
        if (audience === 'terminale' && series) {
            const userSeries = d['series']?.trim().toUpperCase() ?? '';
            return userSeries === series;
        }
        return true;
    });
    const tokens = recipientDocs.map((doc) => doc.data()['fcmToken']);
    // ── Archivage de l'annonce (historique) ──
    const announcementRef = firestore_1.collections.announcements().doc();
    const baseRecord = {
        title,
        body,
        audience,
        series: audience === 'terminale' ? series ?? null : null,
        sentBy: request.auth.uid,
        sentByName: callerData?.['displayName'] ?? '',
        recipientCount: tokens.length,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (tokens.length === 0) {
        await announcementRef.set({ ...baseRecord, successCount: 0 });
        v2_1.logger.info('sendAnnouncement: aucun destinataire avec token FCM.');
        return { recipientCount: 0, successCount: 0 };
    }
    // ── Envoi par lots de 500 ──
    let successCount = 0;
    const allResponses = [];
    for (let i = 0; i < tokens.length; i += FCM_BATCH_SIZE) {
        const batchTokens = tokens.slice(i, i + FCM_BATCH_SIZE);
        const message = {
            tokens: batchTokens,
            notification: { title, body },
            data: { type: 'announcement', announcementId: announcementRef.id },
            // Pas de channelId : on s'aligne sur les notifs paiements/résultats qui
            // fonctionnent (canal de fallback FCM). Le canal "announcements"
            // n'existe pas dans l'app → Android 8+ masquerait la notif en arrière-plan.
            android: { priority: 'high' },
            apns: { payload: { aps: { sound: 'default', badge: 1 } } },
        };
        const result = await admin.messaging().sendEachForMulticast(message);
        successCount += result.successCount;
        allResponses.push(...result.responses);
    }
    await announcementRef.set({ ...baseRecord, successCount });
    // ── Nettoyage des tokens FCM invalides ──
    await cleanupInvalidTokens(allResponses, tokens, recipientDocs);
    v2_1.logger.info(`sendAnnouncement [${audience}${series ? '/' + series : ''}]: ` +
        `${successCount}/${tokens.length} envoyé(s).`);
    return { recipientCount: tokens.length, successCount };
});
// Supprime les tokens FCM devenus invalides des documents utilisateurs
async function cleanupInvalidTokens(responses, tokens, userDocs) {
    const invalidTokens = new Set();
    responses.forEach((resp, idx) => {
        const code = resp.error?.code ?? '';
        if (!resp.success &&
            (code === 'messaging/invalid-registration-token' ||
                code === 'messaging/registration-token-not-registered')) {
            invalidTokens.add(tokens[idx]);
        }
    });
    if (invalidTokens.size === 0)
        return;
    const batch = admin.firestore().batch();
    userDocs.forEach((userDoc) => {
        const token = userDoc.data()['fcmToken'];
        if (token && invalidTokens.has(token)) {
            batch.update(userDoc.ref, {
                fcmToken: admin.firestore.FieldValue.delete(),
            });
        }
    });
    await batch.commit();
    v2_1.logger.info(`sendAnnouncement: ${invalidTokens.size} token(s) FCM invalide(s) nettoyé(s).`);
}
//# sourceMappingURL=sendAnnouncement.js.map