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
const IMAGE_EXTENSIONS = ['.jpg', '.jpeg', '.png', '.webp', '.heic'];
/**
 * Extrait le texte d'un fichier image ou PDF depuis Firebase Storage.
 * Retourne le texte brut ou une chaîne vide en cas d'échec.
 */
async function extractTextFromStorage(fileRef) {
    try {
        const normalizedRef = fileRef.trim().replace(/^\/+|\/+$/g, '');
        if (!normalizedRef) {
            return '';
        }
        if (normalizedRef.toLowerCase().endsWith('.pdf')) {
            return extractPdfText(normalizedRef);
        }
        if (isImagePath(normalizedRef)) {
            return extractImageText(normalizedRef);
        }
        return extractFolderText(normalizedRef);
    }
    catch (error) {
        functions.logger.error('Erreur OCR', { fileRef, error });
        return '';
    }
}
async function extractFolderText(folderRef) {
    const bucket = admin.storage().bucket();
    const prefix = `${folderRef.replace(/\/+$/g, '')}/`;
    const [files] = await bucket.getFiles({ prefix });
    const pageFiles = files
        .filter((file) => !file.name.endsWith('/'))
        .sort((a, b) => a.name.localeCompare(b.name));
    if (pageFiles.length === 0) {
        return '';
    }
    const pages = [];
    for (const file of pageFiles) {
        const lowerName = file.name.toLowerCase();
        if (lowerName.endsWith('.pdf')) {
            pages.push(await extractPdfText(file.name));
            continue;
        }
        if (!isImagePath(file.name)) {
            continue;
        }
        pages.push(await extractImageText(file.name));
    }
    return pages.filter(Boolean).join('\n\n');
}
async function extractImageText(fileRef) {
    const bucket = admin.storage().bucket();
    const [buffer] = await bucket.file(fileRef).download();
    const [result] = await client.documentTextDetection({
        image: { content: buffer.toString('base64') },
        imageContext: {
            languageHints: ['fr'],
        },
    });
    return result.fullTextAnnotation?.text ?? '';
}
async function extractPdfText(fileRef) {
    const bucket = admin.storage().bucket();
    const operationId = `ocr-output/${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    const inputUri = `gs://${bucket.name}/${fileRef}`;
    const outputUri = `gs://${bucket.name}/${operationId}/`;
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
    const [files] = await bucket.getFiles({ prefix: `${operationId}/` });
    if (files.length === 0) {
        return '';
    }
    const contents = await Promise.all(files
        .filter((file) => !file.name.endsWith('/'))
        .sort((a, b) => a.name.localeCompare(b.name))
        .map(async (file) => {
        const [content] = await file.download();
        return content.toString();
    }));
    const texts = contents.flatMap((content) => {
        const result = JSON.parse(content);
        return (result.responses?.map((response) => response.fullTextAnnotation?.text ?? '') ?? []);
    });
    return texts.filter(Boolean).join('\n\n');
}
function isImagePath(fileRef) {
    const lowerRef = fileRef.toLowerCase();
    return IMAGE_EXTENSIONS.some((extension) => lowerRef.endsWith(extension));
}
//# sourceMappingURL=ocr.js.map