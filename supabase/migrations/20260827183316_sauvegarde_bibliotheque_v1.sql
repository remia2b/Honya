-- Sauvegarde versionnee de la bibliotheque Honya, liee au compte Supabase.
-- Une seule ligne par utilisateur : les politiques RLS et les RPC ne voient
-- jamais le contenu d'un autre compte. La revision optimiste interdit qu'un
-- second appareil ecrase silencieusement un snapshot plus recent.

create table if not exists public.sauvegardes_bibliotheque (
  user_id uuid primary key references auth.users(id) on delete cascade,
  contenu jsonb not null,
  version smallint not null,
  empreinte text not null,
  revision bigint not null default 1,
  cree_le timestamptz not null default now(),
  modifie_le timestamptz not null default now(),
  constraint sauvegardes_bibliotheque_version_positive
    check (version > 0),
  constraint sauvegardes_bibliotheque_revision_positive
    check (revision > 0),
  constraint sauvegardes_bibliotheque_empreinte_sha256
    check (empreinte ~ '^[0-9a-f]{64}$'),
  constraint sauvegardes_bibliotheque_contenu_objet
    check (jsonb_typeof(contenu) = 'object')
);

alter table public.sauvegardes_bibliotheque enable row level security;

revoke all on table public.sauvegardes_bibliotheque from public;
revoke all on table public.sauvegardes_bibliotheque from anon;
grant select, insert, update, delete
  on table public.sauvegardes_bibliotheque to authenticated;

drop policy if exists "lecture de sa sauvegarde" on public.sauvegardes_bibliotheque;
create policy "lecture de sa sauvegarde"
on public.sauvegardes_bibliotheque
for select
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "creation de sa sauvegarde" on public.sauvegardes_bibliotheque;
create policy "creation de sa sauvegarde"
on public.sauvegardes_bibliotheque
for insert
to authenticated
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "mise a jour de sa sauvegarde" on public.sauvegardes_bibliotheque;
create policy "mise a jour de sa sauvegarde"
on public.sauvegardes_bibliotheque
for update
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id)
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "suppression de sa sauvegarde" on public.sauvegardes_bibliotheque;
create policy "suppression de sa sauvegarde"
on public.sauvegardes_bibliotheque
for delete
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create or replace function public.lire_ma_sauvegarde_bibliotheque()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'contenu', sauvegarde.contenu,
    'version', sauvegarde.version,
    'empreinte', sauvegarde.empreinte,
    'revision', sauvegarde.revision,
    'modifie_le', sauvegarde.modifie_le
  )
  from public.sauvegardes_bibliotheque as sauvegarde
  where sauvegarde.user_id = (select auth.uid());
$$;

revoke all on function public.lire_ma_sauvegarde_bibliotheque() from public;
revoke all on function public.lire_ma_sauvegarde_bibliotheque() from anon;
grant execute on function public.lire_ma_sauvegarde_bibliotheque() to authenticated;

create or replace function public.enregistrer_ma_sauvegarde_bibliotheque(
  p_contenu jsonb,
  p_version integer,
  p_empreinte text,
  p_revision_attendue bigint
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  utilisateur uuid := auth.uid();
  sauvegarde public.sauvegardes_bibliotheque%rowtype;
begin
  if utilisateur is null then
    raise exception 'Authentification requise' using errcode = '28000';
  end if;
  if p_version <> 1 then
    raise exception 'Version de sauvegarde non prise en charge' using errcode = '22023';
  end if;
  if p_contenu is null or jsonb_typeof(p_contenu) <> 'object' then
    raise exception 'Contenu de sauvegarde invalide' using errcode = '22023';
  end if;
  if octet_length(p_contenu::text) > 20000000 then
    raise exception 'Sauvegarde trop volumineuse' using errcode = '22001';
  end if;
  if p_empreinte is null or p_empreinte !~ '^[0-9a-f]{64}$' then
    raise exception 'Empreinte de sauvegarde invalide' using errcode = '22023';
  end if;
  if p_revision_attendue is null or p_revision_attendue < 0 then
    raise exception 'Revision attendue invalide' using errcode = '22023';
  end if;

  select *
  into sauvegarde
  from public.sauvegardes_bibliotheque
  where user_id = utilisateur
  for update;

  if found then
    -- Rejouer le meme upload apres une perte de reponse est idempotent.
    if sauvegarde.empreinte = p_empreinte then
      return jsonb_build_object(
        'contenu', sauvegarde.contenu,
        'version', sauvegarde.version,
        'empreinte', sauvegarde.empreinte,
        'revision', sauvegarde.revision,
        'modifie_le', sauvegarde.modifie_le
      );
    end if;
    if sauvegarde.revision <> p_revision_attendue then
      raise exception 'revision_conflict' using errcode = '40001';
    end if;

    update public.sauvegardes_bibliotheque
    set contenu = p_contenu,
        version = p_version,
        empreinte = p_empreinte,
        revision = revision + 1,
        modifie_le = now()
    where user_id = utilisateur
    returning * into sauvegarde;
  else
    if p_revision_attendue <> 0 then
      raise exception 'revision_conflict' using errcode = '40001';
    end if;

    insert into public.sauvegardes_bibliotheque(
      user_id, contenu, version, empreinte, revision
    ) values (
      utilisateur, p_contenu, p_version, p_empreinte, 1
    )
    returning * into sauvegarde;
  end if;

  return jsonb_build_object(
    'contenu', sauvegarde.contenu,
    'version', sauvegarde.version,
    'empreinte', sauvegarde.empreinte,
    'revision', sauvegarde.revision,
    'modifie_le', sauvegarde.modifie_le
  );
end;
$$;

revoke all on function public.enregistrer_ma_sauvegarde_bibliotheque(
  jsonb, integer, text, bigint
) from public;
revoke all on function public.enregistrer_ma_sauvegarde_bibliotheque(
  jsonb, integer, text, bigint
) from anon;
grant execute on function public.enregistrer_ma_sauvegarde_bibliotheque(
  jsonb, integer, text, bigint
) to authenticated;
