import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { getAuth } from 'firebase-admin/auth';
import { collections } from '../lib/firestore';

interface CreateStaffUserPayload {
  email: string;
  password: string;
  displayName: string;
  role: 'corrector' | 'admin';
  phone?: string;
}

export const createStaffUser = onCall<CreateStaffUserPayload>({ invoker: 'public' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Authentification requise.');
    }

    const callerSnap = await collections.user(request.auth.uid).get();
    if (callerSnap.data()?.['role'] !== 'admin') {
      throw new HttpsError('permission-denied', 'Réservé aux admins.');
    }

    const { email, password, displayName, role, phone } = request.data;

    if (!email?.trim() || !password || !displayName?.trim()) {
      throw new HttpsError(
        'invalid-argument',
        'email, password et displayName sont requis.'
      );
    }

    if (role !== 'admin' && role !== 'corrector') {
      throw new HttpsError('invalid-argument', 'Rôle staff invalide.');
    }

    if (password.length < 6) {
      throw new HttpsError(
        'invalid-argument',
        'Le mot de passe doit contenir au moins 6 caractères.'
      );
    }

    const normalizedEmail = email.trim().toLowerCase();
    const normalizedDisplayName = displayName.trim();
    const normalizedPhone = phone?.trim() ?? '';

    try {
      const userRecord = await getAuth().createUser({
        email: normalizedEmail,
        password,
        displayName: normalizedDisplayName,
        phoneNumber: normalizedPhone || undefined,
      });

      await collections.user(userRecord.uid).set({
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
    } catch (error) {
      if (
        typeof error === 'object' &&
        error !== null &&
        'code' in error &&
        error.code === 'auth/email-already-exists'
      ) {
        throw new HttpsError(
          'already-exists',
          'Un compte existe déjà avec cet email.'
        );
      }

      throw new HttpsError(
        'internal',
        error instanceof Error ? error.message : 'Création impossible.'
      );
    }
  }
);
