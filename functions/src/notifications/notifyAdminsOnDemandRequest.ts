import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import * as admin from 'firebase-admin';
import { logger } from 'firebase-functions/v2';
import { collections } from '../lib/firestore';

export const notifyAdminsOnDemandRequest = onDocumentCreated(
  { document: 'sessions/{sessionId}', region: 'europe-west1' },
  async (event) => {
    const data = event.data?.data();
    if (!data || data['isOnDemand'] !== true) return;

    const adminsSnap = await collections.users().where('role', '==', 'admin').get();
    const tokens = adminsSnap.docs
      .map((d) => d.data()['fcmToken'] as string | undefined)
      .filter((t): t is string => !!t);

    if (tokens.length === 0) {
      logger.info('notifyAdminsOnDemandRequest: aucun admin avec token FCM.');
      return;
    }

    const startDate = (data['startDate'] as admin.firestore.Timestamp | undefined)?.toDate();
    const dateLabel = startDate ? startDate.toLocaleDateString('fr-FR') : '';

    const message: admin.messaging.MulticastMessage = {
      tokens,
      notification: {
        title: '🆕 Session à la demande',
        body: `${data['title']} — à composer avant le ${dateLabel}.`,
      },
      data: { type: 'on_demand_session_requested', sessionId: event.params.sessionId },
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } },
    };

    const result = await admin.messaging().sendEachForMulticast(message);
    logger.info(`notifyAdminsOnDemandRequest: ${result.successCount}/${tokens.length} envoyé(s).`);
  },
);
