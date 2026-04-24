'use client';

import { type ElementType, useEffect, useState } from 'react';
import Link from 'next/link';
import {
  Activity,
  AlertTriangle,
  ArrowRight,
  CalendarDays,
  ClipboardCheck,
  ClipboardList,
  Clock3,
  CreditCard,
  Send,
  Sparkles,
  Users,
} from 'lucide-react';
import { AdminShell } from '@/components/admin/admin-shell';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { useAuth } from '@/lib/auth-context';
import {
  DashboardStats,
  subscribeToDashboardStats,
  subscribeToPendingHumanSubmissions,
  subscribeToSessions,
} from '@/lib/firestore-helpers';
import { SessionModel, SubmissionModel } from '@/lib/types';

export default function DashboardPage() {
  return (
    <AdminShell>
      <DashboardContent />
    </AdminShell>
  );
}

function DashboardContent() {
  const { profile } = useAuth();
  const [renderNow] = useState(() => new Date());
  const [stats, setStats] = useState<DashboardStats | null>(null);
  const [sessions, setSessions] = useState<SessionModel[]>([]);
  const [recentPending, setRecentPending] = useState<SubmissionModel[]>([]);

  useEffect(() => {
    if (!profile) return;

    const correctorId = profile.role === 'corrector' ? profile.uid : undefined;

    const unsubStats = subscribeToDashboardStats({ correctorId }, setStats);
    const unsubSessions = subscribeToSessions(setSessions);
    const unsubPending = subscribeToPendingHumanSubmissions(
      correctorId,
      (subs) => setRecentPending(subs.slice(0, 5))
    );

    return () => {
      unsubStats();
      unsubSessions();
      unsubPending();
    };
  }, [profile]);

  const isAdmin = profile?.role === 'admin';
  const pendingHuman = stats?.pendingHuman ?? 0;
  const totalSubmissions = stats?.totalSubmissions ?? 0;
  const publishedToday = stats?.publishedToday ?? 0;
  const autoPublished = stats?.autoPublished ?? 0;
  const activeCorrections = profile?.activeCorrections ?? 0;
  const liveSessions = sessions.filter(
    (session) => session.status === 'open' || session.status === 'active'
  );
  const draftSessions = sessions.filter((session) => session.status === 'draft');
  const publishedSessions = sessions.filter(
    (session) => session.status === 'resultsPublished'
  );
  const upcomingSessions = [...sessions]
    .filter((session) => session.endDate >= renderNow)
    .sort((a, b) => a.startDate.getTime() - b.startDate.getTime());
  const nextSession = upcomingSessions[0];
  const overviewSessions = (liveSessions.length > 0 ? liveSessions : sessions).slice(0, 4);
  const primaryActionHref = recentPending[0]
    ? `/corrections/${recentPending[0].id}`
    : '/corrections';
  const primaryActionLabel = recentPending[0]
    ? 'Traiter la priorité'
    : 'Ouvrir les corrections';
  const shellBadges = buildShellBadges({
    isAdmin,
    pendingHuman,
    liveSessionsCount: liveSessions.length,
    autoPublished,
    activeCorrections,
  });
  const focusPanel = buildFocusPanel({
    isAdmin,
    pendingHuman,
    draftSessionsCount: draftSessions.length,
    nextSession,
  });
  const statCards = isAdmin
    ? [
        {
          label: 'Soumissions reçues',
          value: totalSubmissions,
          helper: `${autoPublished} publication(s) automatiques`,
          tone: 'blue' as const,
          icon: ClipboardList,
          urgent: false,
        },
        {
          label: 'En attente de correction',
          value: pendingHuman,
          helper:
            pendingHuman > 0
              ? 'Copies à attribuer ou relire rapidement'
              : 'Aucune copie ne bloque la file',
          tone: 'orange' as const,
          icon: AlertTriangle,
          urgent: pendingHuman > 0,
        },
        {
          label: 'Sessions ouvertes',
          value: liveSessions.length,
          helper:
            liveSessions.length > 0
              ? `${draftSessions.length} brouillon(s) restent à compléter`
              : 'Aucune session en circulation',
          tone: 'indigo' as const,
          icon: CalendarDays,
          urgent: draftSessions.length > 0,
        },
        {
          label: "Notes publiées aujourd'hui",
          value: publishedToday,
          helper: `${publishedSessions.length} session(s) déjà finalisées`,
          tone: 'green' as const,
          icon: Send,
          urgent: false,
        },
      ]
    : [
        {
          label: 'Copies assignées',
          value: totalSubmissions,
          helper: 'Historique des copies liées à votre file',
          tone: 'blue' as const,
          icon: ClipboardList,
          urgent: false,
        },
        {
          label: 'À corriger maintenant',
          value: pendingHuman,
          helper:
            pendingHuman > 0
              ? 'Vos copies en attente immédiate'
              : 'Votre file est vide pour le moment',
          tone: 'orange' as const,
          icon: AlertTriangle,
          urgent: pendingHuman > 0,
        },
        {
          label: 'Corrections actives',
          value: activeCorrections,
          helper: 'Copies déjà prises en charge',
          tone: 'indigo' as const,
          icon: Activity,
          urgent: false,
        },
        {
          label: "Publiées aujourd'hui",
          value: publishedToday,
          helper: 'Notes déjà sorties sur vos copies',
          tone: 'green' as const,
          icon: Send,
          urgent: false,
        },
      ];
  const quickActions = isAdmin
    ? [
        {
          href: '/corrections',
          label: 'Traiter les corrections',
          description:
            pendingHuman > 0
              ? `${pendingHuman} copie(s) demandent une action`
              : 'File de correction sous contrôle',
          icon: ClipboardCheck,
          tone: 'blue' as const,
        },
        {
          href: '/sessions',
          label: 'Piloter les sessions',
          description: `${liveSessions.length} ouvertes, ${draftSessions.length} brouillon(s)`,
          icon: CalendarDays,
          tone: 'indigo' as const,
        },
        {
          href: '/payments',
          label: 'Valider les paiements',
          description: 'Contrôler les preuves reçues et débloquer les accès',
          icon: CreditCard,
          tone: 'amber' as const,
        },
        {
          href: '/results',
          label: 'Publier les résultats',
          description:
            publishedToday > 0
              ? `${publishedToday} note(s) publiées aujourd'hui`
              : 'Finaliser les sessions déjà prêtes',
          icon: Send,
          tone: 'green' as const,
        },
        {
          href: '/users',
          label: 'Suivre les utilisateurs',
          description: 'Gérer les rôles, blocages et comptes correcteurs',
          icon: Users,
          tone: 'slate' as const,
        },
      ]
    : [
        {
          href: primaryActionHref,
          label: 'Reprendre la priorité',
          description: recentPending[0]
            ? `${recentPending[0].subjectName} attend votre correction`
            : 'Aucune copie urgente en attente',
          icon: ClipboardCheck,
          tone: 'blue' as const,
        },
        {
          href: '/corrections',
          label: 'Voir toute la file',
          description:
            pendingHuman > 0
              ? `${pendingHuman} copie(s) restent à traiter`
              : 'Consulter votre historique de corrections',
          icon: ClipboardList,
          tone: 'orange' as const,
        },
        {
          href: '/corrections',
          label: 'Suivre les publications',
          description:
            publishedToday > 0
              ? `${publishedToday} note(s) déjà publiées aujourd'hui`
              : 'Aucune nouvelle publication pour le moment',
          icon: Send,
          tone: 'green' as const,
        },
      ];
  const FocusIcon = focusPanel?.icon;
  const priorityStats = isAdmin
    ? [
        {
          label: 'Copies en file',
          value: pendingHuman,
          icon: ClipboardList,
          tone: 'orange' as const,
        },
        {
          label: 'Sessions live',
          value: liveSessions.length,
          icon: CalendarDays,
          tone: 'indigo' as const,
        },
        {
          label: 'Auto-publiées',
          value: autoPublished,
          icon: Sparkles,
          tone: 'green' as const,
        },
      ]
    : [
        {
          label: 'Dans votre file',
          value: pendingHuman,
          icon: ClipboardList,
          tone: 'orange' as const,
        },
        {
          label: 'Actives',
          value: activeCorrections,
          icon: Activity,
          tone: 'indigo' as const,
        },
        {
          label: 'Publiées',
          value: publishedToday,
          icon: Send,
          tone: 'green' as const,
        },
      ];

  return (
    <div className="min-h-full bg-[radial-gradient(circle_at_top_left,rgba(10,17,114,0.09),transparent_28%),linear-gradient(180deg,#f8fafc_0%,#ffffff_38%)] px-6 py-8 lg:px-8">
      <div className="mx-auto max-w-6xl space-y-6">
        <section className="overflow-hidden rounded-[28px] border border-[#0A1172]/10 bg-[#0A1172] text-white shadow-[0_24px_80px_-40px_rgba(10,17,114,0.9)]">
          <div className="grid gap-6 px-6 py-6 lg:grid-cols-[minmax(0,1.45fr)_340px] lg:px-8">
            <div className="space-y-4">
              <Badge className="border border-white/10 bg-white/10 text-white">
                En direct
              </Badge>

              <div className="space-y-2">
                <h1 className="text-2xl font-semibold tracking-tight lg:text-3xl">
                  Bonjour, {profile?.displayName}
                </h1>
                <p className="max-w-2xl text-sm leading-6 text-white/72">
                  {isAdmin
                    ? "Vue d'ensemble de l'exploitation: corrections, sessions, publications et points de friction."
                    : 'Votre file de correction, vos urgences et les prochaines copies à traiter sont regroupées ici.'}
                </p>
              </div>

              {shellBadges.length > 0 && (
                <div className="flex flex-wrap gap-2">
                  {shellBadges.map((item) => (
                    <Badge
                      key={item.label}
                      className={`border ${item.className}`}
                    >
                      {item.label}
                    </Badge>
                  ))}
                </div>
              )}

              <div className="flex flex-wrap gap-3 pt-2">
                <Link
                  href={primaryActionHref}
                  className="inline-flex items-center gap-2 rounded-xl bg-[#F5B731] px-4 py-2 text-sm font-semibold text-[#0A1172] transition-transform hover:-translate-y-0.5"
                >
                  {primaryActionLabel}
                  <ArrowRight className="h-4 w-4" />
                </Link>

                {isAdmin && (
                  <Link
                    href="/sessions"
                    className="inline-flex items-center gap-2 rounded-xl border border-white/14 bg-white/8 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-white/12"
                  >
                    Gérer les sessions
                    <CalendarDays className="h-4 w-4" />
                  </Link>
                )}
              </div>
            </div>

            <div className="rounded-[24px] border border-white/10 bg-white/8 p-5 backdrop-blur-sm">
              <p className="text-[11px] font-semibold uppercase tracking-[0.22em] text-white/45">
                Cap du jour
              </p>

              {focusPanel && FocusIcon && (
                <div className={`mt-4 rounded-2xl border px-4 py-4 ${focusPanel.panelClassName}`}>
                  <div className="flex items-start gap-3">
                    <div className={`rounded-xl p-2 ${focusPanel.iconClassName}`}>
                      <FocusIcon className="h-4 w-4" />
                    </div>
                    <div>
                      <p className="text-sm font-semibold">{focusPanel.title}</p>
                      <p className="mt-1 text-sm leading-6 opacity-85">
                        {focusPanel.description}
                      </p>
                    </div>
                  </div>
                </div>
              )}

              <div className="mt-4 space-y-3">
                <SummaryRow
                  label={isAdmin ? 'Sessions en circulation' : 'File à traiter'}
                  value={
                    isAdmin
                      ? `${liveSessions.length} active(s) ou ouverte(s)`
                      : `${pendingHuman} copie(s) à corriger`
                  }
                />
                <SummaryRow
                  label={isAdmin ? 'Brouillons à compléter' : 'Corrections actives'}
                  value={
                    isAdmin
                      ? `${draftSessions.length} session(s) en brouillon`
                      : `${activeCorrections} copie(s) déjà en cours`
                  }
                />
                <SummaryRow
                  label="Prochaine échéance"
                  value={
                    nextSession
                      ? `${nextSession.title} • ${formatShortDate(nextSession.startDate)}`
                      : 'Aucune session planifiée'
                  }
                />
              </div>
            </div>
          </div>
        </section>

        <section className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
          {statCards.map((card) => (
            <MetricCard key={card.label} {...card} />
          ))}
        </section>

        <section className="grid gap-6 xl:grid-cols-[minmax(0,1.2fr)_360px]">
          <Card className="border-0 bg-white/92 shadow-sm ring-1 ring-slate-200/75">
            <CardHeader className="pb-4">
              <div className="flex items-center justify-between gap-4">
                <div>
                  <CardTitle className="text-base text-gray-900">
                    Priorités du jour
                  </CardTitle>
                  <p className="mt-1 text-sm text-gray-500">
                    Les éléments qui demandent une action rapide avant qu&apos;ils
                    ne bloquent l&apos;expérience élève.
                  </p>
                </div>
                <Link
                  href="/corrections"
                  className="inline-flex items-center gap-1 text-sm font-medium text-primary hover:underline"
                >
                  Voir tout
                  <ArrowRight className="h-4 w-4" />
                </Link>
              </div>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="grid gap-3 sm:grid-cols-3">
                {priorityStats.map((item) => (
                  <MiniStat key={item.label} {...item} />
                ))}
              </div>

              {recentPending.length === 0 ? (
                <div className="rounded-2xl border border-dashed border-slate-200 bg-slate-50/90 px-5 py-10 text-center">
                  <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-2xl bg-white text-slate-400 shadow-sm ring-1 ring-slate-200">
                    <ClipboardCheck className="h-5 w-5" />
                  </div>
                  <p className="mt-4 text-sm font-medium text-slate-600">
                    Aucune copie urgente en attente
                  </p>
                  <p className="mt-1 text-sm text-slate-400">
                    Le flux est propre pour le moment. Revenez ici dès qu&apos;une
                    nouvelle soumission demande une correction humaine.
                  </p>
                </div>
              ) : (
                <div className="space-y-3">
                  {recentPending.map((submission) => (
                    <Link
                      key={submission.id}
                      href={`/corrections/${submission.id}`}
                      className="block rounded-2xl border border-slate-200 bg-white/95 transition-all hover:border-[#0A1172]/20 hover:shadow-md"
                    >
                      <div className="flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between">
                        <div className="min-w-0">
                          <div className="flex flex-wrap items-center gap-2">
                            <p className="truncate text-sm font-semibold text-gray-900">
                              {submission.subjectName}
                            </p>
                            <UrgencyBadge
                              submittedAt={submission.submittedAt}
                              now={renderNow}
                            />
                            {submission.aiConfidence !== undefined && (
                              <Badge className="border border-purple-200 bg-purple-50 text-purple-700">
                                IA {submission.aiConfidence}%
                              </Badge>
                            )}
                          </div>
                          <p className="mt-1 text-sm text-gray-500">
                            Soumise {formatDelay(submission.submittedAt, renderNow)} •{' '}
                            {submission.submittedAt.toLocaleDateString('fr-FR', {
                              day: '2-digit',
                              month: 'short',
                              hour: '2-digit',
                              minute: '2-digit',
                            })}
                          </p>
                        </div>

                        <div className="flex items-center gap-4">
                          {submission.aiScore !== undefined && (
                            <div className="text-right">
                              <p className="text-xs font-medium text-purple-600">
                                Suggestion IA
                              </p>
                              <p className="text-sm font-semibold text-gray-900">
                                {submission.aiScore}/{submission.subjectMaxScore ?? 20}
                              </p>
                            </div>
                          )}
                          <span className="inline-flex items-center gap-1 text-sm font-medium text-[#0A1172]">
                            Ouvrir
                            <ArrowRight className="h-4 w-4" />
                          </span>
                        </div>
                      </div>
                    </Link>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>

          <div className="space-y-6">
            <Card className="border-0 bg-white/92 shadow-sm ring-1 ring-slate-200/75">
              <CardHeader className="pb-4">
                <CardTitle className="text-base text-gray-900">
                  Actions rapides
                </CardTitle>
              </CardHeader>
              <CardContent className="grid gap-3">
                {quickActions.map((action) => (
                  <ActionTile key={action.label} {...action} />
                ))}
              </CardContent>
            </Card>

            <Card className="border-0 bg-white/92 shadow-sm ring-1 ring-slate-200/75">
              <CardHeader className="pb-4">
                <div className="flex items-center justify-between gap-4">
                  <CardTitle className="text-base text-gray-900">
                    Sessions à suivre
                  </CardTitle>
                  {isAdmin && (
                    <Link
                      href="/sessions"
                      className="text-sm font-medium text-primary hover:underline"
                    >
                      Gérer
                    </Link>
                  )}
                </div>
              </CardHeader>
              <CardContent>
                {overviewSessions.length === 0 ? (
                  <div className="rounded-2xl border border-dashed border-slate-200 bg-slate-50/80 px-4 py-8 text-center text-sm text-slate-400">
                    Aucune session à afficher pour le moment.
                  </div>
                ) : (
                  <div className="space-y-3">
                    {overviewSessions.map((session) => (
                      <div
                        key={session.id}
                        className="rounded-2xl border border-slate-200 bg-white p-4"
                      >
                        <div className="flex items-start justify-between gap-3">
                          <div className="min-w-0">
                            <p className="truncate text-sm font-semibold text-gray-900">
                              {session.title}
                            </p>
                            <p className="mt-1 text-sm text-gray-500">
                              {describeAudience(session)} •{' '}
                              {formatSessionRange(session)}
                            </p>
                          </div>
                          <StatusBadge status={session.status} />
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>
          </div>
        </section>
      </div>
    </div>
  );
}

type Tone = 'amber' | 'blue' | 'green' | 'indigo' | 'orange' | 'slate';

function MetricCard({
  icon: Icon,
  label,
  value,
  helper,
  tone,
  urgent,
}: {
  icon: ElementType;
  label: string;
  value: number;
  helper: string;
  tone: Tone;
  urgent: boolean;
}) {
  const styles = toneStyles[tone];

  return (
    <Card
      className={`border-0 bg-white/92 shadow-sm ring-1 ring-slate-200/75 ${urgent ? 'ring-2 ring-orange-200' : ''}`}
    >
      <CardContent className="p-5">
        <div className="flex items-start justify-between gap-3">
          <div className={`rounded-2xl border p-3 ${styles.soft}`}>
            <Icon className={`h-5 w-5 ${styles.text}`} />
          </div>
          {urgent && (
            <Badge className="border border-orange-200 bg-orange-50 text-orange-700">
              À surveiller
            </Badge>
          )}
        </div>

        <div className="mt-5">
          <p className={`text-3xl font-semibold tracking-tight ${styles.text}`}>
            {value}
          </p>
          <p className="mt-1 text-sm font-medium text-gray-700">{label}</p>
          <p className="mt-2 text-sm leading-6 text-gray-500">{helper}</p>
        </div>
      </CardContent>
    </Card>
  );
}

function MiniStat({
  icon: Icon,
  label,
  value,
  tone,
}: {
  icon: ElementType;
  label: string;
  value: number;
  tone: Tone;
}) {
  const styles = toneStyles[tone];

  return (
    <div className={`rounded-2xl border px-4 py-4 ${styles.soft}`}>
      <div className="flex items-center gap-2">
        <Icon className={`h-4 w-4 ${styles.text}`} />
        <p className="text-sm font-medium text-gray-700">{label}</p>
      </div>
      <p className={`mt-3 text-2xl font-semibold ${styles.text}`}>{value}</p>
    </div>
  );
}

function ActionTile({
  href,
  icon: Icon,
  label,
  description,
  tone,
}: {
  href: string;
  icon: ElementType;
  label: string;
  description: string;
  tone: Tone;
}) {
  const styles = toneStyles[tone];

  return (
    <Link
      href={href}
      className={`group rounded-2xl border px-4 py-4 transition-all hover:-translate-y-0.5 hover:shadow-md ${styles.soft}`}
    >
      <div className="flex items-start justify-between gap-3">
        <div className={`rounded-xl border p-2 ${styles.iconBox}`}>
          <Icon className={`h-4 w-4 ${styles.text}`} />
        </div>
        <ArrowRight className="h-4 w-4 text-gray-400 transition-transform group-hover:translate-x-0.5" />
      </div>

      <p className="mt-4 text-sm font-semibold text-gray-900">{label}</p>
      <p className="mt-1 text-sm leading-6 text-gray-500">{description}</p>
    </Link>
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

function UrgencyBadge({
  submittedAt,
  now,
}: {
  submittedAt: Date;
  now: Date;
}) {
  const diffHours = (now.getTime() - submittedAt.getTime()) / 3_600_000;

  if (diffHours >= 24) {
    return (
      <Badge className="border border-red-200 bg-red-50 text-red-700">
        Priorité haute
      </Badge>
    );
  }

  if (diffHours >= 8) {
    return (
      <Badge className="border border-orange-200 bg-orange-50 text-orange-700">
        À traiter vite
      </Badge>
    );
  }

  return (
    <Badge className="border border-blue-200 bg-blue-50 text-blue-700">
      Récent
    </Badge>
  );
}

function StatusBadge({ status }: { status: string }) {
  const map: Record<string, { label: string; className: string }> = {
    draft: {
      label: 'Brouillon',
      className: 'border-gray-200 bg-gray-100 text-gray-600',
    },
    open: {
      label: 'Ouverte',
      className: 'border-blue-200 bg-blue-50 text-blue-700',
    },
    active: {
      label: 'En cours',
      className: 'border-green-200 bg-green-50 text-green-700',
    },
    closed: {
      label: 'Fermée',
      className: 'border-orange-200 bg-orange-50 text-orange-700',
    },
    resultsPublished: {
      label: 'Publiée',
      className: 'border-purple-200 bg-purple-50 text-purple-700',
    },
  };
  const current = map[status] ?? {
    label: status,
    className: 'border-gray-200 bg-gray-100 text-gray-600',
  };

  return <Badge className={`border ${current.className}`}>{current.label}</Badge>;
}

function buildShellBadges({
  isAdmin,
  pendingHuman,
  liveSessionsCount,
  autoPublished,
  activeCorrections,
}: {
  isAdmin: boolean;
  pendingHuman: number;
  liveSessionsCount: number;
  autoPublished: number;
  activeCorrections: number;
}) {
  const items: { label: string; className: string }[] = [];

  if (pendingHuman > 0) {
    items.push({
      label: `${pendingHuman} correction(s) en attente`,
      className: 'border-orange-200/30 bg-orange-50/12 text-orange-100',
    });
  }

  if (isAdmin && liveSessionsCount > 0) {
    items.push({
      label: `${liveSessionsCount} session(s) en circulation`,
      className: 'border-blue-200/30 bg-blue-50/12 text-blue-100',
    });
  }

  if (isAdmin && autoPublished > 0) {
    items.push({
      label: `${autoPublished} copies auto-publiées`,
      className: 'border-emerald-200/30 bg-emerald-50/12 text-emerald-100',
    });
  }

  if (!isAdmin && activeCorrections > 0) {
    items.push({
      label: `${activeCorrections} correction(s) déjà prises en charge`,
      className: 'border-indigo-200/30 bg-indigo-50/12 text-indigo-100',
    });
  }

  return items;
}

function buildFocusPanel({
  isAdmin,
  pendingHuman,
  draftSessionsCount,
  nextSession,
}: {
  isAdmin: boolean;
  pendingHuman: number;
  draftSessionsCount: number;
  nextSession?: SessionModel;
}) {
  if (pendingHuman > 0) {
    return {
      icon: AlertTriangle,
      title: isAdmin
        ? 'La file de correction demande une action'
        : 'Des copies vous attendent',
      description: isAdmin
        ? `${pendingHuman} copie(s) attendent encore une correction humaine. C'est le premier point à vider pour éviter les retards de publication.`
        : `${pendingHuman} copie(s) sont prêtes pour votre relecture. Reprenez la plus ancienne pour garder un flux régulier.`,
      panelClassName: 'border-orange-200/40 bg-orange-50 text-orange-950',
      iconClassName: 'bg-orange-100 text-orange-700',
    };
  }

  if (isAdmin && draftSessionsCount > 0) {
    return {
      icon: CalendarDays,
      title: 'Des sessions restent incomplètes',
      description: `${draftSessionsCount} session(s) sont encore en brouillon. Finalisez les épreuves et l'ouverture avant la prochaine vague d'élèves.`,
      panelClassName: 'border-blue-200/40 bg-blue-50 text-blue-950',
      iconClassName: 'bg-blue-100 text-blue-700',
    };
  }

  if (nextSession) {
    return {
      icon: Clock3,
      title: 'Prochaine échéance identifiée',
      description: `${nextSession.title} démarre le ${formatShortDate(nextSession.startDate)}. Préparez le terrain avant l'ouverture.`,
      panelClassName: 'border-white/15 bg-white text-[#0A1172]',
      iconClassName: 'bg-[#EEF2FF] text-[#0A1172]',
    };
  }

  return null;
}

function formatDelay(date: Date, now: Date): string {
  const elapsedMinutes = Math.max(
    1,
    Math.round((now.getTime() - date.getTime()) / 60_000)
  );

  if (elapsedMinutes < 60) {
    return `il y a ${elapsedMinutes} min`;
  }

  const elapsedHours = Math.round(elapsedMinutes / 60);
  if (elapsedHours < 24) {
    return `il y a ${elapsedHours} h`;
  }

  const elapsedDays = Math.round(elapsedHours / 24);
  return `il y a ${elapsedDays} j`;
}

function formatShortDate(date: Date): string {
  return date.toLocaleDateString('fr-FR', {
    day: '2-digit',
    month: 'short',
  });
}

function formatSessionRange(session: SessionModel): string {
  return `${formatShortDate(session.startDate)} → ${formatShortDate(session.endDate)}`;
}

function describeAudience(session: SessionModel): string {
  const classLabel =
    session.studentClass === 'terminale' ? 'Terminale' : '3ème';
  const seriesLabel =
    session.series.length > 0 ? session.series.join(', ') : 'Audience générale';

  return `${classLabel} • ${seriesLabel}`;
}

const toneStyles: Record<
  Tone,
  { soft: string; text: string; iconBox: string }
> = {
  amber: {
    soft: 'border-amber-200 bg-amber-50/90',
    text: 'text-amber-700',
    iconBox: 'border-amber-200 bg-amber-50',
  },
  blue: {
    soft: 'border-blue-200 bg-blue-50/90',
    text: 'text-blue-700',
    iconBox: 'border-blue-200 bg-blue-50',
  },
  green: {
    soft: 'border-emerald-200 bg-emerald-50/90',
    text: 'text-emerald-700',
    iconBox: 'border-emerald-200 bg-emerald-50',
  },
  indigo: {
    soft: 'border-indigo-200 bg-indigo-50/90',
    text: 'text-indigo-700',
    iconBox: 'border-indigo-200 bg-indigo-50',
  },
  orange: {
    soft: 'border-orange-200 bg-orange-50/90',
    text: 'text-orange-700',
    iconBox: 'border-orange-200 bg-orange-50',
  },
  slate: {
    soft: 'border-slate-200 bg-slate-50/90',
    text: 'text-slate-700',
    iconBox: 'border-slate-200 bg-slate-50',
  },
};
