-- Migration déployée sur le projet Supabase Honya le 27 août 2026.
-- Rend la suppression de compte vérifiable après une perte de réseau.
--
-- Le reçu ne contient ni user_id, ni e-mail, ni autre donnée personnelle :
-- seulement une clé UUID aléatoire choisie par l'app. Le reçu et la
-- suppression de auth.users sont validés dans LA MÊME transaction.
-- Il n'expire pas automatiquement : après une longue absence, il demeure la
-- seule preuve que le compte a bien été supprimé et évite un blocage local.

create table if not exists public.suppressions_compte_confirmees (
  cle uuid primary key,
  confirme_le timestamptz not null default now()
);

alter table public.suppressions_compte_confirmees enable row level security;
revoke all on table public.suppressions_compte_confirmees from public;
revoke all on table public.suppressions_compte_confirmees from anon;
revoke all on table public.suppressions_compte_confirmees from authenticated;

-- Remplace l'ancienne signature sans argument créée par la migration initiale.
drop function if exists public.supprimer_mon_compte();

create or replace function public.supprimer_mon_compte(p_cle uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  utilisateur uuid := auth.uid();
begin
  if utilisateur is null then
    raise exception 'Authentification requise';
  end if;
  if p_cle is null then
    raise exception 'Clé de suppression requise';
  end if;

  insert into public.suppressions_compte_confirmees(cle)
  values (p_cle)
  on conflict (cle) do nothing;

  delete from auth.users where id = utilisateur;
  if not found then
    raise exception 'Compte introuvable';
  end if;
end;
$$;

revoke all on function public.supprimer_mon_compte(uuid) from public;
revoke all on function public.supprimer_mon_compte(uuid) from anon;
grant execute on function public.supprimer_mon_compte(uuid) to authenticated;

create or replace function public.suppression_compte_confirmee(p_cle uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.suppressions_compte_confirmees
    where cle = p_cle
  );
$$;

revoke all on function public.suppression_compte_confirmee(uuid) from public;
grant execute on function public.suppression_compte_confirmee(uuid) to anon;
grant execute on function public.suppression_compte_confirmee(uuid) to authenticated;

-- Cette fonction appartient au mécanisme interne qui active automatiquement
-- RLS après un CREATE TABLE. Elle doit rester utilisable par l'event trigger,
-- jamais être exposée comme RPC aux clients de l'application.
revoke all on function public.rls_auto_enable() from public;
revoke all on function public.rls_auto_enable() from anon;
revoke all on function public.rls_auto_enable() from authenticated;
