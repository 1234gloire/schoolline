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
exports.notifyAdminsOnDemandRequest = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const admin = __importStar(require("firebase-admin"));
const v2_1 = require("firebase-functions/v2");
const firestore_2 = require("../lib/firestore");
exports.notifyAdminsOnDemandRequest = (0, firestore_1.onDocumentCreated)({ document: 'sessions/{sessionId}', region: 'europe-west1' }, async (event) => {
    const data = event.data?.data();
    if (!data || data['isOnDemand'] !== true)
        return;
    const adminsSnap = await firestore_2.collections.users().where('role', '==', 'admin').get();
    const tokens = adminsSnap.docs
        .map((d) => d.data()['fcmToken'])
        .filter((t) => !!t);
    if (tokens.length === 0) {
        v2_1.logger.info('notifyAdminsOnDemandRequest: aucun admin avec token FCM.');
        return;
    }
    const startDate = data['startDate']?.toDate();
    const dateLabel = startDate ? startDate.toLocaleDateString('fr-FR') : '';
    const message = {
        tokens,
        notification: {
            title: '🆕 Session à la demande',
            body: `${data['title']} — à composer avant le ${dateLabel}.`,
        },
        data: { type: 'on_demand_session_requested', sessionId: event.params.sessionId },
        android: { priority: 'high' },
        apns: { payload: { aps: { sound: 'default' } } },
    };
    const result = await admin.messaging().sendEachForMulticast(message);
    v2_1.logger.info(`notifyAdminsOnDemandRequest: ${result.successCount}/${tokens.length} envoyé(s).`);
});
//# sourceMappingURL=notifyAdminsOnDemandRequest.js.map