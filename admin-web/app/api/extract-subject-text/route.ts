import { NextRequest, NextResponse } from 'next/server';
import OpenAI from 'openai';

// eslint-disable-next-line @typescript-eslint/no-require-imports
const pdfParse = require('pdf-parse');
// eslint-disable-next-line @typescript-eslint/no-require-imports
const mammoth  = require('mammoth');

const MAX_SIZE_MB = 15;

function resolveFileType(file: File): 'image' | 'pdf' | 'docx' | null {
  const ext = file.name.split('.').pop()?.toLowerCase() ?? '';
  const mime = file.type.toLowerCase();

  if (['jpg', 'jpeg', 'png', 'webp'].includes(ext)) return 'image';
  if (mime.startsWith('image/')) return 'image';

  if (ext === 'pdf') return 'pdf';
  if (mime === 'application/pdf' || mime === 'application/x-pdf') return 'pdf';

  if (ext === 'docx') return 'docx';
  if (mime.includes('wordprocessingml') || mime === 'application/docx') return 'docx';

  return null;
}

export async function POST(req: NextRequest) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    return NextResponse.json({ error: 'OPENAI_API_KEY non configurée.' }, { status: 500 });
  }

  let formData: FormData;
  try {
    formData = await req.formData();
  } catch {
    return NextResponse.json({ error: 'Requête multipart invalide.' }, { status: 400 });
  }

  const file = formData.get('file') as File | null;
  if (!file) {
    return NextResponse.json({ error: 'Aucun fichier reçu.' }, { status: 400 });
  }

  const fileType = resolveFileType(file);
  if (!fileType) {
    return NextResponse.json({
      error: `Format non supporté. Accepté : JPG, PNG, WebP, PDF, DOCX.`,
    }, { status: 400 });
  }
  if (file.size > MAX_SIZE_MB * 1024 * 1024) {
    return NextResponse.json({ error: `Fichier trop lourd (max ${MAX_SIZE_MB} Mo).` }, { status: 400 });
  }

  const bytes  = await file.arrayBuffer();
  const buffer = Buffer.from(bytes);

  try {
    // ── DOCX ────────────────────────────────────────────────────
    if (fileType === 'docx') {
      const result = await mammoth.extractRawText({ buffer });
      const text: string = (result.value ?? '').trim();
      if (!text) {
        return NextResponse.json({ error: 'Aucun texte trouvé dans le document Word.' }, { status: 422 });
      }
      return NextResponse.json({ text });
    }

    // ── PDF ─────────────────────────────────────────────────────
    if (fileType === 'pdf') {
      let extracted = '';
      try {
        const pdfData = await pdfParse(buffer);
        extracted = (pdfData.text ?? '').trim();
      } catch {
        // pdf-parse peut échouer sur certains PDFs chiffrés ou corrompus
      }

      // PDF textuel : on a suffisamment de contenu
      if (extracted.length > 150) {
        return NextResponse.json({ text: extracted });
      }

      // PDF scanné : passer par GPT-4o vision
      const base64  = buffer.toString('base64');
      const dataUrl = `data:application/pdf;base64,${base64}`;
      const openai  = new OpenAI({ apiKey });

      const response = await openai.chat.completions.create({
        model: 'gpt-4o',
        messages: [{
          role: 'user',
          content: [
            { type: 'image_url', image_url: { url: dataUrl, detail: 'high' } },
            {
              type: 'text',
              text: `Transcris exactement le texte de ce sujet d'examen congolais (BEPC ou BAC).
Conserve fidèlement : l'en-tête, les numéros d'exercices, les énoncés, le barème et tous les détails.
Réponds UNIQUEMENT avec le texte transcrit, sans introduction ni commentaire.`,
            },
          ],
        }],
        max_tokens: 4096,
      });

      const text = response.choices[0]?.message?.content ?? '';
      return NextResponse.json({ text });
    }

    // ── Image (JPG / PNG / WebP) ─────────────────────────────────
    const base64  = buffer.toString('base64');
    const dataUrl = `data:${file.type};base64,${base64}`;
    const openai  = new OpenAI({ apiKey });

    const response = await openai.chat.completions.create({
      model: 'gpt-4o',
      messages: [{
        role: 'user',
        content: [
          { type: 'image_url', image_url: { url: dataUrl, detail: 'high' } },
          {
            type: 'text',
            text: `Transcris exactement le texte de ce sujet d'examen congolais (BEPC ou BAC).
Conserve fidèlement : l'en-tête, les numéros d'exercices, les énoncés, le barème et tous les détails.
Réponds UNIQUEMENT avec le texte transcrit, sans introduction ni commentaire.`,
          },
        ],
      }],
      max_tokens: 4096,
    });

    const text = response.choices[0]?.message?.content ?? '';
    return NextResponse.json({ text });

  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Erreur lors de l\'extraction.';
    return NextResponse.json({ error: message }, { status: 502 });
  }
}
