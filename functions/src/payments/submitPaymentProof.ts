import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { collections } from '../lib/firestore';

interface SubmitPaymentPayload {
  sessionId: string;
  proofFileRef: string;
}

export const submitPaymentProof = onCall<SubmitPaymentPayload>({ invoker: 'public' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentification requise.');
  }

  const { sessionId, proofFileRef } = request.data;
  if (!sessionId || !proofFileRef) {
    throw new HttpsError('invalid-argument', 'sessionId et proofFileRef sont requis.');
  }

  const userId = request.auth.uid;

  // Vérifier qu'il n'existe pas déjà un paiement pending ou approved
  const existingSnap = await collections
    .payments()
    .where('userId', '==', userId)
    .where('sessionId', '==', sessionId)
    .where('status', 'in', ['pending', 'approved'])
    .limit(1)
    .get();

  if (!existingSnap.empty) {
    const existing = existingSnap.docs[0].data();
    if (existing['status'] === 'approved') {
      throw new HttpsError('already-exists', 'Accès déjà accordé pour cette session.');
    }
    throw new HttpsError('already-exists', 'Une demande est déjà en attente de validation.');
  }

  // Récupérer le titre et le prix de la session
  const sessionSnap = await collections.session(sessionId).get();
  if (!sessionSnap.exists) {
    throw new HttpsError('not-found', 'Session introuvable.');
  }
  const sessionData = sessionSnap.data()!;

  await collections.payments().add({
    userId,
    sessionId,
    sessionTitle: sessionData['title'] ?? '',
    amount: sessionData['price'] ?? 0,
    proofFileRef,
    status: 'pending',
    submittedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { success: true };
});
