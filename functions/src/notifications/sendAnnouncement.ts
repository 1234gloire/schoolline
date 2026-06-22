import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { logger } from 'firebase-functions/v2';
import { collections } from '../lib/firestore';

type Audience = 'all' | 'troisieme' | 'terminale';

interface SendAnnouncementPayload {
  title: string;
  body: string;
  audience?: Audience;
  series?: string; // filtre optionnel (séries Terminale : A, C, D…)
}

// sendEachForMulticast accepte au maximum 500 tokens par appel.
const FCM_BATCH_SIZE = 500;

export const sendAnnouncement = onCall<SendAnnouncementPayload>(
  { invoker: 'public', region: 'europe-west1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Authentification requise.');
    }

    const callerSnap = await collections.user(request.auth.uid).get();
    const callerData = callerSnap.data();
    if (callerData?.['role'] !== 'admin') {
      throw new HttpsError('permission-denied', 'Réservé aux admins.');
    }

    const title = request.data.title?.trim();
    const body = request.data.body?.trim();
    const audience: Audience = request.data.audience ?? 'all';
    const series = request.data.series?.trim().toUpperCase();

    if (!title || !body) {
      throw new HttpsError('invalid-argument', 'Le titre et le message sont requis.');
    }
    if (title.length > 80) {
      throw new HttpsError('invalid-argument', 'Le titre ne doit pas dépasser 80 caractères.');
    }
    if (body.length > 500) {
      throw new HttpsError('invalid-argument', 'Le message ne doit pas dépasser 500 caractères.');
    }

    // ── Sélection des destinataires (élèves uniquement) ──
    let query: admin.firestore.Query = collections.users().where('role', '==', 'student');
    if (audience === 'troisieme' || audience === 'terminale') {
      query = query.where('class', '==', audience);
    }

    const usersSnap = await query.get();

    const recipientDocs = usersSnap.docs.filter((doc) => {
      const d = doc.data();
      if (!d['fcmToken']) return false;
      // Filtre série uniquement pour la Terminale
      if (audience === 'terminale' && series) {
        const userSeries = (d['series'] as string | undefined)?.trim().toUpperCase() ?? '';
        return userSeries === series;
      }
      return true;
    });

    const tokens = recipientDocs.map((doc) => doc.data()['fcmToken'] as string);

    // ── Archivage de l'annonce (historique) ──
    const announcementRef = collections.announcements().doc();
    const baseRecord = {
      title,
      body,
      audience,
      series: audience === 'terminale' ? series ?? null : null,
      sentBy: request.auth.uid,
      sentByName: (callerData?.['displayName'] as string | undefined) ?? '',
      recipientCount: tokens.length,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (tokens.length === 0) {
      await announcementRef.set({ ...baseRecord, successCount: 0 });
      logger.info('sendAnnouncement: aucun destinataire avec token FCM.');
      return { recipientCount: 0, successCount: 0 };
    }

    // ── Envoi par lots de 500 ──
    let successCount = 0;
    const allResponses: admin.messaging.SendResponse[] = [];

    for (let i = 0; i < tokens.length; i += FCM_BATCH_SIZE) {
      const batchTokens = tokens.slice(i, i + FCM_BATCH_SIZE);
      const message: admin.messaging.MulticastMessage = {
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

    logger.info(
      `sendAnnouncement [${audience}${series ? '/' + series : ''}]: ` +
      `${successCount}/${tokens.length} envoyé(s).`
    );

    return { recipientCount: tokens.length, successCount };
  }
);

// Supprime les tokens FCM devenus invalides des documents utilisateurs
async function cleanupInvalidTokens(
  responses: admin.messaging.SendResponse[],
  tokens: string[],
  userDocs: admin.firestore.QueryDocumentSnapshot[]
): Promise<void> {
  const invalidTokens = new Set<string>();

  responses.forEach((resp, idx) => {
    const code = resp.error?.code ?? '';
    if (
      !resp.success &&
      (code === 'messaging/invalid-registration-token' ||
        code === 'messaging/registration-token-not-registered')
    ) {
      invalidTokens.add(tokens[idx]);
    }
  });

  if (invalidTokens.size === 0) return;

  const batch = admin.firestore().batch();
  userDocs.forEach((userDoc) => {
    const token = userDoc.data()['fcmToken'] as string | undefined;
    if (token && invalidTokens.has(token)) {
      batch.update(userDoc.ref, {
        fcmToken: admin.firestore.FieldValue.delete(),
      });
    }
  });

  await batch.commit();
  logger.info(`sendAnnouncement: ${invalidTokens.size} token(s) FCM invalide(s) nettoyé(s).`);
}
