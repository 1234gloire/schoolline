import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { collections } from '../lib/firestore';

interface RequestOnDemandSessionPayload {
  startDate: string; // ISO
  endDate: string; // ISO
  visibility: 'public' | 'private';
}

const MIN_LEAD_TIME_MS = 48 * 60 * 60 * 1000;

export const requestOnDemandSession = onCall<RequestOnDemandSessionPayload>(
  { invoker: 'public', region: 'europe-west1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Authentification requise.');
    }

    const { startDate: rawStart, endDate: rawEnd, visibility } = request.data;
    if (!rawStart || !rawEnd) {
      throw new HttpsError('invalid-argument', 'startDate et endDate sont requis.');
    }
    if (visibility !== 'public' && visibility !== 'private') {
      throw new HttpsError('invalid-argument', "visibility doit être 'public' ou 'private'.");
    }

    const startDate = new Date(rawStart);
    const endDate = new Date(rawEnd);
    if (Number.isNaN(startDate.getTime()) || Number.isNaN(endDate.getTime())) {
      throw new HttpsError('invalid-argument', 'Dates invalides.');
    }
    if (endDate.getTime() <= startDate.getTime()) {
      throw new HttpsError('invalid-argument', 'La date de fin doit être après la date de début.');
    }

    const uid = request.auth.uid;
    const userSnap = await collections.user(uid).get();
    const userData = userSnap.data();
    if (!userSnap.exists || !userData) {
      throw new HttpsError('not-found', 'Profil utilisateur introuvable.');
    }
    if (userData['role'] !== 'student') {
      throw new HttpsError('permission-denied', 'Réservé aux élèves.');
    }

    const displayName = (userData['displayName'] as string | undefined)?.trim() ?? '';
    const phone = (userData['phone'] as string | undefined)?.trim() ?? '';
    const school = (userData['school'] as string | undefined)?.trim() ?? '';
    const studentClass = userData['class'] as string | undefined;
    const series = (userData['series'] as string | undefined)?.trim() ?? '';

    const missing: string[] = [];
    if (!displayName) missing.push('nom complet');
    if (!phone) missing.push('téléphone');
    if (!school) missing.push('établissement');
    if (!studentClass) missing.push('classe');
    if (studentClass === 'terminale' && !series) missing.push('série');

    if (missing.length > 0) {
      throw new HttpsError(
        'failed-precondition',
        `Profil incomplet : ${missing.join(', ')}.`,
      );
    }

    // Temps serveur uniquement — ne jamais faire confiance à l'horloge du client.
    if (startDate.getTime() - Date.now() < MIN_LEAD_TIME_MS) {
      throw new HttpsError(
        'failed-precondition',
        'La date de début doit être au moins 48h après la demande.',
      );
    }

    const pendingSnap = await collections
      .sessions()
      .where('requestedBy', '==', uid)
      .where('status', 'in', ['draft', 'open'])
      .limit(1)
      .get();
    if (!pendingSnap.empty) {
      throw new HttpsError(
        'already-exists',
        "Tu as déjà une session à la demande en attente ou active.",
      );
    }

    const sessionData = {
      title: `Session à la demande — ${displayName}`,
      class: studentClass,
      series: studentClass === 'terminale' ? [series] : [],
      status: 'draft',
      startDate: admin.firestore.Timestamp.fromDate(startDate),
      endDate: admin.firestore.Timestamp.fromDate(endDate),
      price: 1500,
      createdBy: 'system',
      isOnDemand: true,
      visibility,
      requestedBy: uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const ref = await collections.sessions().add(sessionData);

    return { sessionId: ref.id };
  },
);
