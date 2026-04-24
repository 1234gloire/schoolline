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
Object.defineProperty(exports, "__esModule", { value: true });
exports.extractTextFromStorage = extractTextFromStorage;
const vision = __importStar(require("@google-cloud/vision"));
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions"));
const client = new vision.ImageAnnotatorClient();
/**
 * Extrait le texte d'un fichier image ou PDF depuis Firebase Storage.
 * Retourne le texte brut ou une chaîne vide en cas d'échec.
 */
async function extractTextFromStorage(fileRef) {
    try {
        const bucket = admin.storage().bucket();
        const file = bucket.file(fileRef);
        // Télécharger en mémoire (copies ≤ 5 MB selon AppConstants)
        const [buffer] = await file.download();
        const isPdf = fileRef.toLowerCase().endsWith('.pdf');
        if (isPdf) {
            // OCR asynchrone pour PDF via Google Vision
            const inputUri = `gs://${bucket.name}/${fileRef}`;
            const outputUri = `gs://${bucket.name}/ocr-output/${Date.now()}/`;
            const [operation] = await client.asyncBatchAnnotateFiles({
                requests: [
                    {
                        inputConfig: {
                            gcsSource: { uri: inputUri },
                            mimeType: 'application/pdf',
                        },
                        features: [{ type: 'DOCUMENT_TEXT_DETECTION' }],
                        outputConfig: {
                            gcsDestination: { uri: outputUri },
                            batchSize: 10,
                        },
                    },
                ],
            });
            await operation.promise();
            // Lire le fichier de sortie
            const [files] = await bucket.getFiles({ prefix: `ocr-output/${Date.now()}/` });
            if (files.length === 0)
                return '';
            const [content] = await files[0].download();
            const result = JSON.parse(content.toString());
            return result?.responses
                ?.map((r) => r.fullTextAnnotation?.text ?? '')
                .join('\n') ?? '';
        }
        else {
            // OCR synchrone pour images JPEG/PNG
            const [result] = await client.documentTextDetection({
                image: { content: buffer.toString('base64') },
                imageContext: {
                    languageHints: ['fr'], // Français prioritaire
                },
            });
            return result.fullTextAnnotation?.text ?? '';
        }
    }
    catch (error) {
        functions.logger.error('Erreur OCR', { fileRef, error });
        return '';
    }
}
//# sourceMappingURL=ocr.js.map