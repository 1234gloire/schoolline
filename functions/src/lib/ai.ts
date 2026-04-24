import { GoogleGenerativeAI } from '@google/generative-ai';
import { logger } from 'firebase-functions/v2';
import { AiEvaluationResult } from './types';

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY ?? '');

const AI_CONFIDENCE_THRESHOLD = 80;

/**
 * Évalue une copie d'élève via Gemini Pro.
 */
export async function evaluateCopy(params: {
  subjectName: string;
  ocrText: string;
  bareme: Record<string, number>;
  maxScore: number;
  corrigeText?: string;
}): Promise<AiEvaluationResult> {
  const { subjectName, ocrText, bareme, maxScore, corrigeText } = params;

  const baremeText = Object.entries(bareme)
    .map(([critere, points]) => `- ${critere}: ${points} points`)
    .join('\n');

  const hasCorrige = corrigeText && corrigeText.trim().length > 0;

  const prompt = `Tu es un correcteur expert du Baccalauréat congolais (République du Congo).
Tu dois évaluer la copie d'un élève de Terminale pour l'épreuve de **${subjectName}**.

## Barème officiel (total: ${maxScore} points)
${baremeText || `- Note globale: ${maxScore} points`}

${hasCorrige ? `## Corrigé officiel (solution de référence)
${corrigeText}

` : ''}## Copie de l'élève (texte extrait par OCR)
${ocrText || '[Copie illisible ou vide]'}

## Instructions
${hasCorrige
  ? `1. Compare la copie de l'élève au corrigé officiel critère par critère
2. Attribue une note précise pour chaque critère du barème selon l'écart avec le corrigé
3. Attribue une note globale sur ${maxScore}
4. Estime ta confiance (0-100%) : haute si la copie est lisible et comparable au corrigé, basse si illisible`
  : `1. Évalue chaque critère du barème avec une note précise
2. Attribue une note globale sur ${maxScore}
3. Estime ta confiance dans cette notation (0-100%) selon la lisibilité du texte et la clarté des réponses
4. Si le texte est trop illisible, mets une confiance basse (< 50%)`}

## Réponds UNIQUEMENT avec ce JSON, sans texte autour :
{
  "score": <nombre entre 0 et ${maxScore}>,
  "confidence": <nombre entre 0 et 100>,
  "details": {
    ${Object.entries(bareme).map(([k, v]) => `"${k}": <note sur ${v}>`).join(',\n    ')}
  },
  "feedback": "<appréciation globale en français, 2-3 phrases>",
  "strengths": ["<point fort 1>", "<point fort 2>"],
  "improvements": ["<axe d'amélioration 1>", "<axe d'amélioration 2>"]
}`;

  try {
    const model = genAI.getGenerativeModel({ model: 'gemini-1.5-pro' });

    const result = await model.generateContent({
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: {
        temperature: 0.2,        // Faible pour des notes stables
        maxOutputTokens: 1024,
        responseMimeType: 'application/json',
      },
    });

    const text = result.response.text();
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    if (!jsonMatch) throw new Error('Pas de JSON dans la réponse Gemini');

    const parsed = JSON.parse(jsonMatch[0]) as AiEvaluationResult;

    // Validation
    if (
      typeof parsed.score !== 'number' ||
      typeof parsed.confidence !== 'number' ||
      !parsed.feedback
    ) {
      throw new Error('Structure JSON Gemini incomplète');
    }

    // Borner les valeurs
    parsed.score = Math.max(0, Math.min(maxScore, parsed.score));
    parsed.confidence = Math.max(0, Math.min(100, parsed.confidence));
    parsed.strengths = parsed.strengths ?? [];
    parsed.improvements = parsed.improvements ?? [];

    return parsed;
  } catch (error) {
    logger.error('Erreur évaluation Gemini', error);
    // Faible confiance → correction humaine automatique
    return {
      score: 0,
      confidence: 0,
      details: {},
      feedback: 'Évaluation automatique impossible. Copie transmise à un correcteur.',
      strengths: [],
      improvements: [],
    };
  }
}

export { AI_CONFIDENCE_THRESHOLD };
