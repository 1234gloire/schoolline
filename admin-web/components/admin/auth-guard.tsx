'use client';

import { useEffect, useMemo } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { UserRole } from '@/lib/types';

interface AuthGuardProps {
  children: React.ReactNode;
  requiredRole?: UserRole | UserRole[];
}

export function AuthGuard({ children, requiredRole = ['admin', 'corrector'] }: AuthGuardProps) {
  const { user, profile, loading } = useAuth();
  const router = useRouter();
  const allowedRoles = useMemo(
    () => (Array.isArray(requiredRole) ? requiredRole : [requiredRole]),
    [requiredRole]
  );

  useEffect(() => {
    if (loading) return;
    if (!user || !profile) {
      router.replace('/login');
      return;
    }
    if (!allowedRoles.includes(profile.role)) {
      router.replace('/login');
    }
  }, [user, profile, loading, router, allowedRoles]);

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="text-center space-y-3">
          <div className="w-10 h-10 border-4 border-primary border-t-transparent rounded-full animate-spin mx-auto" />
          <p className="text-sm text-gray-500">Chargement...</p>
        </div>
      </div>
    );
  }

  if (!user || !profile || !allowedRoles.includes(profile.role)) return null;

  return <>{children}</>;
}
