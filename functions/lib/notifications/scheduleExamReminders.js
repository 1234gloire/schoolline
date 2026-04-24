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
exports.scheduleExamReminders = void 0;
const scheduler_1 = require("firebase-functions/v2/scheduler");
const admin = __importStar(require("firebase-admin"));
const v2_1 = require("firebase-functions/v2");
const firestore_1 = require("../lib/firestore");
// Les trois créneaux de rappel avant le début de l'épreuve
const REMINDER_WINDOWS = [
    { key: '30min', minsBefore: 30, label: '30 minutes' },
    { key: '15min', minsBefore: 15, label: '15 minutes' },
    { key: '5min', minsBefore: 5, label: '5 minutes' },
];
// Marge ±2 min autour du créneau nominal pour absorber les variations de scheduling
const WINDOW_MARGIN_MS = 2 * 60 * 1000;
/**
 * Cron toutes les 5 minutes.
 * Envoie des notifications FCM aux élèves abonnés avant le début de leurs épreuves.
 * Chaque rappel (30/15/5 min) est envoyé une seule fois grâce à `notificationsSent`
 * stocké sur le document épreuve dans Firestore.
 */
exports.scheduleExamReminders = (0, scheduler_1.onSchedule)({
    schedule: 'every 5 minutes',
    region: 'europe-west1',
}, async () => {
    const nowMs = Date.now();
    const sessionsSnap = await firestore_1.collections
        .sessions()
        .where('status', 'in', ['open', 'active'])
        .get();
    if (sessionsSnap.empty) {
        v2_1.logger.info('scheduleExamReminders: aucune session ouverte ou active.');
        return;
    }
    let totalSent = 0;
    for (const sessionDoc of sessionsSnap.docs) {
        const sessionId = sessionDoc.id;
        const subjectsSnap = await firestore_1.collections.subjects(sessionId).get();
        if (subjectsSnap.empty)
            continue;
        // Récupérer les abonnés de la session une seule fois pour toutes les épreuves
        const subscribersSnap = await firestore_1.collections
            .users()
            .where('subscriptions', 'array-contains', sessionId)
            .get();
        if (subscribersSnap.empty)
            continue;
        for (const subjectDoc of subjectsSnap.docs) {
            const subject = subjectDoc.data();
            const startTimeMs = subject.startTime.toMillis();
            const sentFlags = (subjectDoc.data()['notificationsSent'] ?? {});
            for (const window of REMINDER_WINDOWS) {
                if (sentFlags[window.key])
                    continue;
                const targetMs = startTimeMs - window.minsBefore * 60000;
                if (Math.abs(nowMs - targetMs) > WINDOW_MARGIN_MS)
                    continue;
                // Filtrer les abonnés éligibles à cette épreuve
                const tokens = subscribersSnap.docs
                    .filter((userDoc) => {
                    const d = userDoc.data();
                    if (!d['fcmToken'])
                        return false;
                    return userMatchesSubject(d, subject);
                })
                    .map((userDoc) => userDoc.data()['fcmToken']);
                // Marquer comme envoyé même s'il n'y a aucun token (évite de reprocesser)
                await subjectDoc.ref.update({
                    [`notificationsSent.${window.key}`]: true,
                });
                if (tokens.length === 0) {
                    v2_1.logger.info(`scheduleExamReminders [${window.key}]: ${subject.name} — aucun destinataire.`);
                    continue;
                }
                const message = {
                    tokens,
                    notification: {
                        title: `⏰ Épreuve dans ${window.label}`,
                        body: `Ton épreuve de ${subject.name} commence dans ${window.label}.`,
                    },
                    data: {
                        type: 'exam_reminder',
                        sessionId,
                        subjectId: subjectDoc.id,
                        minutesBefore: String(window.minsBefore),
                    },
                    android: {
                        priority: 'high',
                        notification: {
                            channelId: 'exam_reminders',
                            priority: 'high',
                            sound: 'default',
                        },
                    },
                    apns: {
                        payload: {
                            aps: { sound: 'default', badge: 1 },
                        },
                    },
                };
                const result = await admin.messaging().sendEachForMulticast(message);
                v2_1.logger.info(`scheduleExamReminders [${window.key}]: ${subject.name} (session ${sessionId})` +
                    ` — ${result.successCount}/${tokens.length} envoyé(s).`);
                totalSent += result.successCount;
                // Nettoyer les tokens FCM devenus invalides
                await cleanupInvalidTokens(result.responses, tokens, subscribersSnap.docs);
            }
        }
    }
    v2_1.logger.info(`scheduleExamReminders: ${totalSent} notification(s) envoyée(s) au total.`);
});
// Vérifie si un utilisateur est éligible à recevoir la notif pour cette épreuve
// (reproduit la logique de sessionMatchesStudent / subjectMatchesStudent côté Flutter)
function userMatchesSubject(userData, subject) {
    const subjectSeries = (subject.series ?? []).map((s) => s.trim().toUpperCase());
    // Pas de restriction de série → tout le monde
    if (subjectSeries.length === 0)
        return true;
    const userClass = userData['class'];
    // Élève de 3ème → toujours éligible (pas de notion de série)
    if (userClass === 'troisieme')
        return true;
    // Élève de Terminale → vérifier la série
    const userSeries = userData['series']?.trim().toUpperCase() ?? '';
    if (userSeries === '')
        return false;
    return subjectSeries.includes(userSeries);
}
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
    v2_1.logger.info(`Tokens FCM invalides nettoyés: ${invalidTokens.size}`);
}
//# sourceMappingURL=scheduleExamReminders.js.map