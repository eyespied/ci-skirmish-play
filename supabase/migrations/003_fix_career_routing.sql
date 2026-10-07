-- Fix: ensure only ONE upsert_career_from_round exists, and club rounds
-- never increment player_career_stats (only player_career_stats_skirmish).

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
    execute 'drop function if exists ' || r.sig || ' cascade';
  end loop;
end $$;

create or replace function public.upsert_career_from_round(
  p_match_id uuid,
  p_round_number int,
  p_steam_id text,
  p_display_name text,
  p_team_side text,
  p_class_group text,
  p_score int,
  p_kills int,
  p_deaths int,
  p_assists int,
  p_is_mvp boolean,
  p_is_winner boolean,
  p_first_kill boolean,
  p_first_death boolean,
  p_horse_damage int,
  p_horse_kills int,
  p_kicks int,
  p_couches int,
  p_shots int,
  p_hits int,
  p_headshots int,
  p_teamkills int,
  p_team_hits int,
  p_team_damage int,
  p_melee_damage int,
  p_mounted_damage int,
  p_ranged_damage int,
  p_is_skirmish_club boolean
)
returns boolean
language plpgsql
security definer
as $$
declare
  rows_inserted int := 0;
  class_key text;
  club boolean := coalesce(p_is_skirmish_club, false);
begin
  insert into public.players (steam_id, display_name, updated_at)
  values (p_steam_id, coalesce(p_display_name, ''), now())
  on conflict (steam_id) do update
    set display_name = excluded.display_name,
        updated_at = now();

  if club then
    update public.matches
      set is_skirmish_club = true
      where id = p_match_id and is_skirmish_club = false;
  end if;

  insert into public.round_player_stats (
    match_id, round_number, steam_id, display_name, team_side, class_group,
    score, kills, deaths, assists, is_mvp, is_winner,
    first_kill, first_death, horse_damage, horse_kills, kicks, couches,
    shots, hits, headshots, teamkills, team_hits, team_damage,
    melee_damage, mounted_damage, ranged_damage, is_skirmish_club
  ) values (
    p_match_id, p_round_number, p_steam_id, coalesce(p_display_name, ''),
    coalesce(p_team_side, ''), coalesce(p_class_group, 'Infantry'),
    coalesce(p_score, 0), coalesce(p_kills, 0), coalesce(p_deaths, 0), coalesce(p_assists, 0),
    coalesce(p_is_mvp, false), coalesce(p_is_winner, false),
    coalesce(p_first_kill, false), coalesce(p_first_death, false),
    coalesce(p_horse_damage, 0), coalesce(p_horse_kills, 0),
    coalesce(p_kicks, 0), coalesce(p_couches, 0),
    coalesce(p_shots, 0), coalesce(p_hits, 0), coalesce(p_headshots, 0),
    coalesce(p_teamkills, 0), coalesce(p_team_hits, 0), coalesce(p_team_damage, 0),
    coalesce(p_melee_damage, 0), coalesce(p_mounted_damage, 0), coalesce(p_ranged_damage, 0),
    club
  )
  on conflict (match_id, round_number, steam_id) do nothing;

  get diagnostics rows_inserted = row_count;
  if rows_inserted = 0 then
    return false;
  end if;

  class_key := lower(coalesce(p_class_group, 'infantry'));

  -- Exactly one career table — never both.
  if club then
    insert into public.player_career_stats_skirmish as c (
      steam_id, display_name, rounds_played, rounds_won, total_score,
      total_kills, total_deaths, total_assists, mvp_count,
      first_kills, first_deaths, horse_damage, horse_kills, kicks, couches,
      shots, hits, headshots, teamkills, team_hits, team_damage,
      melee_damage, mounted_damage, ranged_damage,
      rounds_as_infantry, rounds_as_ranged, rounds_as_cavalry, updated_at
    ) values (
      p_steam_id, coalesce(p_display_name, ''), 1,
      case when p_is_winner then 1 else 0 end,
      coalesce(p_score, 0),
      coalesce(p_kills, 0), coalesce(p_deaths, 0), coalesce(p_assists, 0),
      case when p_is_mvp then 1 else 0 end,
      case when p_first_kill then 1 else 0 end,
      case when p_first_death then 1 else 0 end,
      coalesce(p_horse_damage, 0), coalesce(p_horse_kills, 0),
      coalesce(p_kicks, 0), coalesce(p_couches, 0),
      coalesce(p_shots, 0), coalesce(p_hits, 0), coalesce(p_headshots, 0),
      coalesce(p_teamkills, 0), coalesce(p_team_hits, 0), coalesce(p_team_damage, 0),
      coalesce(p_melee_damage, 0), coalesce(p_mounted_damage, 0), coalesce(p_ranged_damage, 0),
      case when class_key = 'infantry' then 1 else 0 end,
      case when class_key = 'ranged' then 1 else 0 end,
      case when class_key in ('cavalry', 'horsearcher') then 1 else 0 end,
      now()
    )
    on conflict (steam_id) do update set
      display_name = excluded.display_name,
      rounds_played = c.rounds_played + 1,
      rounds_won = c.rounds_won + excluded.rounds_won,
      total_score = c.total_score + excluded.total_score,
      total_kills = c.total_kills + excluded.total_kills,
      total_deaths = c.total_deaths + excluded.total_deaths,
      total_assists = c.total_assists + excluded.total_assists,
      mvp_count = c.mvp_count + excluded.mvp_count,
      first_kills = c.first_kills + excluded.first_kills,
      first_deaths = c.first_deaths + excluded.first_deaths,
      horse_damage = c.horse_damage + excluded.horse_damage,
      horse_kills = c.horse_kills + excluded.horse_kills,
      kicks = c.kicks + excluded.kicks,
      couches = c.couches + excluded.couches,
      shots = c.shots + excluded.shots,
      hits = c.hits + excluded.hits,
      headshots = c.headshots + excluded.headshots,
      teamkills = c.teamkills + excluded.teamkills,
      team_hits = c.team_hits + excluded.team_hits,
      team_damage = c.team_damage + excluded.team_damage,
      melee_damage = c.melee_damage + excluded.melee_damage,
      mounted_damage = c.mounted_damage + excluded.mounted_damage,
      ranged_damage = c.ranged_damage + excluded.ranged_damage,
      rounds_as_infantry = c.rounds_as_infantry + excluded.rounds_as_infantry,
      rounds_as_ranged = c.rounds_as_ranged + excluded.rounds_as_ranged,
      rounds_as_cavalry = c.rounds_as_cavalry + excluded.rounds_as_cavalry,
      updated_at = now();
  else
    insert into public.player_career_stats as c (
      steam_id, display_name, rounds_played, rounds_won, total_score,
      total_kills, total_deaths, total_assists, mvp_count,
      first_kills, first_deaths, horse_damage, horse_kills, kicks, couches,
      shots, hits, headshots, teamkills, team_hits, team_damage,
      melee_damage, mounted_damage, ranged_damage,
      rounds_as_infantry, rounds_as_ranged, rounds_as_cavalry, updated_at
    ) values (
      p_steam_id, coalesce(p_display_name, ''), 1,
      case when p_is_winner then 1 else 0 end,
      coalesce(p_score, 0),
      coalesce(p_kills, 0), coalesce(p_deaths, 0), coalesce(p_assists, 0),
      case when p_is_mvp then 1 else 0 end,
      case when p_first_kill then 1 else 0 end,
      case when p_first_death then 1 else 0 end,
      coalesce(p_horse_damage, 0), coalesce(p_horse_kills, 0),
      coalesce(p_kicks, 0), coalesce(p_couches, 0),
      coalesce(p_shots, 0), coalesce(p_hits, 0), coalesce(p_headshots, 0),
      coalesce(p_teamkills, 0), coalesce(p_team_hits, 0), coalesce(p_team_damage, 0),
      coalesce(p_melee_damage, 0), coalesce(p_mounted_damage, 0), coalesce(p_ranged_damage, 0),
      case when class_key = 'infantry' then 1 else 0 end,
      case when class_key = 'ranged' then 1 else 0 end,
      case when class_key in ('cavalry', 'horsearcher') then 1 else 0 end,
      now()
    )
    on conflict (steam_id) do update set
      display_name = excluded.display_name,
      rounds_played = c.rounds_played + 1,
      rounds_won = c.rounds_won + excluded.rounds_won,
      total_score = c.total_score + excluded.total_score,
      total_kills = c.total_kills + excluded.total_kills,
      total_deaths = c.total_deaths + excluded.total_deaths,
      total_assists = c.total_assists + excluded.total_assists,
      mvp_count = c.mvp_count + excluded.mvp_count,
      first_kills = c.first_kills + excluded.first_kills,
      first_deaths = c.first_deaths + excluded.first_deaths,
      horse_damage = c.horse_damage + excluded.horse_damage,
      horse_kills = c.horse_kills + excluded.horse_kills,
      kicks = c.kicks + excluded.kicks,
      couches = c.couches + excluded.couches,
      shots = c.shots + excluded.shots,
      hits = c.hits + excluded.hits,
      headshots = c.headshots + excluded.headshots,
      teamkills = c.teamkills + excluded.teamkills,
      team_hits = c.team_hits + excluded.team_hits,
      team_damage = c.team_damage + excluded.team_damage,
      melee_damage = c.melee_damage + excluded.melee_damage,
      mounted_damage = c.mounted_damage + excluded.mounted_damage,
      ranged_damage = c.ranged_damage + excluded.ranged_damage,
      rounds_as_infantry = c.rounds_as_infantry + excluded.rounds_as_infantry,
      rounds_as_ranged = c.rounds_as_ranged + excluded.rounds_as_ranged,
      rounds_as_cavalry = c.rounds_as_cavalry + excluded.rounds_as_cavalry,
      updated_at = now();
  end if;

  return true;
end;
$$;

grant execute on function public.upsert_career_from_round to service_role;
