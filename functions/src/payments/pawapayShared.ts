import * as admin from 'firebase-admin';
import { collections } from '../lib/firestore';

export async function finalizeApproved(
  paymentRef: FirebaseFirestore.DocumentReference,
  payment: FirebaseFirestore.DocumentData,
  providerRef: string,
): Promise<{ status: 'approved' }> {
  await paymentRef.update({
    status: 'approved',
    reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
    providerRef,
  });
  await collections.user(payment['userId'] as string).update({
    subscriptions: admin.firestore.FieldValue.arrayUnion(payment['sessionId']),
  });
  await notifyStudent(
    payment['userId'] as string,
    '✅ Paiement confirmé',
    `Ton accès à "${payment['sessionTitle']}" est maintenant actif !`,
    'payment_approved',
  );
  return { status: 'approved' };
}

export async function finalizeRejected(
  paymentRef: FirebaseFirestore.DocumentReference,
  payment: FirebaseFirestore.DocumentData,
  providerRef: string,
  reason: string,
): Promise<{ status: 'rejected'; reason: string }> {
  await paymentRef.update({
    status: 'rejected',
    reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
    providerRef,
    rejectionReason: reason,
  });
  await notifyStudent(
    payment['userId'] as string,
    'Paiement non abouti',
    `Le paiement pour "${payment['sessionTitle']}" a échoué. Réessaie.`,
    'payment_rejected',
  );
  return { status: 'rejected', reason };
}

export function mapFailureReason(code?: string): string {
  switch (code) {
    case 'PAYER_NOT_FOUND':
      return 'Numéro introuvable. Vérifie ton numéro Mobile Money.';
    case 'PAYMENT_NOT_APPROVED':
      return "Tu n'as pas validé la demande de paiement à temps.";
    case 'PAYER_LIMIT_REACHED':
    case 'WALLET_LIMIT_REACHED':
      return 'Limite de transaction atteinte sur ton compte Mobile Money.';
    case 'INSUFFICIENT_BALANCE':
      return 'Solde insuffisant. Recharge ton compte Mobile Money et réessaie.';
    default:
      return 'La transaction a échoué. Réessaie.';
  }
}

export async function notifyStudent(
  userId: string,
  title: string,
  body: string,
  type: string,
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
