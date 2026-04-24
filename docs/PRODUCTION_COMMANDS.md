# Production Commands

Commandes pretes a l'emploi pour preparer et lancer la production.

## 1. Preparer les fichiers locaux

Depuis la racine :

```bash
cp config/legal.prod.example.json config/legal.prod.json
cp admin-web/.env.example admin-web/.env.local
cp functions/.env.example functions/.env
```

Puis remplir :
- `config/legal.prod.json`
- `admin-web/.env.local`
- `functions/.env`

## 2. Verifier avant build

```bash
flutter test
flutter analyze --no-fatal-infos
cd admin-web && npm run lint && npm run build
cd ../functions && npm run build
```

## 3. Lancer le mobile avec les vraies mentions legales

### Debug avec config prod

```bash
flutter run --dart-define-from-file=config/legal.prod.json
```

### Android release

```bash
flutter build apk --release --dart-define-from-file=config/legal.prod.json
```

### Android App Bundle

```bash
flutter build appbundle --release --dart-define-from-file=config/legal.prod.json
```

### iOS release

```bash
flutter build ios --release --dart-define-from-file=config/legal.prod.json --no-codesign
```

## 4. Deployer les regles Firebase

```bash
firebase use vdfapp-7c806
firebase deploy --only firestore:rules,storage
```

## 5. Deployer les Cloud Functions

```bash
cd functions
npm run build
npm run deploy
```

## 6. Construire le back-office admin

```bash
cd admin-web
npm run build
```

## 7. Deployer le back-office sur Vercel

Avant le premier deploiement :
- connecter soit le repo `admin-web`, soit le repo parent avec `Root Directory = admin-web`
- renseigner dans Vercel les variables de [admin-web/.env.example](/Users/rofiegloirehiendamiatadi/StudioProjects/schoolline/admin-web/.env.example:1)
- regler la version Node.js du projet en `22.x`

Puis :

```bash
cd admin-web
vercel
vercel --prod
```

Si tu utilises plus tard un domaine custom ou des flux Firebase Auth avances, pense aussi a verifier les domaines autorises dans Firebase Auth.

## 8. Recette finale

Executer ensuite la checklist complete :

```bash
open docs/GO_LIVE_CHECKLIST.md
```

Si tu ne veux pas utiliser `open`, suis simplement [docs/GO_LIVE_CHECKLIST.md](/Users/rofiegloirehiendamiatadi/StudioProjects/schoolline/docs/GO_LIVE_CHECKLIST.md:1).
