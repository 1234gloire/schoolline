'use client';

import { useRef, useState } from 'react';
import {
  Sparkles, Copy, Check, RefreshCw, RotateCcw,
  Upload, CheckCircle, ImagePlus, X, Loader2, Eye, Pencil,
} from 'lucide-react';
import { ref, uploadBytes } from 'firebase/storage';
import jsPDF from 'jspdf';
import { addDoc, collection, Timestamp } from 'firebase/firestore';
import katex from 'katex';
import { marked } from 'marked';
import 'katex/dist/katex.min.css';
import { AdminShell } from '@/components/admin/admin-shell';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle,
} from '@/components/ui/dialog';
import { getSessions } from '@/lib/firestore-helpers';
import { SessionModel } from '@/lib/types';
import { db, storage } from '@/lib/firebase';

export default function SubjectsPage() {
  return (
    <AdminShell requiredRole="admin">
      <SubjectsContent />
    </AdminShell>
  );
}

// ─── Config ──────────────────────────────────────────────────────────────────

const MATIERES: Record<string, string[]> = {
  '3ème (BEPC)': [
    'Mathématiques', 'Français', 'Sciences Physiques', 'Sciences de la Vie et de la Terre',
    'Histoire-Géographie', 'Anglais', 'Éducation Civique',
  ],
  'Terminale A': ['Français', 'Philosophie', 'Histoire-Géographie', 'Anglais', 'Mathématiques'],
  'Terminale C': ['Mathématiques', 'Sciences Physiques', 'Sciences de la Vie et de la Terre', 'Français', 'Philosophie'],
  'Terminale D': ['Mathématiques', 'Sciences de la Vie et de la Terre', 'Sciences Physiques', 'Français', 'Philosophie'],
};

const DUREES = [60, 90, 120, 180, 240];

const MOIS = [
  'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
  'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
];

const ANNEES = [2024, 2025, 2026, 2027, 2028];

function dureeLabel(d: number) {
  return d >= 60 ? `${d / 60}h${d % 60 ? (d % 60) + 'min' : ''}` : `${d} min`;
}

// ─── KaTeX + Markdown rendering ──────────────────────────────────────────────

function tryKatex(formula: string, displayMode: boolean): string {
  try {
    return katex.renderToString(formula, {
      displayMode,
      throwOnError: false,
      strict: false,
      output: 'html',
    });
  } catch {
    return `<code>${formula}</code>`;
  }
}

async function renderMarkdownWithKatex(raw: string): Promise<string> {
  const store: string[] = [];
  const ph = (i: number) => `DIAKPH${i}END`;

  // Extract and render display math $$...$$ first
  let text = raw.replace(/\$\$([\s\S]+?)\$\$/g, (_, f) => {
    store.push(`<div class="sp-katex-display">${tryKatex(f.trim(), true)}</div>`);
    return ph(store.length - 1);
  });

  // Then inline math $...$
  text = text.replace(/\$([^$\n]{1,300}?)\$/g, (_, f) => {
    store.push(tryKatex(f.trim(), false));
    return ph(store.length - 1);
  });

  // Parse markdown (handle both sync and async versions of marked)
  const parsed = marked.parse(text);
  let html = typeof parsed === 'string' ? parsed : await parsed;

  // Restore math blocks
  store.forEach((rendered, i) => {
    html = html.replaceAll(ph(i), rendered);
  });

  return html;
}

// ─── Subject HTML builder (used for PDF) ─────────────────────────────────────

interface SubjectMeta {
  matiere: string;
  classeLabel: string;
  serieLabel?: string;
  typeExamen: string;
  duree: number;
  coefficient: number;
  sessionDate: string;
}

function buildSubjectHtml(renderedContent: string, meta: SubjectMeta): string {
  const dl = dureeLabel(meta.duree);
  return `
<div style="font-family:Georgia,'Times New Roman',serif;font-size:13px;line-height:1.75;color:#111;background:#fff;">
  <div style="text-align:center;padding-bottom:16px;border-bottom:2px solid #111;margin-bottom:22px;">
    <div style="font-size:22px;font-weight:700;letter-spacing:1px;margin-bottom:3px;">DiakExam</div>
    <div style="font-size:10.5px;color:#555;margin-bottom:12px;text-transform:uppercase;letter-spacing:0.5px;">Plateforme de préparation aux examens nationaux</div>
    <div style="font-size:13px;margin-bottom:2px;">Session de préparation · <strong>${meta.sessionDate}</strong></div>
    <div style="font-size:13px;margin-bottom:2px;">Examen du <strong>${meta.typeExamen}</strong>${meta.serieLabel ? ` &nbsp;|&nbsp; Série : <strong>${meta.serieLabel}</strong>` : ''}</div>
    <div style="font-size:13px;margin-bottom:2px;">Discipline : <strong>${meta.matiere}</strong></div>
    <div style="font-size:13px;">Durée : <strong>${dl}</strong> &nbsp;|&nbsp; Coefficient : <strong>${meta.coefficient}</strong></div>
  </div>
  <div>${renderedContent}</div>
</div>`;
}

// ─── PDF generation via html2canvas ──────────────────────────────────────────

async function generatePdfFromHtml(fullHtml: string): Promise<Uint8Array> {
  const container = document.createElement('div');
  Object.assign(container.style, {
    position: 'absolute',
    top: '0',
    left: '-9999px',
    width: '770px',
    background: '#fff',
    padding: '28px 36px',
    boxSizing: 'border-box',
  });
  container.innerHTML = fullHtml;
  document.body.appendChild(container);

  // Wait for KaTeX fonts to load
  await document.fonts.ready;

  try {
    const h2c = (await import('html2canvas')).default;

    const canvas = await h2c(container, {
      scale: 2,
      useCORS: true,
      allowTaint: true,
      backgroundColor: '#ffffff',
      logging: false,
      width: 770,
      // Tailwind v4 uses oklch()/lab() — html2canvas v1.4.1 throws on these.
      // Patch both inline <style> tags AND external <link> stylesheets.
      onclone: async (clonedDoc: Document) => {
        const fix = /\b(?:oklch|lab|lch|oklab|hwb|color-mix)\s*\([^)]+\)/g;

        // 1. Patch inline <style> tags
        Array.from(clonedDoc.querySelectorAll('style')).forEach((el) => {
          if (el.textContent) el.textContent = el.textContent.replace(fix, '#000');
        });

        // 2. Fetch external <link> stylesheets, patch, and re-inject inline
        //    (html2canvas fetches these itself and throws on unsupported colors)
        const links = Array.from(
          clonedDoc.querySelectorAll<HTMLLinkElement>('link[rel="stylesheet"]'),
        );
        await Promise.all(
          links.map(async (link) => {
            const href = link.href;
            link.remove();
            try {
              const css = await fetch(href).then((r) => r.text());
              const style = clonedDoc.createElement('style');
              style.textContent = css.replace(fix, '#000');
              clonedDoc.head.appendChild(style);
            } catch {
              // ignore fetch errors for external stylesheets
            }
          }),
        );
      },
    });

    const A4W = 210; // mm
    const A4H = 297; // mm
    const pxPerMm = canvas.width / A4W;
    const pageHeightPx = A4H * pxPerMm;

    const doc = new jsPDF({ orientation: 'portrait', unit: 'mm', format: 'a4' });

    let yPx = 0;
    while (yPx < canvas.height) {
      if (yPx > 0) doc.addPage();

      const slicePx = Math.min(pageHeightPx, canvas.height - yPx);
      const pageCanvas = document.createElement('canvas');
      pageCanvas.width = canvas.width;
      pageCanvas.height = Math.ceil(slicePx);

      const ctx = pageCanvas.getContext('2d')!;
      ctx.fillStyle = '#fff';
      ctx.fillRect(0, 0, pageCanvas.width, pageCanvas.height);
      ctx.drawImage(canvas, 0, yPx, canvas.width, slicePx, 0, 0, canvas.width, slicePx);

      doc.addImage(
        pageCanvas.toDataURL('image/jpeg', 0.93),
        'JPEG',
        0, 0,
        A4W,
        slicePx / pxPerMm,
      );

      yPx += pageHeightPx;
    }

    return new Uint8Array(doc.output('arraybuffer') as ArrayBuffer);
  } finally {
    document.body.removeChild(container);
  }
}

// ─── Main component ───────────────────────────────────────────────────────────

function SubjectsContent() {
  // Formulaire
  const [classe,        setClasse]        = useState('');
  const [matiere,       setMatiere]       = useState('');
  const [duree,         setDuree]         = useState(120);
  const [coefficient,   setCoefficient]   = useState(1);
  const [sessionMonth,  setSessionMonth]  = useState(MOIS[new Date().getMonth()]);
  const [sessionYear,   setSessionYear]   = useState(new Date().getFullYear());
  const [exemples,      setExemples]      = useState('');

  // Upload exemples
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [extractingFiles, setExtractingFiles] = useState<{ name: string; status: 'loading' | 'done' | 'error'; error?: string }[]>([]);

  // Génération
  const [output,       setOutput]       = useState('');
  const [loading,      setLoading]      = useState(false);
  const [error,        setError]        = useState('');
  const [copied,       setCopied]       = useState(false);

  // Preview
  const [previewMode,  setPreviewMode]  = useState(false);
  const [renderedHtml, setRenderedHtml] = useState('');
  const [rendering,    setRendering]    = useState(false);

  // Dialogue dépôt
  const [depositOpen,     setDepositOpen]     = useState(false);
  const [sessions,        setSessions]        = useState<SessionModel[]>([]);
  const [sessionsLoading, setSessionsLoading] = useState(false);
  const [targetSession,   setTargetSession]   = useState('');
  const [maxScore,        setMaxScore]        = useState(20);
  const [subjectType,     setSubjectType]     = useState<'structured' | 'literary' | 'qcm'>('structured');
  const [depositing,      setDepositing]      = useState(false);
  const [depositError,    setDepositError]    = useState('');
  const [depositDone,     setDepositDone]     = useState(false);

  const classeLabel = classe.includes('3') ? '3ème' : classe;
  const serieLabel  = classe.startsWith('Terminale') ? classe.replace('Terminale ', '') : undefined;
  const typeExamen  = classe.includes('3') ? 'BEPC' : 'BAC';
  const matiereList = MATIERES[classe] ?? [];
  const canGenerate = !!classe && !!matiere && !loading;
  const sessionDate = `${sessionMonth} ${sessionYear}`;

  // ── Extraction fichiers ────────────────────────────────────────────────────

  async function handleFileUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const files = Array.from(e.target.files ?? []);
    if (!files.length) return;
    e.target.value = '';

    for (const file of files) {
      const entry = { name: file.name, status: 'loading' as const };
      setExtractingFiles((prev) => [...prev, entry]);

      const formData = new FormData();
      formData.append('file', file);

      try {
        const res = await fetch('/api/extract-subject-text', { method: 'POST', body: formData });
        const data = await res.json();

        if (!res.ok || data.error) {
          setExtractingFiles((prev) =>
            prev.map((f) => f.name === file.name ? { ...f, status: 'error', error: data.error ?? `Erreur ${res.status}` } : f)
          );
          continue;
        }

        setExemples((prev) =>
          prev.trim()
            ? `${prev.trim()}\n\n--- ${file.name} ---\n${data.text}`
            : `--- ${file.name} ---\n${data.text}`
        );
        setExtractingFiles((prev) =>
          prev.map((f) => f.name === file.name ? { ...f, status: 'done' } : f)
        );
      } catch {
        setExtractingFiles((prev) =>
          prev.map((f) => f.name === file.name ? { ...f, status: 'error', error: 'Erreur réseau.' } : f)
        );
      }
    }
  }

  function removeExtractedFile(name: string) {
    setExtractingFiles((prev) => prev.filter((f) => f.name !== name));
  }

  // ── Preview ────────────────────────────────────────────────────────────────

  async function switchToPreview(text: string) {
    setRendering(true);
    try {
      const html = await renderMarkdownWithKatex(text);
      setRenderedHtml(html);
      setPreviewMode(true);
    } finally {
      setRendering(false);
    }
  }

  // ── Génération ─────────────────────────────────────────────────────────────

  async function handleGenerate() {
    setLoading(true);
    setError('');
    setOutput('');
    setDepositDone(false);
    setPreviewMode(false);
    setRenderedHtml('');

    let accumulated = '';
    try {
      const res = await fetch('/api/generate-subject', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          matiere, classe: classeLabel, serie: serieLabel, typeExamen, duree, exemples,
        }),
      });

      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        setError(data.error ?? `Erreur ${res.status}`);
        return;
      }

      const reader = res.body?.getReader();
      if (!reader) { setError('Réponse vide.'); return; }
      const decoder = new TextDecoder();

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        accumulated += decoder.decode(value, { stream: true });
        setOutput(accumulated);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Erreur réseau.');
      return;
    } finally {
      setLoading(false);
    }

    // Streaming terminé → rendu KaTeX automatique
    if (accumulated) {
      await switchToPreview(accumulated);
    }
  }

  async function handleCopy() {
    await navigator.clipboard.writeText(output);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  // ── Dépôt ──────────────────────────────────────────────────────────────────

  async function openDepositDialog() {
    setDepositOpen(true);
    setDepositError('');
    setDepositDone(false);
    setTargetSession('');
    setSessionsLoading(true);
    try {
      const list = await getSessions();
      setSessions(list.filter((s) => s.status === 'draft' || s.status === 'open'));
    } finally {
      setSessionsLoading(false);
    }
  }

  async function handleDeposit() {
    if (!targetSession || !output) return;
    setDepositing(true);
    setDepositError('');

    try {
      const session = sessions.find((s) => s.id === targetSession);
      if (!session) throw new Error('Session introuvable.');

      // Rendu HTML si pas encore fait
      const contentHtml = renderedHtml || await renderMarkdownWithKatex(output);

      // Construction du document complet (en-tête DiakExam + contenu)
      const fullHtml = buildSubjectHtml(contentHtml, {
        matiere, classeLabel, serieLabel, typeExamen, duree, coefficient, sessionDate,
      });

      // Génération PDF via html2canvas
      const pdfBytes   = await generatePdfFromHtml(fullHtml);
      const fileId     = `${Date.now()}`;
      const storageRef = ref(storage, `subjects/${targetSession}/${fileId}.pdf`);
      await uploadBytes(storageRef, pdfBytes, { contentType: 'application/pdf' });

      // Calcul horaires
      const startTime = new Date(session.startDate);
      const endTime   = new Date(startTime.getTime() + duree * 60 * 1000);

      await addDoc(collection(db, 'sessions', targetSession, 'subjects'), {
        name:           matiere,
        type:           subjectType,
        duration:       duree,
        startTime:      Timestamp.fromDate(startTime),
        endTime:        Timestamp.fromDate(endTime),
        coefficient,
        maxScore,
        bareme:         {},
        series:         session.series,
        subjectFileRef: storageRef.fullPath,
      });

      setDepositDone(true);
    } catch (e) {
      setDepositError(e instanceof Error ? e.message : 'Erreur lors du dépôt.');
    } finally {
      setDepositing(false);
    }
  }

  // ── Render ─────────────────────────────────────────────────────────────────

  return (
    <div className="p-8">
      {/* Styles pour la preview KaTeX */}
      <style>{`
        .sp h1{font-size:1.15rem;font-weight:700;margin:1.2em 0 0.5em;color:#111}
        .sp h2{font-size:1.05rem;font-weight:700;margin:1.3em 0 0.4em;color:#111;border-top:1px solid #e5e7eb;padding-top:0.8em}
        .sp h2:first-child{border-top:none;padding-top:0}
        .sp h3{font-size:0.95rem;font-weight:600;margin:0.9em 0 0.3em;color:#333}
        .sp p{margin:0.35em 0}
        .sp ol{padding-left:1.5em;margin:0.3em 0}
        .sp ul{padding-left:1.5em;margin:0.3em 0}
        .sp li{margin:0.25em 0}
        .sp strong{font-weight:600}
        .sp hr{border:none;border-top:1px solid #e5e7eb;margin:1em 0}
        .sp blockquote{border-left:3px solid #e5e7eb;padding-left:1em;color:#555;margin:0.5em 0}
        .sp-katex-display{overflow-x:auto;margin:0.6em 0;text-align:center}
        .sp .katex-display{margin:0.4em 0}
        .sp code{font-family:monospace;font-size:0.85em;background:#f3f4f6;padding:0.1em 0.3em;border-radius:3px}
      `}</style>

      <div className="mx-auto max-w-7xl space-y-6">

        {/* En-tête page */}
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-violet-100">
            <Sparkles className="h-5 w-5 text-violet-600" />
          </div>
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Générateur de sujets IA</h1>
            <p className="text-sm text-gray-500">Génère des épreuves BEPC / BAC dans le style des examens congolais.</p>
          </div>
        </div>

        <div className="grid grid-cols-1 gap-6 lg:grid-cols-5">

          {/* ── Formulaire ── */}
          <div className="lg:col-span-2 space-y-4">
            <Card>
              <CardHeader>
                <CardTitle className="text-sm text-gray-700">Configuration</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">

                <div className="space-y-1.5">
                  <Label className="text-xs font-medium text-gray-600">Classe / Série</Label>
                  <Select value={classe} onValueChange={(v) => { if (v) { setClasse(v); setMatiere(''); } }}>
                    <SelectTrigger className="text-sm"><SelectValue placeholder="Choisir une classe…" /></SelectTrigger>
                    <SelectContent>
                      {Object.keys(MATIERES).map((k) => (
                        <SelectItem key={k} value={k}>{k}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>

                <div className="space-y-1.5">
                  <Label className="text-xs font-medium text-gray-600">Matière</Label>
                  <Select value={matiere} onValueChange={(v) => { if (v) setMatiere(v); }} disabled={!classe}>
                    <SelectTrigger className="text-sm">
                      <SelectValue placeholder={classe ? 'Choisir une matière…' : "Sélectionne d'abord une classe"} />
                    </SelectTrigger>
                    <SelectContent>
                      {matiereList.map((m) => (
                        <SelectItem key={m} value={m}>{m}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>

                <div className="grid grid-cols-2 gap-3">
                  <div className="space-y-1.5">
                    <Label className="text-xs font-medium text-gray-600">Durée</Label>
                    <Select value={String(duree)} onValueChange={(v) => { if (v) setDuree(Number(v)); }}>
                      <SelectTrigger className="text-sm"><SelectValue /></SelectTrigger>
                      <SelectContent>
                        {DUREES.map((d) => (
                          <SelectItem key={d} value={String(d)}>{dureeLabel(d)}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="space-y-1.5">
                    <Label className="text-xs font-medium text-gray-600">Coefficient</Label>
                    <input
                      type="number" min={1} max={9} value={coefficient}
                      onChange={(e) => setCoefficient(Number(e.target.value))}
                      className="w-full rounded-md border border-gray-200 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-violet-500"
                    />
                  </div>
                </div>

                <div className="space-y-1.5">
                  <Label className="text-xs font-medium text-gray-600">Date de la session</Label>
                  <div className="grid grid-cols-2 gap-3">
                    <Select value={sessionMonth} onValueChange={(v) => { if (v) setSessionMonth(v); }}>
                      <SelectTrigger className="text-sm"><SelectValue /></SelectTrigger>
                      <SelectContent>
                        {MOIS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}
                      </SelectContent>
                    </Select>
                    <Select value={String(sessionYear)} onValueChange={(v) => { if (v) setSessionYear(Number(v)); }}>
                      <SelectTrigger className="text-sm"><SelectValue /></SelectTrigger>
                      <SelectContent>
                        {ANNEES.map((y) => <SelectItem key={y} value={String(y)}>{y}</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </div>
                </div>

                <div className="space-y-1.5">
                  <div className="flex items-center justify-between">
                    <Label className="text-xs font-medium text-gray-600">
                      Exemples de sujets passés
                      <span className="ml-1 text-gray-400 font-normal">(optionnel)</span>
                    </Label>
                    <button
                      type="button"
                      onClick={() => fileInputRef.current?.click()}
                      className="flex items-center gap-1.5 rounded-md border border-violet-200 bg-violet-50 px-2.5 py-1 text-xs font-medium text-violet-700 hover:bg-violet-100 transition-colors"
                    >
                      <ImagePlus className="w-3.5 h-3.5" />
                      Téléverser (image / PDF / DOCX)
                    </button>
                    <input
                      ref={fileInputRef}
                      type="file"
                      accept="image/jpeg,image/jpg,image/png,image/webp,application/pdf,.docx,application/vnd.openxmlformats-officedocument.wordprocessingml.document"
                      multiple
                      className="hidden"
                      onChange={handleFileUpload}
                    />
                  </div>

                  {extractingFiles.length > 0 && (
                    <div className="space-y-1">
                      {extractingFiles.map((f) => (
                        <div key={f.name} className={`flex items-center gap-2 rounded-md px-3 py-1.5 text-xs ${
                          f.status === 'loading' ? 'bg-blue-50 text-blue-700' :
                          f.status === 'done'    ? 'bg-emerald-50 text-emerald-700' :
                                                   'bg-red-50 text-red-600'
                        }`}>
                          {f.status === 'loading' && <Loader2 className="w-3 h-3 shrink-0 animate-spin" />}
                          {f.status === 'done'    && <Check className="w-3 h-3 shrink-0" />}
                          {f.status === 'error'   && <span className="shrink-0">✕</span>}
                          <span className="flex-1 truncate">{f.name}</span>
                          {f.status === 'loading' && <span className="shrink-0 text-blue-500">Extraction…</span>}
                          {f.status === 'done'    && <span className="shrink-0">Extrait ✓</span>}
                          {f.status === 'error'   && <span className="shrink-0 max-w-[120px] truncate">{f.error}</span>}
                          {f.status !== 'loading' && (
                            <button onClick={() => removeExtractedFile(f.name)} className="ml-1 shrink-0 opacity-60 hover:opacity-100">
                              <X className="w-3 h-3" />
                            </button>
                          )}
                        </div>
                      ))}
                    </div>
                  )}

                  <textarea
                    className="w-full rounded-md border border-gray-200 bg-white px-3 py-2 text-xs text-gray-800 placeholder:text-gray-400 focus:outline-none focus:ring-2 focus:ring-violet-500 resize-none"
                    rows={7}
                    placeholder={"Colle ici 1 à 3 anciens sujets, ou utilise \"Téléverser\" pour importer une image, un PDF ou un DOCX.\n\nExemple :\nMATHÉMATIQUES — BEPC 2022\nExercice 1 (4 points)\n..."}
                    value={exemples}
                    onChange={(e) => setExemples(e.target.value)}
                  />
                </div>

                <Button
                  className="w-full bg-violet-600 hover:bg-violet-700 text-white"
                  onClick={handleGenerate}
                  disabled={!canGenerate}
                >
                  {loading ? (
                    <><RefreshCw className="w-4 h-4 mr-2 animate-spin" />Génération en cours…</>
                  ) : (
                    <><Sparkles className="w-4 h-4 mr-2" />Générer le sujet</>
                  )}
                </Button>

                {error && (
                  <p className="rounded-md bg-red-50 px-3 py-2 text-xs text-red-600">{error}</p>
                )}
              </CardContent>
            </Card>

            <Card className="bg-violet-50 border-violet-100">
              <CardContent className="p-4 space-y-2 text-xs text-violet-700">
                <p className="font-semibold">Conseils pour de meilleurs résultats</p>
                <ul className="space-y-1 text-violet-600 list-disc list-inside">
                  <li>Colle au moins un ancien sujet complet comme exemple</li>
                  <li>Vérifie toujours le barème et les points</li>
                  <li>Tu peux régénérer autant de fois que nécessaire</li>
                  <li>Dépose directement dans une session via le bouton dédié</li>
                </ul>
              </CardContent>
            </Card>
          </div>

          {/* ── Résultat ── */}
          <div className="lg:col-span-3">
            <Card className="h-full flex flex-col">
              <CardHeader className="flex-row items-center justify-between pb-2 flex-wrap gap-2">
                <div className="flex items-center gap-2">
                  <CardTitle className="text-sm text-gray-700">Sujet généré</CardTitle>

                  {/* Toggle Preview / Éditer */}
                  {output && !loading && (
                    <div className="flex overflow-hidden rounded-lg border border-gray-200">
                      <button
                        onClick={() => setPreviewMode(false)}
                        className={`flex items-center gap-1 px-3 py-1 text-xs font-medium transition-colors ${
                          !previewMode ? 'bg-violet-600 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'
                        }`}
                      >
                        <Pencil className="w-3 h-3" />Éditer
                      </button>
                      <button
                        onClick={() => switchToPreview(output)}
                        disabled={rendering}
                        className={`flex items-center gap-1 px-3 py-1 text-xs font-medium transition-colors ${
                          previewMode ? 'bg-violet-600 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'
                        }`}
                      >
                        {rendering
                          ? <Loader2 className="w-3 h-3 animate-spin" />
                          : <Eye className="w-3 h-3" />}
                        Aperçu
                      </button>
                    </div>
                  )}
                </div>

                {output && (
                  <div className="flex gap-2 flex-wrap">
                    <Button variant="outline" size="sm" onClick={handleGenerate} disabled={loading}>
                      <RotateCcw className="w-3.5 h-3.5 mr-1.5" />Régénérer
                    </Button>
                    <Button variant="outline" size="sm" onClick={handleCopy}>
                      {copied
                        ? <><Check className="w-3.5 h-3.5 mr-1.5 text-emerald-600" />Copié !</>
                        : <><Copy className="w-3.5 h-3.5 mr-1.5" />Copier</>}
                    </Button>
                    <Button
                      size="sm"
                      className="bg-violet-600 hover:bg-violet-700 text-white"
                      onClick={openDepositDialog}
                      disabled={loading}
                    >
                      <Upload className="w-3.5 h-3.5 mr-1.5" />
                      Déposer dans une session
                    </Button>
                  </div>
                )}
              </CardHeader>

              <CardContent className="flex-1 p-0 overflow-hidden">
                {/* État vide */}
                {!output && !loading && (
                  <div className="flex h-full min-h-[500px] items-center justify-center text-center px-8">
                    <div className="space-y-2">
                      <Sparkles className="mx-auto h-10 w-10 text-gray-200" />
                      <p className="text-sm text-gray-400">Configure le sujet à gauche, puis clique sur &ldquo;Générer&rdquo;.</p>
                      <p className="text-xs text-gray-300">Le sujet apparaîtra ici en temps réel.</p>
                    </div>
                  </div>
                )}

                {/* Mode édition / streaming */}
                {(output || loading) && !previewMode && (
                  <textarea
                    className="h-full min-h-[600px] w-full resize-none rounded-b-lg border-0 bg-gray-50 px-5 py-4 font-mono text-xs leading-relaxed text-gray-800 focus:outline-none focus:ring-0"
                    value={output}
                    onChange={(e) => { setOutput(e.target.value); setRenderedHtml(''); }}
                    placeholder={loading ? 'Génération en cours…' : ''}
                    spellCheck={false}
                  />
                )}

                {/* Mode aperçu KaTeX */}
                {output && previewMode && (
                  <div className="h-full min-h-[600px] overflow-y-auto bg-white">
                    {/* En-tête DiakExam */}
                    <div className="px-6 pt-6 pb-5 text-center border-b-2 border-gray-800 mb-5">
                      <div className="text-xl font-bold tracking-wide text-gray-900">DiakExam</div>
                      <div className="text-[10px] uppercase tracking-widest text-gray-400 mt-0.5 mb-3">Plateforme de préparation aux examens nationaux</div>
                      <div className="text-sm text-gray-800">Session de préparation · <strong>{sessionDate}</strong></div>
                      <div className="text-sm text-gray-800">Examen du <strong>{typeExamen}</strong>{serieLabel ? `  |  Série : ${serieLabel}` : ''}</div>
                      <div className="text-sm text-gray-800">Discipline : <strong>{matiere}</strong></div>
                      <div className="text-sm text-gray-800">Durée : <strong>{dureeLabel(duree)}</strong> &nbsp;|&nbsp; Coefficient : <strong>{coefficient}</strong></div>
                    </div>
                    {/* Contenu exercices (KaTeX) */}
                    <div
                      className="sp px-6 pb-6 text-sm text-gray-800 leading-relaxed"
                      dangerouslySetInnerHTML={{ __html: renderedHtml }}
                    />
                  </div>
                )}
              </CardContent>
            </Card>
          </div>
        </div>
      </div>

      {/* ── Dialogue dépôt ── */}
      <Dialog open={depositOpen} onOpenChange={(open) => { if (!depositing) setDepositOpen(open); }}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Déposer dans une session</DialogTitle>
          </DialogHeader>

          {depositDone ? (
            <div className="flex flex-col items-center gap-3 py-6 text-center">
              <CheckCircle className="h-12 w-12 text-emerald-500" />
              <p className="font-semibold text-gray-800">Sujet déposé avec succès !</p>
              <p className="text-sm text-gray-500">L&apos;épreuve a été ajoutée à la session et est visible dans la page Sessions.</p>
              <Button className="mt-2 w-full" onClick={() => setDepositOpen(false)}>Fermer</Button>
            </div>
          ) : (
            <div className="space-y-4">

              {/* Récap sujet */}
              <div className="rounded-lg border border-gray-100 bg-gray-50 px-4 py-3 text-xs text-gray-600">
                <span className="font-semibold text-gray-800">{matiere || '—'}</span>
                {' · '}{classeLabel || '—'}
                {serieLabel ? ` série ${serieLabel}` : ''}
                {' · '}{dureeLabel(duree)}
              </div>

              {/* Sélection session */}
              <div className="space-y-1.5">
                <Label className="text-xs font-medium text-gray-600">Session cible</Label>
                {sessionsLoading ? (
                  <p className="text-xs text-gray-400 py-2">Chargement des sessions…</p>
                ) : sessions.length === 0 ? (
                  <p className="text-xs text-orange-500 py-2">Aucune session en brouillon ou ouverte. Crée d&apos;abord une session.</p>
                ) : (
                  <Select value={targetSession} onValueChange={(v) => { if (v) setTargetSession(v); }}>
                    <SelectTrigger className="text-sm">
                      <SelectValue placeholder="Choisir une session…">
                        {targetSession
                          ? sessions.find((s) => s.id === targetSession)?.title ?? targetSession
                          : 'Choisir une session…'}
                      </SelectValue>
                    </SelectTrigger>
                    <SelectContent>
                      {sessions.map((s) => (
                        <SelectItem key={s.id} value={s.id}>
                          {s.title} — {s.status}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                )}
              </div>

              {/* Type épreuve */}
              <div className="space-y-1.5">
                <Label className="text-xs font-medium text-gray-600">Type d&apos;épreuve</Label>
                <Select value={subjectType} onValueChange={(v) => { if (v) setSubjectType(v as 'structured' | 'literary' | 'qcm'); }}>
                  <SelectTrigger className="text-sm"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="structured">Structurée (exercices numérotés)</SelectItem>
                    <SelectItem value="literary">Littéraire (dissertation, commentaire…)</SelectItem>
                    <SelectItem value="qcm">QCM</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              {/* Coefficient + Note max */}
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-1.5">
                  <Label className="text-xs font-medium text-gray-600">Coefficient</Label>
                  <input
                    type="number" min={1} max={9} value={coefficient}
                    onChange={(e) => setCoefficient(Number(e.target.value))}
                    className="w-full rounded-md border border-gray-200 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-violet-500"
                  />
                </div>
                <div className="space-y-1.5">
                  <Label className="text-xs font-medium text-gray-600">Note maximale</Label>
                  <input
                    type="number" min={1} max={100} value={maxScore}
                    onChange={(e) => setMaxScore(Number(e.target.value))}
                    className="w-full rounded-md border border-gray-200 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-violet-500"
                  />
                </div>
              </div>

              {depositError && (
                <p className="rounded-md bg-red-50 px-3 py-2 text-xs text-red-600">{depositError}</p>
              )}

              <div className="flex gap-3 pt-1">
                <Button variant="outline" className="flex-1" onClick={() => setDepositOpen(false)} disabled={depositing}>
                  Annuler
                </Button>
                <Button
                  className="flex-1 bg-violet-600 hover:bg-violet-700 text-white"
                  onClick={handleDeposit}
                  disabled={!targetSession || depositing || sessionsLoading}
                >
                  {depositing ? (
                    <><RefreshCw className="w-4 h-4 mr-2 animate-spin" />Génération PDF…</>
                  ) : (
                    <><Upload className="w-4 h-4 mr-2" />Déposer</>
                  )}
                </Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
