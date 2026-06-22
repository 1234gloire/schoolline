import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { collections } from '../lib/firestore';
import { finalizeApproved, finalizeRejected, mapFailureReason } from './pawapayShared';

const PAWAPAY_BASE_URL = 'https://api.pawapay.io/v2';

interface CheckPawapayPaymentStatusPayload {
  paymentId: string;
}

export const checkPawapayPaymentStatus = onCall<CheckPawapayPaymentStatusPayload>(
  { invoker: 'public', region: 'europe-west1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Authentification requise.');
    }

    const { paymentId } = request.data;
    if (!paymentId) {
      throw new HttpsError('invalid-argument', 'paymentId requis.');
    }

    const paymentRef = collections.payment(paymentId);
    const snap = await paymentRef.get();
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Paiement introuvable.');
    }
    const payment = snap.data()!;
    if (payment['userId'] !== request.auth.uid) {
      throw new HttpsError('permission-denied', "Ce paiement ne t'appartient pas.");
    }

    if (payment['status'] === 'approved') {
      return { status: 'approved' };
    }
    if (payment['status'] === 'rejected') {
      return { status: 'rejected', reason: payment['rejectionReason'] ?? null };
    }

    const apiToken = process.env.PAWAPAY_API_TOKEN;
    const depositId = payment['transKey'] as string | undefined;
    if (!apiToken || !depositId) {
      return { status: 'pending' };
    }

    let response: Response;
    try {
      response = await fetch(`${PAWAPAY_BASE_URL}/deposits/${depositId}`, {
        headers: { Authorization: `Bearer ${apiToken}` },
      });
    } catch (_) {
      return { status: 'pending' };
    }

    const body = (await response.json().catch(() => null)) as
      | {
          status?: string;
          data?: { status?: string; failureReason?: { failureCode?: string } };
        }
      | null;

    if (body?.status !== 'FOUND' || !body.data) {
      return { status: 'pending' };
    }

    if (body.data.status === 'COMPLETED') {
      return finalizeApproved(paymentRef, payment, depositId);
    }
    if (body.data.status === 'FAILED') {
      const reason = mapFailureReason(body.data.failureReason?.failureCode);
      return finalizeRejected(paymentRef, payment, depositId, reason);
    }

    return { status: 'pending' };
  },
);
