-- À exécuter une seule fois dans l'éditeur SQL de Supabase, après les
-- deux migrations. Remplace les e-mails et les noms par ceux des associés.
-- Chaque associé se connecte ensuite avec son e-mail et reçoit un code.
with a as (
  insert into personnes (prenom, nom, email) values
    ('Prénom1', 'Nom1', 'associe1@exemple.fr'),
    ('Prénom2', 'Nom2', 'associe2@exemple.fr')
  returning id
)
insert into postes (personne_id, role, date_debut, cout_charge_mensuel)
select id, 'associe', current_date, 0 from a;
