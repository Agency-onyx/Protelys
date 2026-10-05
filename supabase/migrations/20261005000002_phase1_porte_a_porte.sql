-- =====================================================================
-- Phase 1 : porte-à-porte
-- Droits par rôle, liaison des comptes, affectation des rues, visites.
-- =====================================================================

-- Date du jour à Paris (Supabase tourne en UTC).
create function fn_aujourdhui() returns date
language sql stable as $$ select (now() at time zone 'Europe/Paris')::date $$;

-- Une adresse e-mail = une personne réelle.
create unique index personnes_email_unique on personnes (lower(email))
  where scenario_id is null and email is not null;

-- ---------------------------------------------------------------------
-- Qui suis-je, quel est mon rôle
-- ---------------------------------------------------------------------
create function moi() returns uuid
language sql stable security definer set search_path = public as $$
  select id from personnes where user_id = auth.uid() and scenario_id is null
$$;

create function a_le_role(r role_personne) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from postes p
    where p.personne_id = moi() and p.role = r
      and p.date_debut <= fn_aujourdhui()
      and (p.date_fin is null or p.date_fin >= fn_aujourdhui()))
$$;

create function est_direction() returns boolean
language sql stable as $$ select a_le_role('associe') or a_le_role('administratif') $$;

-- Un compte Supabase créé avec l'e-mail d'une personne s'y rattache seul.
create function lier_utilisateur() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update personnes set user_id = new.id
   where lower(email) = lower(new.email) and user_id is null and scenario_id is null;
  return new;
end $$;

create trigger lier_utilisateur
  after insert or update of email on auth.users
  for each row execute function lier_utilisateur();

-- ---------------------------------------------------------------------
-- Sécurité : tout est fermé, on ouvre ce que la phase 1 utilise
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table %I enable row level security', t);
  end loop;
end $$;

-- Lecture pour toute l'équipe connectée.
create policy lecture_equipe on personnes            for select to authenticated using (scenario_id is null);
create policy lecture_equipe on postes               for select to authenticated using (true);
create policy lecture_equipe on communes             for select to authenticated using (true);
create policy lecture_equipe on rues                 for select to authenticated using (true);
create policy lecture_equipe on etablissements       for select to authenticated using (true);
create policy lecture_equipe on affectations_prospect for select to authenticated using (true);
create policy lecture_equipe on tournees             for select to authenticated using (true);
create policy lecture_equipe on visites              for select to authenticated using (true);

-- Écriture directe réservée aux associés. Les commerciaux écrivent
-- uniquement par les fonctions ci-dessous, qui contrôlent l'affectation.
create policy direction_ecrit on personnes      for all to authenticated using (est_direction()) with check (est_direction());
create policy direction_ecrit on postes         for all to authenticated using (est_direction()) with check (est_direction());
create policy direction_ecrit on etablissements for all to authenticated using (est_direction()) with check (est_direction());

-- ---------------------------------------------------------------------
-- Affecter une rue à un commercial pour un jour
-- Crée la tournée et affecte toutes les portes encore libres de la rue.
-- Les portes déjà tenues par un autre commercial restent à lui.
-- ---------------------------------------------------------------------
create function affecter_rue(p_rue uuid, p_commercial uuid, p_jour date default null)
returns table (affectees integer, deja_a_lui integer, tenues_par_autre integer)
language plpgsql security definer set search_path = public as $$
declare
  v_jour date := coalesce(p_jour, fn_aujourdhui());
begin
  if not est_direction() then
    raise exception 'Seul un associé peut affecter une rue.';
  end if;
  if not exists (select 1 from postes p where p.personne_id = p_commercial
                   and p.role in ('commercial','associe')
                   and p.date_debut <= v_jour and (p.date_fin is null or p.date_fin >= v_jour)) then
    raise exception 'Cette personne n''est pas commerciale à cette date.';
  end if;

  insert into tournees (jour, commercial_id, rue_id)
  values (v_jour, p_commercial, p_rue)
  on conflict do nothing;

  with portes as (
    select e.id from etablissements e
    where e.rue_id = p_rue and e.actif_sirene and e.priorite <> 'chaine'
  ), tenues as (
    select a.etablissement_id, a.commercial_id from affectations_prospect a
    join portes on portes.id = a.etablissement_id
    where a.au is null or a.au > v_jour
  ), ajout as (
    insert into affectations_prospect (etablissement_id, commercial_id, du)
    select id, p_commercial, v_jour from portes
    where id not in (select etablissement_id from tenues)
    returning 1
  )
  select (select count(*) from ajout)::int,
         (select count(*) from tenues where commercial_id = p_commercial)::int,
         (select count(*) from tenues where commercial_id <> p_commercial)::int
  into affectees, deja_a_lui, tenues_par_autre;
  return next;
end $$;

-- Rendre les portes d'une rue : elles redeviennent libres dès aujourd'hui.
create function liberer_rue(p_rue uuid, p_commercial uuid)
returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not est_direction() then
    raise exception 'Seul un associé peut libérer une rue.';
  end if;
  update affectations_prospect a
     set au = greatest(a.du, fn_aujourdhui())
    from etablissements e
   where e.id = a.etablissement_id and e.rue_id = p_rue
     and a.commercial_id = p_commercial
     and (a.au is null or a.au > fn_aujourdhui());
  get diagnostics n = row_count;
  delete from tournees
   where rue_id = p_rue and commercial_id = p_commercial and jour > fn_aujourdhui();
  return n;
end $$;

-- ---------------------------------------------------------------------
-- Noter une porte en un appui
-- Un second appui dans les 10 minutes corrige le statut au lieu
-- d'ajouter une visite, pour que les erreurs de doigt ne faussent pas
-- les taux de conversion.
-- ---------------------------------------------------------------------
create function noter_visite(p_etablissement uuid, p_statut statut_visite)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_moi     uuid := moi();
  v_rue     uuid;
  v_tournee uuid;
  v_id      uuid;
begin
  if v_moi is null then
    raise exception 'Compte non rattaché à une personne de l''équipe.';
  end if;

  select rue_id into v_rue from etablissements where id = p_etablissement;
  if v_rue is null then
    raise exception 'Établissement introuvable.';
  end if;

  if not est_direction() and not exists (
      select 1 from affectations_prospect a
      where a.etablissement_id = p_etablissement and a.commercial_id = v_moi
        and a.du <= fn_aujourdhui() and (a.au is null or a.au > fn_aujourdhui())) then
    raise exception 'Cette porte n''est pas affectée à toi.';
  end if;

  select id into v_id from visites
   where etablissement_id = p_etablissement and commercial_id = v_moi
     and visite_le > now() - interval '10 minutes'
   order by visite_le desc limit 1;

  if v_id is not null then
    update visites set statut = p_statut where id = v_id;
    return v_id;
  end if;

  select id into v_tournee from tournees
   where jour = fn_aujourdhui() and commercial_id = v_moi and rue_id = v_rue;

  insert into visites (etablissement_id, commercial_id, tournee_id, statut)
  values (p_etablissement, v_moi, v_tournee, p_statut)
  returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- Fermeture des établissements disparus de SIRENE (script d'import)
-- ---------------------------------------------------------------------
create function marquer_etablissements_inactifs(p_code_insee text, p_sirets text[])
returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  update etablissements e set actif_sirene = false, maj_sirene_le = now()
    from rues r
   where r.id = e.rue_id and r.code_insee = p_code_insee
     and e.actif_sirene and not (e.siret = any (p_sirets));
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------------------------------------------------------------------
-- Vue des rues pour l'écran d'affectation
-- ---------------------------------------------------------------------
create view v_rues with (security_invoker = true) as
select r.id, r.code_insee, c.nom as commune, r.nom_voie,
       count(p.id) filter (where p.priorite <> 'chaine' and p.actif_sirene)                    as portes,
       count(p.id) filter (where p.priorite = 'A' and p.actif_sirene)                          as prio_a,
       count(p.id) filter (where p.priorite = 'B' and p.actif_sirene)                          as prio_b,
       count(p.id) filter (where p.priorite = 'C' and p.actif_sirene)                          as prio_c,
       count(p.id) filter (where p.priorite <> 'chaine' and p.actif_sirene
                             and p.commercial_id is null)                                      as libres,
       count(p.id) filter (where p.nb_visites > 0)                                             as visitees,
       count(p.id) filter (where p.est_client)                                                 as clients,
       max(p.derniere_visite_le)                                                               as derniere_visite_le,
       coalesce(array_agg(distinct p.commercial_id) filter (where p.commercial_id is not null),
                '{}')                                                                          as commerciaux
from rues r
join communes c on c.code_insee = r.code_insee
left join v_prospects p on p.rue_id = r.id
group by r.id, c.nom;

-- ---------------------------------------------------------------------
-- Droits d'exécution
-- ---------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon;
grant  execute on function fn_aujourdhui(), fn_debut_mois_courant(), moi(), a_le_role(role_personne),
       est_direction(), affecter_rue(uuid, uuid, date), liberer_rue(uuid, uuid),
       noter_visite(uuid, statut_visite) to authenticated;
grant  execute on function marquer_etablissements_inactifs(text, text[]) to service_role;
