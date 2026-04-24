'use client';

import Image from 'next/image';
import { useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { httpsCallable } from 'firebase/functions';
import { AdminShell } from '@/components/admin/admin-shell';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import { getFirebaseFunctionErrorMessage } from '@/lib/firebase-function-error';
import { getSubmission, getSession } from '@/lib/firestore-helpers';
import { functions } from '@/lib/firebase';
import { SubmissionModel, SessionModel } from '@/lib/types';

interface SignedAsset {
  path: string;
  name: string;
  url: string;
}

interface SubmissionAssetsResult {
  copyFiles: SignedAsset[];
  subjectFile: SignedAsset | null;
}

export default function CorrectionDetailPage() {
  return (
    <AdminShell>
      <CorrectionDetail />
    </AdminShell>
  );
}

function CorrectionDetail() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const [submission, setSubmission] = useState<SubmissionModel | null>(null);
  const [session, setSession] = useState<SessionModel | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadingAssets, setLoadingAssets] = useState(true);
  const [finalScore, setFinalScore] = useState('');
  const [notes, setNotes] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [publishing, setPublishing] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState(false);
  const [copyFiles, setCopyFiles] = useState<SignedAsset[]>([]);
  const [subjectFile, setSubjectFile] = useState<SignedAsset | null>(null);

  useEffect(() => {
    let active = true;

    async function loadCorrectionData() {
      const sub = await getSubmission(id);
      if (!active) return;

      setSubmission(sub);
      if (sub?.aiScore !== undefined) setFinalScore(String(sub.aiScore));
      if (sub?.correctorNotes) setNotes(sub.correctorNotes);
      setLoading(false);

      if (!sub) {
        setLoadingAssets(false);
        return;
      }

      // Charger session et assets en parallèle
      const [sess, assets] = await Promise.allSettled([
        getSession(sub.sessionId),
        httpsCallable<{ submissionId: string }, SubmissionAssetsResult>(
          functions,
          'getSubmissionAssets'
        )({ submissionId: id }),
      ]);

      if (!active) return;

      if (sess.status === 'fulfilled') setSession(sess.value);
      if (assets.status === 'fulfilled') {
        setCopyFiles(assets.value.data.copyFiles);
        setSubjectFile(assets.value.data.subjectFile);
      }
      setLoadingAssets(false);
    }

    loadCorrectionData();
    return () => { active = false; };
  }, [id]);

  async function handleSubmit(e: React.SyntheticEvent<HTMLFormElement>) {
    e.preventDefault();
    const score = parseFloat(finalScore);
    const max = submission?.subjectMaxScore ?? 20;
    if (isNaN(score) || score < 0 || score > max) {
      setError(`La note doit être entre 0 et ${max}.`);
      return;
    }
    setSubmitting(true);
    setError('');
    try {
      const submitFn = httpsCallable(functions, 'submitCorrection');
      await submitFn({ submissionId: id, finalScore: score, correctorNotes: notes });
      setSuccess(true);
      setTimeout(() => router.push('/corrections'), 1500);
    } catch (err) {
      setError(getFirebaseFunctionErrorMessage(err, 'Erreur lors de la soumission.'));
    } finally {
      setSubmitting(false);
    }
  }

  async function handlePublish() {
    setPublishing(true);
    setError('');
    try {
      const publishFn = httpsCallable(functions, 'publishSingleResult');
      await publishFn({ submissionId: id });
      setSuccess(true);
      setTimeout(() => router.push('/corrections'), 1500);
    } catch (err) {
      setError(getFirebaseFunctionErrorMessage(err, 'Publication impossible pour le moment.'));
    } finally {
      setPublishing(false);
    }
  }

  const sessionFinished =
    session?.status === 'closed' || session?.status === 'resultsPublished';

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <div className="w-8 h-8 border-4 border-primary border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  if (!submission) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <p className="text-gray-400">Soumission introuvable.</p>
      </div>
    );
  }

  const maxScore = submission.subjectMaxScore ?? 20;

  return (
    <div className="p-8">
      <div className="max-w-6xl mx-auto space-y-6">

        {/* Header */}
        <div className="flex items-center justify-between">
          <div>
            <button
              onClick={() => router.back()}
              className="text-sm text-gray-500 hover:text-gray-900 mb-2 flex items-center gap-1 transition-colors"
            >
              ← Retour
            </button>
            <h1 className="text-2xl font-bold text-gray-900">{submission.subjectName}</h1>
            <p className="text-gray-500 text-sm mt-1">
              Soumis le{' '}
              {submission.submittedAt.toLocaleDateString('fr', {
                day: '2-digit', month: 'long', year: 'numeric',
                hour: '2-digit', minute: '2-digit',
              })}
            </p>
          </div>
          <Badge className={
            submission.status === 'published'
              ? 'bg-green-100 text-green-800 border-0'
              : 'bg-orange-100 text-orange-800 border-0'
          }>
            {submission.status === 'published' ? 'Publiée' : 'En attente'}
          </Badge>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">

          {/* Colonne gauche : copie + sujet + OCR */}
          <div className="space-y-4">
            <Card>
              <CardHeader className="pb-3">
                <CardTitle className="text-sm">Copie de l&apos;élève</CardTitle>
              </CardHeader>
              <CardContent>
                {loadingAssets ? (
                  <p className="text-sm text-gray-400">Chargement des pages...</p>
                ) : copyFiles.length === 0 ? (
                  <p className="text-sm text-gray-400">Aucune page disponible.</p>
                ) : (
                  <div className="space-y-4">
                    {copyFiles.map((file, index) => (
                      <div key={file.path} className="space-y-2">
                        <div className="flex items-center justify-between">
                          <p className="text-xs font-medium text-gray-500">Page {index + 1}</p>
                          <a
                            href={file.url}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="text-xs text-primary hover:underline"
                          >
                            Ouvrir ↗
                          </a>
                        </div>
                        {isPdfFile(file.name) ? (
                          <a
                            href={file.url}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="block rounded-lg border border-dashed border-gray-300 bg-gray-50 p-4 text-sm text-primary hover:border-primary transition-colors"
                          >
                            {file.name}
                          </a>
                        ) : (
                          <Image
                            src={file.url}
                            alt={`Copie page ${index + 1}`}
                            width={1400}
                            height={2000}
                            unoptimized
                            className="h-auto w-full rounded-lg border border-gray-200"
                          />
                        )}
                      </div>
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>

            {subjectFile && (
              <Card>
                <CardHeader className="pb-3">
                  <CardTitle className="text-sm">Sujet officiel</CardTitle>
                </CardHeader>
                <CardContent className="space-y-3">
                  <div className="flex items-center justify-between gap-3">
                    <p className="text-sm text-gray-500 truncate">{subjectFile.name}</p>
                    <a
                      href={subjectFile.url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-sm text-primary hover:underline shrink-0"
                    >
                      Ouvrir PDF ↗
                    </a>
                  </div>
                  <div className="overflow-hidden rounded-lg border border-gray-200 bg-gray-50">
                    <iframe
                      key={subjectFile.path}
                      src={`${subjectFile.url}#toolbar=0&navpanes=0&scrollbar=1`}
                      title="Sujet officiel"
                      className="h-[520px] w-full"
                    />
                  </div>
                </CardContent>
              </Card>
            )}

            <Card>
              <CardHeader className="pb-3">
                <CardTitle className="text-sm">Texte extrait (OCR)</CardTitle>
              </CardHeader>
              <CardContent>
                <pre className="whitespace-pre-wrap text-sm text-gray-700 bg-gray-50 rounded-lg p-4 max-h-80 overflow-y-auto font-mono leading-relaxed border border-gray-200">
                  {submission.ocrText || 'Aucun texte extrait.'}
                </pre>
              </CardContent>
            </Card>
          </div>

          {/* Colonne droite : IA + barème + formulaire */}
          <div className="space-y-4">

            {submission.subjectBareme && Object.keys(submission.subjectBareme).length > 0 && (
              <Card>
                <CardHeader className="pb-3">
                  <CardTitle className="text-sm">Barème officiel</CardTitle>
                </CardHeader>
                <CardContent className="space-y-2">
                  {Object.entries(submission.subjectBareme).map(([critere, points]) => (
                    <div key={critere} className="flex items-center justify-between text-sm">
                      <span className="text-gray-600">{critere}</span>
                      <span className="font-medium text-gray-900">{points} pts</span>
                    </div>
                  ))}
                </CardContent>
              </Card>
            )}

            {submission.aiScore !== undefined && (
              <Card className="border-purple-200">
                <CardHeader className="pb-3">
                  <CardTitle className="text-sm flex items-center justify-between">
                    <span>Suggestion IA</span>
                    <Badge className="bg-purple-100 text-purple-700 border-0">
                      Conf.: {submission.aiConfidence ?? 0}%
                    </Badge>
                  </CardTitle>
                </CardHeader>
                <CardContent className="space-y-4">
                  <div className="flex items-center gap-3">
                    <div className="w-14 h-14 rounded-full bg-purple-50 border-4 border-purple-200 flex items-center justify-center shrink-0">
                      <span className="text-lg font-bold text-purple-700">{submission.aiScore}</span>
                    </div>
                    <div>
                      <p className="text-sm font-medium text-gray-900">
                        Score : {submission.aiScore}/{maxScore}
                      </p>
                      <p className="text-xs text-gray-500 mt-0.5">{submission.aiFeedback}</p>
                    </div>
                  </div>

                  <Separator />

                  {submission.subjectBareme && Object.keys(submission.subjectBareme).length > 0 && (
                    <div className="space-y-2">
                      <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                        Détail par critère
                      </p>
                      {Object.entries(submission.subjectBareme).map(([critere, maxPts]) => {
                        const pts = submission.aiDetails?.[critere] ?? 0;
                        const pct = Math.round((pts / maxPts) * 100);
                        return (
                          <div key={critere} className="space-y-1">
                            <div className="flex justify-between text-xs text-gray-600">
                              <span>{critere}</span>
                              <span className="font-medium">{pts}/{maxPts}</span>
                            </div>
                            <div className="h-1.5 bg-gray-100 rounded-full overflow-hidden">
                              <div className="h-full bg-purple-400 rounded-full" style={{ width: `${pct}%` }} />
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  )}

                  {(submission.aiStrengths?.length ?? 0) > 0 && (
                    <div className="space-y-1">
                      <p className="text-xs font-semibold text-green-700">Points forts</p>
                      {submission.aiStrengths!.map((s, i) => (
                        <p key={i} className="text-xs text-gray-600">✓ {s}</p>
                      ))}
                    </div>
                  )}
                  {(submission.aiImprovements?.length ?? 0) > 0 && (
                    <div className="space-y-1">
                      <p className="text-xs font-semibold text-orange-700">À améliorer</p>
                      {submission.aiImprovements!.map((s, i) => (
                        <p key={i} className="text-xs text-gray-600">• {s}</p>
                      ))}
                    </div>
                  )}
                </CardContent>
              </Card>
            )}

            {['pendingHuman', 'aiReviewed'].includes(submission.status) && (
              <Card>
                <CardHeader className="pb-3">
                  <CardTitle className="text-sm">Votre correction</CardTitle>
                </CardHeader>
                <CardContent>
                  <form onSubmit={handleSubmit} className="space-y-4">
                    <div className="space-y-1.5">
                      <Label htmlFor="score">
                        Note finale <span className="text-gray-400 font-normal">/ {maxScore}</span>
                      </Label>
                      <Input
                        id="score"
                        type="number"
                        min={0}
                        max={maxScore}
                        step={0.5}
                        value={finalScore}
                        onChange={(e) => setFinalScore(e.target.value)}
                        placeholder={`Note sur ${maxScore}`}
                        required
                      />
                    </div>
                    <div className="space-y-1.5">
                      <Label htmlFor="notes">
                        Commentaires <span className="text-gray-400 font-normal">(facultatif)</span>
                      </Label>
                      <Textarea
                        id="notes"
                        value={notes}
                        onChange={(e) => setNotes(e.target.value)}
                        placeholder="Observations pour l'élève..."
                        rows={4}
                      />
                    </div>
                    {error && (
                      <p className="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-lg">{error}</p>
                    )}
                    {success && (
                      <p className="text-sm text-green-600 bg-green-50 px-3 py-2 rounded-lg">
                        ✅ Correction enregistrée ! Redirection...
                      </p>
                    )}
                    <Button
                      type="submit"
                      className="w-full bg-primary hover:bg-primary/90 text-white"
                      disabled={submitting || success}
                    >
                      {submitting ? 'Enregistrement...' : 'Valider la correction'}
                    </Button>
                  </form>
                </CardContent>
              </Card>
            )}

            {submission.status === 'published' && (
              <Card className="border-green-200 bg-green-50/50">
                <CardContent className="py-6 text-center">
                  <p className="text-2xl mb-2">✅</p>
                  <p className="font-semibold text-green-800">
                    Note publiée : {submission.finalScore}/{maxScore}
                  </p>
                  {submission.correctorNotes && (
                    <p className="text-sm text-green-700 mt-2">{submission.correctorNotes}</p>
                  )}
                </CardContent>
              </Card>
            )}

            {submission.status === 'humanReviewed' && (
              <Card className={sessionFinished ? 'border-green-200' : 'border-blue-200 bg-blue-50/50'}>
                <CardContent className="py-6 text-center space-y-3">
                  {sessionFinished ? (
                    <>
                      <p className="text-2xl">✅</p>
                      <p className="font-semibold text-green-800">Correction enregistrée</p>
                      <p className="text-sm text-green-700">
                        La session est terminée. Tu peux publier cette copie.
                      </p>
                      {error && (
                        <p className="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-lg">{error}</p>
                      )}
                      {success ? (
                        <p className="text-sm text-green-600 bg-green-50 px-3 py-2 rounded-lg">
                          ✅ Résultat publié ! Redirection...
                        </p>
                      ) : (
                        <Button
                          onClick={handlePublish}
                          disabled={publishing}
                          className="w-full bg-green-700 hover:bg-green-800 text-white"
                        >
                          {publishing ? 'Publication...' : 'Publier le résultat'}
                        </Button>
                      )}
                    </>
                  ) : (
                    <>
                      <p className="text-2xl">📝</p>
                      <p className="font-semibold text-blue-800">Correction enregistrée</p>
                      <p className="text-sm text-blue-700">
                        La session est en cours. Les résultats seront publiés à la fin de l&apos;examen.
                      </p>
                    </>
                  )}
                </CardContent>
              </Card>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function isPdfFile(name: string): boolean {
  return name.toLowerCase().endsWith('.pdf');
}
