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
exports.autoCloseSessions = void 0;
const scheduler_1 = require("firebase-functions/v2/scheduler");
const admin = __importStar(require("firebase-admin"));
const v2_1 = require("firebase-functions/v2");
const firestore_1 = require("../lib/firestore");
/**
 * Cron toutes les 15 minutes.
 * Ferme automatiquement les sessions dont la dernière épreuve est terminée
 * depuis plus de 15 minutes (pour laisser le temps aux soumissions tardives).
 *
 * Transitions :
 *   open   → closed  (si toutes les épreuves sont terminées)
 *   active → closed  (idem)
 */
exports.autoCloseSessions = (0, scheduler_1.onSchedule)({
    schedule: 'every 15 minutes',
    region: 'europe-west1',
}, async () => {
    const now = admin.firestore.Timestamp.now();
    const gracePeriodMs = 15 * 60 * 1000; // 15 min après la fin de la dernière épreuve
    // Récupérer toutes les sessions ouvertes ou actives
    const snap = await firestore_1.collections
        .sessions()
        .where('status', 'in', ['open', 'active'])
        .get();
    if (snap.empty) {
        v2_1.logger.info('autoCloseSessions: aucune session active ou ouverte.');
        return;
    }
    v2_1.logger.info(`autoCloseSessions: ${snap.docs.length} session(s) à vérifier.`);
    const batch = admin.firestore().batch();
    let closedCount = 0;
    for (const sessionDoc of snap.docs) {
        const sessionId = sessionDoc.id;
        try {
            // Récupérer toutes les épreuves de la session
            const subjectsSnap = await firestore_1.collections.subjects(sessionId).get();
            if (subjectsSnap.empty) {
                // Pas d'épreuves → fermer si endDate dépassée (fallback sur le champ session)
                const sessionData = sessionDoc.data();
                const sessionEndDate = sessionData['endDate'];
                if (sessionEndDate && sessionEndDate.toMillis() + gracePeriodMs < now.toMillis()) {
                    batch.update(sessionDoc.ref, {
                        status: 'closed',
                        closedAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                    closedCount++;
                    v2_1.logger.info(`Session ${sessionId} fermée (pas d'épreuves, endDate dépassée).`);
                }
                continue;
            }
            // Trouver la date de fin la plus tardive parmi toutes les épreuves
            let latestEndMs = 0;
            for (const subjectDoc of subjectsSnap.docs) {
                const endTime = subjectDoc.data()['endTime'];
                if (endTime && endTime.toMillis() > latestEndMs) {
                    latestEndMs = endTime.toMillis();
                }
            }
            if (latestEndMs === 0)
                continue; // endTime manquant sur toutes les épreuves
            const deadline = latestEndMs + gracePeriodMs;
            if (now.toMillis() > deadline) {
                batch.update(sessionDoc.ref, {
                    status: 'closed',
                    closedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                closedCount++;
                v2_1.logger.info(`Session ${sessionId} fermée (dernière épreuve terminée à ${new Date(latestEndMs).toISOString()}).`);
            }
        }
        catch (err) {
            v2_1.logger.error(`Erreur lors du traitement de la session ${sessionId}`, err);
        }
    }
    if (closedCount > 0) {
        await batch.commit();
        v2_1.logger.info(`autoCloseSessions: ${closedCount} session(s) fermée(s).`);
    }
    else {
        v2_1.logger.info('autoCloseSessions: aucune session à fermer pour l\'instant.');
    }
});
//# sourceMappingURL=autoCloseSessions.js.map