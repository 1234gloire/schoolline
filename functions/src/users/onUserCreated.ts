import { onRequest } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { logger } from 'firebase-functions/v2';
import { collections } from '../lib/firestore';
import { getAuth } from 'firebase-admin/auth';

/**
 * Appelée via une tâche planifiée ou hook Auth pour créer le profil Firestore.
 * Note: Firebase Functions v2 Auth triggers utilisent onCall ou eventarc.
 * Ici on expose un endpoint HTTP appelé par la Cloud Task déclenchée à la création.
 */
export const onUserCreated = onRequest(async (req, res) => {
  if (req.method !== 'POST') { res.status(405).send('Method Not Allowed'); return; }

  const { uid } = req.body as { uid?: string };
  if (!uid) { res.status(400).send('uid requis'); return; }

  try {
    const existing = await collections.user(uid).get();
    if (existing.exists) { res.json({ skipped: true }); return; }

    const authUser = await getAuth().getUser(uid);

    await collections.user(uid).set({
      uid,
      displayName: authUser.displayName ?? authUser.email ?? 'Utilisateur',
      email: authUser.email ?? '',
      phone: authUser.phoneNumber ?? '',
      role: 'student',
      series: '',
      school: '',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      subscriptions: [],
      abandonedSubjectIds: [],
      activeCorrections: 0,
    });

    logger.info(`Profil créé: ${uid}`);
    res.json({ success: true });
  } catch (err) {
    logger.error('Erreur onUserCreated', err);
    res.status(500).json({ error: String(err) });
  }
});
