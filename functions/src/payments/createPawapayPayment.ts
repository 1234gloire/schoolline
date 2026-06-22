import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { randomUUID } from 'node:crypto';
import { collections } from '../lib/firestore';
import { mapFailureReason } from './pawapayShared';

interface CreatePawapayPaymentPayload {
  sessionId: string;
  /** Saisie brute de l'utilisateur, avec ou sans indicatif (242). */
  phoneNumber: string;
}

const PAWAPAY_BASE_URL = 'https://api.pawapay.io/v2';

export const createPawapayPayment = onCall<CreatePawapayPaymentPayload>(
  { invoker: 'public', region: 'europe-west1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Authentification requise.');
    }

    const { sessionId, phoneNumber: rawPhone } = request.data;
    const uid = request.auth.uid;
    if (!sessionId || !rawPhone) {
      throw new HttpsError('invalid-argument', 'sessionId et phoneNumber requis.');
    }

    const userSnap = await collections.user(uid).get();
    const userData = userSnap.data() ?? {};
    const subscriptions = (userData['subscriptions'] as string[]) ?? [];
    if (subscriptions.includes(sessionId)) {
      throw new HttpsError('already-exists', 'Tu as déjà accès à cette session.');
    }

    const sessionSnap = await collections.session(sessionId).get();
    if (!sessionSnap.exists) {
      throw new HttpsError('not-found', 'Session introuvable.');
    }
    const session = sessionSnap.data()!;

    const startDate = session['startDate'] as admin.firestore.Timestamp | undefined;
    if (startDate && startDate.toMillis() <= Date.now()) {
      throw new HttpsError(
        'failed-precondition',
        'Les inscriptions sont closes : cette session a déjà commencé.',
      );
    }

    const amount = Math.round(Number(session['price']) || 0);
    if (amount < 1) {
      throw new HttpsError('failed-precondition', 'Montant invalide.');
    }

    const apiToken = process.env.PAWAPAY_API_TOKEN;
    if (!apiToken) {
      throw new HttpsError('internal', 'Paiement Mobile Money indisponible pour le moment.');
    }

    // Normalisation minimale (indicatif Congo) puis validation/détection de
    // l'opérateur via predict-provider, recommandé par pawaPay pour éviter
    // les rejets liés au format du numéro.
    const digits = rawPhone.replace(/\D/g, '');
    const local = digits.startsWith('242') ? digits.slice(3) : digits;
    const withoutLeadingZero = local.startsWith('0') ? local.slice(1) : local;
    const candidate = `242${withoutLeadingZero}`;

    let predictResponse: Response;
    try {
      predictResponse = await fetch(`${PAWAPAY_BASE_URL}/predict-provider`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${apiToken}`,
        },
        body: JSON.stringify({ phoneNumber: candidate }),
      });
    } catch (_) {
      throw new HttpsError('unavailable', 'Impossible de contacter le service de paiement.');
    }

    const predicted = (await predictResponse.json().catch(() => null)) as
      | { country?: string; provider?: string; phoneNumber?: string }
      | null;

    if (
      !predictResponse.ok ||
      !predicted?.provider ||
      !predicted?.phoneNumber ||
      predicted.country !== 'COG'
    ) {
      throw new HttpsError(
        'invalid-argument',
        'Numéro Mobile Money invalide pour le Congo. Vérifie ton numéro.',
      );
    }

    const depositId = randomUUID();

    let response: Response;
    try {
      response = await fetch(`${PAWAPAY_BASE_URL}/deposits`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${apiToken}`,
        },
        body: JSON.stringify({
          depositId,
          payer: {
            type: 'MMO',
            accountDetails: {
              phoneNumber: predicted.phoneNumber,
              provider: predicted.provider,
            },
          },
          amount: String(amount),
          currency: 'XAF',
          customerMessage: 'Paiement ExamSim',
        }),
      });
    } catch (_) {
      throw new HttpsError('unavailable', 'Impossible de contacter le service de paiement.');
    }

    const data = (await response.json().catch(() => null)) as
      | {
          status?: string;
          failureReason?: { failureCode?: string; failureMessage?: string };
        }
      | null;

    if (!response.ok || data?.status !== 'ACCEPTED') {
      throw new HttpsError(
        'unavailable',
        data?.failureReason?.failureCode
          ? mapFailureReason(data.failureReason.failureCode)
          : 'Le paiement a été refusé. Vérifie ton numéro et réessaie.',
      );
    }

    // Réutilise le document pending existant pour cette session, sinon en crée un.
    const existingSnap = await collections
      .payments()
      .where('userId', '==', uid)
      .where('sessionId', '==', sessionId)
      .where('provider', '==', 'pawapay')
      .where('status', '==', 'pending')
      .limit(1)
      .get();

    const paymentData = {
      userId: uid,
      sessionId,
      sessionTitle: session['title'] ?? '',
      amount,
      provider: 'pawapay',
      transKey: depositId,
      proofFileRef: '',
      status: 'pending',
      submittedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    let paymentId: string;
    if (!existingSnap.empty) {
      paymentId = existingSnap.docs[0].id;
      await existingSnap.docs[0].ref.set(paymentData, { merge: true });
    } else {
      const ref = await collections.payments().add(paymentData);
      paymentId = ref.id;
    }

    return { paymentId, depositId, amount };
  },
);
