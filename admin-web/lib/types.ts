export type UserRole = 'student' | 'corrector' | 'admin';
export type SubmissionStatus =
  | 'submitted'
  | 'ocrDone'
  | 'aiReviewed'
  | 'pendingHuman'
  | 'humanReviewed'
  | 'published'
  | 'rejected'
  | 'error';

export type SessionStatus =
  | 'draft'
  | 'open'
  | 'active'
  | 'closed'
  | 'resultsPublished';

export interface UserProfile {
  uid: string;
  displayName: string;
  email: string;
  phone: string;
  role: UserRole;
  class?: string;
  series: string;
  school: string;
  createdAt: Date;
  subscriptions: string[];
  abandonedSubjectIds?: string[];
  activeCorrections?: number;
  blocked?: boolean;
}

export interface SessionModel {
  id: string;
  title: string;
  studentClass: 'terminale' | 'troisieme';
  status: SessionStatus;
  series: string[];
  startDate: Date;
  endDate: Date;
  price: number;
  createdBy: string;
}

export interface SubjectModel {
  corrigeText?: string;
  id: string;
  sessionId: string;
  name: string;
  type: 'structured' | 'literary' | 'qcm';
  durationMinutes: number;
  startTime: Date;
  endTime: Date;
  coefficient: number;
  maxScore: number;
  bareme: Record<string, number>;
  series: string[];
  subjectFileRef: string;
}

export type PaymentStatus = 'pending' | 'approved' | 'rejected';

export interface PaymentModel {
  id: string;
  userId: string;
  sessionId: string;
  sessionTitle: string;
  amount: number;
  proofFileRef: string;
  status: PaymentStatus;
  submittedAt: Date;
  reviewedAt?: Date;
  reviewedBy?: string;
  rejectionReason?: string;
}

export interface SubmissionModel {
  id: string;
  userId: string;
  sessionId: string;
  subjectId: string;
  subjectName: string;
  submittedAt: Date;
  statusUpdatedAt: Date;
  fileRef: string;
  signedUrl?: string;
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
  errorReason?: string;
  publishedAt?: Date;
  subjectMaxScore?: number;
  subjectBareme?: Record<string, number>;
}
