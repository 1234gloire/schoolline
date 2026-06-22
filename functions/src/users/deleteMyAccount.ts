import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { getAuth } from 'firebase-admin/auth';
import { collections } from '../lib/firestore';

export const deleteMyAccount = onCall(
  { invoker: 'public', region: 'europe-west1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Authentification requise.');
    }

    const uid = request.auth.uid;
    const userRef = collections.user(uid);
    const userSnap = await userRef.get();
    const user = userSnap.data();

    if (user?.['role'] === 'admin' || user?.['role'] === 'corrector') {
      throw new HttpsError(
        'failed-precondition',
        'Les comptes staff doivent être supprimés depuis l’administration.',
      );
    }

    const now = admin.firestore.FieldValue.serverTimestamp();

    await userRef.set(
      {
        displayName: 'Compte supprimé',
        email: '',
        phone: '',
        school: '',
        avatarUrl: '',
        fcmToken: admin.firestore.FieldValue.delete(),
        blocked: true,
        deleted: true,
        deletedAt: now,
        subscriptions: [],
      },
      { merge: true },
    );

    try {
      await getAuth().deleteUser(uid);
    } catch (error) {
      console.error('deleteMyAccount auth delete failed', { uid, error });
      throw new HttpsError(
        'internal',
        'Impossible de supprimer le compte d’authentification.',
      );
    }

    return { ok: true };
  },
);
