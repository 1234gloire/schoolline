'use client';

import { type ReactNode } from 'react';
import { AuthGuard } from './auth-guard';
import { Sidebar } from './sidebar';
import { type UserRole } from '@/lib/types';

interface AdminShellProps {
  children: ReactNode;
  requiredRole?: UserRole | UserRole[];
}

export function AdminShell({ children, requiredRole }: AdminShellProps) {
  return (
    <AuthGuard requiredRole={requiredRole}>
      <div className="flex min-h-screen bg-gray-50">
        <Sidebar />
        <main className="flex-1 overflow-y-auto">
          {children}
        </main>
      </div>
    </AuthGuard>
  );
}
