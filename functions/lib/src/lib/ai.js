"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AI_CONFIDENCE_THRESHOLD = void 0;
exports.evaluateCopy = evaluateCopy;
const sdk_1 = __importDefault(require("@anthropic-ai/sdk"));
const functions = __importStar(require("firebase-functions"));
const anthropic = new sdk_1.default({
    apiKey: process.env.ANTHROPIC_API_KEY,
});
const AI_CONFIDENCE_THRESHOLD = 80;
exports.AI_CONFIDENCE_THRESHOLD = AI_CONFIDENCE_THRESHOLD;
/**
 * Évalue une copie d'élève via Claude.
 * Retourne un score, une confiance, et un feedback détaillé.
 */
async function evaluateCopy(params) {
    const { subjectName, ocrText, bareme, maxScore } = params;
    const baremeText = Object.entries(bareme)
        .map(([critere, points]) => `- ${critere}: ${points} points`)
        .join('\n');
    const prompt = `Tu es un correcteur expert du Baccalauréat congolais (République du Congo).
Tu dois évaluer la copie d'un élève de Terminale pour l'épreuve de **${subjectName}**.

## Barème officiel (total: ${maxScore} points)
${baremeText}

## Copie de l'élève (texte extrait par OCR)
${ocrText || '[Copie illisible ou vide]'}

## Instructions d'évaluation
1. Évalue chaque critère du barème avec une note précise
2. Attribue une note globale sur ${maxScore}
3. Estime ta confiance dans cette notation (0-100%) selon :
   - La lisibilité du texte OCR
   - La clarté des réponses de l'élève
   - Ta certitude sur l'interprétation des réponses
4. Si le texte OCR est trop illisible (< 50% de confiance), indique-le

## Format de réponse (JSON strict, aucun texte autour)
{
  "score": <nombre entre 0 et ${maxScore}>,
  "confidence": <nombre entre 0 et 100>,
  "details": {
    ${Object.keys(bareme).map(k => `"${k}": <note sur ${bareme[k]}>`).join(',\n    ')}
  },
  "feedback": "<paragraphe d'appréciation globale en français, 2-3 phrases>",
  "strengths": ["<point fort 1>", "<point fort 2>", "<point fort 3>"],
  "improvements": ["<axe d'amélioration 1>", "<axe d'amélioration 2>"]
}`;
    try {
        const message = await anthropic.messages.create({
            model: 'claude-opus-4-5',
            max_tokens: 1024,
            messages: [{ role: 'user', content: prompt }],
        });
        const content = message.content[0];
        if (content.type !== 'text')
            throw new Error('Réponse IA invalide');
        // Extraire le JSON de la réponse
        const jsonMatch = content.text.match(/\{[\s\S]*\}/);
        if (!jsonMatch)
            throw new Error('Pas de JSON dans la réponse IA');
        const result = JSON.parse(jsonMatch[0]);
        // Validation des champs obligatoires
        if (typeof result.score !== 'number' ||
            typeof result.confidence !== 'number' ||
            !result.feedback ||
            !Array.isArray(result.strengths) ||
            !Array.isArray(result.improvements)) {
            throw new Error('Structure JSON IA incomplète');
        }
        // Borner les valeurs
        result.score = Math.max(0, Math.min(maxScore, result.score));
        result.confidence = Math.max(0, Math.min(100, result.confidence));
        return result;
    }
    catch (error) {
        functions.logger.error('Erreur évaluation IA', error);
        // Retourner un résultat de faible confiance pour déclencher correction humaine
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
//# sourceMappingURL=ai.js.map