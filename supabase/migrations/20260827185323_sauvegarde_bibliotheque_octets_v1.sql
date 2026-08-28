-- Conserve les octets canoniques exacts du snapshot en Base64.
-- JSONB reordonne les cles et normalise certains nombres : le document reste
-- semantiquement identique, mais son SHA-256 ne peut alors plus prouver les
-- octets envoyes. Cette migration intervient avant toute sauvegarde cliente.

drop function if exists public.enregistrer_ma_sauvegarde_bibliotheque(
  jsonb, integer, text, bigint
);
drop function if exists public.lire_ma_sauvegarde_bibliotheque();

alter table public.sauvegardes_bibliotheque
  drop constraint if exists sauvegardes_bibliotheque_contenu_objet;

alter table public.sauvegardes_bibliotheque
  alter column contenu type text
  using encode(convert_to(contenu::text, 'UTF8'), 'base64');

alter table public.sauvegardes_bibliotheque
  add constraint sauvegardes_bibliotheque_contenu_base64
  check (
    length(contenu) > 0
    and length(contenu) <= 26666668
    and length(contenu) % 4 = 0
    and contenu ~ '^[A-Za-z0-9+/]*={0,2}$'
    and octet_length(decode(contenu, 'base64')) <= 20000000
  );

create or replace function public.lire_ma_sauvegarde_bibliotheque()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'contenu_base64', sauvegarde.contenu,
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
  p_contenu text,
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
  if p_contenu is null
     or length(p_contenu) = 0
     or length(p_contenu) > 26666668
     or length(p_contenu) % 4 <> 0
     or p_contenu !~ '^[A-Za-z0-9+/]*={0,2}$'
     or octet_length(decode(p_contenu, 'base64')) > 20000000 then
    raise exception 'Contenu de sauvegarde invalide' using errcode = '22023';
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
    if sauvegarde.empreinte = p_empreinte then
      return jsonb_build_object(
        'contenu_base64', sauvegarde.contenu,
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
    'contenu_base64', sauvegarde.contenu,
    'version', sauvegarde.version,
    'empreinte', sauvegarde.empreinte,
    'revision', sauvegarde.revision,
    'modifie_le', sauvegarde.modifie_le
  );
end;
$$;

revoke all on function public.enregistrer_ma_sauvegarde_bibliotheque(
  text, integer, text, bigint
) from public;
revoke all on function public.enregistrer_ma_sauvegarde_bibliotheque(
  text, integer, text, bigint
) from anon;
grant execute on function public.enregistrer_ma_sauvegarde_bibliotheque(
  text, integer, text, bigint
) to authenticated;
