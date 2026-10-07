-- Lock down upsert_career_from_round: Postgres grants EXECUTE to PUBLIC by
-- default, and this function is SECURITY DEFINER (bypasses RLS).
-- Only the dedicated-server service_role key should be able to write stats.
-- Safe to re-run.

do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'upsert_career_from_round'
  loop
    execute 'revoke all on function ' || r.sig || ' from public';
    execute 'revoke all on function ' || r.sig || ' from anon';
    execute 'revoke all on function ' || r.sig || ' from authenticated';
    execute 'grant execute on function ' || r.sig || ' to service_role';
    execute 'alter function ' || r.sig || ' set search_path = public';
  end loop;
end $$;
