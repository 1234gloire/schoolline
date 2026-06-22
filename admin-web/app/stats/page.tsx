'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { RefreshCw } from 'lucide-react';
import { AdminShell } from '@/components/admin/admin-shell';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import {
  getUsers,
  getSessions,
  getAllPayments,
  getSubmissionStats,
  SubmissionStats,
} from '@/lib/firestore-helpers';
import { UserProfile, SessionModel, PaymentModel } from '@/lib/types';

export default function StatsPage() {
  return (
    <AdminShell requiredRole="admin">
      <StatsContent />
    </AdminShell>
  );
}

// ─── Status labels ────────────────────────────────────────────────

const SUBMISSION_PIPELINE: { key: string; label: string; color: string }[] = [
  { key: 'submitted',     label: 'Soumis',              color: 'bg-slate-400'   },
  { key: 'ocrDone',       label: 'OCR terminé',         color: 'bg-blue-400'    },
  { key: 'aiReviewed',    label: 'Noté par IA',         color: 'bg-violet-400'  },
  { key: 'pendingHuman',  label: 'En attente correcteur', color: 'bg-yellow-400' },
  { key: 'humanReviewed', label: 'Corrigé',             color: 'bg-orange-400'  },
  { key: 'published',     label: 'Publié',              color: 'bg-emerald-500' },
  { key: 'rejected',      label: 'Rejeté',              color: 'bg-red-400'     },
  { key: 'error',         label: 'Erreur',              color: 'bg-red-300'     },
];

const SESSION_STATUSES: { key: string; label: string; color: string }[] = [
  { key: 'draft',             label: 'Brouillon',  color: 'bg-slate-300'   },
  { key: 'open',              label: 'Ouverte',    color: 'bg-blue-400'    },
  { key: 'active',            label: 'Active',     color: 'bg-emerald-400' },
  { key: 'closed',            label: 'Fermée',     color: 'bg-orange-400'  },
  { key: 'resultsPublished',  label: 'Publiée',    color: 'bg-purple-400'  },
];

// ─── Main component ───────────────────────────────────────────────

function StatsContent() {
  const [users,       setUsers]       = useState<UserProfile[]>([]);
  const [sessions,    setSessions]    = useState<SessionModel[]>([]);
  const [payments,    setPayments]    = useState<PaymentModel[]>([]);
  const [subStats,    setSubStats]    = useState<SubmissionStats | null>(null);
  const [loading,     setLoading]     = useState(true);
  const [lastLoaded,  setLastLoaded]  = useState<Date | null>(null);

  const loadAll = useCallback(async () => {
    setLoading(true);
    try {
      const [u, s, p, st] = await Promise.all([
        getUsers(),
        getSessions(),
        getAllPayments(),
        getSubmissionStats(),
      ]);
      setUsers(u);
      setSessions(s);
      setPayments(p);
      setSubStats(st);
      setLastLoaded(new Date());
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { loadAll(); }, [loadAll]);

  // ── KPIs ─────────────────────────────────────────────────────────
  const students   = users.filter((u) => u.role === 'student').length;
  const correctors = users.filter((u) => u.role === 'corrector').length;
  const admins     = users.filter((u) => u.role === 'admin').length;

  const approvedRevenue = useMemo(
    () => payments.filter((p) => p.status === 'approved').reduce((s, p) => s + p.amount, 0),
    [payments]
  );
  const pendingRevenue = useMemo(
    () => payments.filter((p) => p.status === 'pending').reduce((s, p) => s + p.amount, 0),
    [payments]
  );

  const publishedCount = subStats?.byStatus['published'] ?? 0;
  const totalSubs      = subStats?.total ?? 0;
  const pubRate        = totalSubs > 0 ? Math.round((publishedCount / totalSubs) * 100) : 0;

  // ── Sessions par statut ───────────────────────────────────────────
  const sessionsByStatus = useMemo(() => {
    const m: Record<string, number> = {};
    for (const s of sessions) { m[s.status] = (m[s.status] ?? 0) + 1; }
    return m;
  }, [sessions]);

  // ── Paiements par statut ──────────────────────────────────────────
  const payByStatus = useMemo(() => {
    const approved = payments.filter((p) => p.status === 'approved');
    const pending  = payments.filter((p) => p.status === 'pending');
    const rejected = payments.filter((p) => p.status === 'rejected');
    return { approved, pending, rejected };
  }, [payments]);

  // ── Revenus 6 derniers mois ───────────────────────────────────────
  const revenueByMonth = useMemo(() => {
    const now   = new Date();
    const months: { label: string; amount: number }[] = [];
    for (let i = 5; i >= 0; i--) {
      const d     = new Date(now.getFullYear(), now.getMonth() - i, 1);
      const label = d.toLocaleDateString('fr-FR', { month: 'short', year: '2-digit' });
      const start = d;
      const end   = new Date(d.getFullYear(), d.getMonth() + 1, 1);
      const amount = payments
        .filter((p) => p.status === 'approved' && p.submittedAt >= start && p.submittedAt < end)
        .reduce((s, p) => s + p.amount, 0);
      months.push({ label, amount });
    }
    return months;
  }, [payments]);

  const maxRevenue = Math.max(...revenueByMonth.map((m) => m.amount), 1);

  // ── Nouveaux élèves ce mois ───────────────────────────────────────
  const thisMonth = new Date(); thisMonth.setDate(1); thisMonth.setHours(0,0,0,0);
  const newStudentsThisMonth = users.filter(
    (u) => u.role === 'student' && u.createdAt >= thisMonth
  ).length;

  return (
    <div className="p-8">
      <div className="mx-auto max-w-7xl space-y-8">

        {/* En-tête */}
        <div className="flex items-start justify-between">
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Statistiques</h1>
            <p className="mt-1 text-sm text-gray-500">
              {lastLoaded
                ? `Dernière mise à jour : ${lastLoaded.toLocaleTimeString('fr-FR')}`
                : 'Chargement…'}
            </p>
          </div>
          <Button variant="outline" size="sm" onClick={loadAll} disabled={loading}>
            <RefreshCw className={`w-4 h-4 mr-2 ${loading ? 'animate-spin' : ''}`} />
            Rafraîchir
          </Button>
        </div>

        {/* ── KPIs ── */}
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          <KpiCard label="Élèves inscrits"    value={students.toLocaleString('fr-FR')}
            sub={`+${newStudentsThisMonth} ce mois`} color="text-emerald-600" />
          <KpiCard label="Revenus approuvés"  value={`${approvedRevenue.toLocaleString('fr-FR')} F`}
            sub={`${pendingRevenue.toLocaleString('fr-FR')} F en attente`} color="text-blue-600" />
          <KpiCard label="Copies soumises"    value={totalSubs.toLocaleString('fr-FR')}
            sub={`${subStats?.aiOnly ?? 0} publiées auto IA`} color="text-violet-600" />
          <KpiCard label="Taux de publication" value={`${pubRate} %`}
            sub={`${publishedCount} publiées / ${totalSubs} total`} color="text-orange-600" />
        </div>

        {/* ── Pipeline corrections ── */}
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Pipeline de correction</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            {/* Barre empilée */}
            <div className="flex h-6 w-full overflow-hidden rounded-full bg-gray-100">
              {SUBMISSION_PIPELINE.map(({ key, color }) => {
                const count = subStats?.byStatus[key] ?? 0;
                const pct   = totalSubs > 0 ? (count / totalSubs) * 100 : 0;
                return pct > 0 ? (
                  <div
                    key={key}
                    className={`${color} transition-all`}
                    style={{ width: `${pct}%` }}
                    title={`${count}`}
                  />
                ) : null;
              })}
            </div>
            {/* Légende */}
            <div className="grid grid-cols-2 gap-x-8 gap-y-2 sm:grid-cols-4">
              {SUBMISSION_PIPELINE.map(({ key, label, color }) => {
                const count = subStats?.byStatus[key] ?? 0;
                const pct   = totalSubs > 0 ? Math.round((count / totalSubs) * 100) : 0;
                return (
                  <div key={key} className="flex items-center gap-2 text-sm">
                    <span className={`h-2.5 w-2.5 shrink-0 rounded-full ${color}`} />
                    <span className="text-gray-600 truncate">{label}</span>
                    <span className="ml-auto font-semibold text-gray-900">{count}</span>
                    <span className="text-gray-400 text-xs">({pct}%)</span>
                  </div>
                );
              })}
            </div>
          </CardContent>
        </Card>

        {/* ── Revenus + Sessions ── */}
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">

          {/* Revenus 6 mois */}
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Revenus — 6 derniers mois</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {revenueByMonth.map(({ label, amount }) => (
                <div key={label} className="flex items-center gap-3">
                  <span className="w-14 shrink-0 text-xs text-gray-500 uppercase">{label}</span>
                  <div className="flex-1 h-5 rounded bg-gray-100 overflow-hidden">
                    <div
                      className="h-full rounded bg-blue-500 transition-all"
                      style={{ width: `${(amount / maxRevenue) * 100}%` }}
                    />
                  </div>
                  <span className="w-28 shrink-0 text-right text-sm font-medium text-gray-800">
                    {amount.toLocaleString('fr-FR')} F
                  </span>
                </div>
              ))}
              {revenueByMonth.every((m) => m.amount === 0) && (
                <p className="py-4 text-center text-sm text-gray-400">Aucun revenu sur la période.</p>
              )}
            </CardContent>
          </Card>

          {/* Sessions par statut */}
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Sessions par statut</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {SESSION_STATUSES.map(({ key, label, color }) => {
                const count = sessionsByStatus[key] ?? 0;
                const pct   = sessions.length > 0 ? (count / sessions.length) * 100 : 0;
                return (
                  <div key={key} className="flex items-center gap-3">
                    <span className="w-20 shrink-0 text-xs text-gray-500">{label}</span>
                    <div className="flex-1 h-5 rounded bg-gray-100 overflow-hidden">
                      <div
                        className={`h-full rounded ${color} transition-all`}
                        style={{ width: `${pct}%` }}
                      />
                    </div>
                    <span className="w-8 shrink-0 text-right text-sm font-semibold text-gray-800">{count}</span>
                  </div>
                );
              })}
              <p className="pt-1 text-xs text-gray-400 text-right">{sessions.length} session(s) au total</p>
            </CardContent>
          </Card>
        </div>

        {/* ── Paiements + Utilisateurs ── */}
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">

          {/* Paiements */}
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Paiements</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              {[
                { label: 'Approuvés', items: payByStatus.approved, color: 'bg-emerald-500', text: 'text-emerald-700' },
                { label: 'En attente', items: payByStatus.pending,  color: 'bg-yellow-400',  text: 'text-yellow-700' },
                { label: 'Rejetés',   items: payByStatus.rejected, color: 'bg-red-400',     text: 'text-red-600'   },
              ].map(({ label, items, color, text }) => {
                const total    = payments.length;
                const pct      = total > 0 ? Math.round((items.length / total) * 100) : 0;
                const amount   = items.reduce((s, p) => s + p.amount, 0);
                return (
                  <div key={label} className="space-y-1">
                    <div className="flex justify-between text-sm">
                      <span className="font-medium text-gray-700">{label}</span>
                      <span className={`font-semibold ${text}`}>
                        {items.length} · {amount.toLocaleString('fr-FR')} F
                      </span>
                    </div>
                    <div className="h-3 w-full rounded bg-gray-100 overflow-hidden">
                      <div className={`h-full rounded ${color}`} style={{ width: `${pct}%` }} />
                    </div>
                    <p className="text-xs text-gray-400 text-right">{pct}% des transactions</p>
                  </div>
                );
              })}
            </CardContent>
          </Card>

          {/* Utilisateurs */}
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Utilisateurs</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              {[
                { label: 'Élèves',      count: students,   sub: `+${newStudentsThisMonth} ce mois`, color: 'bg-emerald-500' },
                { label: 'Correcteurs', count: correctors, sub: `${subStats?.byStatus['pendingHuman'] ?? 0} copies en attente`, color: 'bg-blue-500' },
                { label: 'Admins',      count: admins,     sub: 'Accès complet', color: 'bg-purple-500' },
              ].map(({ label, count, sub, color }) => {
                const total = users.length;
                const pct   = total > 0 ? Math.round((count / total) * 100) : 0;
                return (
                  <div key={label} className="space-y-1">
                    <div className="flex justify-between text-sm">
                      <span className="font-medium text-gray-700">{label}</span>
                      <span className="font-bold text-gray-900">{count}</span>
                    </div>
                    <div className="h-3 w-full rounded bg-gray-100 overflow-hidden">
                      <div className={`h-full rounded ${color}`} style={{ width: `${pct}%` }} />
                    </div>
                    <p className="text-xs text-gray-400">{sub}</p>
                  </div>
                );
              })}
              <p className="pt-1 text-xs text-gray-400 text-right">{users.length} comptes au total</p>
            </CardContent>
          </Card>
        </div>

        {/* ── Score IA moyen ── */}
        {subStats?.avgAiScore !== null && (
          <Card>
            <CardContent className="flex items-center gap-6 p-6">
              <div className="text-center">
                <p className="text-4xl font-bold text-violet-600">{subStats?.avgAiScore}</p>
                <p className="mt-1 text-xs text-gray-500">Score IA moyen</p>
              </div>
              <div className="flex-1 text-sm text-gray-600">
                <p>Moyenne des scores attribués par l&apos;IA sur l&apos;ensemble des copies analysées.</p>
                <p className="mt-1 text-xs text-gray-400">
                  Basé sur {(subStats?.byStatus['aiReviewed'] ?? 0) + (subStats?.byStatus['pendingHuman'] ?? 0) + (subStats?.byStatus['humanReviewed'] ?? 0) + (subStats?.byStatus['published'] ?? 0)} copies notées par l&apos;IA.
                </p>
              </div>
              <div className="text-center">
                <p className="text-4xl font-bold text-emerald-600">{subStats?.aiOnly ?? 0}</p>
                <p className="mt-1 text-xs text-gray-500">Publiées auto (sans correcteur)</p>
              </div>
            </CardContent>
          </Card>
        )}

      </div>
    </div>
  );
}

// ─── KPI Card ─────────────────────────────────────────────────────

function KpiCard({ label, value, sub, color }: {
  label: string; value: string; sub: string; color: string;
}) {
  return (
    <Card>
      <CardContent className="p-5">
        <p className="text-xs font-medium uppercase tracking-wide text-gray-400">{label}</p>
        <p className={`mt-1 text-3xl font-bold ${color}`}>{value}</p>
        <p className="mt-1 text-xs text-gray-500">{sub}</p>
      </CardContent>
    </Card>
  );
}
