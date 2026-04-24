'use client';

import { useEffect, useMemo, useState } from 'react';
import {
  AlertTriangle,
  CalendarDays,
  Clock3,
  FileText,
  Layers3,
  Plus,
} from 'lucide-react';
import {
  addDoc,
  collection,
  deleteDoc,
  doc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';
import { deleteObject, ref as storageRef, uploadBytes } from 'firebase/storage';
import { AdminShell } from '@/components/admin/admin-shell';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Textarea } from '@/components/ui/textarea';
import { db, storage } from '@/lib/firebase';
import { getSessionSubjects, subscribeToSessions } from '@/lib/firestore-helpers';
import { SessionModel, SessionStatus, SubjectModel } from '@/lib/types';
import { useAuth } from '@/lib/auth-context';

const BAC_SERIES = ['A', 'B', 'C', 'D', 'TI', 'G'];
const THIRD_GRADE_SERIES = ['3EME'];
const SUBJECT_TYPES: Array<SubjectModel['type']> = [
  'structured',
  'literary',
  'qcm',
];
const STATUS_LABELS: Record<SessionStatus, string> = {
  draft: 'Brouillon',
  open: 'Ouverte',
  active: 'En cours',
  closed: 'Fermée',
  resultsPublished: 'Résultats publiés',
};
const SUBJECT_TYPE_LABELS: Record<SubjectModel['type'], string> = {
  structured: 'Structurée',
  literary: 'Littéraire',
  qcm: 'QCM',
};
const CLASS_LABELS: Record<SessionModel['studentClass'], string> = {
  terminale: 'Terminale',
  troisieme: '3ème',
};

interface SubjectFormState {
  id: string | null;
  name: string;
  type: SubjectModel['type'];
  durationMinutes: number;
  coefficient: number;
  maxScore: number;
  startDate: string;
  startTime: string;
  endDate: string;
  endTime: string;
  series: string[];
  baremeText: string;
  subjectFileRef: string;
  corrigeText: string;
}

const EMPTY_SUBJECT_FORM: SubjectFormState = {
  id: null,
  name: '',
  type: 'structured',
  durationMinutes: 120,
  coefficient: 1,
  maxScore: 20,
  startDate: '',
  startTime: '08:00',
  endDate: '',
  endTime: '10:00',
  series: ['D'],
  baremeText: '',
  subjectFileRef: '',
  corrigeText: '',
};

function seriesOptionsForClass(
  studentClass: SessionModel['studentClass']
): string[] {
  return studentClass === 'troisieme' ? THIRD_GRADE_SERIES : BAC_SERIES;
}

function seriesOptionsForSession(
  session: SessionModel | null | undefined
): string[] {
  if (!session) {
    return [];
  }

  if (session.studentClass === 'troisieme') {
    return THIRD_GRADE_SERIES;
  }

  return session.series.length > 0
    ? [...session.series]
    : seriesOptionsForClass(session.studentClass);
}

function normalizeSeriesSelection(
  selectedSeries: string[],
  allowedSeries: string[]
): string[] {
  const normalizedSelected = selectedSeries.map((series) =>
    series.trim().toUpperCase()
  );

  return allowedSeries.filter((series) =>
    normalizedSelected.includes(series.trim().toUpperCase())
  );
}

export default function SessionsPage() {
  return (
    <AdminShell requiredRole="admin">
      <SessionsContent />
    </AdminShell>
  );
}

function SessionsContent() {
  const { profile } = useAuth();
  const [sessions, setSessions] = useState<SessionModel[]>([]);
  const [subjectsBySession, setSubjectsBySession] = useState<
    Record<string, SubjectModel[]>
  >({});
  const [loading, setLoading] = useState(true);

  const [showSessionForm, setShowSessionForm] = useState(false);
  const [editingSession, setEditingSession] = useState<SessionModel | null>(null);
  const [savingSession, setSavingSession] = useState(false);
  const [deletingSessionId, setDeletingSessionId] = useState<string | null>(null);
  const [sessionMessage, setSessionMessage] = useState('');
  const [sessionMessageIsError, setSessionMessageIsError] = useState(false);

  const [title, setTitle] = useState('');
  const [studentClass, setStudentClass] =
    useState<SessionModel['studentClass']>('terminale');
  const [status, setStatus] = useState<SessionStatus>('draft');
  const [selectedSeries, setSelectedSeries] = useState<string[]>(['D']);
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  const [price, setPrice] = useState('0');

  const [showSubjectForm, setShowSubjectForm] = useState(false);
  const [activeSession, setActiveSession] = useState<SessionModel | null>(null);
  const [subjectForm, setSubjectForm] =
    useState<SubjectFormState>(EMPTY_SUBJECT_FORM);
  const [subjectPdfFile, setSubjectPdfFile] = useState<File | null>(null);
  const [subjectError, setSubjectError] = useState('');
  const [savingSubject, setSavingSubject] = useState(false);
  const [deletingSubjectId, setDeletingSubjectId] = useState<string | null>(null);

  async function loadSubjectsForSessions(loadedSessions: SessionModel[]) {
    const entries = await Promise.all(
      loadedSessions.map(async (session: SessionModel) => [
        session.id,
        await getSessionSubjects(session.id),
      ] as const)
    );
    setSubjectsBySession(Object.fromEntries(entries));
  }

  useEffect(() => {
    setLoading(true);
    const unsub = subscribeToSessions((loadedSessions) => {
      setSessions(loadedSessions);
      loadSubjectsForSessions(loadedSessions).finally(() => setLoading(false));
    });
    return unsub;
  }, []);

  const totalSubjects = useMemo(
    () =>
      Object.values(subjectsBySession).reduce(
        (count, subjects) => count + subjects.length,
        0
      ),
    [subjectsBySession]
  );
  const liveSessionsCount = useMemo(
    () =>
      sessions.filter(
        (session) => session.status === 'open' || session.status === 'active'
      ).length,
    [sessions]
  );
  const draftSessionsCount = useMemo(
    () => sessions.filter((session) => session.status === 'draft').length,
    [sessions]
  );
  const publishedSessionsCount = useMemo(
    () =>
      sessions.filter((session) => session.status === 'resultsPublished').length,
    [sessions]
  );
  const incompleteSessionsCount = useMemo(
    () =>
      sessions.filter((session) => (subjectsBySession[session.id] ?? []).length === 0)
        .length,
    [sessions, subjectsBySession]
  );
  const sessionSeriesOptions = seriesOptionsForClass(studentClass);
  const subjectSeriesOptions = seriesOptionsForSession(activeSession);

  function openCreateSession() {
    setSessionMessage('');
    setEditingSession(null);
    setTitle('');
    setStudentClass('terminale');
    setStatus('draft');
    setSelectedSeries(['D']);
    setStartDate('');
    setEndDate('');
    setPrice('0');
    setShowSessionForm(true);
  }

  function openEditSession(session: SessionModel) {
    setSessionMessage('');
    setEditingSession(session);
    setTitle(session.title);
    setStudentClass(session.studentClass);
    setStatus(session.status);
    setSelectedSeries(
      session.series.length > 0
        ? [...session.series]
        : seriesOptionsForClass(session.studentClass)
    );
    setStartDate(toDateInput(session.startDate));
    setEndDate(toDateInput(session.endDate));
    setPrice(String(session.price));
    setShowSessionForm(true);
  }

  function toggleSeries(series: string) {
    setSelectedSeries((prev) =>
      prev.includes(series)
        ? prev.filter((item) => item !== series)
        : [...prev, series]
    );
  }

  function handleSessionClassChange(nextClass: SessionModel['studentClass']) {
    setStudentClass(nextClass);
    setSelectedSeries(seriesOptionsForClass(nextClass));
  }

  function openCreateSubject(session: SessionModel) {
    const allowedSeries = seriesOptionsForSession(session);
    setActiveSession(session);
    setSubjectError('');
    setSubjectPdfFile(null);
    setSubjectForm({
      ...EMPTY_SUBJECT_FORM,
      startDate: toDateInput(session.startDate),
      endDate: toDateInput(session.startDate),
      series: [...allowedSeries],
    });
    setShowSubjectForm(true);
  }

  function openEditSubject(session: SessionModel, subject: SubjectModel) {
    const allowedSeries = seriesOptionsForSession(session);
    const normalizedSubjectSeries = normalizeSeriesSelection(
      subject.series.length > 0 ? subject.series : allowedSeries,
      allowedSeries
    );
    setActiveSession(session);
    setSubjectError('');
    setSubjectPdfFile(null);
    setSubjectForm({
      id: subject.id,
      name: subject.name,
      type: subject.type,
      durationMinutes: subject.durationMinutes,
      coefficient: subject.coefficient,
      maxScore: subject.maxScore,
      startDate: toDateInput(subject.startTime),
      startTime: toTimeInput(subject.startTime),
      endDate: toDateInput(subject.endTime),
      endTime: toTimeInput(subject.endTime),
      series:
        normalizedSubjectSeries.length > 0
          ? normalizedSubjectSeries
          : [...allowedSeries],
      baremeText: formatBareme(subject.bareme),
      subjectFileRef: subject.subjectFileRef,
      corrigeText: subject.corrigeText ?? '',
    });
    setShowSubjectForm(true);
  }

  function resetSubjectDialog() {
    setShowSubjectForm(false);
    setActiveSession(null);
    setSubjectError('');
    setSubjectPdfFile(null);
    setSubjectForm(EMPTY_SUBJECT_FORM);
  }

  async function loadSubjects(sessionId: string) {
    const subjects = await getSessionSubjects(sessionId);
    setSubjectsBySession((prev) => ({
      ...prev,
      [sessionId]: subjects,
    }));
  }

  async function handleSaveSession() {
    if (!title || !startDate || !endDate || selectedSeries.length === 0) {
      return;
    }

    setSavingSession(true);

    try {
      const normalizedSeries = seriesOptionsForClass(studentClass).filter(
        (series) =>
          studentClass === 'troisieme' || selectedSeries.includes(series)
      );
      const payload = {
        title,
        class: studentClass,
        status,
        series: normalizedSeries,
        startDate: Timestamp.fromDate(new Date(`${startDate}T00:00:00`)),
        endDate: Timestamp.fromDate(new Date(`${endDate}T23:59:59`)),
        price: Number(price || 0),
        createdBy: profile?.uid ?? '',
      };

      if (editingSession) {
        await updateDoc(doc(db, 'sessions', editingSession.id), payload);
        setShowSessionForm(false);
        // Le listener sessions met à jour automatiquement
      } else {
        const docRef = await addDoc(collection(db, 'sessions'), {
          ...payload,
          createdAt: serverTimestamp(),
        });

        const createdSession: SessionModel = {
          id: docRef.id,
          title,
          studentClass,
          status,
          series: [...normalizedSeries],
          startDate: new Date(`${startDate}T00:00:00`),
          endDate: new Date(`${endDate}T23:59:59`),
          price: Number(price || 0),
          createdBy: profile?.uid ?? '',
        };

        setShowSessionForm(false);
        openCreateSubject(createdSession);
      }
    } finally {
      setSavingSession(false);
    }
  }

  async function changeStatus(sessionId: string, newStatus: SessionStatus) {
    await updateDoc(doc(db, 'sessions', sessionId), { status: newStatus });
    // Le listener sessions met à jour automatiquement
  }

  async function handleDeleteSession(session: SessionModel) {
    const isFinished =
      session.status === 'closed' || session.status === 'resultsPublished';

    setDeletingSessionId(session.id);
    setSessionMessage('');

    try {
      const [submissionsSnap, paymentsSnap, studentResultsSnap] =
        await Promise.all([
          getDocs(
            query(
              collection(db, 'submissions'),
              where('sessionId', '==', session.id),
            ),
          ),
          getDocs(
            query(
              collection(db, 'payments'),
              where('sessionId', '==', session.id),
            ),
          ),
          getDocs(
            collection(db, 'sessions', session.id, 'studentResults'),
          ),
        ]);

      const hasData =
        !submissionsSnap.empty ||
        !paymentsSnap.empty ||
        !studentResultsSnap.empty;

      // Sessions actives (draft/open/active) : bloquer si des données existent
      if (!isFinished && hasData) {
        setDeletingSessionId(null);
        setSessionMessageIsError(true);
        setSessionMessage(
          'Suppression impossible : cette session contient des copies ou des paiements. Ferme-la avant de la supprimer.',
        );
        return;
      }

      // Confirmation — plus sévère si la session contient des données élèves
      const warningLine = hasData
        ? `\n\n⚠️ Attention : ${submissionsSnap.size} copie(s), ${paymentsSnap.size} paiement(s) et ${studentResultsSnap.size} résultat(s) seront définitivement perdus.`
        : '';
      const confirmed = window.confirm(
        `Supprimer définitivement la session "${session.title}" et toutes ses données ?${warningLine}\n\nCette action est irréversible.`,
      );
      if (!confirmed) {
        setDeletingSessionId(null);
        return;
      }

      const sessionSubjects = subjectsBySession[session.id] ?? [];
      const batch = writeBatch(db);

      // Épreuves
      for (const subject of sessionSubjects) {
        batch.delete(doc(db, 'sessions', session.id, 'subjects', subject.id));
      }
      // Copies
      for (const d of submissionsSnap.docs) {
        batch.delete(d.ref);
      }
      // Paiements
      for (const d of paymentsSnap.docs) {
        batch.delete(d.ref);
      }
      // Résultats élèves
      for (const d of studentResultsSnap.docs) {
        batch.delete(d.ref);
      }
      // Session elle-même
      batch.delete(doc(db, 'sessions', session.id));

      await batch.commit();

      // Nettoyage Storage best-effort
      await Promise.all(
        sessionSubjects
          .map((subject) => subject.subjectFileRef)
          .filter((fileRef): fileRef is string => fileRef.trim().length > 0)
          .map(async (fileRef) => {
            try {
              await deleteObject(storageRef(storage, fileRef));
            } catch {
              // Ignoré volontairement
            }
          }),
      );

      if (editingSession?.id === session.id) {
        setShowSessionForm(false);
        setEditingSession(null);
      }

      setSessionMessageIsError(false);
      setSessionMessage(`Session "${session.title}" supprimée.`);
    } catch (error) {
      setSessionMessageIsError(true);
      setSessionMessage(
        error instanceof Error
          ? error.message
          : 'Impossible de supprimer la session.',
      );
    } finally {
      setDeletingSessionId(null);
    }
  }

  async function handleSaveSubject() {
    if (!activeSession) {
      return;
    }

    setSubjectError('');

    const allowedSeries = seriesOptionsForSession(activeSession);
    const normalizedSubjectSeries =
      activeSession.studentClass === 'troisieme'
        ? [...allowedSeries]
        : normalizeSeriesSelection(subjectForm.series, allowedSeries);

    if (!subjectForm.name.trim()) {
      setSubjectError("Le nom de l'épreuve est requis.");
      return;
    }

    if (normalizedSubjectSeries.length === 0) {
      setSubjectError('Sélectionne au moins une série.');
      return;
    }

    const startAt = toLocalDateTime(subjectForm.startDate, subjectForm.startTime);
    const endAt = toLocalDateTime(subjectForm.endDate, subjectForm.endTime);

    if (!startAt || !endAt) {
      setSubjectError("La date et l'heure de l'épreuve sont requises.");
      return;
    }

    if (endAt <= startAt) {
      setSubjectError("L'heure de fin doit être après l'heure de début.");
      return;
    }

    const bareme = parseBareme(subjectForm.baremeText);
    const baremeTotal = Object.values(bareme).reduce(
      (sum, value) => sum + value,
      0
    );

    if (baremeTotal > 0 && baremeTotal > subjectForm.maxScore) {
      setSubjectError(
        `Le total du barème (${baremeTotal}) dépasse la note maximale (${subjectForm.maxScore}).`
      );
      return;
    }

    if (!subjectPdfFile && !subjectForm.subjectFileRef) {
      setSubjectError("Ajoute le PDF du sujet pour publier l'épreuve.");
      return;
    }

    setSavingSubject(true);

    try {
      const subjectDocRef = subjectForm.id
        ? doc(db, 'sessions', activeSession.id, 'subjects', subjectForm.id)
        : doc(collection(db, 'sessions', activeSession.id, 'subjects'));

      let subjectFileRef = subjectForm.subjectFileRef;
      if (subjectPdfFile) {
        const filePath = `subjects/${activeSession.id}/${subjectDocRef.id}-${sanitizeFileName(
          subjectPdfFile.name
        )}`;

        await uploadBytes(storageRef(storage, filePath), subjectPdfFile, {
          contentType: subjectPdfFile.type || 'application/pdf',
        });

        if (
          subjectForm.subjectFileRef &&
          subjectForm.subjectFileRef !== filePath
        ) {
          try {
            await deleteObject(storageRef(storage, subjectForm.subjectFileRef));
          } catch {
            // Nettoyage best-effort si l'ancien PDF existe encore.
          }
        }

        subjectFileRef = filePath;
      }

      await setDoc(
        subjectDocRef,
        {
          name: subjectForm.name.trim(),
          type: subjectForm.type,
          duration: subjectForm.durationMinutes,
          startTime: Timestamp.fromDate(startAt),
          endTime: Timestamp.fromDate(endAt),
          subjectFileRef,
          coefficient: subjectForm.coefficient,
          maxScore: subjectForm.maxScore,
          bareme,
          series: normalizedSubjectSeries,
          corrigeText: subjectForm.corrigeText.trim(),
        },
        { merge: true }
      );

      await loadSubjects(activeSession.id);
      resetSubjectDialog();
    } catch (error) {
      setSubjectError(
        error instanceof Error
          ? error.message
          : "Impossible d'enregistrer l'épreuve."
      );
    } finally {
      setSavingSubject(false);
    }
  }

  async function handleDeleteSubject(
    session: SessionModel,
    subject: SubjectModel
  ) {
    const confirmed = window.confirm(
      `Supprimer définitivement l'épreuve "${subject.name}" ?`
    );
    if (!confirmed) {
      return;
    }

    setDeletingSubjectId(subject.id);

    try {
      await deleteDoc(doc(db, 'sessions', session.id, 'subjects', subject.id));
      if (subject.subjectFileRef) {
        try {
          await deleteObject(storageRef(storage, subject.subjectFileRef));
        } catch {
          // Nettoyage best-effort du PDF lié à l'épreuve.
        }
      }
      await loadSubjects(session.id);
    } finally {
      setDeletingSubjectId(null);
    }
  }

  return (
    <div className="min-h-full bg-[radial-gradient(circle_at_top_left,rgba(10,17,114,0.09),transparent_26%),linear-gradient(180deg,#f8fafc_0%,#ffffff_38%)] px-6 py-8 lg:px-8">
      <div className="mx-auto max-w-6xl space-y-6">
        <section className="overflow-hidden rounded-[28px] border border-[#0A1172]/10 bg-[#0A1172] text-white shadow-[0_24px_80px_-40px_rgba(10,17,114,0.9)]">
          <div className="grid gap-6 px-6 py-6 lg:grid-cols-[minmax(0,1.45fr)_330px] lg:px-8">
            <div className="space-y-4">
              <Badge className="border border-white/10 bg-white/10 text-white">
                Catalogue de sessions
              </Badge>

              <div className="space-y-2">
                <h1 className="text-2xl font-semibold tracking-tight lg:text-3xl">
                  Sessions & Épreuves
                </h1>
                <p className="max-w-2xl text-sm leading-6 text-white/72">
                  Pilotez l’ouverture des sessions, complétez les épreuves et
                  gardez un œil sur les brouillons avant qu’ils ne deviennent des
                  blocages côté élève.
                </p>
              </div>

              <div className="flex flex-wrap gap-2">
                <Badge className="border border-blue-200/30 bg-blue-50/12 text-blue-100">
                  {liveSessionsCount} session(s) en circulation
                </Badge>
                <Badge className="border border-orange-200/30 bg-orange-50/12 text-orange-100">
                  {incompleteSessionsCount} incomplète(s)
                </Badge>
                <Badge className="border border-emerald-200/30 bg-emerald-50/12 text-emerald-100">
                  {publishedSessionsCount} publiée(s)
                </Badge>
              </div>

              <div className="pt-2">
                <Button
                  onClick={openCreateSession}
                  className="bg-[#F5B731] text-[#0A1172] hover:bg-[#f1c04f]"
                >
                  <Plus className="h-4 w-4" />
                  Nouvelle session
                </Button>
              </div>
            </div>

            <div className="rounded-[24px] border border-white/10 bg-white/8 p-5 backdrop-blur-sm">
              <p className="text-[11px] font-semibold uppercase tracking-[0.22em] text-white/45">
                Vue rapide
              </p>
              {(incompleteSessionsCount > 0 || draftSessionsCount > 0) && (
                <div className="mt-4 rounded-2xl border border-white/12 bg-white px-4 py-4 text-[#0A1172]">
                  <div className="flex items-start gap-3">
                    <div
                      className={`rounded-xl p-2 ${
                        incompleteSessionsCount > 0
                          ? 'bg-orange-100 text-orange-700'
                          : 'bg-blue-100 text-blue-700'
                      }`}
                    >
                      {incompleteSessionsCount > 0 ? (
                        <AlertTriangle className="h-4 w-4" />
                      ) : (
                        <Clock3 className="h-4 w-4" />
                      )}
                    </div>
                    <div>
                      <p className="text-sm font-semibold">
                        {incompleteSessionsCount > 0
                          ? 'Des sessions restent incomplètes'
                          : 'Des brouillons restent à ouvrir'}
                      </p>
                      <p className="mt-1 text-sm leading-6 opacity-85">
                        {incompleteSessionsCount > 0
                          ? "Ajoutez au moins une épreuve aux sessions concernées pour qu'elles soient exploitables."
                          : 'Pensez à finaliser les paramètres d’ouverture avant la mise à disposition aux élèves.'}
                      </p>
                    </div>
                  </div>
                </div>
              )}

              <div className="mt-4 space-y-3">
                <SummaryRow
                  label="Sessions totales"
                  value={String(sessions.length)}
                />
                <SummaryRow
                  label="Épreuves configurées"
                  value={String(totalSubjects)}
                />
                <SummaryRow
                  label="Brouillons"
                  value={String(draftSessionsCount)}
                />
              </div>
            </div>
          </div>
        </section>

        <section className="grid grid-cols-2 gap-4 xl:grid-cols-4">
          {[
            {
              label: 'Sessions',
              value: sessions.length,
              helper: 'Catalogue total',
              icon: Layers3,
              tone: 'slate',
            },
            {
              label: 'En circulation',
              value: liveSessionsCount,
              helper: 'Ouvertes ou actives',
              icon: CalendarDays,
              tone: 'blue',
            },
            {
              label: 'Brouillons',
              value: draftSessionsCount,
              helper: 'Encore à finaliser',
              icon: Clock3,
              tone: 'orange',
            },
            {
              label: 'Épreuves',
              value: totalSubjects,
              helper: 'Déjà configurées',
              icon: FileText,
              tone: 'green',
            },
          ].map((item) => (
            <Card
              key={item.label}
              className="border-0 bg-white/92 shadow-sm ring-1 ring-slate-200/75"
            >
              <CardContent className="p-5">
                <div
                  className={`inline-flex rounded-2xl border p-3 ${
                    item.tone === 'blue'
                      ? 'border-blue-200 bg-blue-50 text-blue-700'
                      : item.tone === 'orange'
                        ? 'border-orange-200 bg-orange-50 text-orange-700'
                        : item.tone === 'green'
                          ? 'border-emerald-200 bg-emerald-50 text-emerald-700'
                          : 'border-slate-200 bg-slate-50 text-slate-700'
                  }`}
                >
                  <item.icon className="h-5 w-5" />
                </div>
                <p
                  className={`mt-5 text-3xl font-semibold tracking-tight ${
                    item.tone === 'blue'
                      ? 'text-blue-700'
                      : item.tone === 'orange'
                        ? 'text-orange-700'
                        : item.tone === 'green'
                          ? 'text-emerald-700'
                          : 'text-slate-700'
                  }`}
                >
                  {item.value}
                </p>
                <p className="mt-1 text-sm font-medium text-gray-700">{item.label}</p>
                <p className="mt-2 text-sm text-gray-500">{item.helper}</p>
              </CardContent>
            </Card>
          ))}
        </section>

        {sessionMessage && (
          <div
            className={`rounded-2xl border px-4 py-3 text-sm ${
              sessionMessageIsError
                ? 'border-red-200 bg-red-50 text-red-700'
                : 'border-emerald-200 bg-emerald-50 text-emerald-700'
            }`}
          >
            {sessionMessage}
          </div>
        )}

        {loading ? (
          <Card className="border-0 bg-white/92 shadow-sm ring-1 ring-slate-200/75">
            <CardContent className="py-16 text-center text-slate-400">
              Chargement des sessions...
            </CardContent>
          </Card>
        ) : sessions.length === 0 ? (
          <Card className="border-0 bg-white/92 shadow-sm ring-1 ring-slate-200/75">
            <CardContent className="py-16 text-center text-slate-400">
              Aucune session. Créez une session puis ajoutez immédiatement ses
              épreuves.
            </CardContent>
          </Card>
        ) : (
          <div className="space-y-5">
            {sessions.map((session) => {
              const subjects = subjectsBySession[session.id] ?? [];

              return (
                <Card
                  key={session.id}
                  className="border-0 bg-white/92 shadow-sm ring-1 ring-slate-200/75"
                >
                  <CardContent className="space-y-5 p-5">
                    <div className="flex flex-col gap-4 xl:flex-row xl:items-start xl:justify-between">
                      <div className="space-y-3">
                        <div className="flex flex-wrap items-center gap-2">
                          <p className="text-base font-semibold text-gray-900">
                            {session.title}
                          </p>
                          <StatusPill status={session.status} />
                          <Badge className="border border-slate-200 bg-slate-100 text-slate-700">
                            {subjects.length} épreuve{subjects.length > 1 ? 's' : ''}
                          </Badge>
                          {subjects.length === 0 && (
                            <Badge className="border border-orange-200 bg-orange-50 text-orange-700">
                              Incomplète
                            </Badge>
                          )}
                        </div>

                        <div className="flex flex-wrap gap-2 text-xs text-slate-500">
                          <span className="rounded-full bg-slate-100 px-2.5 py-1">
                            {session.startDate.toLocaleDateString('fr-FR')} →{' '}
                            {session.endDate.toLocaleDateString('fr-FR')}
                          </span>
                          <span className="rounded-full bg-slate-100 px-2.5 py-1">
                            {describeAudience(session)}
                          </span>
                          <span className="rounded-full bg-slate-100 px-2.5 py-1">
                            {session.price.toLocaleString('fr-FR')} FCFA
                          </span>
                        </div>
                      </div>

                      <div className="flex flex-wrap items-center gap-2">
                        <Select
                          value={session.status}
                          onValueChange={(value) =>
                            value
                              ? changeStatus(session.id, value as SessionStatus)
                              : undefined
                          }
                        >
                          <SelectTrigger className="h-8 w-40 text-xs">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            {Object.entries(STATUS_LABELS).map(([value, label]) => (
                              <SelectItem key={value} value={value}>
                                {label}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>

                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => openEditSession(session)}
                        >
                          Modifier
                        </Button>

                        <Button
                          variant="outline"
                          size="sm"
                          className="border-red-200 text-red-600 hover:bg-red-50 hover:text-red-700"
                          disabled={deletingSessionId === session.id}
                          onClick={() => handleDeleteSession(session)}
                        >
                          {deletingSessionId === session.id
                            ? 'Suppression...'
                            : 'Supprimer'}
                        </Button>

                        <Button
                          size="sm"
                          onClick={() => openCreateSubject(session)}
                          className="bg-primary text-white hover:bg-primary/90"
                        >
                          <Plus className="h-4 w-4" />
                          Ajouter une épreuve
                        </Button>
                      </div>
                    </div>

                    <div className="space-y-3 rounded-2xl border border-slate-200 bg-slate-50/80 p-4">
                      <div className="flex flex-wrap items-center justify-between gap-3">
                        <div>
                          <h2 className="text-sm font-semibold text-gray-900">
                            Épreuves de la session
                          </h2>
                          <p className="mt-1 text-sm text-slate-500">
                            Structurez ici les sujets, durées, séries et barèmes.
                          </p>
                        </div>
                        {subjects.length === 0 && (
                          <Badge className="border border-orange-200 bg-orange-50 text-orange-700">
                            Session incomplète
                          </Badge>
                        )}
                      </div>

                      {subjects.length === 0 ? (
                        <div className="rounded-2xl border border-dashed border-slate-200 bg-white px-4 py-8 text-center text-sm text-slate-400">
                          Ajoutez au moins une épreuve pour rendre cette session
                          exploitable côté élève.
                        </div>
                      ) : (
                        <div className="space-y-3">
                          {subjects.map((subject) => (
                            <div
                              key={subject.id}
                              className="rounded-2xl border border-slate-200 bg-white p-4"
                            >
                              <div className="flex flex-col gap-4 xl:flex-row xl:items-start xl:justify-between">
                                <div className="space-y-3">
                                  <div className="flex flex-wrap items-center gap-2">
                                    <p className="text-sm font-semibold text-gray-900">
                                      {subject.name}
                                    </p>
                                    <Badge className="border border-blue-200 bg-blue-50 text-blue-700">
                                      {SUBJECT_TYPE_LABELS[subject.type]}
                                    </Badge>
                                    <Badge className="border border-purple-200 bg-purple-50 text-purple-700">
                                      coeff. {subject.coefficient}
                                    </Badge>
                                    <Badge className="border border-emerald-200 bg-emerald-50 text-emerald-700">
                                      / {subject.maxScore}
                                    </Badge>
                                  </div>

                                  <div className="flex flex-wrap gap-2 text-xs text-slate-500">
                                    <span className="rounded-full bg-slate-100 px-2.5 py-1">
                                      {subject.startTime.toLocaleDateString('fr-FR')}{' '}
                                      {toTimeInput(subject.startTime)} →{' '}
                                      {subject.endTime.toLocaleDateString('fr-FR')}{' '}
                                      {toTimeInput(subject.endTime)}
                                    </span>
                                    <span className="rounded-full bg-slate-100 px-2.5 py-1">
                                      {subject.durationMinutes} min
                                    </span>
                                    <span className="rounded-full bg-slate-100 px-2.5 py-1">
                                      {describeSubjectAudience(subject, session)}
                                    </span>
                                  </div>

                                  <p className="text-xs text-slate-400">
                                    PDF :{' '}
                                    {subject.subjectFileRef || 'non renseigné'}
                                  </p>

                                  {Object.keys(subject.bareme).length > 0 && (
                                    <p className="text-xs text-slate-500">
                                      Barème : {formatBareme(subject.bareme)}
                                    </p>
                                  )}
                                </div>

                                <div className="flex flex-wrap items-center gap-2">
                                  <Button
                                    variant="outline"
                                    size="sm"
                                    onClick={() => openEditSubject(session, subject)}
                                  >
                                    Modifier
                                  </Button>
                                  <Button
                                    variant="outline"
                                    size="sm"
                                    className="border-red-200 text-red-600 hover:bg-red-50 hover:text-red-700"
                                    disabled={deletingSubjectId === subject.id}
                                    onClick={() =>
                                      handleDeleteSubject(session, subject)
                                    }
                                  >
                                    {deletingSubjectId === subject.id
                                      ? 'Suppression...'
                                      : 'Supprimer'}
                                  </Button>
                                </div>
                              </div>
                            </div>
                          ))}
                        </div>
                      )}
                    </div>
                  </CardContent>
                </Card>
              );
            })}
          </div>
        )}

        <Dialog open={showSessionForm} onOpenChange={setShowSessionForm}>
          <DialogContent className="max-w-lg">
            <DialogHeader>
              <DialogTitle>
                {editingSession ? 'Modifier la session' : 'Nouvelle session'}
              </DialogTitle>
            </DialogHeader>

            <div className="mt-2 space-y-4">
              <div className="space-y-1">
                <Label>Titre</Label>
                <Input
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder="BAC 2026 — Session Normale"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1">
                  <Label>Classe</Label>
                  <Select
                    value={studentClass}
                    onValueChange={(value) =>
                      value
                        ? handleSessionClassChange(
                            value as SessionModel['studentClass']
                          )
                        : undefined
                    }
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {Object.entries(CLASS_LABELS).map(([value, label]) => (
                        <SelectItem key={value} value={value}>
                          {label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>

                <div className="space-y-1">
                  <Label>Tarif (FCFA)</Label>
                  <Input
                    type="number"
                    min={0}
                    value={price}
                    onChange={(e) => setPrice(e.target.value)}
                  />
                </div>

                <div className="space-y-1">
                  <Label>Date de début</Label>
                  <Input
                    type="date"
                    value={startDate}
                    onChange={(e) => setStartDate(e.target.value)}
                  />
                </div>
                <div className="space-y-1">
                  <Label>Date de fin</Label>
                  <Input
                    type="date"
                    value={endDate}
                    onChange={(e) => setEndDate(e.target.value)}
                  />
                </div>
              </div>

              <div className="space-y-2">
                <Label>Séries concernées</Label>
                <p className="text-xs text-gray-500">
                  Les séries cochées ici définissent l&apos;audience globale de la
                  session. Chaque épreuve pourra ensuite viser toutes ou
                  seulement certaines de ces séries.
                </p>
                <div className="flex flex-wrap gap-2">
                  {sessionSeriesOptions.map((series) => (
                    <button
                      key={series}
                      type="button"
                      onClick={() => toggleSeries(series)}
                      className={`rounded-full border px-3 py-1 text-sm font-medium transition-colors ${
                        selectedSeries.includes(series)
                          ? 'border-primary bg-primary text-white'
                          : 'border-gray-300 bg-white text-gray-600 hover:border-primary'
                      }`}
                    >
                      {series}
                    </button>
                  ))}
                </div>
                {studentClass === 'troisieme' && (
                  <p className="text-xs text-gray-400">
                    La session 3ème utilise une audience unique.
                  </p>
                )}
              </div>

              <div className="space-y-1">
                <Label>Statut</Label>
                <Select
                  value={status}
                  onValueChange={(value) => {
                    if (value) {
                      setStatus(value as SessionStatus);
                    }
                  }}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {Object.entries(STATUS_LABELS).map(([value, label]) => (
                      <SelectItem key={value} value={value}>
                        {label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              {!editingSession && (
                <div className="rounded-lg border border-blue-100 bg-blue-50 px-4 py-3 text-sm text-blue-700">
                  Après enregistrement, le formulaire de création d&apos;épreuve
                  s&apos;ouvrira automatiquement.
                </div>
              )}

              <div className="flex justify-end gap-3 pt-2">
                <Button
                  variant="outline"
                  onClick={() => setShowSessionForm(false)}
                >
                  Annuler
                </Button>
                <Button
                  onClick={handleSaveSession}
                  disabled={
                    savingSession ||
                    !title ||
                    !startDate ||
                    !endDate ||
                    selectedSeries.length === 0
                  }
                  className="bg-primary text-white hover:bg-primary/90"
                >
                  {savingSession ? 'Enregistrement...' : 'Enregistrer'}
                </Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>

        <Dialog open={showSubjectForm} onOpenChange={resetSubjectDialog}>
          <DialogContent className="max-h-[90vh] max-w-2xl overflow-y-auto">
            <DialogHeader>
              <DialogTitle>
                {subjectForm.id ? "Modifier l'épreuve" : 'Nouvelle épreuve'}
                {activeSession ? ` — ${activeSession.title}` : ''}
              </DialogTitle>
            </DialogHeader>

            <div className="mt-2 space-y-4">
              <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
                <div className="space-y-1 md:col-span-2">
                  <Label>Nom de l&apos;épreuve</Label>
                  <Input
                    value={subjectForm.name}
                    onChange={(e) =>
                      setSubjectForm((prev) => ({
                        ...prev,
                        name: e.target.value,
                      }))
                    }
                    placeholder="Mathématiques"
                  />
                </div>

                <div className="space-y-1">
                  <Label>Type</Label>
                  <Select
                    value={subjectForm.type}
                    onValueChange={(value) =>
                      value
                        ? setSubjectForm((prev) => ({
                            ...prev,
                            type: value as SubjectModel['type'],
                          }))
                        : undefined
                    }
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {SUBJECT_TYPES.map((type) => (
                        <SelectItem key={type} value={type}>
                          {SUBJECT_TYPE_LABELS[type]}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>

                <div className="space-y-1">
                  <Label>Durée (minutes)</Label>
                  <Input
                    type="number"
                    min={1}
                    value={subjectForm.durationMinutes}
                    onChange={(e) =>
                      setSubjectForm((prev) => ({
                        ...prev,
                        durationMinutes: Number(e.target.value || 0),
                      }))
                    }
                  />
                </div>

                <div className="space-y-1">
                  <Label>Coefficient</Label>
                  <Input
                    type="number"
                    min={1}
                    step="0.5"
                    value={subjectForm.coefficient}
                    onChange={(e) =>
                      setSubjectForm((prev) => ({
                        ...prev,
                        coefficient: Number(e.target.value || 0),
                      }))
                    }
                  />
                </div>

                <div className="space-y-1">
                  <Label>Note maximale</Label>
                  <Input
                    type="number"
                    min={1}
                    step="0.5"
                    value={subjectForm.maxScore}
                    onChange={(e) =>
                      setSubjectForm((prev) => ({
                        ...prev,
                        maxScore: Number(e.target.value || 0),
                      }))
                    }
                  />
                </div>

                <div className="space-y-1">
                  <Label>Date de début</Label>
                  <Input
                    type="date"
                    value={subjectForm.startDate}
                    onChange={(e) =>
                      setSubjectForm((prev) => ({
                        ...prev,
                        startDate: e.target.value,
                      }))
                    }
                  />
                </div>

                <div className="space-y-1">
                  <Label>Heure de début</Label>
                  <Input
                    type="time"
                    value={subjectForm.startTime}
                    onChange={(e) =>
                      setSubjectForm((prev) => ({
                        ...prev,
                        startTime: e.target.value,
                      }))
                    }
                  />
                </div>

                <div className="space-y-1">
                  <Label>Date de fin</Label>
                  <Input
                    type="date"
                    value={subjectForm.endDate}
                    onChange={(e) =>
                      setSubjectForm((prev) => ({
                        ...prev,
                        endDate: e.target.value,
                      }))
                    }
                  />
                </div>

                <div className="space-y-1">
                  <Label>Heure de fin</Label>
                  <Input
                    type="time"
                    value={subjectForm.endTime}
                    onChange={(e) =>
                      setSubjectForm((prev) => ({
                        ...prev,
                        endTime: e.target.value,
                      }))
                    }
                  />
                </div>
              </div>

              <div className="space-y-2">
                <div className="flex items-center justify-between gap-3">
                  <Label>Audience de l&apos;épreuve</Label>
                  {activeSession?.studentClass === 'terminale' &&
                    subjectSeriesOptions.length > 1 && (
                      <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        onClick={() =>
                          setSubjectForm((prev) => ({
                            ...prev,
                            series: [...subjectSeriesOptions],
                          }))
                        }
                      >
                        Toutes les séries
                      </Button>
                    )}
                </div>
                {activeSession?.studentClass === 'terminale' ? (
                  <>
                    <p className="text-xs text-gray-500">
                      La session fixe l&apos;audience globale. Ici, choisis
                      seulement les séries qui reçoivent ce sujet.
                      Exemple: Philosophie = A, C, D ; Physique = C ; SVT = D.
                    </p>
                    <div className="flex flex-wrap gap-2">
                      {subjectSeriesOptions.map((series) => (
                        <button
                          key={series}
                          type="button"
                          onClick={() =>
                            setSubjectForm((prev) => ({
                              ...prev,
                              series: prev.series.includes(series)
                                ? prev.series.filter((item) => item !== series)
                                : [...prev.series, series],
                            }))
                          }
                          className={`rounded-full border px-3 py-1 text-sm font-medium transition-colors ${
                            subjectForm.series.includes(series)
                              ? 'border-primary bg-primary text-white'
                              : 'border-gray-300 bg-white text-gray-600 hover:border-primary'
                          }`}
                        >
                          {series}
                        </button>
                      ))}
                    </div>
                    <p className="text-xs text-gray-400">
                      {subjectSeriesOptions.length > 0 &&
                      normalizeSeriesSelection(
                        subjectForm.series,
                        subjectSeriesOptions
                      ).length === subjectSeriesOptions.length
                        ? 'Ce sujet sera visible pour toutes les séries de la session.'
                        : normalizeSeriesSelection(
                              subjectForm.series,
                              subjectSeriesOptions
                            ).length > 0
                          ? `Ce sujet sera visible uniquement pour : ${normalizeSeriesSelection(
                              subjectForm.series,
                              subjectSeriesOptions
                            ).join(', ')}.`
                          : 'Choisis au moins une série pour cette épreuve.'}
                    </p>
                  </>
                ) : (
                  <p className="text-xs text-gray-400">
                    Cette épreuve sera visible directement par les élèves de 3ème sur mobile.
                  </p>
                )}
              </div>

              <div className="space-y-1">
                <Label>Barème</Label>
                <Textarea
                  value={subjectForm.baremeText}
                  onChange={(e) =>
                    setSubjectForm((prev) => ({
                      ...prev,
                      baremeText: e.target.value,
                    }))
                  }
                  rows={6}
                  placeholder={'Compréhension: 5\nMéthode: 7\nRédaction: 8'}
                />
                <p className="text-xs text-gray-400">
                  Un critère par ligne, au format <code>Nom: points</code>.
                </p>
              </div>

              <div className="space-y-1">
                <Label>Corrigé officiel</Label>
                <Textarea
                  value={subjectForm.corrigeText}
                  onChange={(e) =>
                    setSubjectForm((prev) => ({
                      ...prev,
                      corrigeText: e.target.value,
                    }))
                  }
                  rows={8}
                  placeholder={"Exercice 1 :\n- Question a) : La réponse est X car...\n- Question b) : ...\n\nExercice 2 :\n..."}
                />
                <p className="text-xs text-gray-400">
                  Saisis la solution complète. L&apos;IA s&apos;en servira pour corriger les copies des élèves par comparaison.
                </p>
              </div>

              <div className="space-y-2">
                <Label>PDF du sujet</Label>
                <Input
                  type="file"
                  accept="application/pdf"
                  onChange={(e) =>
                    setSubjectPdfFile(e.target.files?.[0] ?? null)
                  }
                />
                {subjectPdfFile && (
                  <p className="text-xs text-blue-600">
                    Nouveau fichier sélectionné : {subjectPdfFile.name}
                  </p>
                )}
                {!subjectPdfFile && subjectForm.subjectFileRef && (
                  <p className="text-xs text-gray-500">
                    Fichier actuel : {subjectForm.subjectFileRef}
                  </p>
                )}
              </div>

              {subjectError && (
                <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-600">
                  {subjectError}
                </p>
              )}

              <div className="flex justify-end gap-3 pt-2">
                <Button variant="outline" onClick={resetSubjectDialog}>
                  Annuler
                </Button>
                <Button
                  onClick={handleSaveSubject}
                  disabled={savingSubject}
                  className="bg-primary text-white hover:bg-primary/90"
                >
                  {savingSubject ? 'Enregistrement...' : "Enregistrer l'épreuve"}
                </Button>
              </div>
            </div>
        </DialogContent>
      </Dialog>
    </div>
  </div>
  );
}

function StatusPill({ status }: { status: SessionStatus }) {
  const map: Record<SessionStatus, string> = {
    draft: 'border-gray-200 bg-gray-100 text-gray-600',
    open: 'border-blue-200 bg-blue-50 text-blue-700',
    active: 'border-emerald-200 bg-emerald-50 text-emerald-700',
    closed: 'border-orange-200 bg-orange-50 text-orange-700',
    resultsPublished: 'border-purple-200 bg-purple-50 text-purple-700',
  };

  return (
    <span className={`rounded-full border px-2 py-0.5 text-xs font-medium ${map[status]}`}>
      {STATUS_LABELS[status]}
    </span>
  );
}

function SummaryRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between gap-4 border-b border-white/8 pb-3 text-sm last:border-b-0 last:pb-0">
      <span className="text-white/55">{label}</span>
      <span className="text-right font-medium text-white">{value}</span>
    </div>
  );
}

function describeAudience(session: SessionModel): string {
  const classLabel = CLASS_LABELS[session.studentClass];
  const seriesLabel =
    session.series.length > 0 ? session.series.join(', ') : 'Audience générale';

  return `${classLabel} • ${seriesLabel}`;
}

function describeSubjectAudience(
  subject: SubjectModel,
  session: SessionModel
): string {
  if (session.studentClass === 'troisieme') {
    return 'Audience : 3ème';
  }

  const allowedSeries = seriesOptionsForSession(session);
  const appliedSeries = normalizeSeriesSelection(
    subject.series.length > 0 ? subject.series : allowedSeries,
    allowedSeries
  );

  if (appliedSeries.length === 0 || appliedSeries.length === allowedSeries.length) {
    return 'Toutes les séries de la session';
  }

  return `Séries : ${appliedSeries.join(', ')}`;
}

function toDateInput(date: Date): string {
  return new Date(date.getTime() - date.getTimezoneOffset() * 60_000)
    .toISOString()
    .split('T')[0];
}

function toTimeInput(date: Date): string {
  return date.toLocaleTimeString('fr-FR', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });
}

function toLocalDateTime(date: string, time: string): Date | null {
  if (!date || !time) {
    return null;
  }

  const parsed = new Date(`${date}T${time}`);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function parseBareme(value: string): Record<string, number> {
  return value
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .reduce<Record<string, number>>((acc, line) => {
      const [label, points] = line.split(':');
      const parsedPoints = Number(points?.trim());
      if (!label?.trim() || Number.isNaN(parsedPoints)) {
        return acc;
      }
      acc[label.trim()] = parsedPoints;
      return acc;
    }, {});
}

function formatBareme(bareme: Record<string, number>): string {
  return Object.entries(bareme)
    .map(([label, points]) => `${label}: ${points}`)
    .join('\n');
}

function sanitizeFileName(fileName: string): string {
  return fileName
    .toLowerCase()
    .replace(/[^a-z0-9.]+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '');
}
