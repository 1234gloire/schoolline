import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as admin from 'firebase-admin';
import { logger } from 'firebase-functions/v2';
import { collections } from '../lib/firestore';

/**
 * Cron toutes les 15 minutes.
 * Ferme automatiquement les sessions dont la dernière épreuve est terminée
 * depuis plus de 15 minutes (pour laisser le temps aux soumissions tardives).
 *
 * Transitions :
 *   open   → closed  (si toutes les épreuves sont terminées)
 *   active → closed  (idem)
 */
export const autoCloseSessions = onSchedule(
  {
    schedule: 'every 15 minutes',
    region: 'europe-west1',
  },
  async () => {
    const now = admin.firestore.Timestamp.now();
    const gracePeriodMs = 15 * 60 * 1000; // 15 min après la fin de la dernière épreuve

    // Récupérer toutes les sessions ouvertes ou actives
    const snap = await collections
      .sessions()
      .where('status', 'in', ['open', 'active'])
      .get();

    if (snap.empty) {
      logger.info('autoCloseSessions: aucune session active ou ouverte.');
      return;
    }

    logger.info(`autoCloseSessions: ${snap.docs.length} session(s) à vérifier.`);

    const batch = admin.firestore().batch();
    let closedCount = 0;

    for (const sessionDoc of snap.docs) {
      const sessionId = sessionDoc.id;

      try {
        // Récupérer toutes les épreuves de la session
        const subjectsSnap = await collections.subjects(sessionId).get();

        if (subjectsSnap.empty) {
          // Pas d'épreuves → fermer si endDate dépassée (fallback sur le champ session)
          const sessionData = sessionDoc.data();
          const sessionEndDate = sessionData['endDate'] as admin.firestore.Timestamp | undefined;
          if (sessionEndDate && sessionEndDate.toMillis() + gracePeriodMs < now.toMillis()) {
            batch.update(sessionDoc.ref, {
              status: 'closed',
              closedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            closedCount++;
            logger.info(`Session ${sessionId} fermée (pas d'épreuves, endDate dépassée).`);
          }
          continue;
        }

        // Trouver la date de fin la plus tardive parmi toutes les épreuves
        let latestEndMs = 0;
        for (const subjectDoc of subjectsSnap.docs) {
          const endTime = subjectDoc.data()['endTime'] as admin.firestore.Timestamp | undefined;
          if (endTime && endTime.toMillis() > latestEndMs) {
            latestEndMs = endTime.toMillis();
          }
        }

        if (latestEndMs === 0) continue; // endTime manquant sur toutes les épreuves

        const deadline = latestEndMs + gracePeriodMs;
        if (now.toMillis() > deadline) {
          batch.update(sessionDoc.ref, {
            status: 'closed',
            closedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          closedCount++;
          logger.info(
            `Session ${sessionId} fermée (dernière épreuve terminée à ${new Date(latestEndMs).toISOString()}).`
          );
        }
      } catch (err) {
        logger.error(`Erreur lors du traitement de la session ${sessionId}`, err);
      }
    }

    if (closedCount > 0) {
      await batch.commit();
      logger.info(`autoCloseSessions: ${closedCount} session(s) fermée(s).`);
    } else {
      logger.info('autoCloseSessions: aucune session à fermer pour l\'instant.');
    }
  }
);
