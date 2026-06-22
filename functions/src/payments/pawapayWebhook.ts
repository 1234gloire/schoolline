import { onRequest } from 'firebase-functions/v2/https';
import { collections } from '../lib/firestore';
import { finalizeApproved, finalizeRejected, mapFailureReason } from './pawapayShared';

interface PawapayCallbackBody {
  depositId?: string;
  status?: string;
  failureReason?: { failureCode?: string };
}

export const pawapayWebhook = onRequest(
  { region: 'europe-west1', invoker: 'public' },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).send('Method Not Allowed');
      return;
    }

    const body = req.body as PawapayCallbackBody;
    const depositId = body.depositId;
    if (!depositId) {
      res.status(400).json({ error: 'depositId manquant' });
      return;
    }

    const snap = await collections
      .payments()
      .where('transKey', '==', depositId)
      .where('provider', '==', 'pawapay')
      .limit(1)
      .get();

    if (snap.empty) {
      res.status(200).json({ ok: true, note: 'transaction inconnue' });
      return;
    }

    const paymentDoc = snap.docs[0];
    const payment = paymentDoc.data();
    if (payment['status'] === 'approved' || payment['status'] === 'rejected') {
      res.status(200).json({ ok: true, note: 'déjà traité' });
      return;
    }

    if (body.status === 'COMPLETED') {
      await finalizeApproved(paymentDoc.ref, payment, depositId);
    } else if (body.status === 'FAILED') {
      await finalizeRejected(
        paymentDoc.ref,
        payment,
        depositId,
        mapFailureReason(body.failureReason?.failureCode),
      );
    }

    res.status(200).json({ ok: true });
  },
);
