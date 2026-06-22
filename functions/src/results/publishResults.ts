import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { logger } from 'firebase-functions/v2';
import { collections } from '../lib/firestore';
import { SubjectResultEntry } from '../lib/types';

// ─── Publication globale (toute la session) ───────────────────────────────────
export const publishResults = onCall<{ sessionId: string }>({ invoker: 'public' }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Authentification requise.');

  const callerSnap = await collections.user(request.auth.uid).get();
  if (callerSnap.data()?.['role'] !== 'admin') {
    throw new HttpsError('permission-denied', 'Réservé aux admins.');
  }

  const { sessionId } = request.data;
  if (!sessionId) throw new HttpsError('invalid-argument', 'sessionId requis.');

  // 1. Toutes les soumissions de la session
  const allSnap = await collections.submissions()
    .where('sessionId', '==', sessionId)
    .get();

  if (allSnap.empty) {
    return { success: true, published: 0, skipped: 0 };
  }

  // 2. Grouper par userId
  const byUser = new Map<string, admin.firestore.QueryDocumentSnapshot[]>();
  for (const doc of allSnap.docs) {
    const uid = doc.data()['userId'] as string;
    if (!byUser.has(uid)) byUser.set(uid, []);
    byUser.get(uid)!.push(doc);
  }

  // 3. Traitement par élève
  const RESULT_READY = new Set(['humanReviewed', 'aiReviewed', 'published']);
  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();

  // Gérer la limite Firestore de 500 ops par batch
  let currentBatch = db.batch();
  let opsInBatch = 0;
  const batches: admin.firestore.WriteBatch[] = [currentBatch];

  const addOp = (fn: (b: admin.firestore.WriteBatch) => void) => {
    if (opsInBatch >= 490) {
      currentBatch = db.batch();
      batches.push(currentBatch);
      opsInBatch = 0;
    }
    fn(currentBatch);
    opsInBatch++;
  };

  const notifyUserIds: string[] = [];
  let publishedCount = 0;
  let skippedCount = 0;

  for (const [userId, submissions] of byUser) {
    const effectiveSubmissions = submissions.filter(
      (submission) => submission.data()['status'] !== 'rejected'
    );

    if (effectiveSubmissions.length === 0) {
      skippedCount++;
      logger.warn('Élève ignoré : aucune copie exploitable', { userId, sessionId });
      continue;
    }

    // Vérifier que toutes les copies exploitables sont corrigées ou déjà publiées
    const allCorrected = effectiveSubmissions.every((submission) =>
      RESULT_READY.has(submission.data()['status'] as string)
    );

    if (!allCorrected) {
      skippedCount++;
      logger.warn('Élève ignoré : copies non toutes corrigées', { userId, sessionId });
      continue;
    }

    // Calculer la moyenne générale pondérée
    let totalPoints = 0;
    let totalCoefficients = 0;
    let lastSubmittedAtMs = 0;
    const subjectResults: SubjectResultEntry[] = [];

    for (const sub of effectiveSubmissions) {
      const data = sub.data();
      const rawScore = ((data['finalScore'] ?? data['aiScore']) as number | undefined) ?? 0;
      const maxScore = (data['subjectMaxScore'] as number | undefined) ?? 20;
      const coefficient = (data['subjectCoefficient'] as number | undefined) ?? 1;

      // Normaliser sur 20
      const scoreOn20 = maxScore > 0 ? (rawScore / maxScore) * 20 : 0;
      const rounded = Math.round(scoreOn20 * 100) / 100;

      totalPoints += rounded * coefficient;
      totalCoefficients += coefficient;

      const submittedAt = data['submittedAt'] as admin.firestore.Timestamp | undefined;
      if (submittedAt && submittedAt.toMillis() > lastSubmittedAtMs) {
        lastSubmittedAtMs = submittedAt.toMillis();
      }

      subjectResults.push({
        subjectId: data['subjectId'] as string,
        subjectName: data['subjectName'] as string,
        finalScore: rounded,
        maxScore: 20,
        coefficient,
        submissionId: sub.id,
      });

      // Passer la soumission à "published" si elle ne l'est pas encore.
      if (data['status'] !== 'published') {
        addOp(b => b.update(sub.ref, {
          status: 'published',
          publishedAt: now,
          statusUpdatedAt: now,
          errorReason: admin.firestore.FieldValue.delete(),
        }));
        publishedCount++;
      }
    }

    const moyenneGenerale =
      totalCoefficients > 0
        ? Math.round((totalPoints / totalCoefficients) * 100) / 100
        : 0;

    const isAdmis = moyenneGenerale >= 10;
    const mention = computeMention(moyenneGenerale);

    // Écrire le bulletin de résultat de l'élève
    const resultRef = collections.studentResult(sessionId, userId);
    addOp(b => b.set(resultRef, {
      userId,
      sessionId,
      moyenneGenerale,
      totalPoints: Math.round(totalPoints * 100) / 100,
      totalCoefficients,
      isAdmis,
      mention,
      subjects: subjectResults,
      publishedAt: now,
      lastSubmittedAt: lastSubmittedAtMs > 0
        ? admin.firestore.Timestamp.fromMillis(lastSubmittedAtMs)
        : now,
    }));

    notifyUserIds.push(userId);
  }

  // Commiter tous les batches
  for (const b of batches) {
    await b.commit();
  }

  // Mettre à jour le statut de la session
  await collections.session(sessionId).update({
    status: 'resultsPublished',
    statusUpdatedAt: now,
  });

  // Notifications push
  await sendBatchNotifications(notifyUserIds, sessionId);

  logger.info(`Publication : ${publishedCount} copies publiées, ${skippedCount} élèves ignorés`, { sessionId });
  return { success: true, published: publishedCount, skipped: skippedCount };
});

// ─── Publication individuelle (une seule copie) ───────────────────────────────
export const publishSingleResult = onCall<{ submissionId: string }>({ invoker: 'public' }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Authentification requise.');

  const callerSnap = await collections.user(request.auth.uid).get();
  if (callerSnap.data()?.['role'] !== 'admin') {
    throw new HttpsError('permission-denied', 'Réservé aux admins.');
  }

  const { submissionId } = request.data;
  if (!submissionId) throw new HttpsError('invalid-argument', 'submissionId requis.');

  const ref = collections.submission(submissionId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'Soumission introuvable.');

  const data = snap.data()!;
  const allowed = ['humanReviewed', 'aiReviewed'];
  if (!allowed.includes(data['status'])) {
    throw new HttpsError('failed-precondition', `Statut invalide: ${data['status']}`);
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  await ref.update({
    status: 'published',
    publishedAt: now,
    statusUpdatedAt: now,
    finalScore: data['finalScore'] ?? data['aiScore'],
    errorReason: admin.firestore.FieldValue.delete(),
  });

  // Vérifier si toutes les copies de cet élève pour cette session sont publiées
  const userId = data['userId'] as string;
  const sessionId = data['sessionId'] as string;
  await tryComputeStudentResult(sessionId, userId, now);

  await notifyStudent(
    userId,
    data['subjectName'] as string,
    data['finalScore'] ?? data['aiScore'],
    (data['subjectMaxScore'] as number) ?? 20
  );

  return { success: true, submissionId };
});

// ─── Calcul du bulletin si toutes les copies sont publiées ───────────────────
async function tryComputeStudentResult(
  sessionId: string,
  userId: string,
  now: admin.firestore.FieldValue
): Promise<void> {
  try {
    const userSnap = await collections.submissions()
      .where('sessionId', '==', sessionId)
      .where('userId', '==', userId)
      .get();

    const effectiveDocs = userSnap.docs.filter(
      (doc) => doc.data()['status'] !== 'rejected'
    );

    if (effectiveDocs.length === 0) {
      return;
    }

    const allPublished = effectiveDocs.every(
      (doc) => doc.data()['status'] === 'published'
    );
    if (!allPublished) return;

    let totalPoints = 0;
    let totalCoefficients = 0;
    let lastSubmittedAtMs = 0;
    const subjectResults: SubjectResultEntry[] = [];

    for (const sub of effectiveDocs) {
      const d = sub.data();
      const rawScore = ((d['finalScore'] ?? d['aiScore']) as number | undefined) ?? 0;
      const maxScore = (d['subjectMaxScore'] as number | undefined) ?? 20;
      const coefficient = (d['subjectCoefficient'] as number | undefined) ?? 1;
      const scoreOn20 = maxScore > 0 ? (rawScore / maxScore) * 20 : 0;
      const rounded = Math.round(scoreOn20 * 100) / 100;
      totalPoints += rounded * coefficient;
      totalCoefficients += coefficient;
      const submittedAt = d['submittedAt'] as admin.firestore.Timestamp | undefined;
      if (submittedAt && submittedAt.toMillis() > lastSubmittedAtMs) {
        lastSubmittedAtMs = submittedAt.toMillis();
      }
      subjectResults.push({
        subjectId: d['subjectId'] as string,
        subjectName: d['subjectName'] as string,
        finalScore: rounded,
        maxScore: 20,
        coefficient,
        submissionId: sub.id,
      });
    }

    const moyenneGenerale =
      totalCoefficients > 0
        ? Math.round((totalPoints / totalCoefficients) * 100) / 100
        : 0;

    await collections.studentResult(sessionId, userId).set({
      userId,
      sessionId,
      moyenneGenerale,
      totalPoints: Math.round(totalPoints * 100) / 100,
      totalCoefficients,
      isAdmis: moyenneGenerale >= 10,
      mention: computeMention(moyenneGenerale),
      subjects: subjectResults,
      publishedAt: now,
      lastSubmittedAt: lastSubmittedAtMs > 0
        ? admin.firestore.Timestamp.fromMillis(lastSubmittedAtMs)
        : now,
    });
  } catch (err) {
    logger.warn('tryComputeStudentResult échoué (best-effort)', { sessionId, userId, err });
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
function computeMention(moyenne: number): string {
  if (moyenne >= 16) return 'Très Bien';
  if (moyenne >= 14) return 'Bien';
  if (moyenne >= 12) return 'Assez Bien';
  if (moyenne >= 10) return 'Passable';
  return 'Insuffisant';
}

async function sendBatchNotifications(userIds: string[], sessionId: string): Promise<void> {
  const CHUNK = 100;
  for (let i = 0; i < userIds.length; i += CHUNK) {
    const chunk = userIds.slice(i, i + CHUNK);
    const snaps = await Promise.all(chunk.map((uid) => collections.user(uid).get()));
    const messages: admin.messaging.Message[] = snaps
      .map((s) => s.data()?.['fcmToken'] as string | undefined)
      .filter(Boolean)
      .map((token) => ({
        token: token!,
        notification: {
          title: 'Ton bulletin est disponible !',
          body: 'Consulte ta moyenne et tes notes dans ExamSim Congo.',
        },
        data: { type: 'results_published', sessionId },
        android: { priority: 'high' as const },
        apns: { payload: { aps: { badge: 1 } } },
      }));

    if (messages.length > 0) {
      const res = await admin.messaging().sendEach(messages);
      logger.info(`FCM: ${res.successCount}/${messages.length}`);
    }
  }
}

async function notifyStudent(
  userId: string,
  subjectName: string,
  score: number,
  maxScore: number
): Promise<void> {
  try {
    const snap = await collections.user(userId).get();
    const token = snap.data()?.['fcmToken'] as string | undefined;
    if (!token) return;
    await admin.messaging().send({
      token,
      notification: { title: `Résultat — ${subjectName}`, body: `Ta note : ${score}/${maxScore}` },
      data: { type: 'result_published', subjectName },
      android: { priority: 'high' },
      apns: { payload: { aps: { badge: 1 } } },
    });
  } catch (_) { /* non bloquant */ }
}
