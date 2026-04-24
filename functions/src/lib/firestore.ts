import * as admin from 'firebase-admin';

// ─── Références Firestore centralisées ───
export const db = admin.firestore();

export const collections = {
  users: () => db.collection('users'),
  user: (uid: string) => db.collection('users').doc(uid),

  sessions: () => db.collection('sessions'),
  session: (sessionId: string) => db.collection('sessions').doc(sessionId),

  subjects: (sessionId: string) =>
    db.collection('sessions').doc(sessionId).collection('subjects'),
  subject: (sessionId: string, subjectId: string) =>
    db.collection('sessions').doc(sessionId).collection('subjects').doc(subjectId),

  submissions: () => db.collection('submissions'),
  submission: (submissionId: string) =>
    db.collection('submissions').doc(submissionId),

  payments: () => db.collection('payments'),
  payment: (paymentId: string) => db.collection('payments').doc(paymentId),

  studentResults: (sessionId: string) =>
    db.collection('sessions').doc(sessionId).collection('studentResults'),
  studentResult: (sessionId: string, userId: string) =>
    db.collection('sessions').doc(sessionId).collection('studentResults').doc(userId),
};

// ─── Helpers ───

export async function getAvailableCorrector(): Promise<string | null> {
  const snap = await collections
    .users()
    .where('role', '==', 'corrector')
    .get();

  if (snap.empty) return null;
  const corrector = snap.docs
    .map((doc) => ({
      id: doc.id,
      activeCorrections: Number(doc.data()['activeCorrections'] ?? 0),
      createdAt:
        typeof doc.data()['createdAt']?.toMillis === 'function'
          ? doc.data()['createdAt'].toMillis()
          : 0,
    }))
    .sort((a, b) => {
      if (a.activeCorrections != b.activeCorrections) {
        return a.activeCorrections - b.activeCorrections;
      }
      return a.createdAt - b.createdAt;
    })[0];

  return corrector?.id ?? null;
}

export async function incrementCorrectorLoad(correctorId: string): Promise<void> {
  await collections.user(correctorId).update({
    activeCorrections: admin.firestore.FieldValue.increment(1),
  });
}

export async function decrementCorrectorLoad(correctorId: string): Promise<void> {
  await db.runTransaction(async (transaction) => {
    const ref = collections.user(correctorId);
    const snap = await transaction.get(ref);
    if (!snap.exists) {
      return;
    }

    const current = Number(snap.data()?.['activeCorrections'] ?? 0);
    transaction.update(ref, {
      activeCorrections: Math.max(0, current - 1),
    });
  });
}
