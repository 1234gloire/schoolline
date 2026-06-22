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
exports.publishSingleResult = exports.publishResults = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const v2_1 = require("firebase-functions/v2");
const firestore_1 = require("../lib/firestore");
// ─── Publication globale (toute la session) ───────────────────────────────────
exports.publishResults = (0, https_1.onCall)({ invoker: 'public' }, async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Authentification requise.');
    const callerSnap = await firestore_1.collections.user(request.auth.uid).get();
    if (callerSnap.data()?.['role'] !== 'admin') {
        throw new https_1.HttpsError('permission-denied', 'Réservé aux admins.');
    }
    const { sessionId } = request.data;
    if (!sessionId)
        throw new https_1.HttpsError('invalid-argument', 'sessionId requis.');
    // 1. Toutes les soumissions de la session
    const allSnap = await firestore_1.collections.submissions()
        .where('sessionId', '==', sessionId)
        .get();
    if (allSnap.empty) {
        return { success: true, published: 0, skipped: 0 };
    }
    // 2. Grouper par userId
    const byUser = new Map();
    for (const doc of allSnap.docs) {
        const uid = doc.data()['userId'];
        if (!byUser.has(uid))
            byUser.set(uid, []);
        byUser.get(uid).push(doc);
    }
    // 3. Traitement par élève
    const RESULT_READY = new Set(['humanReviewed', 'aiReviewed', 'published']);
    const db = admin.firestore();
    const now = admin.firestore.FieldValue.serverTimestamp();
    // Gérer la limite Firestore de 500 ops par batch
    let currentBatch = db.batch();
    let opsInBatch = 0;
    const batches = [currentBatch];
    const addOp = (fn) => {
        if (opsInBatch >= 490) {
            currentBatch = db.batch();
            batches.push(currentBatch);
            opsInBatch = 0;
        }
        fn(currentBatch);
        opsInBatch++;
    };
    const notifyUserIds = [];
    let publishedCount = 0;
    let skippedCount = 0;
    for (const [userId, submissions] of byUser) {
        const effectiveSubmissions = submissions.filter((submission) => submission.data()['status'] !== 'rejected');
        if (effectiveSubmissions.length === 0) {
            skippedCount++;
            v2_1.logger.warn('Élève ignoré : aucune copie exploitable', { userId, sessionId });
            continue;
        }
        // Vérifier que toutes les copies exploitables sont corrigées ou déjà publiées
        const allCorrected = effectiveSubmissions.every((submission) => RESULT_READY.has(submission.data()['status']));
        if (!allCorrected) {
            skippedCount++;
            v2_1.logger.warn('Élève ignoré : copies non toutes corrigées', { userId, sessionId });
            continue;
        }
        // Calculer la moyenne générale pondérée
        let totalPoints = 0;
        let totalCoefficients = 0;
        let lastSubmittedAtMs = 0;
        const subjectResults = [];
        for (const sub of effectiveSubmissions) {
            const data = sub.data();
            const rawScore = (data['finalScore'] ?? data['aiScore']) ?? 0;
            const maxScore = data['subjectMaxScore'] ?? 20;
            const coefficient = data['subjectCoefficient'] ?? 1;
            // Normaliser sur 20
            const scoreOn20 = maxScore > 0 ? (rawScore / maxScore) * 20 : 0;
            const rounded = Math.round(scoreOn20 * 100) / 100;
            totalPoints += rounded * coefficient;
            totalCoefficients += coefficient;
            const submittedAt = data['submittedAt'];
            if (submittedAt && submittedAt.toMillis() > lastSubmittedAtMs) {
                lastSubmittedAtMs = submittedAt.toMillis();
            }
            subjectResults.push({
                subjectId: data['subjectId'],
                subjectName: data['subjectName'],
                finalScore: rounded,
                maxScore: 20,
                coefficient,
                submissionId: sub.id,
            });
            // Passer la soumission à "published" si elle ne l'est pas encore.
            if (data['status'] !== 'published') {
                addOp(b => b.update(sub.ref, {
                    status: 'published',
                    publishedAt: now,
                    statusUpdatedAt: now,
                    errorReason: admin.firestore.FieldValue.delete(),
                }));
                publishedCount++;
            }
        }
        const moyenneGenerale = totalCoefficients > 0
            ? Math.round((totalPoints / totalCoefficients) * 100) / 100
            : 0;
        const isAdmis = moyenneGenerale >= 10;
        const mention = computeMention(moyenneGenerale);
        // Écrire le bulletin de résultat de l'élève
        const resultRef = firestore_1.collections.studentResult(sessionId, userId);
        addOp(b => b.set(resultRef, {
            userId,
            sessionId,
            moyenneGenerale,
            totalPoints: Math.round(totalPoints * 100) / 100,
            totalCoefficients,
            isAdmis,
            mention,
            subjects: subjectResults,
            publishedAt: now,
            lastSubmittedAt: lastSubmittedAtMs > 0
                ? admin.firestore.Timestamp.fromMillis(lastSubmittedAtMs)
                : now,
        }));
        notifyUserIds.push(userId);
    }
    // Commiter tous les batches
    for (const b of batches) {
        await b.commit();
    }
    // Mettre à jour le statut de la session
    await firestore_1.collections.session(sessionId).update({
        status: 'resultsPublished',
        statusUpdatedAt: now,
    });
    // Notifications push
    await sendBatchNotifications(notifyUserIds, sessionId);
    v2_1.logger.info(`Publication : ${publishedCount} copies publiées, ${skippedCount} élèves ignorés`, { sessionId });
    return { success: true, published: publishedCount, skipped: skippedCount };
});
// ─── Publication individuelle (une seule copie) ───────────────────────────────
exports.publishSingleResult = (0, https_1.onCall)({ invoker: 'public' }, async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Authentification requise.');
    const callerSnap = await firestore_1.collections.user(request.auth.uid).get();
    if (callerSnap.data()?.['role'] !== 'admin') {
        throw new https_1.HttpsError('permission-denied', 'Réservé aux admins.');
    }
    const { submissionId } = request.data;
    if (!submissionId)
        throw new https_1.HttpsError('invalid-argument', 'submissionId requis.');
    const ref = firestore_1.collections.submission(submissionId);
    const snap = await ref.get();
    if (!snap.exists)
        throw new https_1.HttpsError('not-found', 'Soumission introuvable.');
    const data = snap.data();
    const allowed = ['humanReviewed', 'aiReviewed'];
    if (!allowed.includes(data['status'])) {
        throw new https_1.HttpsError('failed-precondition', `Statut invalide: ${data['status']}`);
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    await ref.update({
        status: 'published',
        publishedAt: now,
        statusUpdatedAt: now,
        finalScore: data['finalScore'] ?? data['aiScore'],
        errorReason: admin.firestore.FieldValue.delete(),
    });
    // Vérifier si toutes les copies de cet élève pour cette session sont publiées
    const userId = data['userId'];
    const sessionId = data['sessionId'];
    await tryComputeStudentResult(sessionId, userId, now);
    await notifyStudent(userId, data['subjectName'], data['finalScore'] ?? data['aiScore'], data['subjectMaxScore'] ?? 20);
    return { success: true, submissionId };
});
// ─── Calcul du bulletin si toutes les copies sont publiées ───────────────────
async function tryComputeStudentResult(sessionId, userId, now) {
    try {
        const userSnap = await firestore_1.collections.submissions()
            .where('sessionId', '==', sessionId)
            .where('userId', '==', userId)
            .get();
        const effectiveDocs = userSnap.docs.filter((doc) => doc.data()['status'] !== 'rejected');
        if (effectiveDocs.length === 0) {
            return;
        }
        const allPublished = effectiveDocs.every((doc) => doc.data()['status'] === 'published');
        if (!allPublished)
            return;
        let totalPoints = 0;
        let totalCoefficients = 0;
        let lastSubmittedAtMs = 0;
        const subjectResults = [];
        for (const sub of effectiveDocs) {
            const d = sub.data();
            const rawScore = (d['finalScore'] ?? d['aiScore']) ?? 0;
            const maxScore = d['subjectMaxScore'] ?? 20;
            const coefficient = d['subjectCoefficient'] ?? 1;
            const scoreOn20 = maxScore > 0 ? (rawScore / maxScore) * 20 : 0;
            const rounded = Math.round(scoreOn20 * 100) / 100;
            totalPoints += rounded * coefficient;
            totalCoefficients += coefficient;
            const submittedAt = d['submittedAt'];
            if (submittedAt && submittedAt.toMillis() > lastSubmittedAtMs) {
                lastSubmittedAtMs = submittedAt.toMillis();
            }
            subjectResults.push({
                subjectId: d['subjectId'],
                subjectName: d['subjectName'],
                finalScore: rounded,
                maxScore: 20,
                coefficient,
                submissionId: sub.id,
            });
        }
        const moyenneGenerale = totalCoefficients > 0
            ? Math.round((totalPoints / totalCoefficients) * 100) / 100
            : 0;
        await firestore_1.collections.studentResult(sessionId, userId).set({
            userId,
            sessionId,
            moyenneGenerale,
            totalPoints: Math.round(totalPoints * 100) / 100,
            totalCoefficients,
            isAdmis: moyenneGenerale >= 10,
            mention: computeMention(moyenneGenerale),
            subjects: subjectResults,
            publishedAt: now,
            lastSubmittedAt: lastSubmittedAtMs > 0
                ? admin.firestore.Timestamp.fromMillis(lastSubmittedAtMs)
                : now,
        });
    }
    catch (err) {
        v2_1.logger.warn('tryComputeStudentResult échoué (best-effort)', { sessionId, userId, err });
    }
}
// ─── Helpers ──────────────────────────────────────────────────────────────────
function computeMention(moyenne) {
    if (moyenne >= 16)
        return 'Très Bien';
    if (moyenne >= 14)
        return 'Bien';
    if (moyenne >= 12)
        return 'Assez Bien';
    if (moyenne >= 10)
        return 'Passable';
    return 'Insuffisant';
}
async function sendBatchNotifications(userIds, sessionId) {
    const CHUNK = 100;
    for (let i = 0; i < userIds.length; i += CHUNK) {
        const chunk = userIds.slice(i, i + CHUNK);
        const snaps = await Promise.all(chunk.map((uid) => firestore_1.collections.user(uid).get()));
        const messages = snaps
            .map((s) => s.data()?.['fcmToken'])
            .filter(Boolean)
            .map((token) => ({
            token: token,
            notification: {
                title: 'Ton bulletin est disponible !',
                body: 'Consulte ta moyenne et tes notes dans ExamSim Congo.',
            },
            data: { type: 'results_published', sessionId },
            android: { priority: 'high' },
            apns: { payload: { aps: { badge: 1 } } },
        }));
        if (messages.length > 0) {
            const res = await admin.messaging().sendEach(messages);
            v2_1.logger.info(`FCM: ${res.successCount}/${messages.length}`);
        }
    }
}
async function notifyStudent(userId, subjectName, score, maxScore) {
    try {
        const snap = await firestore_1.collections.user(userId).get();
        const token = snap.data()?.['fcmToken'];
        if (!token)
            return;
        await admin.messaging().send({
            token,
            notification: { title: `Résultat — ${subjectName}`, body: `Ta note : ${score}/${maxScore}` },
            data: { type: 'result_published', subjectName },
            android: { priority: 'high' },
            apns: { payload: { aps: { badge: 1 } } },
        });
    }
    catch (_) { /* non bloquant */ }
}
//# sourceMappingURL=publishResults.js.map