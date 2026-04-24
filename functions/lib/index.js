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
exports.scheduleExamReminders = exports.autoCloseSessions = exports.validatePayment = exports.submitPaymentProof = exports.onUserBlocked = exports.createStaffUser = exports.onUserCreated = exports.getSubmissionAssets = exports.submitCorrection = exports.assignCorrector = exports.publishSingleResult = exports.publishResults = exports.retrySubmissionProcessing = exports.onAiReviewed = exports.onOcrCompleted = exports.onSubmissionCreated = void 0;
const admin = __importStar(require("firebase-admin"));
const v2_1 = require("firebase-functions/v2");
admin.initializeApp();
(0, v2_1.setGlobalOptions)({
    region: 'europe-west1',
    maxInstances: 10,
});
var onSubmissionCreated_1 = require("./submissions/onSubmissionCreated");
Object.defineProperty(exports, "onSubmissionCreated", { enumerable: true, get: function () { return onSubmissionCreated_1.onSubmissionCreated; } });
var onOcrCompleted_1 = require("./submissions/onOcrCompleted");
Object.defineProperty(exports, "onOcrCompleted", { enumerable: true, get: function () { return onOcrCompleted_1.onOcrCompleted; } });
var onAiReviewed_1 = require("./submissions/onAiReviewed");
Object.defineProperty(exports, "onAiReviewed", { enumerable: true, get: function () { return onAiReviewed_1.onAiReviewed; } });
var retrySubmissionProcessing_1 = require("./submissions/retrySubmissionProcessing");
Object.defineProperty(exports, "retrySubmissionProcessing", { enumerable: true, get: function () { return retrySubmissionProcessing_1.retrySubmissionProcessing; } });
var publishResults_1 = require("./results/publishResults");
Object.defineProperty(exports, "publishResults", { enumerable: true, get: function () { return publishResults_1.publishResults; } });
Object.defineProperty(exports, "publishSingleResult", { enumerable: true, get: function () { return publishResults_1.publishSingleResult; } });
var assignCorrector_1 = require("./corrections/assignCorrector");
Object.defineProperty(exports, "assignCorrector", { enumerable: true, get: function () { return assignCorrector_1.assignCorrector; } });
var submitCorrection_1 = require("./corrections/submitCorrection");
Object.defineProperty(exports, "submitCorrection", { enumerable: true, get: function () { return submitCorrection_1.submitCorrection; } });
var getSubmissionAssets_1 = require("./corrections/getSubmissionAssets");
Object.defineProperty(exports, "getSubmissionAssets", { enumerable: true, get: function () { return getSubmissionAssets_1.getSubmissionAssets; } });
var onUserCreated_1 = require("./users/onUserCreated");
Object.defineProperty(exports, "onUserCreated", { enumerable: true, get: function () { return onUserCreated_1.onUserCreated; } });
var createStaffUser_1 = require("./users/createStaffUser");
Object.defineProperty(exports, "createStaffUser", { enumerable: true, get: function () { return createStaffUser_1.createStaffUser; } });
var onUserBlocked_1 = require("./users/onUserBlocked");
Object.defineProperty(exports, "onUserBlocked", { enumerable: true, get: function () { return onUserBlocked_1.onUserBlocked; } });
var submitPaymentProof_1 = require("./payments/submitPaymentProof");
Object.defineProperty(exports, "submitPaymentProof", { enumerable: true, get: function () { return submitPaymentProof_1.submitPaymentProof; } });
var validatePayment_1 = require("./payments/validatePayment");
Object.defineProperty(exports, "validatePayment", { enumerable: true, get: function () { return validatePayment_1.validatePayment; } });
var autoCloseSessions_1 = require("./sessions/autoCloseSessions");
Object.defineProperty(exports, "autoCloseSessions", { enumerable: true, get: function () { return autoCloseSessions_1.autoCloseSessions; } });
var scheduleExamReminders_1 = require("./notifications/scheduleExamReminders");
Object.defineProperty(exports, "scheduleExamReminders", { enumerable: true, get: function () { return scheduleExamReminders_1.scheduleExamReminders; } });
//# sourceMappingURL=index.js.map