# Cloud Functions

Fonctions Firebase pour :
- pipeline de soumission OCR / IA
- corrections et affectation des correcteurs
- paiements et validation
- rappels de sessions
- publication des resultats

## Prerequis

- Node.js `22`
- Firebase CLI
- acces au projet Firebase cible

## Variables d'environnement

Copier [functions/.env.example](/Users/rofiegloirehiendamiatadi/StudioProjects/schoolline/functions/.env.example:1) vers `.env`.

Variables attendues :
- `GEMINI_API_KEY`

La region globale est definie dans [src/index.ts](/Users/rofiegloirehiendamiatadi/StudioProjects/schoolline/functions/src/index.ts:1) avec `europe-west1`.

## Commandes

```bash
npm install
npm run build
npm run serve
npm run deploy
```

## Export principal

- soumissions : creation, OCR termine, revue IA, retry
- corrections : assignation, assets, soumission correction
- paiements : soumission preuve, validation
- utilisateurs : creation staff, blocage
- sessions : fermeture automatique, rappels
- resultats : publication individuelle et globale

## Verification avant deploiement

- `npm run build`
- regles Firebase deployees
- `GEMINI_API_KEY` renseignee
- recette paiement -> correction -> publication validee
