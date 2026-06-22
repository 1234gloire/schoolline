'use client';

import { useCallback, useEffect, useState } from 'react';
import { httpsCallable } from 'firebase/functions';
import { collection, getDocs, orderBy, query, limit, Timestamp } from 'firebase/firestore';
import { Megaphone, Send, RefreshCw, CheckCircle, Users, Clock } from 'lucide-react';
import { AdminShell } from '@/components/admin/admin-shell';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import { functions, db } from '@/lib/firebase';
import { getFirebaseFunctionErrorMessage } from '@/lib/firebase-function-error';

export default function AnnouncementsPage() {
  return (
    <AdminShell requiredRole="admin">
      <AnnouncementsContent />
    </AdminShell>
  );
}

type Audience = 'all' | 'troisieme' | 'terminale';

const AUDIENCE_LABELS: Record<Audience, string> = {
  all: 'Tous les élèves',
  troisieme: '3ème (BEPC)',
  terminale: 'Terminale (BAC)',
};

const SERIES = ['A', 'C', 'D'];

interface AnnouncementRecord {
  id: string;
  title: string;
  body: string;
  audience: Audience;
  series: string | null;
  sentByName: string;
  recipientCount: number;
  successCount: number;
  createdAt: Date | null;
}

const TITLE_MAX = 80;
const BODY_MAX = 500;

function AnnouncementsContent() {
  const [title, setTitle]       = useState('');
  const [body, setBody]         = useState('');
  const [audience, setAudience] = useState<Audience>('all');
  const [series, setSeries]     = useState('');

  const [sending, setSending] = useState(false);
  const [error, setError]     = useState('');
  const [result, setResult]   = useState<{ recipientCount: number; successCount: number } | null>(null);

  const [history, setHistory]               = useState<AnnouncementRecord[]>([]);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [historyError, setHistoryError]     = useState('');

  const loadHistory = useCallback(async () => {
    setHistoryLoading(true);
    setHistoryError('');
    try {
      const snap = await getDocs(
        query(collection(db, 'announcements'), orderBy('createdAt', 'desc'), limit(30))
      );
      const list: AnnouncementRecord[] = snap.docs.map((d) => {
        const data = d.data();
        const created = data.createdAt as Timestamp | undefined;
        return {
          id: d.id,
          title: data.title ?? '',
          body: data.body ?? '',
          audience: (data.audience ?? 'all') as Audience,
          series: data.series ?? null,
          sentByName: data.sentByName ?? '',
          recipientCount: data.recipientCount ?? 0,
          successCount: data.successCount ?? 0,
          createdAt: created ? created.toDate() : null,
        };
      });
      setHistory(list);
    } catch (e) {
      // Évite un crash overlay : affiche l'erreur en ligne avec retry.
      const msg = e instanceof Error ? e.message : String(e);
      setHistoryError(
        /permission/i.test(msg)
          ? "Accès à l'historique refusé. Si les règles viennent d'être déployées, patiente une minute puis rafraîchis."
          : "Impossible de charger l'historique."
      );
    } finally {
      setHistoryLoading(false);
    }
  }, []);

  useEffect(() => { loadHistory(); }, [loadHistory]);

  const canSend = title.trim().length > 0 && body.trim().length > 0 && !sending;

  async function handleSend() {
    setSending(true);
    setError('');
    setResult(null);
    try {
      const send = httpsCallable<
        { title: string; body: string; audience: Audience; series?: string },
        { recipientCount: number; successCount: number }
      >(functions, 'sendAnnouncement');

      const res = await send({
        title: title.trim(),
        body: body.trim(),
        audience,
        series: audience === 'terminale' && series ? series : undefined,
      });

      setResult(res.data);
      setTitle('');
      setBody('');
      await loadHistory();
    } catch (e) {
      setError(getFirebaseFunctionErrorMessage(e, "Échec de l'envoi de l'annonce."));
    } finally {
      setSending(false);
    }
  }

  function audienceBadge(a: Audience, s: string | null) {
    const label = a === 'terminale' && s ? `Terminale ${s}` : AUDIENCE_LABELS[a];
    return <Badge className="border-0 bg-indigo-100 text-indigo-700">{label}</Badge>;
  }

  return (
    <div className="p-8">
      <div className="mx-auto max-w-5xl space-y-6">

        {/* En-tête */}
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-indigo-100">
            <Megaphone className="h-5 w-5 text-indigo-600" />
          </div>
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Annonces</h1>
            <p className="text-sm text-gray-500">Envoie une notification push aux élèves de l&apos;application.</p>
          </div>
        </div>

        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">

          {/* ── Composer ── */}
          <Card>
            <CardHeader>
              <CardTitle className="text-sm text-gray-700">Nouvelle annonce</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">

              <div className="space-y-1.5">
                <Label className="text-xs font-medium text-gray-600">Titre</Label>
                <Input
                  value={title}
                  onChange={(e) => setTitle(e.target.value.slice(0, TITLE_MAX))}
                  placeholder="Ex. Nouvelle session disponible !"
                />
                <p className="text-right text-[11px] text-gray-400">{title.length}/{TITLE_MAX}</p>
              </div>

              <div className="space-y-1.5">
                <Label className="text-xs font-medium text-gray-600">Message</Label>
                <Textarea
                  rows={5}
                  value={body}
                  onChange={(e) => setBody(e.target.value.slice(0, BODY_MAX))}
                  placeholder="Rédige ton message. Il apparaîtra dans la notification reçue par les élèves."
                  className="resize-none"
                />
                <p className="text-right text-[11px] text-gray-400">{body.length}/{BODY_MAX}</p>
              </div>

              <div className="space-y-1.5">
                <Label className="text-xs font-medium text-gray-600">Destinataires</Label>
                <Select value={audience} onValueChange={(v) => { if (v) setAudience(v as Audience); }}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">{AUDIENCE_LABELS.all}</SelectItem>
                    <SelectItem value="troisieme">{AUDIENCE_LABELS.troisieme}</SelectItem>
                    <SelectItem value="terminale">{AUDIENCE_LABELS.terminale}</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              {audience === 'terminale' && (
                <div className="space-y-1.5">
                  <Label className="text-xs font-medium text-gray-600">
                    Série <span className="text-gray-400 font-normal">(optionnel)</span>
                  </Label>
                  <Select value={series || 'all'} onValueChange={(v) => { if (v) setSeries(v === 'all' ? '' : v); }}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">Toutes les séries</SelectItem>
                      {SERIES.map((s) => (
                        <SelectItem key={s} value={s}>Série {s}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              )}

              {result && (
                <div className="flex items-start gap-2 rounded-lg bg-emerald-50 px-4 py-3 text-sm text-emerald-700">
                  <CheckCircle className="h-4 w-4 mt-0.5 shrink-0" />
                  <span>
                    Annonce envoyée à <strong>{result.successCount}</strong> appareil(s)
                    {result.recipientCount !== result.successCount && ` sur ${result.recipientCount} ciblé(s)`}.
                    {result.recipientCount === 0 && ' Aucun élève ciblé n’a de notifications activées.'}
                  </span>
                </div>
              )}

              {error && (
                <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-600">{error}</p>
              )}

              <Button
                className="w-full bg-indigo-600 hover:bg-indigo-700 text-white"
                onClick={handleSend}
                disabled={!canSend}
              >
                {sending
                  ? <><RefreshCw className="w-4 h-4 mr-2 animate-spin" />Envoi en cours…</>
                  : <><Send className="w-4 h-4 mr-2" />Envoyer l&apos;annonce</>}
              </Button>

              <p className="text-[11px] text-gray-400 text-center">
                L&apos;annonce part immédiatement vers les appareils ayant autorisé les notifications.
              </p>
            </CardContent>
          </Card>

          {/* ── Historique ── */}
          <Card className="flex flex-col">
            <CardHeader className="flex-row items-center justify-between">
              <CardTitle className="text-sm text-gray-700">Historique</CardTitle>
              <Button variant="outline" size="sm" onClick={loadHistory} disabled={historyLoading}>
                <RefreshCw className={`w-3.5 h-3.5 mr-1.5 ${historyLoading ? 'animate-spin' : ''}`} />
                Rafraîchir
              </Button>
            </CardHeader>
            <CardContent className="flex-1 space-y-3">
              {historyError && (
                <p className="rounded-md bg-red-50 px-3 py-2 text-xs text-red-600">{historyError}</p>
              )}
              {historyLoading && history.length === 0 ? (
                <p className="text-sm text-gray-400 py-6 text-center">Chargement…</p>
              ) : historyError && history.length === 0 ? (
                <div className="py-6" />
              ) : history.length === 0 ? (
                <div className="flex flex-col items-center gap-2 py-10 text-center">
                  <Megaphone className="h-8 w-8 text-gray-200" />
                  <p className="text-sm text-gray-400">Aucune annonce envoyée pour l&apos;instant.</p>
                </div>
              ) : (
                history.map((a) => (
                  <div key={a.id} className="rounded-lg border border-gray-100 bg-gray-50 px-4 py-3">
                    <div className="flex items-start justify-between gap-3">
                      <p className="font-semibold text-gray-800 text-sm">{a.title}</p>
                      {audienceBadge(a.audience, a.series)}
                    </div>
                    <p className="mt-1 text-xs text-gray-600 line-clamp-2">{a.body}</p>
                    <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-[11px] text-gray-400">
                      <span className="flex items-center gap-1">
                        <Users className="w-3 h-3" />
                        {a.successCount}/{a.recipientCount} reçu(s)
                      </span>
                      {a.createdAt && (
                        <span className="flex items-center gap-1">
                          <Clock className="w-3 h-3" />
                          {a.createdAt.toLocaleString('fr-FR', {
                            day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit',
                          })}
                        </span>
                      )}
                      {a.sentByName && <span>par {a.sentByName}</span>}
                    </div>
                  </div>
                ))
              )}
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
