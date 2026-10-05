-- =====================================================================
-- Schéma complet : société de dératisation (Paris, Île-de-France)
-- Supabase / Postgres 15. Une seule base, chaque écran en est une vue.
--
-- Règles qui traversent tout le schéma :
--   1. Chaque fait porte sa date. Une période est un filtre.
--   2. Ce qui est signé, facturé ou payé est figé dans la ligne
--      (prix, taille, coût unitaire). Un changement de tarif ne réécrit
--      jamais le passé.
--   3. Réel et prévu vivent côte à côte : salaires / postes,
--      dépenses / charges récurrentes, encaissements / hypothèses.
--      Avant le mois courant on lit le réel, à partir du mois courant on
--      projette. La frontière est calculée (fn_debut_mois_courant).
--   4. Montants en euros, numeric(12,2), HT sauf mention contraire.
-- =====================================================================

create extension if not exists btree_gist;

-- ---------------------------------------------------------------------
-- 0. Types
-- ---------------------------------------------------------------------
create type role_personne      as enum ('associe','commercial','technicien','administratif');
create type priorite_prospect  as enum ('A','B','C','chaine');
create type cote_rue           as enum ('pair','impair');
create type statut_visite      as enum ('absent','ferme','refus','a_rappeler','interesse',
                                        'signe','deja_equipe','hors_cible','introuvable');
create type taille_site        as enum ('petit','moyen','grand');
create type mode_paiement      as enum ('mensuel_sepa','annuel_sepa','annuel_virement');
create type motif_resiliation  as enum ('prix','service','fermeture','concurrent',
                                        'plus_de_besoin','impaye','autre');
create type type_passage       as enum ('contrat','rappel','curatif');
create type statut_passage     as enum ('prevu','fait','reporte','annule','client_absent');
create type statut_mandat      as enum ('en_attente','actif','revoque','expire');
create type type_facture       as enum ('facture','avoir');
create type statut_facture     as enum ('brouillon','emise');
create type type_ligne         as enum ('abonnement','rappel','curatif','remise','autre');
create type statut_prelevement as enum ('cree','on_hold','completed','failed','returned','refunded');
create type type_encaissement  as enum ('prelevement','virement','retour','remboursement');
create type periodicite        as enum ('mensuel','trimestriel','annuel');
create type type_commission    as enum ('signature','reprise');
create type rubrique_resultat  as enum ('achats','services_exterieurs','impots_taxes',
                                        'personnel','financier','exceptionnel');
create type type_alerte        as enum ('manque_technicien','tresorerie_sous_seuil',
                                        'prelevement_echoue','impaye');

-- Premier jour du mois courant, heure de Paris. C'est la frontière
-- réel / prévu. Elle avance seule le 1er de chaque mois.
create function fn_debut_mois_courant() returns date
language sql stable as $$
  select date_trunc('month', now() at time zone 'Europe/Paris')::date
$$;

-- ---------------------------------------------------------------------
-- 1. Scénarios (le scénario de référence est le plan officiel)
-- ---------------------------------------------------------------------
create table scenarios (
  id             uuid primary key default gen_random_uuid(),
  nom            text not null,
  description    text,
  est_reference  boolean not null default false,
  parent_id      uuid references scenarios(id),   -- hérite des hypothèses du parent
  cree_le        timestamptz not null default now()
);
create unique index un_seul_scenario_reference on scenarios (est_reference) where est_reference;

-- ---------------------------------------------------------------------
-- 2. Personnes et effectifs
-- ---------------------------------------------------------------------
create table personnes (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid unique references auth.users(id),
  prenom       text not null,
  nom          text not null,
  email        text,
  telephone    text,
  -- null : personne réelle. Renseigné : poste fictif d'un scénario
  -- (ex. "commercial n°3 embauché en mars").
  scenario_id  uuid references scenarios(id),
  cree_le      timestamptz not null default now()
);

-- Qui est en poste, de quand à quand, à quel coût chargé.
-- Un changement de salaire = on ferme la ligne et on en ouvre une autre.
create table postes (
  id                    uuid primary key default gen_random_uuid(),
  personne_id           uuid not null references personnes(id),
  role                  role_personne not null,
  date_debut            date not null,
  date_fin              date,                       -- null : toujours en poste
  cout_charge_mensuel   numeric(12,2) not null,     -- prévu, sert à projeter
  salaire_brut_mensuel  numeric(12,2),
  temps_travail         numeric(3,2) not null default 1,  -- 1 = temps plein
  check (date_fin is null or date_fin >= date_debut),
  exclude using gist (personne_id with =, role with =,
                      daterange(date_debut, date_fin, '[]') with &&)
);

-- ---------------------------------------------------------------------
-- 3. Territoire
-- ---------------------------------------------------------------------
create table communes (
  code_insee    text primary key,
  nom           text not null,
  code_postal   text,
  departement   text not null,
  importee_le   timestamptz            -- dernier passage du script SIRENE
);

create table rues (
  id          uuid primary key default gen_random_uuid(),
  code_insee  text not null references communes(code_insee),
  nom_voie    text not null,           -- normalisé : "RUE DE PARIS"
  unique (code_insee, nom_voie)
);

-- ---------------------------------------------------------------------
-- 4. Prospection
-- ---------------------------------------------------------------------
-- Alimentée par le script Python (API Recherche d'Entreprises).
-- L'ordre de marche n'est pas stocké : il se lit par rue, côté, numéro.
create table etablissements (
  id                        uuid primary key default gen_random_uuid(),
  siret                     char(14) not null unique,
  siren                     char(9)  not null,
  nom                       text not null,
  enseigne                  text,
  naf                       text not null,
  rue_id                    uuid not null references rues(id),
  numero                    integer,
  indice_repetition         text,      -- bis, ter
  complement_adresse        text,
  code_postal               text,
  cote                      cote_rue generated always as (
                              case when numero is null then null
                                   when numero % 2 = 0 then 'pair'::cote_rue
                                   else 'impair'::cote_rue end) stored,
  priorite                  priorite_prospect not null,
  tranche_effectif          text,
  nb_etablissements_groupe  integer,
  latitude                  numeric(9,6),
  longitude                 numeric(9,6),
  actif_sirene              boolean not null default true,
  importe_le                timestamptz not null default now(),
  maj_sirene_le             timestamptz
);
create index on etablissements (rue_id, cote, numero);

-- Un établissement n'a qu'un commercial à la fois : pas de doublon.
-- 'au' est exclu : une affectation libérée le 5 s'arrête le 4 au soir.
create table affectations_prospect (
  id                uuid primary key default gen_random_uuid(),
  etablissement_id  uuid not null references etablissements(id),
  commercial_id     uuid not null references personnes(id),
  du                date not null default current_date,
  au                date,
  check (au is null or au >= du),
  exclude using gist (etablissement_id with =, daterange(du, au, '[)') with &&)
);

-- La rue du jour d'un commercial.
create table tournees (
  id             uuid primary key default gen_random_uuid(),
  jour           date not null,
  commercial_id  uuid not null references personnes(id),
  rue_id         uuid not null references rues(id),
  unique (jour, commercial_id, rue_id)
);

-- Journal des visites. Le statut actuel d'un prospect = sa dernière visite.
create table visites (
  id                uuid primary key default gen_random_uuid(),
  etablissement_id  uuid not null references etablissements(id),
  commercial_id     uuid not null references personnes(id),
  tournee_id        uuid references tournees(id),
  visite_le         timestamptz not null default now(),
  statut            statut_visite not null,
  rappel_prevu_le   timestamptz,
  note              text
);
create index on visites (etablissement_id, visite_le desc);
create index on visites (commercial_id, visite_le);

-- ---------------------------------------------------------------------
-- 5. Tarifs (versionnés, et propres à un scénario si besoin)
-- ---------------------------------------------------------------------
create table tarifs_abonnement (
  id               uuid primary key default gen_random_uuid(),
  scenario_id      uuid references scenarios(id),   -- null : tarif réel en vigueur
  taille           taille_site not null,
  passages_par_an  smallint not null check (passages_par_an in (1,3,6,12)),
  prix_mensuel_ht  numeric(12,2) not null,
  date_effet       date not null,
  unique nulls not distinct (scenario_id, taille, passages_par_an, date_effet)
);

-- Rappel (149 €), curatif (250 €), remise sur paiement annuel (en %).
create table tarifs_divers (
  id           uuid primary key default gen_random_uuid(),
  scenario_id  uuid references scenarios(id),
  code         text not null check (code in ('rappel_ht','curatif_ht','remise_annuelle_pct')),
  valeur       numeric(12,2) not null,
  date_effet   date not null,
  unique nulls not distinct (scenario_id, code, date_effet)
);

-- ---------------------------------------------------------------------
-- 6. Clients, sites, mandats, contrats
-- ---------------------------------------------------------------------
-- Le client paie. Le site est l'endroit où l'on passe.
-- Un patron avec trois restaurants = un client, trois sites, trois contrats,
-- une facture mensuelle qui les regroupe.
create table clients (
  id                    uuid primary key default gen_random_uuid(),
  raison_sociale        text not null,
  siren                 char(9),
  siret_facturation     char(14),
  tva_intracom          text,
  adresse_facturation   text not null,
  code_postal_facturation text not null,
  ville_facturation     text not null,
  contact_nom           text,
  contact_telephone     text,
  contact_email         text,
  email_facturation     text,
  qonto_client_id       text unique,
  cree_le               timestamptz not null default now()
);

create table sites (
  id                uuid primary key default gen_random_uuid(),
  client_id         uuid not null references clients(id),
  etablissement_id  uuid unique references etablissements(id),  -- lien avec le prospect
  nom               text not null,
  rue_id            uuid references rues(id),
  numero            integer,
  adresse_complete  text not null,
  code_insee        text references communes(code_insee),
  taille            taille_site not null,
  surface_m2        integer,
  consignes_acces   text,
  cree_le           timestamptz not null default now()
);

-- Aucun IBAN ici. Qonto le détient.
create table mandats_sepa (
  id                     uuid primary key default gen_random_uuid(),
  client_id              uuid not null references clients(id),
  qonto_mandate_id       text unique,
  qonto_subscription_id  text unique,
  rum                    text unique,      -- référence unique du mandat
  sign_url               text,
  statut                 statut_mandat not null default 'en_attente',
  signe_le               timestamptz,
  revoque_le             timestamptz,
  cree_le                timestamptz not null default now()
);

-- Un contrat = un site, une formule. Prix, taille et remise figés à la
-- signature. Un changement de formule = nouveau contrat qui remplace l'ancien.
create table contrats (
  id                       uuid primary key default gen_random_uuid(),
  site_id                  uuid not null references sites(id),
  taille                   taille_site not null,
  passages_par_an          smallint not null check (passages_par_an in (1,3,6,12)),
  prix_mensuel_ht          numeric(12,2) not null,
  tarif_id                 uuid references tarifs_abonnement(id),
  mode_paiement            mode_paiement not null,
  remise_annuelle_pct      numeric(5,2) not null default 0,
  mandat_id                uuid references mandats_sepa(id),
  date_signature           date not null,
  date_debut               date not null,
  commercial_id            uuid not null references personnes(id),
  rue_origine_id           uuid references rues(id),       -- figée à la signature
  visite_signature_id      uuid references visites(id),
  signature_horodatage     timestamptz,
  signature_ip             inet,
  signature_image_url      text,
  cgv_version              text,
  date_resiliation         date,
  motif_resiliation        motif_resiliation,
  resiliation_commentaire  text,
  remplace_contrat_id      uuid references contrats(id),
  cree_le                  timestamptz not null default now(),
  check (date_debut >= date_signature),
  check (date_resiliation is null or date_resiliation >= date_debut),
  check ((date_resiliation is null) = (motif_resiliation is null))
);
create index on contrats (commercial_id, date_signature);
create index on contrats (date_debut, date_resiliation);

-- ---------------------------------------------------------------------
-- 7. Exploitation
-- ---------------------------------------------------------------------
create table passages (
  id              uuid primary key default gen_random_uuid(),
  site_id         uuid not null references sites(id),
  contrat_id      uuid references contrats(id),   -- null seulement pour un curatif hors contrat
  type            type_passage not null default 'contrat',
  date_prevue     date not null,
  date_reelle     date,
  technicien_id   uuid references personnes(id),
  statut          statut_passage not null default 'prevu',
  duree_minutes   integer,
  cree_le         timestamptz not null default now(),
  check (type = 'curatif' or contrat_id is not null),
  check (statut <> 'fait' or date_reelle is not null)
);
create index on passages (technicien_id, date_prevue);
create index on passages (date_reelle);

create table rapports_intervention (
  passage_id         uuid primary key references passages(id),
  constat            text,
  niveau_activite    text check (niveau_activite in ('nulle','faible','moyenne','forte')),
  postes_controles   integer,
  postes_consommes   integer,
  actions            text,
  recommandations    text,
  signataire_nom     text,
  signature_url      text,
  photos             text[],
  redige_le          timestamptz not null default now()
);

create table produits (
  id                uuid primary key default gen_random_uuid(),
  nom               text not null,
  categorie         text,           -- appât, piège, gel...
  numero_amm        text,           -- autorisation de mise sur le marché du biocide
  unite             text not null,
  cout_unitaire_ht  numeric(12,4),  -- valeur courante, copiée à la consommation
  actif             boolean not null default true
);

-- Le coût produits d'un passage = somme de ces lignes (pas de saisie double).
create table consommations_produits (
  id                uuid primary key default gen_random_uuid(),
  passage_id        uuid not null references passages(id),
  produit_id        uuid not null references produits(id),
  quantite          numeric(10,3) not null check (quantite > 0),
  cout_unitaire_ht  numeric(12,4) not null
);

-- ---------------------------------------------------------------------
-- 8. Argent entrant : facturé d'un côté, encaissé de l'autre
-- ---------------------------------------------------------------------
-- L'app émet les factures. Numéro attribué à l'émission, sans trou.
-- Une facture émise ne se modifie plus : on la corrige par un avoir.
create table compteurs_factures (
  annee    integer primary key,
  dernier  integer not null default 0
);

create table factures (
  id                  uuid primary key default gen_random_uuid(),
  numero              text unique,              -- null tant que brouillon
  type                type_facture not null default 'facture',
  facture_origine_id  uuid references factures(id),   -- pour un avoir
  client_id           uuid not null references clients(id),
  statut              statut_facture not null default 'brouillon',
  date_emission       date,
  date_echeance       date,
  taux_tva            numeric(5,2) not null default 20,
  total_ht            numeric(12,2),   -- figés à l'émission
  total_tva           numeric(12,2),
  total_ttc           numeric(12,2),
  pdf_url             text,
  cree_le             timestamptz not null default now(),
  check (statut = 'brouillon' or (numero is not null and date_emission is not null)),
  check (type = 'facture' or facture_origine_id is not null)
);
create index on factures (client_id, date_emission);

-- La période de chaque ligne sert à étaler le chiffre d'affaires :
-- une facture annuelle compte 1/12 dans chaque mois du compte de résultat.
create table lignes_facture (
  id                 uuid primary key default gen_random_uuid(),
  facture_id         uuid not null references factures(id) on delete cascade,
  type               type_ligne not null,
  contrat_id         uuid references contrats(id),
  passage_id         uuid references passages(id),
  libelle            text not null,
  periode_debut      date not null,
  periode_fin        date not null,
  quantite           numeric(10,3) not null default 1,
  prix_unitaire_ht   numeric(12,2) not null,
  montant_ht         numeric(12,2) generated always as (round(quantite * prix_unitaire_ht, 2)) stored,
  check (periode_fin >= periode_debut)
);
create index on lignes_facture (contrat_id);
create index on lignes_facture (periode_debut, periode_fin);

-- Journal brut des webhooks Qonto. Clé unique = traitement une seule fois.
create table evenements_qonto (
  id               uuid primary key default gen_random_uuid(),
  qonto_event_id   text not null unique,
  type             text not null,
  payload          jsonb not null,
  recu_le          timestamptz not null default now(),
  traite_le        timestamptz,
  erreur           text
);

-- État courant de chaque prélèvement, mis à jour par les webhooks.
create table prelevements (
  id                     uuid primary key default gen_random_uuid(),
  qonto_direct_debit_id  text unique,
  mandat_id              uuid not null references mandats_sepa(id),
  facture_id             uuid references factures(id),
  montant                numeric(12,2) not null,
  date_prevue            date not null,
  statut                 statut_prelevement not null default 'cree',
  status_reason          text,
  maj_le                 timestamptz not null default now()
);

-- Le grand livre de l'argent réellement reçu. Une ligne par mouvement :
-- +montant quand completed, -montant quand returned ou refunded.
-- C'est la seule source de l'encaissement réel.
create table encaissements (
  id                  uuid primary key default gen_random_uuid(),
  client_id           uuid not null references clients(id),
  facture_id          uuid references factures(id),
  prelevement_id      uuid references prelevements(id),
  evenement_qonto_id  uuid unique references evenements_qonto(id),
  type                type_encaissement not null,
  montant_ttc         numeric(12,2) not null,
  date_valeur         date not null,
  cree_le             timestamptz not null default now()
);
create index on encaissements (date_valeur);
create index on encaissements (facture_id);

-- ---------------------------------------------------------------------
-- 9. Argent sortant
-- ---------------------------------------------------------------------
create table categories_charges (
  code      text primary key,
  libelle   text not null,
  rubrique  rubrique_resultat not null
);

-- Prévu : loyer, assurance, véhicule, logiciels, comptable...
create table charges_recurrentes (
  id              uuid primary key default gen_random_uuid(),
  scenario_id     uuid references scenarios(id),   -- null : charge réelle engagée
  libelle         text not null,
  categorie_code  text not null references categories_charges(code),
  montant_ht      numeric(12,2) not null,
  taux_tva        numeric(5,2) not null default 20,
  periodicite     periodicite not null,
  date_debut      date not null,
  date_fin        date
);

-- Réel : chaque sortie d'argent, récurrente ou ponctuelle.
create table depenses (
  id                    uuid primary key default gen_random_uuid(),
  date_depense          date not null,          -- date de la charge (compte de résultat)
  paye_le               date,                   -- date de sortie de trésorerie
  libelle               text not null,
  categorie_code        text not null references categories_charges(code),
  fournisseur           text,
  montant_ht            numeric(12,2) not null,
  montant_tva           numeric(12,2) not null default 0,
  charge_recurrente_id  uuid references charges_recurrentes(id),
  justificatif_url      text,
  cree_le               timestamptz not null default now()
);
create index on depenses (date_depense);

-- Réel : la paie de chaque mois.
create table salaires (
  id                   uuid primary key default gen_random_uuid(),
  personne_id          uuid not null references personnes(id),
  mois                 date not null check (extract(day from mois) = 1),
  salaire_brut         numeric(12,2) not null,
  salaire_net          numeric(12,2),
  charges_patronales   numeric(12,2) not null,
  cout_total           numeric(12,2) generated always as (salaire_brut + charges_patronales) stored,
  paye_le              date,
  unique (personne_id, mois)
);

-- Règle de commission, versionnée.
create table regles_commission (
  id                    uuid primary key default gen_random_uuid(),
  scenario_id           uuid references scenarios(id),
  montant_fixe          numeric(12,2) not null default 0,   -- par signature
  multiple_prix_mensuel numeric(5,2) not null default 0,    -- ex. 1 = un mois d'abonnement
  delai_reprise_mois    integer not null default 0,         -- reprise si résilié avant N mois
  date_effet            date not null,
  unique nulls not distinct (scenario_id, date_effet)
);

-- Calculées par une fonction depuis les contrats signés. Jamais saisies.
create table commissions (
  id              uuid primary key default gen_random_uuid(),
  personne_id     uuid not null references personnes(id),
  contrat_id      uuid not null references contrats(id),
  regle_id        uuid not null references regles_commission(id),
  type            type_commission not null,
  mois            date not null check (extract(day from mois) = 1),
  montant         numeric(12,2) not null,      -- négatif pour une reprise
  calcule_le      timestamptz not null default now(),
  unique (contrat_id, type)
);

-- Solde bancaire relevé chaque jour sur Qonto par une fonction planifiée.
create table soldes_bancaires (
  date_solde  date primary key,
  solde       numeric(12,2) not null,
  releve_le   timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 10. Hypothèses et prévisions
-- ---------------------------------------------------------------------
create table catalogue_hypotheses (
  cle          text primary key,
  libelle      text not null,
  unite        text not null,
  description  text
);

insert into catalogue_hypotheses (cle, libelle, unite) values
  ('portes_par_jour',              'Portes visitées par jour et par commercial', 'portes'),
  ('jours_terrain_par_mois',       'Jours de terrain par commercial',            'jours'),
  ('taux_transformation',          'Signatures / portes visitées',               '%'),
  ('signatures_par_mois',          'Rythme de signature (si fixé directement)',  'contrats'),
  ('mix_formule',                  'Part des signatures par taille et formule',  '%'),
  ('taux_resiliation_mensuel',     'Contrats résiliés chaque mois',              '%'),
  ('part_paiement_annuel',         'Part des clients qui paient à l''année',     '%'),
  ('part_curatif',                 'Curatifs vendus / contrats actifs par mois', '%'),
  ('part_rappel',                  'Rappels facturés / contrats actifs par mois','%'),
  ('capacite_passages_technicien', 'Passages par technicien et par mois',        'passages'),
  ('cout_produits_passage',        'Coût produits moyen d''un passage',          '€'),
  ('taux_echec_prelevement',       'Prélèvements en échec',                      '%'),
  ('delai_encaissement_jours',     'Délai entre facture et encaissement',        'jours'),
  ('taux_charges_patronales',      'Charges patronales / brut',                  '%');

-- Deux dates par ligne :
--   date_effet : à partir de quel mois la valeur s'applique ;
--   cree_le    : quand la décision a été prise.
-- On peut ainsi relire "ce qu'on croyait au 1er mars" sans rien écraser.
-- Un scénario lit ses propres lignes, puis celles de son parent,
-- puis celles du scénario de référence.
create table hypotheses (
  id             uuid primary key default gen_random_uuid(),
  scenario_id    uuid not null references scenarios(id),
  cle            text not null references catalogue_hypotheses(cle),
  commercial_id  uuid references personnes(id),   -- valeur propre à un commercial
  dimension      text,                            -- ex. 'petit_3' pour mix_formule
  valeur         numeric(14,4) not null,
  date_effet     date not null,
  cree_le        timestamptz not null default now(),
  cree_par       uuid references personnes(id),
  commentaire    text
);
create index on hypotheses (scenario_id, cle, date_effet);

-- Photo de la prévision, prise le 1er de chaque mois par une fonction
-- planifiée. Sert à l'écart prévu / réel, mois par mois.
create table previsions_figees (
  id           uuid primary key default gen_random_uuid(),
  scenario_id  uuid not null references scenarios(id),
  fige_le      date not null,
  mois         date not null check (extract(day from mois) = 1),
  indicateur   text not null,    -- ca_ht, encaissements, signatures, resiliations, tresorerie...
  valeur       numeric(14,2) not null,
  unique (scenario_id, fige_le, mois, indicateur)
);

-- ---------------------------------------------------------------------
-- 11. Réglages et alertes
-- ---------------------------------------------------------------------
-- Identité de la société (mentions de facture, ICS), seuil de trésorerie...
create table parametres (
  cle         text not null,
  valeur      text not null,
  date_effet  date not null default current_date,
  primary key (cle, date_effet)
);

create table alertes (
  id           uuid primary key default gen_random_uuid(),
  type         type_alerte not null,
  mois         date,
  objet_table  text,
  objet_id     uuid,
  message      text not null,
  cree_le      timestamptz not null default now(),
  resolue_le   timestamptz,
  unique nulls not distinct (type, objet_id, mois)
);

-- ---------------------------------------------------------------------
-- 12. Vues de base (preuve que le modèle tient ; le pilotage s'appuie dessus)
-- ---------------------------------------------------------------------

-- Calendrier : 36 mois en arrière, 24 en avant, et la frontière réel / prévu.
create view v_mois with (security_invoker = true) as
select m::date as mois,
       (m::date < fn_debut_mois_courant()) as est_clos
from generate_series(fn_debut_mois_courant() - interval '36 months',
                     fn_debut_mois_courant() + interval '24 months',
                     interval '1 month') as m;

-- Statut actuel de chaque prospect et son commercial du moment.
create view v_prospects with (security_invoker = true) as
select e.*,
       r.nom_voie, r.code_insee,
       -- Ordre de marche : on monte côté impair, on redescend côté pair,
       -- les adresses sans numéro en fin de rue.
       case e.cote when 'impair' then 0 when 'pair' then 1 else 2 end as ordre_cote,
       case when e.cote = 'pair' then -e.numero else e.numero end    as ordre_numero,
       a.commercial_id,
       dv.statut     as dernier_statut,
       dv.visite_le  as derniere_visite_le,
       (select count(*) from visites v where v.etablissement_id = e.id) as nb_visites,
       exists (select 1 from sites s join contrats c on c.site_id = s.id
               where s.etablissement_id = e.id and c.date_resiliation is null) as est_client
from etablissements e
join rues r on r.id = e.rue_id
left join affectations_prospect a
       on a.etablissement_id = e.id
      and a.du <= current_date and (a.au is null or a.au > current_date)
left join lateral (select statut, visite_le from visites v
                   where v.etablissement_id = e.id
                   order by visite_le desc limit 1) dv on true;

-- Contrats actifs à chaque mois (actif = commencé avant la fin du mois,
-- pas résilié avant son début).
create view v_contrats_par_mois with (security_invoker = true) as
select m.mois, c.*
from v_mois m
join contrats c
  on c.date_debut < (m.mois + interval '1 month')
 and (c.date_resiliation is null or c.date_resiliation >= m.mois)
where m.est_clos or m.mois = fn_debut_mois_courant();

-- Chiffre d'affaires reconnu par mois, étalé au prorata des jours de la
-- période de chaque ligne. Une facture annuelle se répartit sur 12 mois.
create view v_ca_reconnu_mois with (security_invoker = true) as
select m.mois,
       l.type,
       f.client_id,
       l.contrat_id,
       sum( l.montant_ht * (case when f.type = 'avoir' then -1 else 1 end)
            * ( greatest(0, least(l.periode_fin, (m.mois + interval '1 month - 1 day')::date)
                           - greatest(l.periode_debut, m.mois) + 1) )::numeric
            / (l.periode_fin - l.periode_debut + 1) ) as ca_ht
from lignes_facture l
join factures f on f.id = l.facture_id and f.statut = 'emise'
join v_mois m on m.mois <= l.periode_fin
             and (m.mois + interval '1 month - 1 day')::date >= l.periode_debut
group by m.mois, l.type, f.client_id, l.contrat_id;

-- Encaissé réel par mois.
create view v_encaissements_mois with (security_invoker = true) as
select date_trunc('month', date_valeur)::date as mois,
       sum(montant_ttc) as encaisse_ttc
from encaissements
group by 1;

-- Reste dû par facture et impayés.
create view v_soldes_factures with (security_invoker = true) as
select f.id, f.numero, f.client_id, f.date_echeance, f.total_ttc,
       coalesce(sum(e.montant_ttc), 0) as encaisse_ttc,
       f.total_ttc - coalesce(sum(e.montant_ttc), 0) as reste_du_ttc,
       (f.date_echeance < current_date
        and f.total_ttc - coalesce(sum(e.montant_ttc), 0) > 0) as est_impayee
from factures f
left join encaissements e on e.facture_id = f.id
where f.statut = 'emise' and f.type = 'facture'
group by f.id;

-- Coût produits de chaque passage.
create view v_cout_passages with (security_invoker = true) as
select p.*,
       coalesce(sum(cp.quantite * cp.cout_unitaire_ht), 0) as cout_produits_ht
from passages p
left join consommations_produits cp on cp.passage_id = p.id
group by p.id;

-- Effectif par mois et par rôle, avec coût chargé prévu.
create view v_effectifs_mois with (security_invoker = true) as
select m.mois, p.role, p.personne_id, pe.scenario_id,
       p.cout_charge_mensuel * p.temps_travail as cout_charge_prevu
from v_mois m
join postes p on p.date_debut < (m.mois + interval '1 month')
             and (p.date_fin is null or p.date_fin >= m.mois)
join personnes pe on pe.id = p.personne_id;

-- Vues prévues pour la phase 4, toutes construites sur les tables ci-dessus :
--   v_compte_resultat      (réel : ca reconnu, salaires, commissions, depenses)
--   v_tresorerie           (soldes_bancaires + flux prévus 12 mois, point bas, mois restants)
--   fn_projeter(scenario, mois_debut, nb_mois)   (mois futurs depuis les hypothèses)
--   v_economie_unitaire    (coût d'acquisition, marge 12 mois, mois de retour, marge par formule)
--   v_perf_commerciaux     (portes, transformation, coût par signature, récurrent apporté)
--   v_rentabilite_rues     (visites, signatures, récurrent, résiliations par rue et commune)
--   v_ecart_prevu_reel     (previsions_figees face au réel)
