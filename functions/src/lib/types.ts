// ─── Types partagés entre les Cloud Functions ───

export type SubmissionStatus =
  | 'submitted'
  | 'ocrDone'
  | 'aiReviewed'
  | 'pendingHuman'
  | 'humanReviewed'
  | 'published'
  | 'rejected'
  | 'error';

export interface SubjectData {
  name: string;
  durationMinutes: number;
  startTime: FirebaseFirestore.Timestamp;
  endTime: FirebaseFirestore.Timestamp;
  coefficient: number;
  maxScore: number;
  bareme: Record<string, number>;
  series: string[];
  type: 'structured' | 'literary' | 'qcm';
  subjectFileRef: string;
  sessionId?: string;
  corrigeText?: string;
}

export interface SubmissionData {
  userId: string;
  sessionId: string;
  subjectId: string;
  subjectName: string;
  submittedAt: FirebaseFirestore.Timestamp;
  statusUpdatedAt: FirebaseFirestore.Timestamp;
  fileRef: string;
  status: SubmissionStatus;
  ocrText?: string;
  aiScore?: number;
  aiConfidence?: number;
  aiDetails?: Record<string, number>;
  aiFeedback?: string;
  aiStrengths?: string[];
  aiImprovements?: string[];
  finalScore?: number;
  correctorId?: string;
  correctorNotes?: string;
  publishedAt?: FirebaseFirestore.Timestamp;
}

export interface UserData {
  uid: string;
  displayName: string;
  email: string;
  phone: string;
  role: 'student' | 'corrector' | 'admin';
  class?: string;
  series: string;
  school: string;
  createdAt: FirebaseFirestore.Timestamp;
  subscriptions: string[];
  abandonedSubjectIds?: string[];
  activeCorrections?: number; // pour équilibrage de charge correcteurs
}

export type PaymentStatus = 'pending' | 'approved' | 'rejected';

export interface PaymentData {
  userId: string;
  sessionId: string;
  sessionTitle: string;
  amount: number;
  proofFileRef: string;
  status: PaymentStatus;
  submittedAt: FirebaseFirestore.Timestamp;
  reviewedAt?: FirebaseFirestore.Timestamp;
  reviewedBy?: string;
  rejectionReason?: string;
}

export interface SubjectResultEntry {
  subjectId: string;
  subjectName: string;
  finalScore: number;   // ramené sur 20
  maxScore: number;     // toujours 20 après normalisation
  coefficient: number;
  submissionId: string;
}

export interface StudentResultData {
  userId: string;
  sessionId: string;
  moyenneGenerale: number;
  totalPoints: number;        // Σ(scoreOn20 × coeff)
  totalCoefficients: number;  // Σcoeff
  isAdmis: boolean;
  mention: string;
  subjects: SubjectResultEntry[];
  publishedAt: FirebaseFirestore.Timestamp;
}

export interface AiEvaluationResult {
  score: number;
  confidence: number;
  details: Record<string, number>;
  feedback: string;
  strengths: string[];
  improvements: string[];
}
