import { NextRequest } from 'next/server';
import { streamText } from 'ai';
import { createOpenAI } from '@ai-sdk/openai';

const SYSTEM_PROMPT = `Tu es un expert en conception de sujets d'examens pour la plateforme DiakExam (République du Congo-Brazzaville).
Tu génères des sujets de préparation authentiques pour les examens nationaux : BEPC (3ème) et BAC (Terminale, séries A, C, D).

Règles strictes :
- Respecte le programme officiel congolais et le niveau attendu pour chaque classe/série.
- Le sujet doit être ORIGINAL — ne répète pas les exercices des exemples fournis.
- Utilise le style, le registre et les thèmes typiques des examens congolais.
- NE génère PAS l'en-tête (il est ajouté automatiquement). Commence DIRECTEMENT par le premier exercice.
- Réponds UNIQUEMENT avec les exercices, sans introduction ni commentaire.

FORMAT DE SORTIE — Markdown avec LaTeX mathématique :
- Titre d'exercice : ## Exercice 1 — Titre (X points)
- Sous-parties : ### Partie A — ...
- Questions numérotées : 1. question  puis  &nbsp;&nbsp;a. sous-question (indente avec 4 espaces ou liste imbriquée)
- Math inline (dans une phrase) : $z^3 + 8i = 0$, $\\sqrt{3}$, $z \\in \\mathbb{C}$, $\\vec{u}$, $\\overrightarrow{AB}$, $\\frac{a}{b}$
- Math display (équation centrée, sur sa propre ligne) : $$U = \\frac{z_C - z_A}{z_B - z_A}$$
- Barème : indique les points dans le titre — ex. ## Exercice 1 — Algèbre (5 points)
- Termine TOUJOURS par une ligne : **Total : 20 points**`;

export async function POST(req: NextRequest) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    return new Response(JSON.stringify({ error: 'OPENAI_API_KEY non configurée.' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  let body: {
    matiere: string;
    classe: string;
    serie?: string;
    typeExamen: string;
    duree: number;
    exemples: string;
  };

  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'Corps de requête invalide.' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const { matiere, classe, serie, typeExamen, duree, exemples } = body;

  if (!matiere || !classe || !typeExamen || !duree) {
    return new Response(JSON.stringify({ error: 'Champs obligatoires manquants.' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const dureeLabel = duree >= 60
    ? `${duree / 60}h${duree % 60 ? (duree % 60) + 'min' : ''}`
    : `${duree} min`;

  const exemplesBlock = exemples?.trim()
    ? `\n\nVoici des exemples de sujets passés pour t'inspirer du style et du niveau :\n\n${exemples.trim()}\n\nGénère maintenant un sujet ORIGINAL dans le même style.`
    : '';

  const userPrompt = `Génère un sujet complet de ${matiere} pour le ${typeExamen} (${classe}${serie ? `, série ${serie}` : ''}), durée : ${dureeLabel}.
NE génère PAS l'en-tête. Commence directement par "## Exercice 1".${exemplesBlock}`;

  const openai = createOpenAI({ apiKey });

  const result = streamText({
    model: openai('gpt-4o'),
    system: SYSTEM_PROMPT,
    prompt: userPrompt,
    temperature: 0.8,
    maxOutputTokens: 4096,
    onError: ({ error }) => {
      console.error('[generate-subject] OpenAI error:', error);
    },
  });

  return result.toTextStreamResponse();
}
