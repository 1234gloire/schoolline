# ExamSim Congo

Plateforme de simulation et de gestion d'examens pour le Congo Brazzaville.

Le projet contient trois briques :
- une application mobile Flutter pour les eleves
- un back-office admin en Next.js pour les admins et correcteurs
- des Cloud Functions Firebase pour les paiements, notifications, corrections et publications

## Structure

- `lib/` : application mobile Flutter
- `admin-web/` : panel admin Next.js
- `functions/` : Cloud Functions TypeScript
- `firestore.rules` et `storage.rules` : securite Firebase
- `docs/GO_LIVE_CHECKLIST.md` : recette finale et checklist de mise en production

## Prerequis

- Flutter SDK compatible Dart `^3.7.0`
- Node.js `22`
- Firebase CLI
- Un projet Firebase configure

## Configuration

### Mobile Flutter

Le projet mobile utilise `lib/firebase_options.dart` genere par FlutterFire et le projet cible est actuellement `vdfapp-7c806` via [firebase.json](/Users/rofiegloirehiendamiatadi/StudioProjects/schoolline/firebase.json:1).

Pour le lancement public, copie d'abord [config/legal.prod.example.json](/Users/rofiegloirehiendamiatadi/StudioProjects/schoolline/config/legal.prod.example.json:1) vers `config/legal.prod.json`, puis utilise `--dart-define-from-file` :

```bash
cp config/legal.prod.example.json config/legal.prod.json
flutter run --dart-define-from-file=config/legal.prod.json
```

### Admin web

Creer `admin-web/.env.local` a partir de [admin-web/.env.example](/Users/rofiegloirehiendamiatadi/StudioProjects/schoolline/admin-web/.env.example:1).

Variables attendues :
- `NEXT_PUBLIC_FIREBASE_API_KEY`
- `NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN`
- `NEXT_PUBLIC_FIREBASE_PROJECT_ID`
- `NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET`
- `NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID`
- `NEXT_PUBLIC_FIREBASE_APP_ID`

### Cloud Functions

Creer `functions/.env` a partir de [functions/.env.example](/Users/rofiegloirehiendamiatadi/StudioProjects/schoolline/functions/.env.example:1).

Variables attendues :
- `GEMINI_API_KEY`

## Commandes utiles

### Mobile

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

### Admin web

```bash
cd admin-web
npm install
npm run dev
npm run lint
npm run build
```

### Functions

```bash
cd functions
npm install
npm run build
```

### Emulateurs Firebase

Les ports sont deja fixes dans [firebase.json](/Users/rofiegloirehiendamiatadi/StudioProjects/schoolline/firebase.json:1).

```bash
firebase emulators:start --only auth,firestore,functions,storage
```

UI emulateurs :
- `http://127.0.0.1:4000`
- Auth `9099`
- Firestore `8080`
- Functions `5001`
- Storage `9199`

## Deploiement

### Regles Firebase

```bash
firebase deploy --project vdfapp-7c806 --only firestore:rules,storage
```

### Cloud Functions

```bash
cd functions
npm run deploy
```

### Admin web

Construire d'abord en prod :

```bash
cd admin-web
npm run build
```

## Verification minimale avant ouverture

- `flutter analyze`
- `flutter test`
- `cd admin-web && npm run lint`
- `cd admin-web && npm run build`
- `cd functions && npm run build`
- deploiement des regles Firebase
- recette E2E de [docs/GO_LIVE_CHECKLIST.md](/Users/rofiegloirehiendamiatadi/StudioProjects/schoolline/docs/GO_LIVE_CHECKLIST.md:1)
- commandes de build/deploiement de [docs/PRODUCTION_COMMANDS.md](/Users/rofiegloirehiendamiatadi/StudioProjects/schoolline/docs/PRODUCTION_COMMANDS.md:1)

## Points connus

- les mentions legales doivent etre renseignees via `--dart-define` avant une mise en production publique
- la recette push doit etre validee sur vrai appareil iOS et Android
- les tests automatiques couvrent surtout le mobile aujourd'hui ; l'admin web et les functions ont encore besoin de tests dedies
