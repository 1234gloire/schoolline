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
exports.deleteMyAccount = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const auth_1 = require("firebase-admin/auth");
const firestore_1 = require("../lib/firestore");
exports.deleteMyAccount = (0, https_1.onCall)({ invoker: 'public', region: 'europe-west1' }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'Authentification requise.');
    }
    const uid = request.auth.uid;
    const userRef = firestore_1.collections.user(uid);
    const userSnap = await userRef.get();
    const user = userSnap.data();
    if (user?.['role'] === 'admin' || user?.['role'] === 'corrector') {
        throw new https_1.HttpsError('failed-precondition', 'Les comptes staff doivent être supprimés depuis l’administration.');
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    await userRef.set({
        displayName: 'Compte supprimé',
        email: '',
        phone: '',
        school: '',
        avatarUrl: '',
        fcmToken: admin.firestore.FieldValue.delete(),
        blocked: true,
        deleted: true,
        deletedAt: now,
        subscriptions: [],
    }, { merge: true });
    try {
        await (0, auth_1.getAuth)().deleteUser(uid);
    }
    catch (error) {
        console.error('deleteMyAccount auth delete failed', { uid, error });
        throw new https_1.HttpsError('internal', 'Impossible de supprimer le compte d’authentification.');
    }
    return { ok: true };
});
//# sourceMappingURL=deleteMyAccount.js.map