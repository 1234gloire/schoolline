'use client';

import {
  createContext,
  useContext,
  useEffect,
  useState,
  ReactNode,
} from 'react';
import {
  onAuthStateChanged,
  signInWithEmailAndPassword,
  signOut as firebaseSignOut,
  User,
} from 'firebase/auth';
import { doc, getDoc } from 'firebase/firestore';
import { auth, db } from './firebase';
import { UserProfile } from './types';

interface AuthContextValue {
  user: User | null;
  profile: UserProfile | null;
  loading: boolean;
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, async (firebaseUser) => {
      setLoading(true);
      setUser(firebaseUser);

      if (firebaseUser) {
        try {
          const snap = await getDoc(doc(db, 'users', firebaseUser.uid));
          if (!snap.exists()) {
            setProfile(null);
            await firebaseSignOut(auth);
            setLoading(false);
            return;
          }

          const data = snap.data();
          const role = data.role ?? 'student';

          if (role !== 'admin' && role !== 'corrector') {
            setProfile(null);
            await firebaseSignOut(auth);
            setLoading(false);
            return;
          }

          setProfile({
            uid: firebaseUser.uid,
            displayName: data.displayName ?? '',
            email: data.email ?? '',
            phone: data.phone ?? '',
            role,
            class: data.class,
            series: data.series ?? '',
            school: data.school ?? '',
            createdAt: data.createdAt?.toDate() ?? new Date(),
            subscriptions: data.subscriptions ?? [],
            activeCorrections: data.activeCorrections ?? 0,
          });
        } catch {
          setProfile(null);
          await firebaseSignOut(auth);
        }
      } else {
        setProfile(null);
      }
      setLoading(false);
    });
    return unsub;
  }, []);

  const signIn = async (email: string, password: string) => {
    const credential = await signInWithEmailAndPassword(auth, email, password);
    const snap = await getDoc(doc(db, 'users', credential.user.uid));
    const role = snap.data()?.role;
    if (role !== 'admin' && role !== 'corrector') {
      await firebaseSignOut(auth);
      throw new Error('Accès réservé aux admins et correcteurs.');
    }
  };

  const signOut = () => firebaseSignOut(auth);

  return (
    <AuthContext.Provider value={{ user, profile, loading, signIn, signOut }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth doit être dans AuthProvider');
  return ctx;
}
