"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onUserBlocked = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const auth_1 = require("firebase-admin/auth");
/**
 * Quand un admin bloque un compte (blocked: true),
 * on révoque tous les tokens Firebase Auth de l'utilisateur.
 * L'app mobile le détecte dès le prochain appel réseau et déconnecte l'élève.
 */
exports.onUserBlocked = (0, firestore_1.onDocumentUpdated)('users/{userId}', async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after)
        return;
    const wasBlocked = before['blocked'] === true;
    const isNowBlocked = after['blocked'] === true;
    // On n'agit que sur le passage false → true
    if (wasBlocked || !isNowBlocked)
        return;
    const userId = event.params.userId;
    try {
        await (0, auth_1.getAuth)().revokeRefreshTokens(userId);
    }
    catch (error) {
        // L'utilisateur peut déjà être supprimé ou inactif — on log sans faire planter la fonction
        console.error(`onUserBlocked: impossible de révoquer les tokens de ${userId}`, error);
    }
});
//# sourceMappingURL=onUserBlocked.js.map