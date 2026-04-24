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
exports.publishResults = (0, https_1.onCall)(async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Authentification requise.');
    const callerSnap = await firestore_1.collections.user(request.auth.uid).get();
    if (callerSnap.data()?.['role'] !== 'admin') {
        throw new https_1.HttpsError('permission-denied', 'Réservé aux admins.');
    }
    const { sessionId } = request.data;
    if (!sessionId)
        throw new https_1.HttpsError('invalid-argument', 'sessionId requis.');
    const snap = await firestore_1.collections
        .submissions()
        .where('sessionId', '==', sessionId)
        .where('status', '==', 'humanReviewed')
        .get();
    if (snap.empty)
        return { success: true, published: 0 };
    const batch = admin.firestore().batch();
    const now = admin.firestore.FieldValue.serverTimestamp();
    const userIds = [];
    for (const doc of snap.docs) {
        batch.update(doc.ref, { status: 'published', publishedAt: now, statusUpdatedAt: now });
        userIds.push(doc.data()['userId']);
    }
    await batch.commit();
    await firestore_1.collections.session(sessionId).update({ status: 'resultsPublished' });
    await sendBatchNotifications(userIds, sessionId);
    v2_1.logger.info(`Publication: ${snap.size} copies`, { sessionId });
    return { success: true, published: snap.size };
});
exports.publishSingleResult = (0, https_1.onCall)(async (request) => {
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
    });
    await notifyStudent(data['userId'], data['subjectName'], data['finalScore'] ?? data['aiScore'], data['subjectMaxScore'] ?? 20);
    return { success: true, submissionId };
});
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
                title: 'Tes résultats sont disponibles !',
                body: "Consulte tes notes dans l'application ExamSim Congo.",
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