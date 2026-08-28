-- La v2 conserve le statut et les dates de chaque tome. Les clients v2
-- peuvent encore lire et promouvoir une sauvegarde v1, tandis qu'un ancien
-- client ne peut jamais faire regresser une ligne deja passee en v2.

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
  if p_version not between 1 and 2 then
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
    -- Barriere anti-regression : une ancienne beta peut continuer a ecrire
    -- tant que sa ligne est en v1, mais ne peut plus amputer une sauvegarde v2.
    if sauvegarde.version > p_version then
      raise exception 'Regression de version de sauvegarde interdite'
        using errcode = '22023';
    end if;
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
