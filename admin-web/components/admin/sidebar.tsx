'use client';

import { useState } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import {
  LayoutDashboard,
  ClipboardList,
  CalendarDays,
  Users,
  CreditCard,
  Send,
  LogOut,
} from 'lucide-react';
import { useAuth } from '@/lib/auth-context';
import { cn } from '@/lib/utils';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';

type NavItem = {
  href: string;
  label: string;
  icon: React.ElementType;
  roles: string[];
};

const navItems: NavItem[] = [
  { href: '/dashboard',   label: 'Tableau de bord',    icon: LayoutDashboard, roles: ['admin', 'corrector'] },
  { href: '/corrections', label: 'Corrections',         icon: ClipboardList,   roles: ['admin', 'corrector'] },
  { href: '/sessions',    label: 'Sessions & Épreuves', icon: CalendarDays,    roles: ['admin'] },
  { href: '/users',       label: 'Utilisateurs',        icon: Users,           roles: ['admin'] },
  { href: '/payments',    label: 'Paiements',           icon: CreditCard,      roles: ['admin'] },
  { href: '/results',     label: 'Publication',         icon: Send,            roles: ['admin'] },
];

export function Sidebar() {
  const pathname = usePathname();
  const { profile, signOut } = useAuth();
  const [confirmOpen, setConfirmOpen] = useState(false);

  const visibleItems = navItems.filter((item) =>
    item.roles.includes(profile?.role ?? '')
  );

  const initials = (profile?.displayName ?? 'A')
    .split(' ')
    .map((w) => w[0])
    .slice(0, 2)
    .join('')
    .toUpperCase();

  return (
    <>
      <aside className="w-64 bg-[#0A1172] min-h-screen flex flex-col shrink-0">

        {/* Logo */}
        <div className="px-5 py-5 border-b border-white/10">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 bg-[#F5B731] rounded-lg flex items-center justify-center shrink-0">
              <span className="text-[#0A1172] font-bold text-sm leading-none">E</span>
            </div>
            <div className="min-w-0">
              <p className="text-white font-bold text-sm leading-tight truncate">ExamSim Congo</p>
              <p className="text-white/50 text-xs">Administration</p>
            </div>
          </div>
        </div>

        {/* Navigation */}
        <nav className="flex-1 px-3 py-4 space-y-0.5">
          {visibleItems.map((item) => {
            const Icon = item.icon;
            const isActive = pathname === item.href || pathname.startsWith(item.href + '/');
            return (
              <Link
                key={item.href}
                href={item.href}
                className={cn(
                  'flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors',
                  isActive
                    ? 'bg-white/15 text-white'
                    : 'text-white/60 hover:bg-white/8 hover:text-white'
                )}
              >
                <Icon className="w-4 h-4 shrink-0" />
                {item.label}
              </Link>
            );
          })}
        </nav>

        {/* Profil + déconnexion */}
        <div className="px-3 py-4 border-t border-white/10 space-y-1">
          <div className="flex items-center gap-3 px-3 py-2">
            <div className="w-7 h-7 rounded-full bg-white/15 flex items-center justify-center shrink-0">
              <span className="text-white text-xs font-semibold">{initials}</span>
            </div>
            <div className="min-w-0">
              <p className="text-white text-sm font-medium truncate leading-tight">
                {profile?.displayName}
              </p>
              <p className="text-white/50 text-xs capitalize">{profile?.role}</p>
            </div>
          </div>
          <button
            onClick={() => setConfirmOpen(true)}
            className="w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium text-white/60 hover:bg-white/8 hover:text-white transition-colors"
          >
            <LogOut className="w-4 h-4 shrink-0" />
            Se déconnecter
          </button>
        </div>
      </aside>

      {/* Dialog confirmation déconnexion */}
      <Dialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Se déconnecter</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-gray-600">
            Veux-tu vraiment te déconnecter de l&apos;administration ?
          </p>
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="outline" onClick={() => setConfirmOpen(false)}>
              Annuler
            </Button>
            <Button
              variant="destructive"
              onClick={() => { setConfirmOpen(false); signOut(); }}
            >
              Déconnecter
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
}
