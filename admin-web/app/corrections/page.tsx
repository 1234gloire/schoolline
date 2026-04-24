'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { httpsCallable } from 'firebase/functions';
import { AdminShell } from '@/components/admin/admin-shell';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button, buttonVariants } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { useAuth } from '@/lib/auth-context';
import { getFirebaseFunctionErrorMessage } from '@/lib/firebase-function-error';
import { getCorrectors, subscribeToPendingHumanSubmissions } from '@/lib/firestore-helpers';
import { functions } from '@/lib/firebase';
import { SubmissionModel, UserProfile } from '@/lib/types';

export default function CorrectionsPage() {
  return (
    <AdminShell>
      <CorrectionsContent />
    </AdminShell>
  );
}

function CorrectionsContent() {
  const { profile } = useAuth();
  const [submissions, setSubmissions] = useState<SubmissionModel[]>([]);
  const [correctors, setCorrectors] = useState<UserProfile[]>([]);
  const [loading, setLoading] = useState(true);
  const [assigningId, setAssigningId] = useState<string | null>(null);
  const [assignDialogOpen, setAssignDialogOpen] = useState(false);
  const [targetSubmission, setTargetSubmission] = useState<SubmissionModel | null>(null);
  const [selectedCorrectorId, setSelectedCorrectorId] = useState('');
  const [assignError, setAssignError] = useState('');
  const [bulkAssigning, setBulkAssigning] = useState(false);
  const [bulkMessage, setBulkMessage] = useState('');

  useEffect(() => {
    if (!profile) return;

    const unsub = subscribeToPendingHumanSubmissions(
      profile.role === 'admin' ? undefined : profile.uid,
      (subs) => {
        setSubmissions(subs);
        setLoading(false);
      }
    );

    return unsub;
  }, [profile]);

  useEffect(() => {
    if (profile?.role !== 'admin') return;

    getCorrectors()
      .then(setCorrectors)
      .catch((error) => {
        setAssignError(
          getFirebaseFunctionErrorMessage(error, 'Impossible de charger les correcteurs.')
        );
      });
  }, [profile]);

  const correctorMap = useMemo(
    () => Object.fromEntries(correctors.map((c) => [c.uid, c])),
    [correctors]
  );

  const unassignedCount = submissions.filter((s) => !s.correctorId).length;
  const assignedCount = submissions.length - unassignedCount;
  const hasCorrectors = correctors.length > 0;

  async function assignSubmission(submissionId: string, correctorId?: string) {
    setAssigningId(submissionId);
    setAssignError('');

    try {
      const assignFn = httpsCallable<
        { submissionId: string; correctorId?: string },
        { success: boolean; correctorId: string }
      >(functions, 'assignCorrector');

      await assignFn(correctorId ? { submissionId, correctorId } : { submissionId });

      if (correctorId) {
        setAssignDialogOpen(false);
        setTargetSubmission(null);
        setSelectedCorrectorId('');
      }

      if (profile?.role === 'admin') {
        const updated = await getCorrectors();
        setCorrectors(updated);
      }
    } catch (error) {
      setAssignError(
        getFirebaseFunctionErrorMessage(error, 'Affectation impossible pour le moment.')
      );
    } finally {
      setAssigningId(null);
    }
  }

  async function handleAutoAssignAll() {
    if (!hasCorrectors) {
      setBulkMessage("Crée au moins un compte correcteur avant d'auto-assigner des copies.");
      return;
    }

    const unassigned = submissions.filter((s) => !s.correctorId);
    if (unassigned.length === 0) {
      setBulkMessage('Toutes les copies ont déjà un correcteur.');
      return;
    }

    setBulkAssigning(true);
    setBulkMessage('');

    try {
      const assignFn = httpsCallable<
        { submissionId: string; correctorId?: string },
        { success: boolean; correctorId: string }
      >(functions, 'assignCorrector');

      let assigned = 0;
      for (const sub of unassigned) {
        await assignFn({ submissionId: sub.id });
        assigned += 1;
      }

      setBulkMessage(`${assigned} copie(s) auto-assignée(s) avec succès.`);

      if (profile?.role === 'admin') {
        setCorrectors(await getCorrectors());
      }
    } catch (error) {
      setBulkMessage(getFirebaseFunctionErrorMessage(error, 'Affectation automatique impossible.'));
    } finally {
      setBulkAssigning(false);
    }
  }

  function openManualAssignDialog(submission: SubmissionModel) {
    setTargetSubmission(submission);
    setSelectedCorrectorId(submission.correctorId ?? correctors[0]?.uid ?? '');
    setAssignError('');
    setAssignDialogOpen(true);
  }

  async function handleManualAssign() {
    if (!targetSubmission || !selectedCorrectorId) {
      setAssignError('Sélectionne un correcteur.');
      return;
    }
    await assignSubmission(targetSubmission.id, selectedCorrectorId);
  }

  return (
    <div className="p-8">
      <div className="mx-auto max-w-6xl space-y-6">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Corrections</h1>
            <p className="mt-1 text-sm text-gray-500">
              {submissions.length} copie{submissions.length !== 1 ? 's' : ''} en attente
            </p>
          </div>

          {profile?.role === 'admin' && (
            <div className="flex flex-col gap-3 sm:items-end">
              <div className="grid grid-cols-2 gap-3 sm:w-auto">
                <Card>
                  <CardContent className="px-4 py-3 text-center">
                    <p className="text-2xl font-bold text-blue-700">{assignedCount}</p>
                    <p className="text-xs text-gray-500">Déjà assignées</p>
                  </CardContent>
                </Card>
                <Card>
                  <CardContent className="px-4 py-3 text-center">
                    <p className="text-2xl font-bold text-orange-600">{unassignedCount}</p>
                    <p className="text-xs text-gray-500">Sans correcteur</p>
                  </CardContent>
                </Card>
              </div>
              <Button
                onClick={handleAutoAssignAll}
                disabled={bulkAssigning || unassignedCount === 0 || !hasCorrectors}
                className="bg-primary text-white hover:bg-primary/90"
              >
                {bulkAssigning
                  ? 'Affectation...'
                  : `Auto-assigner${unassignedCount > 0 ? ` (${unassignedCount})` : ''}`}
              </Button>
              {!hasCorrectors && (
                <p className="text-right text-xs text-orange-600">
                  Aucun compte correcteur disponible.
                </p>
              )}
            </div>
          )}
        </div>

        {bulkMessage && profile?.role === 'admin' && (
          <p className={`rounded-lg px-4 py-3 text-sm ${
            bulkMessage.includes('succès') || bulkMessage.includes('déjà')
              ? 'bg-green-50 text-green-700'
              : 'bg-red-50 text-red-700'
          }`}>
            {bulkMessage}
          </p>
        )}

        {loading ? (
          <div className="py-20 text-center text-gray-400">Chargement...</div>
        ) : submissions.length === 0 ? (
          <Card>
            <CardContent className="py-16 text-center">
              <p className="mb-3 text-3xl">✅</p>
              <p className="text-gray-500 text-sm">Aucune copie en attente de correction.</p>
            </CardContent>
          </Card>
        ) : (
          <div className="space-y-3">
            {submissions.map((submission) => {
              const assignedCorrector = submission.correctorId
                ? correctorMap[submission.correctorId]
                : null;

              return (
                <Card key={submission.id} className="transition-shadow hover:shadow-md">
                  <CardContent className="p-5">
                    <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
                      <div className="space-y-2">
                        <div className="flex flex-wrap items-center gap-2">
                          <p className="font-semibold text-gray-900">
                            {submission.subjectName}
                          </p>
                          <ConfidenceBadge confidence={submission.aiConfidence ?? 0} />
                        </div>

                        <p className="text-sm text-gray-500">
                          Soumis le{' '}
                          {submission.submittedAt.toLocaleDateString('fr', {
                            day: '2-digit', month: 'long', hour: '2-digit', minute: '2-digit',
                          })}
                        </p>

                        <div className="flex flex-wrap items-center gap-3 text-xs">
                          <span className={`rounded-full px-2.5 py-1 font-medium ${
                            submission.correctorId
                              ? 'bg-blue-50 text-blue-700'
                              : 'bg-orange-50 text-orange-700'
                          }`}>
                            {submission.correctorId
                              ? `Assigné à ${
                                  assignedCorrector?.displayName ??
                                  (submission.correctorId === profile?.uid ? 'vous' : submission.correctorId)
                                }`
                              : 'Non assignée'}
                          </span>
                          {submission.aiScore !== undefined && (
                            <span className="text-purple-700">
                              IA: {submission.aiScore}/{submission.subjectMaxScore ?? 20}
                            </span>
                          )}
                          {submission.aiConfidence !== undefined && (
                            <span className="text-gray-400">
                              Conf.: {submission.aiConfidence}%
                            </span>
                          )}
                        </div>
                      </div>

                      <div className="flex flex-wrap items-center gap-2">
                        <Link
                          href={`/corrections/${submission.id}`}
                          className={buttonVariants({ variant: 'outline', size: 'sm' })}
                        >
                          Ouvrir
                        </Link>

                        {profile?.role === 'admin' && (
                          <>
                            <Button
                              variant="outline"
                              size="sm"
                              onClick={() => assignSubmission(submission.id)}
                              disabled={assigningId === submission.id}
                            >
                              {assigningId === submission.id
                                ? 'Affectation...'
                                : submission.correctorId ? 'Réaffectation auto' : 'Auto-assigner'}
                            </Button>
                            <Button
                              size="sm"
                              className="bg-primary text-white hover:bg-primary/90"
                              onClick={() => openManualAssignDialog(submission)}
                              disabled={correctors.length === 0}
                            >
                              {submission.correctorId ? 'Réassigner' : 'Assigner'}
                            </Button>
                          </>
                        )}
                      </div>
                    </div>
                  </CardContent>
                </Card>
              );
            })}
          </div>
        )}
      </div>

      <Dialog open={assignDialogOpen} onOpenChange={setAssignDialogOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Assigner un correcteur</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="rounded-lg bg-gray-50 px-4 py-3 text-sm text-gray-600">
              {targetSubmission?.subjectName ?? 'Copie sélectionnée'}
            </div>
            <div className="space-y-1.5">
              <p className="text-sm font-medium text-gray-900">Correcteur</p>
              <Select
                value={selectedCorrectorId}
                onValueChange={(value) => setSelectedCorrectorId(value ?? '')}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Choisir un correcteur" />
                </SelectTrigger>
                <SelectContent>
                  {correctors.map((c) => (
                    <SelectItem key={c.uid} value={c.uid}>
                      {c.displayName} ({c.activeCorrections ?? 0} en cours)
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            {assignError && (
              <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-600">{assignError}</p>
            )}
            <div className="flex justify-end gap-3">
              <Button variant="outline" onClick={() => setAssignDialogOpen(false)}>
                Annuler
              </Button>
              <Button
                onClick={handleManualAssign}
                disabled={!selectedCorrectorId || (targetSubmission != null && assigningId === targetSubmission.id)}
                className="bg-primary text-white hover:bg-primary/90"
              >
                {targetSubmission != null && assigningId === targetSubmission.id
                  ? 'Enregistrement...'
                  : 'Valider'}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}

function ConfidenceBadge({ confidence }: { confidence: number }) {
  if (confidence >= 70) {
    return <Badge className="border-0 bg-yellow-100 text-yellow-800">IA ~fiable</Badge>;
  }
  if (confidence >= 40) {
    return <Badge className="border-0 bg-orange-100 text-orange-800">Vérifier</Badge>;
  }
  return <Badge variant="destructive">Illisible</Badge>;
}
