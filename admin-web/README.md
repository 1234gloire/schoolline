# Admin Web

Back-office Next.js pour :
- pilotage des sessions
- validation des paiements
- affectation et suivi des corrections
- publication des resultats
- gestion des utilisateurs

## Prerequis

- Node.js `22`
- un projet Firebase avec Auth, Firestore, Functions et Storage

## Configuration

Copier [admin-web/.env.example](/Users/rofiegloirehiendamiatadi/StudioProjects/schoolline/admin-web/.env.example:1) vers `.env.local` puis renseigner :

- `NEXT_PUBLIC_FIREBASE_API_KEY`
- `NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN`
- `NEXT_PUBLIC_FIREBASE_PROJECT_ID`
- `NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET`
- `NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID`
- `NEXT_PUBLIC_FIREBASE_APP_ID`

Le code Firebase est centralise dans [lib/firebase.ts](/Users/rofiegloirehiendamiatadi/StudioProjects/schoolline/admin-web/lib/firebase.ts:1) et les Functions sont appelees dans la region `europe-west1`.

## Deploiement Vercel

- Si tu relies le repo `admin-web` directement a Vercel, garde sa racine comme `Root Directory`.
- Si tu importes le repo parent `schoolline`, regle le `Root Directory` sur `admin-web` comme recommande par Vercel pour les monorepos.
- Configure la version Node.js du projet en `22.x` pour rester coherente avec le developpement local.
- Renseigne dans Vercel les memes variables que dans `.env.local`, au minimum pour `Production`. Replique-les aussi dans `Preview` si tu veux tester des branches.
- Le build attendu par Vercel est `npm run build`. Le repo embarque deja [vercel.json](/Users/rofiegloirehiendamiatadi/StudioProjects/schoolline/admin-web/vercel.json:1) pour expliciter ce comportement.

### Variables Vercel a definir

- `NEXT_PUBLIC_FIREBASE_API_KEY`
- `NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN`
- `NEXT_PUBLIC_FIREBASE_PROJECT_ID`
- `NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET`
- `NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID`
- `NEXT_PUBLIC_FIREBASE_APP_ID`

### Point Firebase a ne pas oublier

- Si tu mets plus tard un domaine custom sur le back-office, garde `NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN` aligne avec le domaine auth Firebase utilise par ton projet.
- Si tu ajoutes ensuite des flux OAuth ou des liens email Firebase Auth, pense aussi a ajouter le domaine Vercel ou le domaine custom dans les domaines autorises Firebase Auth.

## Commandes

```bash
npm install
npm run dev
npm run lint
npm run build
vercel
vercel --prod
```

## Pages principales

- `/dashboard`
- `/sessions`
- `/payments`
- `/results`
- `/corrections`
- `/users`

## Verification avant mise en production

- `npm run lint`
- `npm run build`
- connexion admin et correcteur
- creation / modification de session
- validation / rejet d'un paiement
- affectation d'une copie a un correcteur
- publication des resultats d'une session

## Limites actuelles

- pas encore de suite de tests automatisee dediee au back-office
- la validation finale du flux doit se faire avec Firebase reel ou emulateurs
