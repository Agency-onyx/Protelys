# Terrain

Outil interne : prospection en porte-à-porte, contrats, exploitation, pilotage.
Next.js sur Vercel, Supabase (base, connexion, fonctions planifiées), Tailwind.

## Où en est-on

Phase 1 (porte-à-porte) : faite.

- `/terrain` : la rue du jour dans l'ordre de marche (impairs en montant, pairs au retour), un statut par porte en un appui. Un second appui dans les 10 minutes corrige au lieu d'ajouter une visite.
- `/affectation` : un associé affecte une rue à un commercial pour un jour. Les portes déjà tenues par un autre commercial ne sont pas reprises.
- `/equipe` : un associé ajoute une personne, son rôle et son coût chargé. Elle peut alors se connecter.

## Base

- `supabase/migrations/…_schema.sql` : le schéma complet, toutes phases.
- `supabase/migrations/…_phase1_porte_a_porte.sql` : droits par rôle, liaison des comptes, fonctions de la phase 1.
- `supabase/equipe-initiale.sql` : crée les deux associés, à lancer une fois.

## Importer une commune

```
python3 scripts/import_sirene.py 93048          # Montreuil
python3 scripts/import_sirene.py 93048 -n       # simulation, rien n'est écrit
```

Lit `SUPABASE_URL` et `SUPABASE_SERVICE_ROLE_KEY` dans `.env.local`. Relancer l'import met à jour les fiches et marque comme fermés les établissements disparus de SIRENE.

## Lancer en local

```
cp .env.example .env.local   # puis remplir les clés
npm install
npm run dev
```
