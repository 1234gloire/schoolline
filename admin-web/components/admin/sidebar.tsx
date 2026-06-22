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
  ChevronUp,
  Mail,
  Phone,
  Shield,
  BarChart2,
  Sparkles,
  Megaphone,
} from 'lucide-react';
import { sendPasswordResetEmail } from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { useAuth } from '@/lib/auth-context';
import { cn } from '@/lib/utils';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';

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
  { href: '/stats',         label: 'Statistiques',        icon: BarChart2,       roles: ['admin'] },
  { href: '/subjects',      label: 'Sujets IA',           icon: Sparkles,        roles: ['admin'] },
  { href: '/announcements', label: 'Annonces',            icon: Megaphone,       roles: ['admin'] },
];

export function Sidebar() {
  const pathname = usePathname();
  const { profile, signOut } = useAuth();
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [profileOpen, setProfileOpen] = useState(false);
  const [resetSent, setResetSent] = useState(false);
  const [resetLoading, setResetLoading] = useState(false);

  const visibleItems = navItems.filter((item) =>
    item.roles.includes(profile?.role ?? '')
  );

  async function handleSendResetEmail() {
    const email = profile?.email;
    if (!email) return;
    setResetLoading(true);
    try {
      await sendPasswordResetEmail(auth, email);
      setResetSent(true);
    } catch (_) {
      // ignore
    } finally {
      setResetLoading(false);
    }
  }

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
            <div className="shrink-0">
              <img src="/logo_diakexam.png" alt="DiakExam" className="h-8 w-auto object-contain" />
            </div>
            <div className="min-w-0">
              <p className="text-white font-bold text-sm leading-tight truncate">DiakExam</p>
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
          <button
            onClick={() => { setResetSent(false); setProfileOpen(true); }}
            className="w-full flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-white/8 transition-colors group"
          >
            <div className="w-7 h-7 rounded-full bg-white/15 flex items-center justify-center shrink-0">
              <span className="text-white text-xs font-semibold">{initials}</span>
            </div>
            <div className="min-w-0 flex-1 text-left">
              <p className="text-white text-sm font-medium truncate leading-tight">
                {profile?.displayName}
              </p>
              <p className="text-white/50 text-xs capitalize">{profile?.role}</p>
            </div>
            <ChevronUp className="w-3.5 h-3.5 text-white/40 group-hover:text-white/70 shrink-0" />
          </button>
          <button
            onClick={() => setConfirmOpen(true)}
            className="w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium text-white/60 hover:bg-white/8 hover:text-white transition-colors"
          >
            <LogOut className="w-4 h-4 shrink-0" />
            Se déconnecter
          </button>
        </div>
      </aside>

      {/* Modal profil admin/correcteur */}
      <Dialog open={profileOpen} onOpenChange={setProfileOpen}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Mon profil</DialogTitle>
          </DialogHeader>
          <div className="space-y-5">
            {/* Avatar + nom */}
            <div className="flex items-center gap-4">
              <div className="w-12 h-12 rounded-full bg-[#0A1172] flex items-center justify-center shrink-0">
                <span className="text-white font-bold text-lg">{initials}</span>
              </div>
              <div>
                <p className="font-semibold text-gray-900">{profile?.displayName}</p>
                <Badge className={profile?.role === 'admin' ? 'border-0 bg-purple-100 text-purple-700' : 'border-0 bg-blue-100 text-blue-700'}>
                  {profile?.role === 'admin' ? 'Administrateur' : 'Correcteur'}
                </Badge>
              </div>
            </div>

            {/* Infos */}
            <div className="space-y-2 rounded-lg border border-gray-100 bg-gray-50 p-4 text-sm">
              <div className="flex items-center gap-2 text-gray-700">
                <Mail className="w-4 h-4 text-gray-400 shrink-0" />
                <span>{profile?.email || '—'}</span>
              </div>
              <div className="flex items-center gap-2 text-gray-700">
                <Phone className="w-4 h-4 text-gray-400 shrink-0" />
                <span>{profile?.phone || 'Téléphone non renseigné'}</span>
              </div>
              <div className="flex items-center gap-2 text-gray-700">
                <Shield className="w-4 h-4 text-gray-400 shrink-0" />
                <span className="text-xs text-gray-400 font-mono break-all">{profile?.uid}</span>
              </div>
            </div>

            {/* Actions */}
            <div className="space-y-2">
              {resetSent ? (
                <p className="rounded-lg bg-green-50 px-4 py-3 text-sm text-green-700">
                  Email de réinitialisation envoyé à {profile?.email}.
                </p>
              ) : (
                <Button
                  variant="outline"
                  className="w-full"
                  disabled={resetLoading}
                  onClick={handleSendResetEmail}
                >
                  {resetLoading ? 'Envoi...' : 'Changer mon mot de passe'}
                </Button>
              )}
              <Button
                variant="destructive"
                className="w-full"
                onClick={() => { setProfileOpen(false); setConfirmOpen(true); }}
              >
                <LogOut className="w-4 h-4 mr-2" />
                Se déconnecter
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

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
