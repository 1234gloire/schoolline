import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { collections } from '../lib/firestore';

interface ValidatePaymentPayload {
  paymentId: string;
  approved: boolean;
  rejectionReason?: string;
}

export const validatePayment = onCall<ValidatePaymentPayload>({ invoker: 'public' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentification requise.');
  }

  const callerSnap = await collections.user(request.auth.uid).get();
  if (callerSnap.data()?.['role'] !== 'admin') {
    throw new HttpsError('permission-denied', 'Réservé aux admins.');
  }

  const { paymentId, approved, rejectionReason } = request.data;
  if (!paymentId) {
    throw new HttpsError('invalid-argument', 'paymentId requis.');
  }

  const paymentRef = collections.payment(paymentId);
  const paymentSnap = await paymentRef.get();
  if (!paymentSnap.exists) {
    throw new HttpsError('not-found', 'Paiement introuvable.');
  }

  const payment = paymentSnap.data()!;
  if (payment['status'] !== 'pending') {
    throw new HttpsError('failed-precondition', `Paiement déjà traité : ${payment['status']}`);
  }

  const now = admin.firestore.FieldValue.serverTimestamp();

  if (approved) {
    await paymentRef.update({
      status: 'approved',
      reviewedAt: now,
      reviewedBy: request.auth.uid,
    });

    // Débloquer la session pour l'élève
    await collections.user(payment['userId'] as string).update({
      subscriptions: admin.firestore.FieldValue.arrayUnion(payment['sessionId']),
    });

    await notifyStudent(
      payment['userId'] as string,
      '✅ Paiement validé',
      `Ton accès à "${payment['sessionTitle']}" est maintenant actif. Bonne session !`,
      'payment_approved'
    );
  } else {
    await paymentRef.update({
      status: 'rejected',
      reviewedAt: now,
      reviewedBy: request.auth.uid,
      rejectionReason: rejectionReason?.trim() ?? '',
    });

    await notifyStudent(
      payment['userId'] as string,
      'Paiement non validé',
      rejectionReason?.trim() || `Ton paiement pour "${payment['sessionTitle']}" n'a pas pu être validé. Réessaie.`,
      'payment_rejected'
    );
  }

  return { success: true };
});

async function notifyStudent(
  userId: string,
  title: string,
  body: string,
  type: string
): Promise<void> {
  try {
    const snap = await collections.user(userId).get();
    const token = snap.data()?.['fcmToken'] as string | undefined;
    if (!token) return;
    await admin.messaging().send({
      token,
      notification: { title, body },
      data: { type },
      android: { priority: 'high' },
      apns: { payload: { aps: { badge: 1 } } },
    });
  } catch (_) {
    // Non bloquant
  }
}
