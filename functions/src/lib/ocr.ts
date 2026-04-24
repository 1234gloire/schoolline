import * as vision from '@google-cloud/vision';
import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';

const client = new vision.ImageAnnotatorClient();
const IMAGE_EXTENSIONS = ['.jpg', '.jpeg', '.png', '.webp', '.heic'];

/**
 * Extrait le texte d'un fichier image ou PDF depuis Firebase Storage.
 * Retourne le texte brut ou une chaîne vide en cas d'échec.
 */
export async function extractTextFromStorage(fileRef: string): Promise<string> {
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
  } catch (error) {
    functions.logger.error('Erreur OCR', { fileRef, error });
    return '';
  }
}

async function extractFolderText(folderRef: string): Promise<string> {
  const bucket = admin.storage().bucket();
  const prefix = `${folderRef.replace(/\/+$/g, '')}/`;
  const [files] = await bucket.getFiles({ prefix });

  const pageFiles = files
      .filter((file) => !file.name.endsWith('/'))
      .sort((a, b) => a.name.localeCompare(b.name));

  if (pageFiles.length === 0) {
    return '';
  }

  const pages: string[] = [];
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

async function extractImageText(fileRef: string): Promise<string> {
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

async function extractPdfText(fileRef: string): Promise<string> {
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

  const contents = await Promise.all(
    files
        .filter((file) => !file.name.endsWith('/'))
        .sort((a, b) => a.name.localeCompare(b.name))
        .map(async (file) => {
          const [content] = await file.download();
          return content.toString();
        })
  );

  const texts = contents.flatMap((content) => {
    const result = JSON.parse(content) as {
      responses?: Array<{ fullTextAnnotation?: { text?: string } }>;
    };
    return (
      result.responses?.map(
        (response) => response.fullTextAnnotation?.text ?? ''
      ) ?? []
    );
  });

  return texts.filter(Boolean).join('\n\n');
}

function isImagePath(fileRef: string): boolean {
  const lowerRef = fileRef.toLowerCase();
  return IMAGE_EXTENSIONS.some((extension) => lowerRef.endsWith(extension));
}
