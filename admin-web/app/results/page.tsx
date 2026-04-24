'use client';

import { useEffect, useState } from 'react';
import {
  AlertTriangle,
  CheckCircle2,
  Clock3,
  Download,
  RefreshCw,
  Send,
  Sparkles,
} from 'lucide-react';
import { httpsCallable } from 'firebase/functions';
import { AdminShell } from '@/components/admin/admin-shell';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { getFirebaseFunctionErrorMessage } from '@/lib/firebase-function-error';
import { getSessions, getSessionSubmissions } from '@/lib/firestore-helpers';
import { functions } from '@/lib/firebase';
import { SessionModel, SubmissionModel, SubmissionStatus } from '@/lib/types';

export default function ResultsPage() {
  return (
    <AdminShell requiredRole="admin">
      <ResultsContent />
    </AdminShell>
  );
}

function ResultsContent() {
  const [sessions, setSessions] = useState<SessionModel[]>([]);
  const [selectedSession, setSelectedSession] = useState<SessionModel | null>(null);
  const [submissions, setSubmissions] = useState<SubmissionModel[]>([]);
  const [loadingSubs, setLoadingSubs] = useState(false);
  const [publishing, setPublishing] = useState(false);
  const [retryingId, setRetryingId] = useState<string | null>(null);
  const [message, setMessage] = useState('');

  useEffect(() => {
    getSessions().then((s) => {
      setSessions(s);
      // Sélectionner automatiquement la session active
      const active = s.find((x) => x.status === 'active' || x.status === 'closed');
      if (active) setSelectedSession(active);
    });
  }, []);

  useEffect(() => {
    if (!selectedSession) return;
    setLoadingSubs(true);
    getSessionSubmissions(selectedSession.id).then((s) => {
      setSubmissions(s);
      setLoadingSubs(false);
    });
  }, [selectedSession]);

  const counts = submissions.reduce(
    (acc, s) => {
      acc[s.status] = (acc[s.status] ?? 0) + 1;
      return acc;
    },
    {} as Record<SubmissionStatus, number>
  );

  const readyToPublish = (counts['humanReviewed'] ?? 0) + (counts['aiReviewed'] ?? 0);
  const alreadyPublished = counts['published'] ?? 0;
  const stillPending =
    (counts['submitted'] ?? 0) +
    (counts['ocrDone'] ?? 0) +
    (counts['pendingHuman'] ?? 0) +
    (counts['error'] ?? 0);
  const rejectedCount = counts['rejected'] ?? 0;
  const effectiveSubmissionCount = submissions.filter(
    (submission) => submission.status !== 'rejected'
  ).length;
  const canFinalizePublication =
    selectedSession !== null &&
    selectedSession.status !== 'resultsPublished' &&
    effectiveSubmissionCount > 0 &&
    stillPending === 0;
  const canRunPublishAction = readyToPublish > 0 || canFinalizePublication;

  async function handlePublishAll() {
    if (!selectedSession) return;
    if (!canRunPublishAction) {
      if (stillPending > 0) {
        setMessage('Certaines copies ne sont pas encore prêtes. Termine le traitement avant de finaliser la session.');
      } else if (selectedSession.status === 'resultsPublished') {
        setMessage('Cette session est déjà finalisée.');
      } else {
        setMessage('Aucune copie exploitable à publier pour cette session.');
      }
      return;
    }
    setPublishing(true);
    setMessage('');
    try {
      const fn = httpsCallable<{ sessionId: string }, { published: number; skipped: number }>(
        functions,
        'publishResults'
      );
      const res = await fn({ sessionId: selectedSession.id });
      setSelectedSession((current) =>
        current == null || current.id !== selectedSession.id
          ? current
          : { ...current, status: 'resultsPublished' }
      );
      setSessions((current) =>
        current.map((session) =>
          session.id === selectedSession.id
            ? { ...session, status: 'resultsPublished' }
            : session
        )
      );

      const skippedSuffix =
        res.data.skipped > 0
          ? ` ${res.data.skipped} élève(s) ont été ignoré(s) car toutes leurs copies exploitables ne sont pas prêtes.`
          : '';

      if (res.data.published > 0) {
        setMessage(
          `✅ ${res.data.published} note(s) publiée(s). La session a été finalisée et les élèves concernés ont été notifiés.${skippedSuffix}`
        );
      } else {
        setMessage(
          `✅ Session finalisée. Les copies déjà publiées ont été consolidées pour les bulletins.${skippedSuffix}`
        );
      }
      // Recharger les soumissions
      const updated = await getSessionSubmissions(selectedSession.id);
      setSubmissions(updated);
    } catch (err) {
      setMessage(
        `❌ Erreur: ${getFirebaseFunctionErrorMessage(err, 'Inconnue')}`
      );
    } finally {
      setPublishing(false);
    }
  }

  function handleExportCsv() {
    if (!selectedSession || submissions.length === 0) return;

    const published = submissions.filter((s) => s.status === 'published');
    if (published.length === 0) {
      setMessage('Aucune note publiée à exporter.');
      return;
    }

    const escape = (v: string | number | undefined) => {
      const str = v === undefined || v === null ? '' : String(v);
      return `"${str.replace(/"/g, '""')}"`;
    };

    const headers = [
      'ID élève',
      'Épreuve',
      'Note finale',
      'Note max',
      'Score IA',
      'Confiance IA (%)',
      'Corrigé par IA',
      'Soumis le',
      'Publié le',
    ];

    const rows = published.map((s) => [
      escape(s.userId),
      escape(s.subjectName),
      escape(s.finalScore),
      escape(s.subjectMaxScore ?? 20),
      escape(s.aiScore),
      escape(s.aiConfidence),
      escape(s.correctorId ? 'Non' : 'Oui'),
      escape(s.submittedAt.toLocaleDateString('fr-FR')),
      escape(s.publishedAt?.toLocaleDateString('fr-FR')),
    ]);

    const csv = [headers.join(','), ...rows.map((r) => r.join(','))].join('\n');
    const blob = new Blob(['\uFEFF' + csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `resultats_${selectedSession.title.replace(/\s+/g, '_')}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  async function handleRetrySubmission(submissionId: string) {
    setRetryingId(submissionId);
    setMessage('');

    try {
      const fn = httpsCallable<{ submissionId: string }, { success: boolean }>(
        functions,
        'retrySubmissionProcessing'
      );
      await fn({ submissionId });

      if (selectedSession != null) {
        const updated = await getSessionSubmissions(selectedSession.id);
        setSubmissions(updated);
      }

      setMessage('✅ Soumission relancée. Le pipeline de traitement a redémarré.');
    } catch (err) {
      setMessage(
        `❌ Erreur: ${getFirebaseFunctionErrorMessage(err, 'Inconnue')}`
      );
    } finally {
      setRetryingId(null);
    }
  }

  return (
    <div className="min-h-full bg-[radial-gradient(circle_at_top_left,rgba(10,17,114,0.09),transparent_26%),linear-gradient(180deg,#f8fafc_0%,#ffffff_38%)] px-6 py-8 lg:px-8">
      <div className="mx-auto max-w-6xl space-y-6">
        <section className="overflow-hidden rounded-[28px] border border-[#0A1172]/10 bg-[#0A1172] text-white shadow-[0_24px_80px_-40px_rgba(10,17,114,0.9)]">
          <div className="grid gap-6 px-6 py-6 lg:grid-cols-[minmax(0,1.45fr)_330px] lg:px-8">
            <div className="space-y-4">
              <Badge className="border border-white/10 bg-white/10 text-white">
                Publication des résultats
              </Badge>

              <div className="space-y-2">
                <h1 className="text-2xl font-semibold tracking-tight lg:text-3xl">
                  Consolidation des notes
                </h1>
                <p className="max-w-2xl text-sm leading-6 text-white/72">
                  Publiez les copies prêtes, finalisez les sessions au bon moment
                  et gardez une lecture nette des blocages avant notification des
                  élèves.
                </p>
              </div>

              <div className="flex flex-wrap gap-2">
                <Badge className="border border-blue-200/30 bg-blue-50/12 text-blue-100">
                  {readyToPublish} prête(s) à publier
                </Badge>
                <Badge className="border border-orange-200/30 bg-orange-50/12 text-orange-100">
                  {stillPending} en attente
                </Badge>
                <Badge className="border border-emerald-200/30 bg-emerald-50/12 text-emerald-100">
                  {alreadyPublished} déjà publiée(s)
                </Badge>
              </div>
            </div>

            <div className="rounded-[24px] border border-white/10 bg-white/8 p-5 backdrop-blur-sm">
              <p className="text-[11px] font-semibold uppercase tracking-[0.22em] text-white/45">
                État courant
              </p>
              {selectedSession && (
                <div className="mt-4 rounded-2xl border border-white/12 bg-white px-4 py-4 text-[#0A1172]">
                  <div className="flex items-start gap-3">
                    <div
                      className={`rounded-xl p-2 ${
                        stillPending > 0
                          ? 'bg-orange-100 text-orange-700'
                          : readyToPublish > 0 || canFinalizePublication
                            ? 'bg-blue-100 text-blue-700'
                            : 'bg-emerald-100 text-emerald-700'
                      }`}
                    >
                      {stillPending > 0 ? (
                        <AlertTriangle className="h-4 w-4" />
                      ) : readyToPublish > 0 || canFinalizePublication ? (
                        <Send className="h-4 w-4" />
                      ) : (
                        <CheckCircle2 className="h-4 w-4" />
                      )}
                    </div>
                    <div>
                      <p className="text-sm font-semibold">
                        {selectedSession.title}
                      </p>
                      <p className="mt-1 text-sm leading-6 opacity-85">
                        {stillPending > 0
                          ? `${stillPending} copie(s) bloquent encore la finalisation.`
                          : readyToPublish > 0
                            ? `${readyToPublish} copie(s) peuvent être publiées immédiatement.`
                            : canFinalizePublication
                              ? 'Toutes les copies exploitables sont déjà publiées, la session peut être finalisée.'
                              : selectedSession.status === 'resultsPublished'
                                ? 'Cette session est déjà finalisée.'
                                : 'Aucune copie exploitable n’est disponible pour la publication.'}
                      </p>
                    </div>
                  </div>
                </div>
              )}

              <div className="mt-4 space-y-3">
                <SummaryRow
                  label="Session active"
                  value={selectedSession?.title ?? 'Aucune'}
                />
                <SummaryRow
                  label="Soumissions exploitables"
                  value={String(effectiveSubmissionCount)}
                />
                <SummaryRow
                  label="Rejets exclus"
                  value={String(rejectedCount)}
                />
              </div>
            </div>
          </div>
        </section>

        {message && (
          <div
            className={`rounded-2xl border px-4 py-3 text-sm ${
              message.startsWith('✅')
                ? 'border-emerald-200 bg-emerald-50 text-emerald-700'
                : 'border-red-200 bg-red-50 text-red-700'
            }`}
          >
            {message}
          </div>
        )}

        <section className="grid gap-6 xl:grid-cols-[290px_minmax(0,1fr)]">
          <Card className="border-0 bg-white/92 shadow-sm ring-1 ring-slate-200/75">
            <CardHeader className="pb-4">
              <CardTitle className="text-base text-gray-900">
                Sessions
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              {sessions.length === 0 ? (
                <div className="rounded-2xl border border-dashed border-slate-200 bg-slate-50/80 px-4 py-8 text-center text-sm text-slate-400">
                  Aucune session disponible.
                </div>
              ) : (
                <div className="grid gap-2">
                  {sessions.map((session) => {
                    const active = selectedSession?.id === session.id;
                    return (
                      <button
                        key={session.id}
                        onClick={() => setSelectedSession(session)}
                        className={`rounded-2xl border px-4 py-4 text-left transition-colors ${
                          active
                            ? 'border-[#0A1172]/15 bg-[#0A1172] text-white'
                            : 'border-slate-200 bg-slate-50 text-slate-700 hover:bg-slate-100'
                        }`}
                      >
                        <div className="flex items-start justify-between gap-3">
                          <div className="min-w-0">
                            <p className="truncate text-sm font-semibold">
                              {session.title}
                            </p>
                            <p
                              className={`mt-1 text-sm ${
                                active ? 'text-white/70' : 'text-slate-500'
                              }`}
                            >
                              {session.status === 'resultsPublished'
                                ? 'Déjà finalisée'
                                : session.status === 'closed'
                                  ? 'Prête pour consolidation'
                                  : session.status === 'active'
                                    ? 'Encore en cours'
                                    : 'Session à surveiller'}
                            </p>
                          </div>
                          <ResultsSessionBadge status={session.status} active={active} />
                        </div>
                      </button>
                    );
                  })}
                </div>
              )}

              <div className="rounded-2xl border border-dashed border-slate-200 bg-slate-50/80 px-4 py-4">
                <div className="flex items-start gap-3">
                  <div className="rounded-xl bg-white p-2 text-slate-500 ring-1 ring-slate-200">
                    <Sparkles className="h-4 w-4" />
                  </div>
                  <div>
                    <p className="text-sm font-semibold text-slate-700">
                      Conseil d’exploitation
                    </p>
                    <p className="mt-1 text-sm leading-6 text-slate-500">
                      Publiez d’abord les copies prêtes, puis finalisez la session
                      seulement quand plus rien n’est bloquant.
                    </p>
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>

          <div className="space-y-6">
            {selectedSession && (
              <>
                <section className="grid grid-cols-2 gap-4 xl:grid-cols-4">
                  {[
                    {
                      label: 'Total',
                      value: submissions.length,
                      helper: 'Toutes les copies',
                      icon: Clock3,
                      tone: 'slate',
                    },
                    {
                      label: 'À traiter',
                      value: stillPending,
                      helper: 'Bloque la finalisation',
                      icon: AlertTriangle,
                      tone: 'orange',
                    },
                    {
                      label: 'Prêtes',
                      value: readyToPublish,
                      helper: 'Publisables immédiatement',
                      icon: Send,
                      tone: 'blue',
                    },
                    {
                      label: 'Publiées',
                      value: alreadyPublished,
                      helper: 'Déjà sorties',
                      icon: CheckCircle2,
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
                            item.tone === 'orange'
                              ? 'border-orange-200 bg-orange-50 text-orange-700'
                              : item.tone === 'blue'
                                ? 'border-blue-200 bg-blue-50 text-blue-700'
                                : item.tone === 'green'
                                  ? 'border-emerald-200 bg-emerald-50 text-emerald-700'
                                  : 'border-slate-200 bg-slate-50 text-slate-700'
                          }`}
                        >
                          <item.icon className="h-5 w-5" />
                        </div>
                        <p
                          className={`mt-5 text-3xl font-semibold tracking-tight ${
                            item.tone === 'orange'
                              ? 'text-orange-700'
                              : item.tone === 'blue'
                                ? 'text-blue-700'
                                : item.tone === 'green'
                                  ? 'text-emerald-700'
                                  : 'text-slate-700'
                          }`}
                        >
                          {item.value}
                        </p>
                        <p className="mt-1 text-sm font-medium text-gray-700">
                          {item.label}
                        </p>
                        <p className="mt-2 text-sm text-gray-500">{item.helper}</p>
                      </CardContent>
                    </Card>
                  ))}
                </section>

                <Card
                  className={`border-0 bg-white/92 shadow-sm ring-1 ring-slate-200/75 ${
                    readyToPublish > 0 ? 'ring-2 ring-blue-200' : ''
                  }`}
                >
                  <CardContent className="p-6">
                    <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                      <div>
                        <div className="flex flex-wrap items-center gap-2">
                          <p className="text-base font-semibold text-gray-900">
                            {selectedSession.title}
                          </p>
                          <ResultsSessionBadge status={selectedSession.status} />
                        </div>
                        <p className="mt-2 text-sm leading-6 text-gray-600">
                          {readyToPublish > 0
                            ? `${readyToPublish} copie(s) corrigée(s) sont prêtes. La publication notifiera les élèves concernés.`
                            : stillPending > 0
                              ? `${stillPending} copie(s) sont encore bloquantes. La finalisation doit attendre.`
                              : canFinalizePublication
                                ? 'Toutes les copies exploitables sont déjà publiées. Vous pouvez finaliser la session pour consolider les bulletins.'
                                : selectedSession.status === 'resultsPublished'
                                  ? 'La session est déjà finalisée et consolidée.'
                                  : 'Aucune note supplémentaire n’est disponible pour cette session.'}
                        </p>

                        {rejectedCount > 0 && (
                          <p className="mt-3 text-sm text-amber-700">
                            {rejectedCount} copie(s) rejetée(s) restent exclues de
                            la publication globale.
                          </p>
                        )}
                      </div>

                      <div className="flex flex-wrap gap-2">
                        {alreadyPublished > 0 && (
                          <Button variant="outline" onClick={handleExportCsv}>
                            <Download className="h-4 w-4" />
                            Exporter CSV
                          </Button>
                        )}
                        <Button
                          onClick={handlePublishAll}
                          disabled={publishing || !canRunPublishAction}
                          className="min-w-40 bg-primary text-white hover:bg-primary/90"
                        >
                          {publishing
                            ? 'Publication...'
                            : readyToPublish > 0
                              ? `Publier (${readyToPublish})`
                              : 'Finaliser la session'}
                        </Button>
                      </div>
                    </div>
                  </CardContent>
                </Card>

                {loadingSubs ? (
                  <Card className="border-0 bg-white/92 shadow-sm ring-1 ring-slate-200/75">
                    <CardContent className="py-16 text-center text-slate-400">
                      Chargement des soumissions...
                    </CardContent>
                  </Card>
                ) : (
                  <Card className="border-0 bg-white/92 shadow-sm ring-1 ring-slate-200/75">
                    <CardHeader className="pb-4">
                      <CardTitle className="text-base text-gray-900">
                        Soumissions de la session ({submissions.length})
                      </CardTitle>
                    </CardHeader>
                    <CardContent>
                      {submissions.length === 0 ? (
                        <div className="rounded-2xl border border-dashed border-slate-200 bg-slate-50/80 px-4 py-10 text-center text-sm text-slate-400">
                          Aucune soumission à publier sur cette session.
                        </div>
                      ) : (
                        <div className="space-y-3">
                          {submissions.map((sub) => (
                            <div
                              key={sub.id}
                              className="rounded-2xl border border-slate-200 bg-white p-4 transition-all hover:border-[#0A1172]/15 hover:shadow-md"
                            >
                              <div className="flex flex-col gap-4 xl:flex-row xl:items-center xl:justify-between">
                                <div className="min-w-0">
                                  <div className="flex flex-wrap items-center gap-2">
                                    <p className="truncate text-sm font-semibold text-gray-900">
                                      {sub.subjectName}
                                    </p>
                                    <SubmissionStatusBadge status={sub.status} />
                                    {sub.aiConfidence !== undefined && (
                                      <Badge className="border border-purple-200 bg-purple-50 text-purple-700">
                                        IA {sub.aiConfidence}%
                                      </Badge>
                                    )}
                                  </div>
                                  <div className="mt-2 flex flex-wrap gap-2 text-xs text-slate-500">
                                    <span className="rounded-full bg-slate-100 px-2.5 py-1">
                                      {sub.submittedAt.toLocaleDateString('fr-FR', {
                                        day: '2-digit',
                                        month: 'short',
                                        hour: '2-digit',
                                        minute: '2-digit',
                                      })}
                                    </span>
                                    {sub.finalScore !== undefined && (
                                      <span className="rounded-full bg-slate-100 px-2.5 py-1 font-medium text-slate-700">
                                        {sub.finalScore}/{sub.subjectMaxScore ?? 20}
                                      </span>
                                    )}
                                  </div>
                                  {sub.status === 'error' && sub.errorReason && (
                                    <p className="mt-3 text-sm text-red-600">
                                      {humanizeSubmissionError(sub.errorReason)}
                                    </p>
                                  )}
                                </div>

                                {sub.status === 'error' && (
                                  <Button
                                    variant="outline"
                                    size="sm"
                                    disabled={retryingId === sub.id}
                                    onClick={() => handleRetrySubmission(sub.id)}
                                  >
                                    <RefreshCw className="h-4 w-4" />
                                    {retryingId === sub.id ? 'Relance...' : 'Relancer'}
                                  </Button>
                                )}
                              </div>
                            </div>
                          ))}
                        </div>
                      )}
                    </CardContent>
                  </Card>
                )}
              </>
            )}
          </div>
        </section>
      </div>
    </div>
  );
}

function humanizeSubmissionError(errorReason: string): string {
  switch (errorReason) {
    case 'subject_not_found':
      return 'Sujet introuvable';
    case 'out_of_time_window':
      return 'Soumission hors délai';
    case 'duplicate_submission':
      return 'Doublon détecté';
    default:
      return errorReason;
  }
}

function SubmissionStatusBadge({ status }: { status: SubmissionStatus }) {
  const map: Record<SubmissionStatus, { label: string; class: string }> = {
    submitted: { label: 'Soumise', class: 'border-gray-200 bg-gray-100 text-gray-600' },
    ocrDone: { label: 'OCR ✓', class: 'border-blue-200 bg-blue-50 text-blue-600' },
    aiReviewed: { label: 'IA ✓', class: 'border-purple-200 bg-purple-50 text-purple-600' },
    pendingHuman: { label: 'En attente', class: 'border-orange-200 bg-orange-50 text-orange-700' },
    humanReviewed: { label: 'Corrigée ✓', class: 'border-blue-200 bg-blue-50 text-blue-700' },
    published: { label: 'Publiée', class: 'border-emerald-200 bg-emerald-50 text-emerald-700' },
    rejected: { label: 'Rejetée', class: 'border-red-200 bg-red-50 text-red-700' },
    error: { label: 'Erreur', class: 'border-red-200 bg-red-50 text-red-700' },
  };
  const s = map[status];
  return (
    <Badge className={`border text-xs ${s.class}`}>{s.label}</Badge>
  );
}

function ResultsSessionBadge({
  status,
  active = false,
}: {
  status: SessionModel['status'];
  active?: boolean;
}) {
  const map: Record<SessionModel['status'], { label: string; className: string }> = {
    draft: {
      label: 'Brouillon',
      className: active
        ? 'border-white/20 bg-white/10 text-white'
        : 'border-slate-200 bg-slate-100 text-slate-600',
    },
    open: {
      label: 'Ouverte',
      className: active
        ? 'border-white/20 bg-white/10 text-white'
        : 'border-blue-200 bg-blue-50 text-blue-700',
    },
    active: {
      label: 'En cours',
      className: active
        ? 'border-white/20 bg-white/10 text-white'
        : 'border-blue-200 bg-blue-50 text-blue-700',
    },
    closed: {
      label: 'Clôturée',
      className: active
        ? 'border-white/20 bg-white/10 text-white'
        : 'border-orange-200 bg-orange-50 text-orange-700',
    },
    resultsPublished: {
      label: 'Publiée',
      className: active
        ? 'border-white/20 bg-white/10 text-white'
        : 'border-emerald-200 bg-emerald-50 text-emerald-700',
    },
  };
  const current = map[status];
  return <Badge className={`border text-xs ${current.className}`}>{current.label}</Badge>;
}

function SummaryRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between gap-4 border-b border-white/8 pb-3 text-sm last:border-b-0 last:pb-0">
      <span className="text-white/55">{label}</span>
      <span className="text-right font-medium text-white">{value}</span>
    </div>
  );
}
