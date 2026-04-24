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
exports.createStaffUser = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const auth_1 = require("firebase-admin/auth");
const firestore_1 = require("../lib/firestore");
exports.createStaffUser = (0, https_1.onCall)({ invoker: 'public' }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'Authentification requise.');
    }
    const callerSnap = await firestore_1.collections.user(request.auth.uid).get();
    if (callerSnap.data()?.['role'] !== 'admin') {
        throw new https_1.HttpsError('permission-denied', 'Réservé aux admins.');
    }
    const { email, password, displayName, role, phone } = request.data;
    if (!email?.trim() || !password || !displayName?.trim()) {
        throw new https_1.HttpsError('invalid-argument', 'email, password et displayName sont requis.');
    }
    if (role !== 'admin' && role !== 'corrector') {
        throw new https_1.HttpsError('invalid-argument', 'Rôle staff invalide.');
    }
    if (password.length < 6) {
        throw new https_1.HttpsError('invalid-argument', 'Le mot de passe doit contenir au moins 6 caractères.');
    }
    const normalizedEmail = email.trim().toLowerCase();
    const normalizedDisplayName = displayName.trim();
    const normalizedPhone = phone?.trim() ?? '';
    try {
        const userRecord = await (0, auth_1.getAuth)().createUser({
            email: normalizedEmail,
            password,
            displayName: normalizedDisplayName,
            phoneNumber: normalizedPhone || undefined,
        });
        await firestore_1.collections.user(userRecord.uid).set({
            uid: userRecord.uid,
            displayName: normalizedDisplayName,
            email: normalizedEmail,
            phone: normalizedPhone,
            role,
            series: '',
            school: '',
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            subscriptions: [],
            abandonedSubjectIds: [],
            activeCorrections: role === 'corrector' ? 0 : 0,
        });
        return {
            success: true,
            uid: userRecord.uid,
        };
    }
    catch (error) {
        if (typeof error === 'object' &&
            error !== null &&
            'code' in error &&
            error.code === 'auth/email-already-exists') {
            throw new https_1.HttpsError('already-exists', 'Un compte existe déjà avec cet email.');
        }
        throw new https_1.HttpsError('internal', error instanceof Error ? error.message : 'Création impossible.');
    }
});
//# sourceMappingURL=createStaffUser.js.map