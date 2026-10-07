-- Combat detail stats: kill/death type split, throwing bucket, lifespan,
-- friendly-fire received, culture win rates, headshot rate.
-- Apply after 003_fix_career_routing.sql
--
-- Meaning change going forward:
--   shots / hits / headshots / ranged_damage = bow & crossbow only
--   throwing_* = javelins / throwing axes / knives / stones
--   mounted_ranged_damage / mounted_throwing_damage are split out of ranged
-- Historical rows keep their old lumped values; new generated rates still work
-- on whatever is stored.

-- ---------------------------------------------------------------------------
-- round_player_stats
-- ---------------------------------------------------------------------------
alter table public.round_player_stats
  add column if not exists culture_id text not null default '',
  add column if not exists kills_melee int not null default 0,
  add column if not exists kills_ranged int not null default 0,
  add column if not exists kills_throwing int not null default 0,
  add column if not exists kills_mounted_melee int not null default 0,
  add column if not exists kills_mounted_ranged int not null default 0,
  add column if not exists kills_mounted_throwing int not null default 0,
  add column if not exists deaths_melee int not null default 0,
  add column if not exists deaths_ranged int not null default 0,
  add column if not exists deaths_throwing int not null default 0,
  add column if not exists deaths_mounted_melee int not null default 0,
  add column if not exists deaths_mounted_ranged int not null default 0,
  add column if not exists deaths_mounted_throwing int not null default 0,
  add column if not exists suicides int not null default 0,
  add column if not exists throwing_damage int not null default 0,
  add column if not exists mounted_ranged_damage int not null default 0,
  add column if not exists mounted_throwing_damage int not null default 0,
  add column if not exists throwing_shots int not null default 0,
  add column if not exists throwing_hits int not null default 0,
  add column if not exists throwing_headshots int not null default 0,
  add column if not exists team_hits_received int not null default 0,
  add column if not exists team_damage_received int not null default 0,
  add column if not exists deaths_by_teammate int not null default 0,
  add column if not exists alive_ms int not null default 0,
  add column if not exists spawn_count int not null default 0;

alter table public.round_player_stats
  add column if not exists headshot_pct numeric generated always as (
    case when hits > 0 then round((headshots::numeric / hits::numeric) * 100, 2) else 0 end
  ) stored,
  add column if not exists throwing_hit_pct numeric generated always as (
    case when throwing_shots > 0 then round((throwing_hits::numeric / throwing_shots::numeric) * 100, 2) else 0 end
  ) stored,
  add column if not exists throwing_headshot_pct numeric generated always as (
    case when throwing_hits > 0 then round((throwing_headshots::numeric / throwing_hits::numeric) * 100, 2) else 0 end
  ) stored,
  add column if not exists avg_lifespan_seconds numeric generated always as (
    case when spawn_count > 0 then round((alive_ms::numeric / 1000.0) / spawn_count, 2) else 0 end
  ) stored;

create index if not exists idx_round_player_stats_culture
  on public.round_player_stats (culture_id);

-- ---------------------------------------------------------------------------
-- career tables (same combat columns; alive_ms is bigint)
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
  col text;
  data_cols text[] := ARRAY[
    'kills_melee int not null default 0',
    'kills_ranged int not null default 0',
    'kills_throwing int not null default 0',
    'kills_mounted_melee int not null default 0',
    'kills_mounted_ranged int not null default 0',
    'kills_mounted_throwing int not null default 0',
    'deaths_melee int not null default 0',
    'deaths_ranged int not null default 0',
    'deaths_throwing int not null default 0',
    'deaths_mounted_melee int not null default 0',
    'deaths_mounted_ranged int not null default 0',
    'deaths_mounted_throwing int not null default 0',
    'suicides int not null default 0',
    'throwing_damage bigint not null default 0',
    'mounted_ranged_damage bigint not null default 0',
    'mounted_throwing_damage bigint not null default 0',
    'throwing_shots int not null default 0',
    'throwing_hits int not null default 0',
    'throwing_headshots int not null default 0',
    'team_hits_received int not null default 0',
    'team_damage_received bigint not null default 0',
    'deaths_by_teammate int not null default 0',
    'alive_ms bigint not null default 0',
    'spawn_count int not null default 0'
  ];
begin
  foreach t in array ARRAY['player_career_stats', 'player_career_stats_skirmish'] loop
    foreach col in array data_cols loop
      execute format('alter table public.%I add column if not exists %s', t, col);
    end loop;

    execute format($f$
      alter table public.%I
        add column if not exists headshot_pct numeric generated always as (
          case when hits > 0 then round((headshots::numeric / hits::numeric) * 100, 2) else 0 end
        ) stored
    $f$, t);

    execute format($f$
      alter table public.%I
        add column if not exists throwing_hit_pct numeric generated always as (
          case when throwing_shots > 0 then round((throwing_hits::numeric / throwing_shots::numeric) * 100, 2) else 0 end
        ) stored
    $f$, t);

    execute format($f$
      alter table public.%I
        add column if not exists throwing_headshot_pct numeric generated always as (
          case when throwing_hits > 0 then round((throwing_headshots::numeric / throwing_hits::numeric) * 100, 2) else 0 end
        ) stored
    $f$, t);

    execute format($f$
      alter table public.%I
        add column if not exists avg_lifespan_seconds numeric generated always as (
          case when spawn_count > 0 then round((alive_ms::numeric / 1000.0) / spawn_count, 2) else 0 end
        ) stored
    $f$, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- per-culture win rates (normal vs skirmish club)
-- ---------------------------------------------------------------------------
create table if not exists public.player_culture_stats (
  steam_id text not null references public.players (steam_id) on delete cascade,
  culture_id text not null,
  is_skirmish_club boolean not null default false,
  rounds_played int not null default 0,
  rounds_won int not null default 0,
  updated_at timestamptz not null default now(),
  win_rate numeric generated always as (
    case when rounds_played > 0 then round((rounds_won::numeric / rounds_played::numeric) * 100, 2) else 0 end
  ) stored,
  primary key (steam_id, culture_id, is_skirmish_club)
);

create index if not exists idx_player_culture_stats_steam
  on public.player_culture_stats (steam_id);

alter table public.player_culture_stats enable row level security;

drop policy if exists player_culture_stats_public_read on public.player_culture_stats;
create policy player_culture_stats_public_read
  on public.player_culture_stats for select to anon using (true);

-- ---------------------------------------------------------------------------
-- Replace RPC (drop every overload, then recreate)
-- ---------------------------------------------------------------------------
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
  p_is_skirmish_club boolean default false,
  p_culture_id text default '',
  p_kills_melee int default 0,
  p_kills_ranged int default 0,
  p_kills_throwing int default 0,
  p_kills_mounted_melee int default 0,
  p_kills_mounted_ranged int default 0,
  p_kills_mounted_throwing int default 0,
  p_deaths_melee int default 0,
  p_deaths_ranged int default 0,
  p_deaths_throwing int default 0,
  p_deaths_mounted_melee int default 0,
  p_deaths_mounted_ranged int default 0,
  p_deaths_mounted_throwing int default 0,
  p_suicides int default 0,
  p_throwing_damage int default 0,
  p_mounted_ranged_damage int default 0,
  p_mounted_throwing_damage int default 0,
  p_throwing_shots int default 0,
  p_throwing_hits int default 0,
  p_throwing_headshots int default 0,
  p_team_hits_received int default 0,
  p_team_damage_received int default 0,
  p_deaths_by_teammate int default 0,
  p_alive_ms int default 0,
  p_spawn_count int default 0
)
returns boolean
language plpgsql
security definer
as $$
declare
  rows_inserted int := 0;
  class_key text;
  club boolean := coalesce(p_is_skirmish_club, false);
  culture_key text := coalesce(p_culture_id, '');
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
    match_id, round_number, steam_id, display_name, team_side, class_group, culture_id,
    score, kills, deaths, assists, is_mvp, is_winner,
    first_kill, first_death, horse_damage, horse_kills, kicks, couches,
    shots, hits, headshots, teamkills, team_hits, team_damage,
    melee_damage, mounted_damage, ranged_damage, is_skirmish_club,
    kills_melee, kills_ranged, kills_throwing,
    kills_mounted_melee, kills_mounted_ranged, kills_mounted_throwing,
    deaths_melee, deaths_ranged, deaths_throwing,
    deaths_mounted_melee, deaths_mounted_ranged, deaths_mounted_throwing,
    suicides, throwing_damage, mounted_ranged_damage, mounted_throwing_damage,
    throwing_shots, throwing_hits, throwing_headshots,
    team_hits_received, team_damage_received, deaths_by_teammate,
    alive_ms, spawn_count
  ) values (
    p_match_id, p_round_number, p_steam_id, coalesce(p_display_name, ''),
    coalesce(p_team_side, ''), coalesce(p_class_group, 'Infantry'), culture_key,
    coalesce(p_score, 0), coalesce(p_kills, 0), coalesce(p_deaths, 0), coalesce(p_assists, 0),
    coalesce(p_is_mvp, false), coalesce(p_is_winner, false),
    coalesce(p_first_kill, false), coalesce(p_first_death, false),
    coalesce(p_horse_damage, 0), coalesce(p_horse_kills, 0),
    coalesce(p_kicks, 0), coalesce(p_couches, 0),
    coalesce(p_shots, 0), coalesce(p_hits, 0), coalesce(p_headshots, 0),
    coalesce(p_teamkills, 0), coalesce(p_team_hits, 0), coalesce(p_team_damage, 0),
    coalesce(p_melee_damage, 0), coalesce(p_mounted_damage, 0), coalesce(p_ranged_damage, 0),
    club,
    coalesce(p_kills_melee, 0), coalesce(p_kills_ranged, 0), coalesce(p_kills_throwing, 0),
    coalesce(p_kills_mounted_melee, 0), coalesce(p_kills_mounted_ranged, 0), coalesce(p_kills_mounted_throwing, 0),
    coalesce(p_deaths_melee, 0), coalesce(p_deaths_ranged, 0), coalesce(p_deaths_throwing, 0),
    coalesce(p_deaths_mounted_melee, 0), coalesce(p_deaths_mounted_ranged, 0), coalesce(p_deaths_mounted_throwing, 0),
    coalesce(p_suicides, 0),
    coalesce(p_throwing_damage, 0), coalesce(p_mounted_ranged_damage, 0), coalesce(p_mounted_throwing_damage, 0),
    coalesce(p_throwing_shots, 0), coalesce(p_throwing_hits, 0), coalesce(p_throwing_headshots, 0),
    coalesce(p_team_hits_received, 0), coalesce(p_team_damage_received, 0), coalesce(p_deaths_by_teammate, 0),
    coalesce(p_alive_ms, 0), coalesce(p_spawn_count, 0)
  )
  on conflict (match_id, round_number, steam_id) do nothing;

  get diagnostics rows_inserted = row_count;
  if rows_inserted = 0 then
    return false;
  end if;

  class_key := lower(coalesce(p_class_group, 'infantry'));

  if club then
    insert into public.player_career_stats_skirmish as c (
      steam_id, display_name, rounds_played, rounds_won, total_score,
      total_kills, total_deaths, total_assists, mvp_count,
      first_kills, first_deaths, horse_damage, horse_kills, kicks, couches,
      shots, hits, headshots, teamkills, team_hits, team_damage,
      melee_damage, mounted_damage, ranged_damage,
      rounds_as_infantry, rounds_as_ranged, rounds_as_cavalry,
      kills_melee, kills_ranged, kills_throwing,
      kills_mounted_melee, kills_mounted_ranged, kills_mounted_throwing,
      deaths_melee, deaths_ranged, deaths_throwing,
      deaths_mounted_melee, deaths_mounted_ranged, deaths_mounted_throwing,
      suicides, throwing_damage, mounted_ranged_damage, mounted_throwing_damage,
      throwing_shots, throwing_hits, throwing_headshots,
      team_hits_received, team_damage_received, deaths_by_teammate,
      alive_ms, spawn_count, updated_at
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
      coalesce(p_kills_melee, 0), coalesce(p_kills_ranged, 0), coalesce(p_kills_throwing, 0),
      coalesce(p_kills_mounted_melee, 0), coalesce(p_kills_mounted_ranged, 0), coalesce(p_kills_mounted_throwing, 0),
      coalesce(p_deaths_melee, 0), coalesce(p_deaths_ranged, 0), coalesce(p_deaths_throwing, 0),
      coalesce(p_deaths_mounted_melee, 0), coalesce(p_deaths_mounted_ranged, 0), coalesce(p_deaths_mounted_throwing, 0),
      coalesce(p_suicides, 0),
      coalesce(p_throwing_damage, 0), coalesce(p_mounted_ranged_damage, 0), coalesce(p_mounted_throwing_damage, 0),
      coalesce(p_throwing_shots, 0), coalesce(p_throwing_hits, 0), coalesce(p_throwing_headshots, 0),
      coalesce(p_team_hits_received, 0), coalesce(p_team_damage_received, 0), coalesce(p_deaths_by_teammate, 0),
      coalesce(p_alive_ms, 0), coalesce(p_spawn_count, 0), now()
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
      kills_melee = c.kills_melee + excluded.kills_melee,
      kills_ranged = c.kills_ranged + excluded.kills_ranged,
      kills_throwing = c.kills_throwing + excluded.kills_throwing,
      kills_mounted_melee = c.kills_mounted_melee + excluded.kills_mounted_melee,
      kills_mounted_ranged = c.kills_mounted_ranged + excluded.kills_mounted_ranged,
      kills_mounted_throwing = c.kills_mounted_throwing + excluded.kills_mounted_throwing,
      deaths_melee = c.deaths_melee + excluded.deaths_melee,
      deaths_ranged = c.deaths_ranged + excluded.deaths_ranged,
      deaths_throwing = c.deaths_throwing + excluded.deaths_throwing,
      deaths_mounted_melee = c.deaths_mounted_melee + excluded.deaths_mounted_melee,
      deaths_mounted_ranged = c.deaths_mounted_ranged + excluded.deaths_mounted_ranged,
      deaths_mounted_throwing = c.deaths_mounted_throwing + excluded.deaths_mounted_throwing,
      suicides = c.suicides + excluded.suicides,
      throwing_damage = c.throwing_damage + excluded.throwing_damage,
      mounted_ranged_damage = c.mounted_ranged_damage + excluded.mounted_ranged_damage,
      mounted_throwing_damage = c.mounted_throwing_damage + excluded.mounted_throwing_damage,
      throwing_shots = c.throwing_shots + excluded.throwing_shots,
      throwing_hits = c.throwing_hits + excluded.throwing_hits,
      throwing_headshots = c.throwing_headshots + excluded.throwing_headshots,
      team_hits_received = c.team_hits_received + excluded.team_hits_received,
      team_damage_received = c.team_damage_received + excluded.team_damage_received,
      deaths_by_teammate = c.deaths_by_teammate + excluded.deaths_by_teammate,
      alive_ms = c.alive_ms + excluded.alive_ms,
      spawn_count = c.spawn_count + excluded.spawn_count,
      updated_at = now();
  else
    insert into public.player_career_stats as c (
      steam_id, display_name, rounds_played, rounds_won, total_score,
      total_kills, total_deaths, total_assists, mvp_count,
      first_kills, first_deaths, horse_damage, horse_kills, kicks, couches,
      shots, hits, headshots, teamkills, team_hits, team_damage,
      melee_damage, mounted_damage, ranged_damage,
      rounds_as_infantry, rounds_as_ranged, rounds_as_cavalry,
      kills_melee, kills_ranged, kills_throwing,
      kills_mounted_melee, kills_mounted_ranged, kills_mounted_throwing,
      deaths_melee, deaths_ranged, deaths_throwing,
      deaths_mounted_melee, deaths_mounted_ranged, deaths_mounted_throwing,
      suicides, throwing_damage, mounted_ranged_damage, mounted_throwing_damage,
      throwing_shots, throwing_hits, throwing_headshots,
      team_hits_received, team_damage_received, deaths_by_teammate,
      alive_ms, spawn_count, updated_at
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
      coalesce(p_kills_melee, 0), coalesce(p_kills_ranged, 0), coalesce(p_kills_throwing, 0),
      coalesce(p_kills_mounted_melee, 0), coalesce(p_kills_mounted_ranged, 0), coalesce(p_kills_mounted_throwing, 0),
      coalesce(p_deaths_melee, 0), coalesce(p_deaths_ranged, 0), coalesce(p_deaths_throwing, 0),
      coalesce(p_deaths_mounted_melee, 0), coalesce(p_deaths_mounted_ranged, 0), coalesce(p_deaths_mounted_throwing, 0),
      coalesce(p_suicides, 0),
      coalesce(p_throwing_damage, 0), coalesce(p_mounted_ranged_damage, 0), coalesce(p_mounted_throwing_damage, 0),
      coalesce(p_throwing_shots, 0), coalesce(p_throwing_hits, 0), coalesce(p_throwing_headshots, 0),
      coalesce(p_team_hits_received, 0), coalesce(p_team_damage_received, 0), coalesce(p_deaths_by_teammate, 0),
      coalesce(p_alive_ms, 0), coalesce(p_spawn_count, 0), now()
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
      kills_melee = c.kills_melee + excluded.kills_melee,
      kills_ranged = c.kills_ranged + excluded.kills_ranged,
      kills_throwing = c.kills_throwing + excluded.kills_throwing,
      kills_mounted_melee = c.kills_mounted_melee + excluded.kills_mounted_melee,
      kills_mounted_ranged = c.kills_mounted_ranged + excluded.kills_mounted_ranged,
      kills_mounted_throwing = c.kills_mounted_throwing + excluded.kills_mounted_throwing,
      deaths_melee = c.deaths_melee + excluded.deaths_melee,
      deaths_ranged = c.deaths_ranged + excluded.deaths_ranged,
      deaths_throwing = c.deaths_throwing + excluded.deaths_throwing,
      deaths_mounted_melee = c.deaths_mounted_melee + excluded.deaths_mounted_melee,
      deaths_mounted_ranged = c.deaths_mounted_ranged + excluded.deaths_mounted_ranged,
      deaths_mounted_throwing = c.deaths_mounted_throwing + excluded.deaths_mounted_throwing,
      suicides = c.suicides + excluded.suicides,
      throwing_damage = c.throwing_damage + excluded.throwing_damage,
      mounted_ranged_damage = c.mounted_ranged_damage + excluded.mounted_ranged_damage,
      mounted_throwing_damage = c.mounted_throwing_damage + excluded.mounted_throwing_damage,
      throwing_shots = c.throwing_shots + excluded.throwing_shots,
      throwing_hits = c.throwing_hits + excluded.throwing_hits,
      throwing_headshots = c.throwing_headshots + excluded.throwing_headshots,
      team_hits_received = c.team_hits_received + excluded.team_hits_received,
      team_damage_received = c.team_damage_received + excluded.team_damage_received,
      deaths_by_teammate = c.deaths_by_teammate + excluded.deaths_by_teammate,
      alive_ms = c.alive_ms + excluded.alive_ms,
      spawn_count = c.spawn_count + excluded.spawn_count,
      updated_at = now();
  end if;

  if culture_key <> '' then
    insert into public.player_culture_stats as g (
      steam_id, culture_id, is_skirmish_club, rounds_played, rounds_won, updated_at
    ) values (
      p_steam_id, culture_key, club, 1,
      case when p_is_winner then 1 else 0 end,
      now()
    )
    on conflict (steam_id, culture_id, is_skirmish_club) do update set
      rounds_played = g.rounds_played + 1,
      rounds_won = g.rounds_won + excluded.rounds_won,
      updated_at = now();
  end if;

  return true;
end;
$$;

grant execute on function public.upsert_career_from_round to service_role;
