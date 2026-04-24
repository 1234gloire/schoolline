import {
  collection,
  query,
  where,
  orderBy,
  getDocs,
  getDoc,
  doc,
  Timestamp,
  onSnapshot,
  QuerySnapshot,
  DocumentData,
  QueryConstraint,
} from 'firebase/firestore';
import { db } from './firebase';
import { SubmissionModel, SessionModel, SubjectModel, UserProfile, PaymentModel } from './types';

// ─── Conversions Firestore ───────────────────────────────────────

function toDate(val: unknown): Date {
  if (val instanceof Timestamp) return val.toDate();
  if (val instanceof Date) return val;
  return new Date();
}

export function submissionFromDoc(id: string, data: DocumentData): SubmissionModel {
  return {
    id,
    userId: data.userId ?? '',
    sessionId: data.sessionId ?? '',
    subjectId: data.subjectId ?? '',
    subjectName: data.subjectName ?? '',
    submittedAt: toDate(data.submittedAt),
    statusUpdatedAt: toDate(data.statusUpdatedAt),
    fileRef: data.fileRef ?? '',
    signedUrl: data.signedUrl,
    status: data.status ?? 'submitted',
    ocrText: data.ocrText,
    aiScore: data.aiScore,
    aiConfidence: data.aiConfidence,
    aiDetails: data.aiDetails,
    aiFeedback: data.aiFeedback,
    aiStrengths: data.aiStrengths ?? [],
    aiImprovements: data.aiImprovements ?? [],
    finalScore: data.finalScore,
    correctorId: data.correctorId,
    correctorNotes: data.correctorNotes,
    errorReason: data.errorReason,
    publishedAt: data.publishedAt ? toDate(data.publishedAt) : undefined,
    subjectMaxScore: data.subjectMaxScore,
    subjectBareme: data.subjectBareme,
  };
}

export function sessionFromDoc(id: string, data: DocumentData): SessionModel {
  return {
    id,
    title: data.title ?? '',
    studentClass: data.class ?? 'terminale',
    status: data.status ?? 'draft',
    series: data.series ?? [],
    startDate: toDate(data.startDate),
    endDate: toDate(data.endDate),
    price: Number(data.price ?? 0),
    createdBy: data.createdBy ?? '',
  };
}

export function subjectFromDoc(id: string, sessionId: string, data: DocumentData): SubjectModel {
  return {
    id,
    sessionId,
    name: data.name ?? '',
    type: data.type ?? 'structured',
    durationMinutes: data.duration ?? 120,
    startTime: toDate(data.startTime),
    endTime: toDate(data.endTime),
    coefficient: data.coefficient ?? 1,
    maxScore: data.maxScore ?? 20,
    bareme: data.bareme ?? {},
    series: data.series ?? [],
    subjectFileRef: data.subjectFileRef ?? '',
  };
}

export function userFromDoc(id: string, data: DocumentData): UserProfile {
  return {
    uid: id,
    displayName: data.displayName ?? '',
    email: data.email ?? '',
    phone: data.phone ?? '',
    role: data.role ?? 'student',
    class: data.class,
    series: data.series ?? '',
    school: data.school ?? '',
    createdAt: toDate(data.createdAt),
    subscriptions: data.subscriptions ?? [],
    abandonedSubjectIds: data.abandonedSubjectIds ?? [],
    activeCorrections: data.activeCorrections ?? 0,
    blocked: data.blocked ?? false,
  };
}

// ─── Queries ─────────────────────────────────────────────────────

export async function getSubmissionsForCorrector(
  correctorId: string
): Promise<SubmissionModel[]> {
  const snap = await getDocs(
    query(
      collection(db, 'submissions'),
      where('correctorId', '==', correctorId),
      where('status', '==', 'pendingHuman'),
      orderBy('submittedAt', 'asc')
    )
  );
  return snap.docs.map((d) => submissionFromDoc(d.id, d.data()));
}

export async function getAllPendingSubmissions(): Promise<SubmissionModel[]> {
  const snap = await getDocs(
    query(
      collection(db, 'submissions'),
      where('status', '==', 'pendingHuman'),
      orderBy('submittedAt', 'asc')
    )
  );
  return snap.docs.map((d) => submissionFromDoc(d.id, d.data()));
}

export async function getSessionSubmissions(
  sessionId: string
): Promise<SubmissionModel[]> {
  const snap = await getDocs(
    query(
      collection(db, 'submissions'),
      where('sessionId', '==', sessionId),
      orderBy('submittedAt', 'desc')
    )
  );
  return snap.docs.map((d) => submissionFromDoc(d.id, d.data()));
}

export async function getSession(id: string): Promise<SessionModel | null> {
  const snap = await getDoc(doc(db, 'sessions', id));
  if (!snap.exists()) return null;
  return sessionFromDoc(snap.id, snap.data());
}

export async function getSessions(): Promise<SessionModel[]> {
  const snap = await getDocs(
    query(collection(db, 'sessions'), orderBy('startDate', 'desc'))
  );
  return snap.docs.map((d) => sessionFromDoc(d.id, d.data()));
}

export async function getSessionSubjects(sessionId: string): Promise<SubjectModel[]> {
  const snap = await getDocs(
    query(
      collection(db, 'sessions', sessionId, 'subjects'),
      orderBy('startTime', 'asc')
    )
  );
  return snap.docs.map((d) => subjectFromDoc(d.id, sessionId, d.data()));
}

export async function getSubmission(id: string): Promise<SubmissionModel | null> {
  const snap = await getDoc(doc(db, 'submissions', id));
  if (!snap.exists()) return null;
  return submissionFromDoc(snap.id, snap.data());
}

export async function getCorrectors(): Promise<UserProfile[]> {
  const snap = await getDocs(
    query(
      collection(db, 'users'),
      where('role', '==', 'corrector')
    )
  );

  return snap.docs
    .map((d) => userFromDoc(d.id, d.data()))
    .sort((a, b) => {
      const loadDiff = (a.activeCorrections ?? 0) - (b.activeCorrections ?? 0);
      if (loadDiff !== 0) {
        return loadDiff;
      }

      return a.createdAt.getTime() - b.createdAt.getTime();
    });
}

export async function getUsers(): Promise<UserProfile[]> {
  const snap = await getDocs(query(collection(db, 'users'), orderBy('createdAt', 'desc')));
  return snap.docs.map((d) => userFromDoc(d.id, d.data()));
}

// ─── Stats dashboard ─────────────────────────────────────────────

export interface DashboardStats {
  totalSubmissions: number;
  pendingHuman: number;
  publishedToday: number;
  autoPublished: number;
}

interface DashboardStatsOptions {
  sessionId?: string;
  correctorId?: string;
}

export async function getDashboardStats(
  options: DashboardStatsOptions = {}
): Promise<DashboardStats> {
  const filters: QueryConstraint[] = [];
  if (options.sessionId) {
    filters.push(where('sessionId', '==', options.sessionId));
  }
  if (options.correctorId) {
    filters.push(where('correctorId', '==', options.correctorId));
  }

  const baseQuery = filters.length > 0
    ? query(collection(db, 'submissions'), ...filters)
    : query(collection(db, 'submissions'));

  const snap = await getDocs(baseQuery);
  const docs = snap.docs.map((d) => d.data());

  const today = new Date();
  today.setHours(0, 0, 0, 0);

  return {
    totalSubmissions: docs.length,
    pendingHuman: docs.filter((d) => d.status === 'pendingHuman').length,
    publishedToday: docs.filter((d) => {
      const pub = d.publishedAt as Timestamp | undefined;
      return pub && pub.toDate() >= today;
    }).length,
    autoPublished: docs.filter(
      (d) => d.status === 'published' && !d.correctorId
    ).length,
  };
}

// ─── Paiements ───────────────────────────────────────────────────

function paymentFromDoc(id: string, data: DocumentData): PaymentModel {
  return {
    id,
    userId: data.userId ?? '',
    sessionId: data.sessionId ?? '',
    sessionTitle: data.sessionTitle ?? '',
    amount: data.amount ?? 0,
    proofFileRef: data.proofFileRef ?? '',
    status: data.status ?? 'pending',
    submittedAt: toDate(data.submittedAt),
    reviewedAt: data.reviewedAt ? toDate(data.reviewedAt) : undefined,
    reviewedBy: data.reviewedBy,
    rejectionReason: data.rejectionReason,
  };
}

/** Listener temps réel sur TOUS les paiements (toutes sessions, tous statuts). */
export function subscribeToAllPayments(
  callback: (payments: PaymentModel[]) => void
): () => void {
  const q = query(
    collection(db, 'payments'),
    orderBy('submittedAt', 'desc')
  );
  return onSnapshot(q, (snap: QuerySnapshot) => {
    callback(snap.docs.map((d) => paymentFromDoc(d.id, d.data())));
  });
}

// ─── Sessions temps réel ─────────────────────────────────────────

export function subscribeToSessions(
  callback: (sessions: SessionModel[]) => void
): () => void {
  const q = query(collection(db, 'sessions'), orderBy('startDate', 'desc'));
  return onSnapshot(q, (snap: QuerySnapshot) => {
    callback(snap.docs.map((d) => sessionFromDoc(d.id, d.data())));
  });
}

// ─── Utilisateurs temps réel ─────────────────────────────────────

export function subscribeToUsers(
  callback: (users: UserProfile[]) => void
): () => void {
  const q = query(collection(db, 'users'), orderBy('createdAt', 'desc'));
  return onSnapshot(q, (snap: QuerySnapshot) => {
    callback(snap.docs.map((d) => userFromDoc(d.id, d.data())));
  });
}

// ─── Stats dashboard temps réel ──────────────────────────────────

export function subscribeToDashboardStats(
  options: DashboardStatsOptions,
  callback: (stats: DashboardStats) => void
): () => void {
  const filters: QueryConstraint[] = [];
  if (options.sessionId) filters.push(where('sessionId', '==', options.sessionId));
  if (options.correctorId) filters.push(where('correctorId', '==', options.correctorId));

  const q = filters.length > 0
    ? query(collection(db, 'submissions'), ...filters)
    : query(collection(db, 'submissions'));

  return onSnapshot(q, (snap: QuerySnapshot) => {
    const docs = snap.docs.map((d) => d.data());
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    callback({
      totalSubmissions: docs.length,
      pendingHuman: docs.filter((d) => d.status === 'pendingHuman').length,
      publishedToday: docs.filter((d) => {
        const pub = d.publishedAt as Timestamp | undefined;
        return pub && pub.toDate() >= today;
      }).length,
      autoPublished: docs.filter(
        (d) => d.status === 'published' && !d.correctorId
      ).length,
    });
  });
}

// ─── Listener temps réel ─────────────────────────────────────────

export function subscribeToPendingHumanSubmissions(
  correctorId: string | undefined,
  callback: (submissions: SubmissionModel[]) => void
): () => void {
  const filters: QueryConstraint[] = [where('status', '==', 'pendingHuman')];
  if (correctorId) {
    filters.push(where('correctorId', '==', correctorId));
  }

  const q = query(collection(db, 'submissions'), ...filters, orderBy('submittedAt', 'asc'));

  return onSnapshot(q, (snap: QuerySnapshot) => {
    callback(snap.docs.map((d) => submissionFromDoc(d.id, d.data())));
  });
}
