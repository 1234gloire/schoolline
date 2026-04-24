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
exports.onUserCreated = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const v2_1 = require("firebase-functions/v2");
const firestore_1 = require("../lib/firestore");
const auth_1 = require("firebase-admin/auth");
/**
 * Appelée via une tâche planifiée ou hook Auth pour créer le profil Firestore.
 * Note: Firebase Functions v2 Auth triggers utilisent onCall ou eventarc.
 * Ici on expose un endpoint HTTP appelé par la Cloud Task déclenchée à la création.
 */
exports.onUserCreated = (0, https_1.onRequest)(async (req, res) => {
    if (req.method !== 'POST') {
        res.status(405).send('Method Not Allowed');
        return;
    }
    const { uid } = req.body;
    if (!uid) {
        res.status(400).send('uid requis');
        return;
    }
    try {
        const existing = await firestore_1.collections.user(uid).get();
        if (existing.exists) {
            res.json({ skipped: true });
            return;
        }
        const authUser = await (0, auth_1.getAuth)().getUser(uid);
        await firestore_1.collections.user(uid).set({
            uid,
            displayName: authUser.displayName ?? authUser.email ?? 'Utilisateur',
            email: authUser.email ?? '',
            phone: authUser.phoneNumber ?? '',
            role: 'student',
            series: '',
            school: '',
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            subscriptions: [],
            abandonedSubjectIds: [],
            activeCorrections: 0,
        });
        v2_1.logger.info(`Profil créé: ${uid}`);
        res.json({ success: true });
    }
    catch (err) {
        v2_1.logger.error('Erreur onUserCreated', err);
        res.status(500).json({ error: String(err) });
    }
});
//# sourceMappingURL=onUserCreated.js.map