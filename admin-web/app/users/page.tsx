'use client';

import { useEffect, useMemo, useState } from 'react';
import { doc, updateDoc } from 'firebase/firestore';
import { httpsCallable } from 'firebase/functions';
import { AdminShell } from '@/components/admin/admin-shell';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import { useAuth } from '@/lib/auth-context';
import { getFirebaseFunctionErrorMessage } from '@/lib/firebase-function-error';
import { subscribeToUsers } from '@/lib/firestore-helpers';
import { db, functions } from '@/lib/firebase';
import { UserProfile, UserRole } from '@/lib/types';

type RoleFilter = 'all' | UserRole;

interface CreateStaffPayload {
  email: string;
  password: string;
  displayName: string;
  role: 'corrector' | 'admin';
  phone?: string;
}

export default function UsersPage() {
  return (
    <AdminShell requiredRole="admin">
      <UsersContent />
    </AdminShell>
  );
}

function UsersContent() {
  const { profile } = useAuth();
  const [users, setUsers] = useState<UserProfile[]>([]);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState('');
  const [search, setSearch] = useState('');
  const [roleFilter, setRoleFilter] = useState<RoleFilter>('all');
  const [dialogOpen, setDialogOpen] = useState(false);
  const [creating, setCreating] = useState(false);
  const [updatingRoleId, setUpdatingRoleId] = useState<string | null>(null);
  const [togglingBlockId, setTogglingBlockId] = useState<string | null>(null);

  const [displayName, setDisplayName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [phone, setPhone] = useState('');
  const [staffRole, setStaffRole] = useState<'corrector' | 'admin'>('corrector');

  useEffect(() => {
    setLoading(true);
    const unsub = subscribeToUsers((loadedUsers) => {
      setUsers(loadedUsers);
      setLoading(false);
    });
    return unsub;
  }, []);

  const filteredUsers = useMemo(() => {
    const q = search.trim().toLowerCase();
    return users.filter((user) => {
      if (roleFilter !== 'all' && user.role !== roleFilter) return false;
      if (!q) return true;
      return [user.displayName, user.email, user.phone, user.school, user.series]
        .some((v) => v.toLowerCase().includes(q));
    });
  }, [users, search, roleFilter]);

  const stats = useMemo(() => ({
    total: users.length,
    students: users.filter((u) => u.role === 'student').length,
    correctors: users.filter((u) => u.role === 'corrector').length,
    admins: users.filter((u) => u.role === 'admin').length,
  }), [users]);

  function resetStaffForm() {
    setDisplayName(''); setEmail(''); setPassword(''); setPhone(''); setStaffRole('corrector');
  }

  async function handleCreateStaff() {
    if (!displayName.trim() || !email.trim() || !password) {
      setMessage('Nom, email et mot de passe sont requis.');
      return;
    }
    setCreating(true);
    setMessage('');
    try {
      const createStaffUser = httpsCallable<CreateStaffPayload, { success: boolean; uid: string }>(
        functions, 'createStaffUser'
      );
      await createStaffUser({
        email: email.trim(), password,
        displayName: displayName.trim(),
        role: staffRole,
        phone: phone.trim() || undefined,
      });
      resetStaffForm();
      setDialogOpen(false);
      setMessage('Compte staff créé avec succès.');
    } catch (error) {
      setMessage(getFirebaseFunctionErrorMessage(error, 'Création du compte impossible.'));
    } finally {
      setCreating(false);
    }
  }

  async function handleToggleBlock(user: UserProfile) {
    const nextBlocked = !user.blocked;
    const confirmed = window.confirm(
      `Voulez-vous ${nextBlocked ? 'bloquer' : 'débloquer'} le compte de ${user.displayName} ?`
    );
    if (!confirmed) return;

    setTogglingBlockId(user.uid);
    setMessage('');
    try {
      await updateDoc(doc(db, 'users', user.uid), { blocked: nextBlocked });
      setMessage(`Compte de ${user.displayName} ${nextBlocked ? 'bloqué' : 'débloqué'}.`);
    } catch (error) {
      setMessage(getFirebaseFunctionErrorMessage(error, 'Impossible de modifier le compte.'));
    } finally {
      setTogglingBlockId(null);
    }
  }

  async function handleRoleChange(user: UserProfile, nextRole: UserRole) {
    if (user.uid === profile?.uid) {
      setMessage('Tu ne peux pas modifier ton propre rôle depuis cette page.');
      return;
    }
    if (user.role === nextRole) return;
    if (
      user.role === 'corrector' &&
      nextRole !== 'corrector' &&
      (user.activeCorrections ?? 0) > 0
    ) {
      setMessage(`Réaffecte d'abord les ${user.activeCorrections} copie(s) de ${user.displayName}.`);
      return;
    }

    setUpdatingRoleId(user.uid);
    setMessage('');
    try {
      await updateDoc(doc(db, 'users', user.uid), {
        role: nextRole,
        activeCorrections: nextRole === 'corrector' ? user.activeCorrections ?? 0 : 0,
      });
      setMessage(`Rôle mis à jour pour ${user.displayName}.`);
    } catch (error) {
      setMessage(getFirebaseFunctionErrorMessage(error, 'Mise à jour du rôle impossible.'));
    } finally {
      setUpdatingRoleId(null);
    }
  }

  return (
    <div className="p-8">
      <div className="mx-auto max-w-7xl space-y-6">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Utilisateurs</h1>
            <p className="mt-1 text-sm text-gray-500">
              Gestion des comptes élèves, correcteurs et administrateurs.
            </p>
          </div>
          <Button
            onClick={() => { resetStaffForm(); setDialogOpen(true); }}
            className="bg-primary text-white hover:bg-primary/90"
          >
            + Nouveau compte staff
          </Button>
        </div>

        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          <StatCard label="Total"       value={stats.total}      color="text-gray-800" />
          <StatCard label="Élèves"      value={stats.students}   color="text-green-700" />
          <StatCard label="Correcteurs" value={stats.correctors} color="text-blue-700" />
          <StatCard label="Admins"      value={stats.admins}     color="text-purple-700" />
        </div>

        <Card>
          <CardContent className="flex flex-col gap-4 p-5 lg:flex-row">
            <div className="flex-1 space-y-1">
              <Label>Recherche</Label>
              <Input
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Nom, email, téléphone, école, série..."
              />
            </div>
            <div className="w-full space-y-1 lg:w-56">
              <Label>Rôle</Label>
              <Select
                value={roleFilter}
                onValueChange={(value) => { if (value) setRoleFilter(value as RoleFilter); }}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">Tous</SelectItem>
                  <SelectItem value="student">Élèves</SelectItem>
                  <SelectItem value="corrector">Correcteurs</SelectItem>
                  <SelectItem value="admin">Admins</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </CardContent>
        </Card>

        {message && (
          <p className={`rounded-lg px-4 py-3 text-sm ${
            message.includes('succès') || message.includes('mis à jour') || message.includes('bloqué') || message.includes('débloqué')
              ? 'bg-green-50 text-green-700'
              : 'bg-red-50 text-red-700'
          }`}>
            {message}
          </p>
        )}

        <Card>
          <CardContent className="p-0">
            {loading ? (
              <div className="py-16 text-center text-gray-400 text-sm">Chargement des utilisateurs...</div>
            ) : filteredUsers.length === 0 ? (
              <div className="py-16 text-center text-gray-400 text-sm">
                Aucun utilisateur ne correspond au filtre courant.
              </div>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Utilisateur</TableHead>
                    <TableHead>Contact</TableHead>
                    <TableHead>Profil élève</TableHead>
                    <TableHead>Rôle</TableHead>
                    <TableHead>Charge</TableHead>
                    <TableHead>Créé le</TableHead>
                    <TableHead>Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filteredUsers.map((user) => (
                    <TableRow key={user.uid}>
                      <TableCell className="align-top">
                        <div className="flex items-center gap-2">
                          <p className="font-medium text-gray-900">{user.displayName}</p>
                          {user.blocked && (
                            <span className="rounded-full bg-red-100 px-2 py-0.5 text-xs font-medium text-red-700">
                              Bloqué
                            </span>
                          )}
                        </div>
                        <p className="text-xs text-gray-400 mt-0.5">{user.uid}</p>
                      </TableCell>
                      <TableCell className="align-top">
                        <p className="text-sm">{user.email || '—'}</p>
                        <p className="text-xs text-gray-500">{user.phone || '—'}</p>
                      </TableCell>
                      <TableCell className="align-top text-sm text-gray-600">
                        <p>{user.school || 'École non renseignée'}</p>
                        <p className="text-xs text-gray-500">
                          {user.class ?? 'Classe —'}{user.series ? ` · Série ${user.series}` : ''}
                        </p>
                      </TableCell>
                      <TableCell className="align-top">
                        <div className="space-y-2">
                          <RoleBadge role={user.role} />
                          {user.uid === profile?.uid ? (
                            <p className="text-xs text-gray-400">Compte connecté</p>
                          ) : (
                            <Select
                              value={user.role}
                              onValueChange={(value) => value ? handleRoleChange(user, value as UserRole) : undefined}
                              disabled={updatingRoleId === user.uid}
                            >
                              <SelectTrigger className="h-8 w-40 text-xs">
                                <SelectValue />
                              </SelectTrigger>
                              <SelectContent>
                                <SelectItem value="student">Élève</SelectItem>
                                <SelectItem value="corrector">Correcteur</SelectItem>
                                <SelectItem value="admin">Admin</SelectItem>
                              </SelectContent>
                            </Select>
                          )}
                        </div>
                      </TableCell>
                      <TableCell className="align-top">
                        {user.role === 'corrector' ? (
                          <span className="text-sm font-medium text-blue-700">
                            {user.activeCorrections ?? 0} copie(s)
                          </span>
                        ) : (
                          <span className="text-sm text-gray-400">—</span>
                        )}
                      </TableCell>
                      <TableCell className="align-top text-sm text-gray-500">
                        {user.createdAt.toLocaleDateString('fr-FR', {
                          day: '2-digit', month: 'short', year: 'numeric',
                        })}
                      </TableCell>
                      <TableCell className="align-top">
                        {user.role === 'student' && user.uid !== profile?.uid && (
                          <Button
                            variant="outline"
                            size="sm"
                            disabled={togglingBlockId === user.uid}
                            onClick={() => handleToggleBlock(user)}
                            className={
                              user.blocked
                                ? 'border-green-200 text-green-700 hover:bg-green-50'
                                : 'border-red-200 text-red-600 hover:bg-red-50 hover:text-red-700'
                            }
                          >
                            {togglingBlockId === user.uid ? '...' : user.blocked ? 'Débloquer' : 'Bloquer'}
                          </Button>
                        )}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>
      </div>

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>Nouveau compte staff</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label>Nom complet</Label>
              <Input
                value={displayName}
                onChange={(e) => setDisplayName(e.target.value)}
                placeholder="Marie Nkouka"
              />
            </div>
            <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
              <div className="space-y-1.5">
                <Label>Email</Label>
                <Input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="correcteur@examsim.cg"
                />
              </div>
              <div className="space-y-1.5">
                <Label>Téléphone</Label>
                <Input
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  placeholder="+242..."
                />
              </div>
            </div>
            <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
              <div className="space-y-1.5">
                <Label>Mot de passe temporaire</Label>
                <Input
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="Minimum 6 caractères"
                />
              </div>
              <div className="space-y-1.5">
                <Label>Rôle</Label>
                <Select
                  value={staffRole}
                  onValueChange={(value) => value ? setStaffRole(value as 'corrector' | 'admin') : undefined}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="corrector">Correcteur</SelectItem>
                    <SelectItem value="admin">Admin</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
            <div className="rounded-lg border border-blue-100 bg-blue-50 px-4 py-3 text-sm text-blue-700">
              Le compte est créé dans Firebase Auth et devient immédiatement utilisable.
            </div>
            <div className="flex justify-end gap-3">
              <Button variant="outline" onClick={() => setDialogOpen(false)}>Annuler</Button>
              <Button
                onClick={handleCreateStaff}
                disabled={creating}
                className="bg-primary text-white hover:bg-primary/90"
              >
                {creating ? 'Création...' : 'Créer le compte'}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}

function StatCard({ label, value, color }: { label: string; value: number; color: string }) {
  return (
    <Card>
      <CardContent className="p-4 text-center">
        <p className={`text-3xl font-bold ${color}`}>{value}</p>
        <p className="mt-1 text-xs text-gray-500">{label}</p>
      </CardContent>
    </Card>
  );
}

function RoleBadge({ role }: { role: UserRole }) {
  const config: Record<UserRole, string> = {
    student:   'bg-green-100 text-green-700',
    corrector: 'bg-blue-100 text-blue-700',
    admin:     'bg-purple-100 text-purple-700',
  };
  const label: Record<UserRole, string> = {
    student:   'Élève',
    corrector: 'Correcteur',
    admin:     'Admin',
  };
  return <Badge className={`border-0 ${config[role]}`}>{label[role]}</Badge>;
}
