'use client';

import { useEffect, useState } from 'react';
import Image from 'next/image';
import {
  AlertTriangle,
  Clock3,
  CreditCard,
  Eye,
  Receipt,
  ShieldCheck,
  XCircle,
} from 'lucide-react';
import { httpsCallable } from 'firebase/functions';
import { getDownloadURL, ref as storageRef } from 'firebase/storage';
import { AdminShell } from '@/components/admin/admin-shell';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import { functions, storage } from '@/lib/firebase';
import { subscribeToAllPayments } from '@/lib/firestore-helpers';
import { PaymentModel, PaymentStatus } from '@/lib/types';

export default function PaymentsPage() {
  return (
    <AdminShell requiredRole="admin">
      <PaymentsContent />
    </AdminShell>
  );
}

function PaymentsContent() {
  const [allPayments, setAllPayments] = useState<PaymentModel[]>([]);
  const [tab, setTab] = useState<'pending' | 'all'>('pending');
  const [message, setMessage] = useState('');
  const [processing, setProcessing] = useState<string | null>(null);
  const [bulkProcessing, setBulkProcessing] = useState(false);
  const [rejectDialog, setRejectDialog] = useState<PaymentModel | null>(null);
  const [rejectionReason, setRejectionReason] = useState('');
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [previewPayment, setPreviewPayment] = useState<PaymentModel | null>(null);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());

  useEffect(() => {
    const unsub = subscribeToAllPayments(setAllPayments);
    return unsub;
  }, []);

  const manualPendingPayments = allPayments.filter(
    (p) =>
      p.status === 'pending' &&
      p.provider !== 'paydunya' &&
      p.provider !== 'pawapay' &&
      Boolean(p.proofFileRef)
  );
  const automaticPendingPayments = allPayments.filter(
    (p) =>
      p.status === 'pending' &&
      (p.provider === 'paydunya' || p.provider === 'pawapay')
  );

  async function openProof(payment: PaymentModel) {
    setPreviewPayment(payment);
    setPreviewUrl(null);
    try {
      const url = await getDownloadURL(storageRef(storage, payment.proofFileRef));
      setPreviewUrl(url);
    } catch {
      setPreviewUrl('error');
    }
  }

  async function handleApprove(payment: PaymentModel) {
    setProcessing(payment.id);
    setMessage('');
    try {
      const fn = httpsCallable<{ paymentId: string; approved: boolean }, { success: boolean }>(
        functions, 'validatePayment'
      );
      await fn({ paymentId: payment.id, approved: true });
      setMessage(`✅ Paiement de ${payment.sessionTitle} validé. L'élève a été notifié.`);
    } catch (err) {
      setMessage(`❌ ${err instanceof Error ? err.message : 'Erreur inconnue'}`);
    } finally {
      setProcessing(null);
    }
  }

  async function handleReject() {
    if (!rejectDialog) return;
    setProcessing(rejectDialog.id);
    setMessage('');
    try {
      const fn = httpsCallable<
        { paymentId: string; approved: boolean; rejectionReason?: string },
        { success: boolean }
      >(functions, 'validatePayment');
      await fn({ paymentId: rejectDialog.id, approved: false, rejectionReason: rejectionReason.trim() || undefined });
      setMessage(`Paiement rejeté. L'élève a été informé.`);
      setRejectDialog(null);
      setRejectionReason('');
    } catch (err) {
      setMessage(`❌ ${err instanceof Error ? err.message : 'Erreur inconnue'}`);
    } finally {
      setProcessing(null);
    }
  }

  async function handleBulkApprove() {
    if (selectedIds.size === 0) return;
    setBulkProcessing(true);
    setMessage('');
    const fn = httpsCallable<{ paymentId: string; approved: boolean }, { success: boolean }>(
      functions, 'validatePayment'
    );
    let ok = 0; let ko = 0;
    for (const id of Array.from(selectedIds)) {
      try { await fn({ paymentId: id, approved: true }); ok++; }
      catch { ko++; }
    }
    setSelectedIds(new Set());
    setMessage(`✅ ${ok} paiement(s) validé(s)${ko > 0 ? ` · ${ko} erreur(s)` : ''}.`);
    setBulkProcessing(false);
  }

  async function handleBulkReject() {
    if (selectedIds.size === 0) return;
    setBulkProcessing(true);
    setMessage('');
    const fn = httpsCallable<
      { paymentId: string; approved: boolean; rejectionReason?: string },
      { success: boolean }
    >(functions, 'validatePayment');
    let ok = 0; let ko = 0;
    for (const id of Array.from(selectedIds)) {
      try { await fn({ paymentId: id, approved: false }); ok++; }
      catch { ko++; }
    }
    setSelectedIds(new Set());
    setMessage(`${ok} paiement(s) rejeté(s)${ko > 0 ? ` · ${ko} erreur(s)` : ''}.`);
    setBulkProcessing(false);
  }

  function toggleSelect(id: string) {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  }

  function toggleSelectAll() {
    setSelectedIds(
      selectedIds.size === manualPendingPayments.length
        ? new Set()
        : new Set(manualPendingPayments.map((p) => p.id))
    );
  }

  const displayed = tab === 'pending' ? manualPendingPayments : allPayments;
  const counts = {
    pending:  manualPendingPayments.length,
    approved: allPayments.filter((p) => p.status === 'approved').length,
    rejected: allPayments.filter((p) => p.status === 'rejected').length,
  };
  const selectedCount = selectedIds.size;
  const pendingTotal = manualPendingPayments.reduce((sum, payment) => sum + payment.amount, 0);
  const approvedTotal = allPayments
    .filter((payment) => payment.status === 'approved')
    .reduce((sum, payment) => sum + payment.amount, 0);
  const automaticPendingTotal = automaticPendingPayments
    .reduce((sum, payment) => sum + payment.amount, 0);
  const rejectedTotal = allPayments
    .filter((payment) => payment.status === 'rejected')
    .reduce((sum, payment) => sum + payment.amount, 0);

  return (
    <div className="min-h-full bg-[radial-gradient(circle_at_top_left,rgba(10,17,114,0.09),transparent_26%),linear-gradient(180deg,#f8fafc_0%,#ffffff_38%)] px-6 py-8 lg:px-8">
      <div className="mx-auto max-w-6xl space-y-6">
        <section className="overflow-hidden rounded-[28px] border border-[#0A1172]/10 bg-[#0A1172] text-white shadow-[0_24px_80px_-40px_rgba(10,17,114,0.9)]">
          <div className="grid gap-6 px-6 py-6 lg:grid-cols-[minmax(0,1.45fr)_330px] lg:px-8">
            <div className="space-y-4">
              <Badge className="border border-white/10 bg-white/10 text-white">
                Opérations de paiement
              </Badge>

              <div className="space-y-2">
                <h1 className="text-2xl font-semibold tracking-tight lg:text-3xl">
                  Paiements élèves
                </h1>
                <p className="max-w-2xl text-sm leading-6 text-white/72">
                  Suivez les encaissements Mobile Money (PawaPay), les paiements en cours de
                  confirmation et l&apos;historique des transactions élèves.
                </p>
              </div>

              <div className="flex flex-wrap gap-2">
                <Badge className="border border-orange-200/30 bg-orange-50/12 text-orange-100">
                  {counts.pending} en attente
                </Badge>
                <Badge className="border border-emerald-200/30 bg-emerald-50/12 text-emerald-100">
                  {counts.approved} validé(s)
                </Badge>
                <Badge className="border border-red-200/30 bg-red-50/12 text-red-100">
                  {counts.rejected} rejeté(s)
                </Badge>
              </div>
            </div>

            <div className="rounded-[24px] border border-white/10 bg-white/8 p-5 backdrop-blur-sm">
              <p className="text-[11px] font-semibold uppercase tracking-[0.22em] text-white/45">
                Point de contrôle
              </p>
              {counts.pending > 0 && (
                <div className="mt-4 rounded-2xl border border-orange-200/40 bg-orange-50 px-4 py-4 text-orange-950">
                  <div className="flex items-start gap-3">
                    <div className="rounded-xl bg-orange-100 p-2 text-orange-700">
                      <AlertTriangle className="h-4 w-4" />
                    </div>
                    <div>
                      <p className="text-sm font-semibold">
                        {counts.pending} preuve(s) attendent une décision
                      </p>
                      <p className="mt-1 text-sm leading-6 opacity-85">
                        Traitez en priorité les preuves les plus anciennes pour limiter les accès bloqués.
                      </p>
                    </div>
                  </div>
                </div>
              )}

              <div className="mt-4 space-y-3">
                <SummaryRow
                  label="Total encaissé"
                  value={`${approvedTotal.toLocaleString('fr-FR')} FCFA`}
                />
                <SummaryRow
                  label="Mobile Money en cours"
                  value={`${automaticPendingTotal.toLocaleString('fr-FR')} FCFA`}
                />
                <SummaryRow
                  label="Preuves manuelles"
                  value={`${pendingTotal.toLocaleString('fr-FR')} FCFA`}
                />
                <SummaryRow
                  label="Vue active"
                  value={tab === 'pending' ? 'Preuves manuelles' : 'Historique complet'}
                />
              </div>
            </div>
          </div>
        </section>

        <section className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
          {[
            {
              label: 'Encaissé',
              value: approvedTotal.toLocaleString('fr-FR'),
              suffix: 'FCFA',
              helper: `${counts.approved} paiement(s) validé(s)`,
              icon: CreditCard,
              tone: 'green',
            },
            {
              label: 'Mobile Money en cours',
              value: automaticPendingTotal.toLocaleString('fr-FR'),
              suffix: 'FCFA',
              helper: `${automaticPendingPayments.length} confirmation(s)`,
              icon: Clock3,
              tone: 'blue',
            },
            {
              label: 'Preuves manuelles',
              value: counts.pending,
              helper: `${pendingTotal.toLocaleString('fr-FR')} FCFA à vérifier`,
              icon: Clock3,
              tone: 'orange',
            },
            {
              label: 'Rejetés',
              value: counts.rejected,
              helper: `${rejectedTotal.toLocaleString('fr-FR')} FCFA non encaissé`,
              icon: XCircle,
              tone: 'red',
            },
          ].map((item) => (
            <Card
              key={item.label}
              className="border-0 bg-white/92 shadow-sm ring-1 ring-slate-200/75"
            >
              <CardContent className="p-5">
                <div className="flex items-start justify-between gap-3">
                  <div
                    className={`rounded-2xl border p-3 ${
                      item.tone === 'orange'
                        ? 'border-orange-200 bg-orange-50 text-orange-700'
                        : item.tone === 'blue'
                          ? 'border-blue-200 bg-blue-50 text-blue-700'
                        : item.tone === 'green'
                          ? 'border-emerald-200 bg-emerald-50 text-emerald-700'
                          : 'border-red-200 bg-red-50 text-red-700'
                    }`}
                  >
                    <item.icon className="h-5 w-5" />
                  </div>
                </div>
                <p
                  className={`mt-5 text-3xl font-semibold tracking-tight ${
                    item.tone === 'orange'
                      ? 'text-orange-700'
                      : item.tone === 'blue'
                        ? 'text-blue-700'
                      : item.tone === 'green'
                        ? 'text-emerald-700'
                        : 'text-red-700'
                  }`}
                >
                  {item.value}
                  {'suffix' in item && item.suffix && (
                    <span className="ml-1 text-base font-semibold text-slate-500">
                      {item.suffix}
                    </span>
                  )}
                </p>
                <p className="mt-1 text-sm font-medium text-gray-700">{item.label}</p>
                <p className="mt-2 text-sm text-gray-500">{item.helper}</p>
              </CardContent>
            </Card>
          ))}
        </section>

        {message && (
          <div
            className={`rounded-2xl border px-4 py-3 text-sm ${
              message.startsWith('✅')
                ? 'border-emerald-200 bg-emerald-50 text-emerald-700'
                : message.startsWith('❌')
                  ? 'border-red-200 bg-red-50 text-red-700'
                  : 'border-slate-200 bg-slate-50 text-slate-700'
            }`}
          >
            {message}
          </div>
        )}

        <section className="grid gap-6 xl:grid-cols-[290px_minmax(0,1fr)]">
          <Card className="border-0 bg-white/92 shadow-sm ring-1 ring-slate-200/75">
            <CardHeader className="pb-4">
              <CardTitle className="text-base text-gray-900">
                Pilotage
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="grid gap-2">
                {(['pending', 'all'] as const).map((currentTab) => {
                  const active = tab === currentTab;
                  return (
                    <button
                      key={currentTab}
                      onClick={() => setTab(currentTab)}
                      className={`rounded-2xl border px-4 py-4 text-left transition-colors ${
                        active
                          ? 'border-[#0A1172]/15 bg-[#0A1172] text-white'
                          : 'border-slate-200 bg-slate-50 text-slate-700 hover:bg-slate-100'
                      }`}
                    >
                      <p className="text-sm font-semibold">
                        {currentTab === 'pending'
                          ? `En attente (${counts.pending})`
                          : `Historique (${allPayments.length})`}
                      </p>
                      <p
                        className={`mt-1 text-sm ${
                          active ? 'text-white/70' : 'text-slate-500'
                        }`}
                      >
                        {currentTab === 'pending'
                          ? 'Vérifier les preuves manuelles'
                          : 'Consulter toutes les validations passées'}
                      </p>
                    </button>
                  );
                })}
              </div>

              {tab === 'pending' && manualPendingPayments.length > 0 && (
                <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
                  <label className="flex items-center gap-2 text-sm text-slate-600">
                    <input
                      type="checkbox"
                      className="h-4 w-4 rounded"
                      checked={selectedIds.size === manualPendingPayments.length && manualPendingPayments.length > 0}
                      onChange={toggleSelectAll}
                    />
                    Tout sélectionner
                  </label>

                  <div className="mt-4 grid gap-2">
                    <Button
                      disabled={selectedCount === 0 || bulkProcessing}
                      onClick={handleBulkApprove}
                      className="w-full bg-green-600 text-white hover:bg-green-700"
                    >
                      {bulkProcessing
                        ? 'Traitement...'
                        : `Valider la sélection (${selectedCount})`}
                    </Button>
                    <Button
                      variant="outline"
                      disabled={selectedCount === 0 || bulkProcessing}
                      onClick={handleBulkReject}
                      className="w-full border-red-300 text-red-600 hover:bg-red-50"
                    >
                      {bulkProcessing
                        ? 'Traitement...'
                        : `Rejeter la sélection (${selectedCount})`}
                    </Button>
                  </div>
                </div>
              )}

              <div className="rounded-2xl border border-dashed border-slate-200 bg-slate-50/80 px-4 py-4">
                <div className="flex items-start gap-3">
                  <div className="rounded-xl bg-white p-2 text-slate-500 ring-1 ring-slate-200">
                    <ShieldCheck className="h-4 w-4" />
                  </div>
                  <div>
                    <p className="text-sm font-semibold text-slate-700">
                      Règle métier
                    </p>
                    <p className="mt-1 text-sm leading-6 text-slate-500">
                      Une validation débloque immédiatement la session côté élève.
                      Un rejet doit idéalement être motivé pour faciliter la
                      régularisation.
                    </p>
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>

          <Card className="border-0 bg-white/92 shadow-sm ring-1 ring-slate-200/75">
            <CardHeader className="pb-4">
              <div className="flex items-center justify-between gap-4">
                <CardTitle className="text-base text-gray-900">
                  {tab === 'pending'
                    ? `Preuves à valider (${displayed.length})`
                    : `Historique des paiements (${displayed.length})`}
                </CardTitle>
                <Badge className="border border-slate-200 bg-slate-50 text-slate-700">
                  {tab === 'pending' ? 'Traitement' : 'Historique'}
                </Badge>
              </div>
            </CardHeader>
            <CardContent>
              {displayed.length === 0 ? (
                <div className="rounded-2xl border border-dashed border-slate-200 bg-slate-50/80 px-4 py-10 text-center">
                  <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-2xl bg-white text-slate-400 shadow-sm ring-1 ring-slate-200">
                    <Receipt className="h-5 w-5" />
                  </div>
                  <p className="mt-4 text-sm font-medium text-slate-600">
                    {tab === 'pending'
                      ? 'Aucun paiement en attente'
                      : 'Aucun paiement enregistré'}
                  </p>
                  <p className="mt-1 text-sm text-slate-400">
                    {tab === 'pending'
                      ? "Le flux est vide pour l'instant."
                      : 'Les paiements apparaîtront ici au fil des soumissions.'}
                  </p>
                </div>
              ) : (
                <div className="space-y-3">
                  {displayed.map((payment) => (
                    <div
                      key={payment.id}
                      className="rounded-2xl border border-slate-200 bg-white p-4 transition-all hover:border-[#0A1172]/15 hover:shadow-md"
                    >
                      <div className="flex flex-col gap-4 xl:flex-row xl:items-center xl:justify-between">
                        <div className="flex min-w-0 items-start gap-3">
                          {tab === 'pending' && (
                            <input
                              type="checkbox"
                              className="mt-1 h-4 w-4 shrink-0 rounded"
                              checked={selectedIds.has(payment.id)}
                              onChange={() => toggleSelect(payment.id)}
                            />
                          )}

                          <div className="min-w-0">
                            <div className="flex flex-wrap items-center gap-2">
                              <p className="truncate text-sm font-semibold text-gray-900">
                                {payment.sessionTitle}
                              </p>
                              <PaymentStatusBadge status={payment.status} />
                              {payment.provider && payment.provider !== 'manual' && (
                                <Badge className="border border-blue-200 bg-blue-50 text-blue-700">
                                  {payment.provider}
                                </Badge>
                              )}
                            </div>

                            <div className="mt-2 flex flex-wrap gap-2 text-xs text-slate-500">
                              <span className="rounded-full bg-slate-100 px-2.5 py-1">
                                Élève {payment.userId.slice(0, 12)}…
                              </span>
                              <span className="rounded-full bg-slate-100 px-2.5 py-1">
                                {payment.submittedAt.toLocaleDateString('fr-FR', {
                                  day: '2-digit',
                                  month: 'short',
                                  year: 'numeric',
                                  hour: '2-digit',
                                  minute: '2-digit',
                                })}
                              </span>
                            </div>

                            {payment.rejectionReason && (
                              <p className="mt-3 text-sm text-red-600">
                                Motif : {payment.rejectionReason}
                              </p>
                            )}
                          </div>
                        </div>

                        <div className="flex flex-col gap-3 xl:items-end">
                          <div className="flex items-center gap-2 text-sm font-semibold text-gray-800">
                            <CreditCard className="h-4 w-4 text-slate-400" />
                            {payment.amount.toLocaleString('fr-FR')} FCFA
                          </div>

                          <div className="flex flex-wrap gap-2">
                            {payment.proofFileRef && (
                              <Button
                                variant="outline"
                                size="sm"
                                onClick={() => openProof(payment)}
                              >
                                <Eye className="h-4 w-4" />
                                Voir preuve
                              </Button>
                            )}

                            {payment.status === 'pending' && payment.proofFileRef && (
                              <>
                                <Button
                                  size="sm"
                                  disabled={processing === payment.id || bulkProcessing}
                                  onClick={() => handleApprove(payment)}
                                  className="bg-green-600 text-white hover:bg-green-700"
                                >
                                  {processing === payment.id ? '...' : 'Valider'}
                                </Button>
                                <Button
                                  size="sm"
                                  variant="outline"
                                  disabled={processing === payment.id || bulkProcessing}
                                  onClick={() => {
                                    setRejectDialog(payment);
                                    setRejectionReason('');
                                  }}
                                  className="border-red-300 text-red-600 hover:bg-red-50"
                                >
                                  Rejeter
                                </Button>
                              </>
                            )}
                          </div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
        </section>
      </div>

      {/* Dialog preuve photo */}
      <Dialog open={previewPayment !== null} onOpenChange={() => setPreviewPayment(null)}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>Preuve de paiement — {previewPayment?.sessionTitle}</DialogTitle>
          </DialogHeader>
          <div className="space-y-3">
            <p className="text-sm text-gray-500">
              Montant attendu :{' '}
              <span className="font-semibold text-gray-900">
                {previewPayment?.amount.toLocaleString('fr-FR')} FCFA
              </span>
            </p>
            <div className="rounded-lg overflow-hidden border border-gray-200 bg-gray-50 flex items-center justify-center min-h-64">
              {previewUrl === null && <p className="text-sm text-gray-400">Chargement…</p>}
              {previewUrl === 'error' && (
                <p className="text-sm text-red-500">Impossible de charger l&apos;image.</p>
              )}
              {previewUrl && previewUrl !== 'error' && (
                <Image
                  src={previewUrl}
                  alt="Preuve de paiement"
                  width={480}
                  height={640}
                  className="object-contain max-h-[60vh] w-full"
                  unoptimized
                />
              )}
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Dialog rejet */}
      <Dialog open={rejectDialog !== null} onOpenChange={() => setRejectDialog(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Rejeter le paiement</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <p className="text-sm text-gray-600">
              L&apos;élève sera notifié du rejet. Tu peux indiquer un motif pour l&apos;aider à régulariser.
            </p>
            <div className="space-y-1.5">
              <Label>Motif (optionnel)</Label>
              <Textarea
                value={rejectionReason}
                onChange={(e) => setRejectionReason(e.target.value)}
                placeholder="Ex : Montant incorrect, reçu illisible, mauvais opérateur…"
                rows={3}
              />
            </div>
            <div className="flex justify-end gap-3">
              <Button variant="outline" onClick={() => setRejectDialog(null)}>Annuler</Button>
              <Button
                onClick={handleReject}
                disabled={processing === rejectDialog?.id}
                variant="destructive"
              >
                {processing === rejectDialog?.id ? 'Rejet…' : 'Confirmer le rejet'}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}

function PaymentStatusBadge({ status }: { status: PaymentStatus }) {
  const map: Record<PaymentStatus, { label: string; class: string }> = {
    pending:  { label: 'En attente', class: 'border-orange-200 bg-orange-50 text-orange-700' },
    approved: { label: 'Validé', class: 'border-emerald-200 bg-emerald-50 text-emerald-700' },
    rejected: { label: 'Rejeté', class: 'border-red-200 bg-red-50 text-red-700' },
  };
  const s = map[status];
  return <Badge className={`border text-xs ${s.class}`}>{s.label}</Badge>;
}

function SummaryRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between gap-4 border-b border-white/8 pb-3 text-sm last:border-b-0 last:pb-0">
      <span className="text-white/55">{label}</span>
      <span className="text-right font-medium text-white">{value}</span>
    </div>
  );
}
