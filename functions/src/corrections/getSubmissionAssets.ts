import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { collections } from '../lib/firestore';

interface SubmissionAssetPayload {
  submissionId: string;
}

interface SignedAsset {
  path: string;
  name: string;
  url: string;
}

interface SubmissionAssetsResult {
  copyFiles: SignedAsset[];
  subjectFile: SignedAsset | null;
}

export const getSubmissionAssets = onCall<
  SubmissionAssetPayload,
  Promise<SubmissionAssetsResult>
>({ invoker: 'public' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentification requise.');
  }

  const callerId = request.auth.uid;
  const callerSnap = await collections.user(callerId).get();
  const callerRole = callerSnap.data()?.['role'];

  if (callerRole !== 'admin' && callerRole !== 'corrector') {
    throw new HttpsError(
      'permission-denied',
      'Réservé aux admins et correcteurs.'
    );
  }

  const { submissionId } = request.data;
  if (!submissionId) {
    throw new HttpsError('invalid-argument', 'submissionId requis.');
  }

  const submissionSnap = await collections.submission(submissionId).get();
  if (!submissionSnap.exists) {
    throw new HttpsError('not-found', 'Soumission introuvable.');
  }

  const submission = submissionSnap.data()!;
  if (callerRole !== 'admin' && submission['correctorId'] !== callerId) {
    throw new HttpsError(
      'permission-denied',
      "Cette copie n'est pas assignée à ce correcteur."
    );
  }

  const copyFiles = await getSignedAssetsForRef(
    (submission['fileRef'] as string | undefined) ?? ''
  );

  let subjectFile: SignedAsset | null = null;
  const subjectSnap = await collections
    .subject(
      submission['sessionId'] as string,
      submission['subjectId'] as string
    )
    .get();

  if (subjectSnap.exists) {
    const subjectFileRef = subjectSnap.data()?.['subjectFileRef'] as
      | string
      | undefined;
    if (subjectFileRef) {
      subjectFile = await getSignedAsset(subjectFileRef);
    }
  }

  return {
    copyFiles,
    subjectFile,
  };
});

async function getSignedAssetsForRef(storageRef: string): Promise<SignedAsset[]> {
  const normalizedRef = normalizeStorageRef(storageRef);
  if (!normalizedRef) {
    return [];
  }

  if (looksLikeFile(normalizedRef)) {
    return [await getSignedAsset(normalizedRef)];
  }

  const prefix = `${normalizedRef}/`;
  const [files] = await admin.storage().bucket().getFiles({ prefix });
  const sortedFiles = files
    .filter((file) => !file.name.endsWith('/'))
    .sort((a, b) => a.name.localeCompare(b.name));

  return Promise.all(sortedFiles.map((file) => getSignedAsset(file.name)));
}

async function getSignedAsset(storageRef: string): Promise<SignedAsset> {
  const normalizedRef = normalizeStorageRef(storageRef);
  const file = admin.storage().bucket().file(normalizedRef);
  const [url] = await file.getSignedUrl({
    action: 'read',
    expires: Date.now() + 60 * 60 * 1000,
  });

  return {
    path: normalizedRef,
    name: normalizedRef.split('/').pop() ?? normalizedRef,
    url,
  };
}

function normalizeStorageRef(storageRef: string): string {
  return storageRef.trim().replace(/^\/+|\/+$/g, '');
}

function looksLikeFile(storageRef: string): boolean {
  const lastSegment = storageRef.split('/').pop() ?? '';
  return lastSegment.includes('.');
}
