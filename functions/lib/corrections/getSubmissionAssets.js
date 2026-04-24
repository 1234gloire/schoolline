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
exports.getSubmissionAssets = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("../lib/firestore");
exports.getSubmissionAssets = (0, https_1.onCall)({ invoker: 'public' }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'Authentification requise.');
    }
    const callerId = request.auth.uid;
    const callerSnap = await firestore_1.collections.user(callerId).get();
    const callerRole = callerSnap.data()?.['role'];
    if (callerRole !== 'admin' && callerRole !== 'corrector') {
        throw new https_1.HttpsError('permission-denied', 'Réservé aux admins et correcteurs.');
    }
    const { submissionId } = request.data;
    if (!submissionId) {
        throw new https_1.HttpsError('invalid-argument', 'submissionId requis.');
    }
    const submissionSnap = await firestore_1.collections.submission(submissionId).get();
    if (!submissionSnap.exists) {
        throw new https_1.HttpsError('not-found', 'Soumission introuvable.');
    }
    const submission = submissionSnap.data();
    if (callerRole !== 'admin' && submission['correctorId'] !== callerId) {
        throw new https_1.HttpsError('permission-denied', "Cette copie n'est pas assignée à ce correcteur.");
    }
    const copyFiles = await getSignedAssetsForRef(submission['fileRef'] ?? '');
    let subjectFile = null;
    const subjectSnap = await firestore_1.collections
        .subject(submission['sessionId'], submission['subjectId'])
        .get();
    if (subjectSnap.exists) {
        const subjectFileRef = subjectSnap.data()?.['subjectFileRef'];
        if (subjectFileRef) {
            subjectFile = await getSignedAsset(subjectFileRef);
        }
    }
    return {
        copyFiles,
        subjectFile,
    };
});
async function getSignedAssetsForRef(storageRef) {
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
async function getSignedAsset(storageRef) {
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
function normalizeStorageRef(storageRef) {
    return storageRef.trim().replace(/^\/+|\/+$/g, '');
}
function looksLikeFile(storageRef) {
    const lastSegment = storageRef.split('/').pop() ?? '';
    return lastSegment.includes('.');
}
//# sourceMappingURL=getSubmissionAssets.js.map