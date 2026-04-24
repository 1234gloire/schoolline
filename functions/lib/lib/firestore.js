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
exports.collections = exports.db = void 0;
exports.getAvailableCorrector = getAvailableCorrector;
exports.incrementCorrectorLoad = incrementCorrectorLoad;
exports.decrementCorrectorLoad = decrementCorrectorLoad;
const admin = __importStar(require("firebase-admin"));
// ─── Références Firestore centralisées ───
exports.db = admin.firestore();
exports.collections = {
    users: () => exports.db.collection('users'),
    user: (uid) => exports.db.collection('users').doc(uid),
    sessions: () => exports.db.collection('sessions'),
    session: (sessionId) => exports.db.collection('sessions').doc(sessionId),
    subjects: (sessionId) => exports.db.collection('sessions').doc(sessionId).collection('subjects'),
    subject: (sessionId, subjectId) => exports.db.collection('sessions').doc(sessionId).collection('subjects').doc(subjectId),
    submissions: () => exports.db.collection('submissions'),
    submission: (submissionId) => exports.db.collection('submissions').doc(submissionId),
    payments: () => exports.db.collection('payments'),
    payment: (paymentId) => exports.db.collection('payments').doc(paymentId),
    studentResults: (sessionId) => exports.db.collection('sessions').doc(sessionId).collection('studentResults'),
    studentResult: (sessionId, userId) => exports.db.collection('sessions').doc(sessionId).collection('studentResults').doc(userId),
};
// ─── Helpers ───
async function getAvailableCorrector() {
    const snap = await exports.collections
        .users()
        .where('role', '==', 'corrector')
        .get();
    if (snap.empty)
        return null;
    const corrector = snap.docs
        .map((doc) => ({
        id: doc.id,
        activeCorrections: Number(doc.data()['activeCorrections'] ?? 0),
        createdAt: typeof doc.data()['createdAt']?.toMillis === 'function'
            ? doc.data()['createdAt'].toMillis()
            : 0,
    }))
        .sort((a, b) => {
        if (a.activeCorrections != b.activeCorrections) {
            return a.activeCorrections - b.activeCorrections;
        }
        return a.createdAt - b.createdAt;
    })[0];
    return corrector?.id ?? null;
}
async function incrementCorrectorLoad(correctorId) {
    await exports.collections.user(correctorId).update({
        activeCorrections: admin.firestore.FieldValue.increment(1),
    });
}
async function decrementCorrectorLoad(correctorId) {
    await exports.db.runTransaction(async (transaction) => {
        const ref = exports.collections.user(correctorId);
        const snap = await transaction.get(ref);
        if (!snap.exists) {
            return;
        }
        const current = Number(snap.data()?.['activeCorrections'] ?? 0);
        transaction.update(ref, {
            activeCorrections: Math.max(0, current - 1),
        });
    });
}
//# sourceMappingURL=firestore.js.map