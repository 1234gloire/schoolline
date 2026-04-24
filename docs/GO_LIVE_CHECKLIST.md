# Go-Live Checklist

Checklist finale avant ouverture publique.

## 1. Configuration bloquante

- renseigner les `dart-define` legaux :
  - `LEGAL_ENTITY_NAME`
  - `LEGAL_ENTITY_ADDRESS`
  - `LEGAL_SUPPORT_EMAIL`
  - `LEGAL_SUPPORT_PHONE`
  - `LEGAL_PRIVACY_CONTACT`
  - `LEGAL_DATA_RETENTION`
- verifier `admin-web/.env.local`
- verifier `functions/.env`
- confirmer le projet Firebase cible avec `firebase use`

## 2. Validation technique locale

Depuis la racine :

```bash
flutter analyze
flutter test
cd admin-web && npm run lint && npm run build
cd ../functions && npm run build
```

## 3. Validation des regles Firebase

Demarrer les emulateurs :

```bash
firebase emulators:start --only auth,firestore,functions,storage
```

Valider ces cas :
- un eleve ne peut pas modifier `role`, `subscriptions`, `blocked`
- un eleve peut mettre a jour `displayName`, `phone`, `school`, `avatarUrl`, `fcmToken`
- un eleve peut seulement ajouter a `abandonedSubjectIds`, pas supprimer ni vider
- un eleve peut uploader sa photo uniquement dans `/avatars/{uid}/...`
- un eleve ne peut pas lire ou ecrire dans le dossier avatar d'un autre
- un eleve ne peut pas valider lui-meme un paiement ni corriger une copie

## 4. Recette E2E metier

### Parcours eleve

- inscription
- connexion
- completion profil
- changement mot de passe
- upload / suppression photo de profil

### Paiement

- ouverture d'une session payante
- soumission d'une preuve de paiement
- validation admin
- verification du deverrouillage de la session cote eleve

### Epreuve

- ouverture d'une epreuve accessible
- soumission complete
- mode hors ligne puis reprise de la queue
- impossibilite d'ouvrir une epreuve fermee ou non payee

### Correction / publication

- affectation a un correcteur
- soumission d'une correction
- auto-correction IA si applicable
- publication d'un resultat individuel
- publication finale de session
- consultation du bulletin par l'eleve

### Cas sensibles

- utilisateur bloque
- copie rejetee
- deux sessions actives en parallele
- session ouverte mais resultat deja publie ailleurs

## 5. Notifications push

Tester sur vrai appareil Android et iPhone :
- autorisation acceptee
- autorisation refusee
- app fermee
- app en arriere-plan
- app au premier plan
- clic sur notification -> bonne navigation

Verifier en particulier :
- rappel d'epreuve
- paiement approuve / rejete
- resultat publie

## 6. Deploiement

```bash
firebase deploy --project vdfapp-7c806 --only firestore:rules,storage
cd functions && npm run deploy
cd ../admin-web && npm run build
```

## 7. Go / No-Go

Go si :
- config legale complete
- regles Firebase validees
- recette E2E verte
- push testees sur vrai appareil
- builds Flutter, admin web et functions verts

No-Go si :
- les contacts legaux sont encore manquants
- les regles ne sont pas verifiees
- le flux paiement -> publication n'a pas ete execute une fois completement
