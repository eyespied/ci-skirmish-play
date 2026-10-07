-- SkirmishPlay stats schema
-- Apply via Supabase SQL editor or: supabase db push

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- players
-- ---------------------------------------------------------------------------
create table if not exists public.players (
  steam_id text primary key,
  display_name text not null default '',
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- matches
-- ---------------------------------------------------------------------------
create table if not exists public.matches (
  id uuid primary key default gen_random_uuid(),
  server_name text not null default '',
  map_id text not null default '',
  game_type text not null default 'Skirmish',
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  rounds_played int not null default 0,
  winning_side text
);

-- ---------------------------------------------------------------------------
-- round_player_stats (one row per player per live round)
-- ---------------------------------------------------------------------------
create table if not exists public.round_player_stats (
  match_id uuid not null references public.matches (id) on delete cascade,
  round_number int not null,
  steam_id text not null references public.players (steam_id),
  display_name text not null default '',
  team_side text not null default '',
  class_group text not null default 'Infantry',
  score int not null default 0,
  kills int not null default 0,
  deaths int not null default 0,
  assists int not null default 0,
  is_mvp boolean not null default false,
  is_winner boolean not null default false,
  first_kill boolean not null default false,
  first_death boolean not null default false,
  horse_damage int not null default 0,
  horse_kills int not null default 0,
  kicks int not null default 0,
  couches int not null default 0,
  shots int not null default 0,
  hits int not null default 0,
  headshots int not null default 0,
  hit_pct numeric generated always as (
    case when shots > 0 then round((hits::numeric / shots::numeric) * 100, 2) else 0 end
  ) stored,
  teamkills int not null default 0,
  team_hits int not null default 0,
  team_damage int not null default 0,
  melee_damage int not null default 0,
  mounted_damage int not null default 0,
  ranged_damage int not null default 0,
  created_at timestamptz not null default now(),
  primary key (match_id, round_number, steam_id)
);

create index if not exists idx_round_player_stats_steam
  on public.round_player_stats (steam_id);

create index if not exists idx_round_player_stats_match
  on public.round_player_stats (match_id, round_number);

-- ---------------------------------------------------------------------------
-- player_career_stats (denormalized totals)
-- ---------------------------------------------------------------------------
create table if not exists public.player_career_stats (
  steam_id text primary key references public.players (steam_id) on delete cascade,
  display_name text not null default '',
  rounds_played int not null default 0,
  rounds_won int not null default 0,
  total_score bigint not null default 0,
  total_kills int not null default 0,
  total_deaths int not null default 0,
  total_assists int not null default 0,
  mvp_count int not null default 0,
  first_kills int not null default 0,
  first_deaths int not null default 0,
  horse_damage bigint not null default 0,
  horse_kills int not null default 0,
  kicks int not null default 0,
  couches int not null default 0,
  shots int not null default 0,
  hits int not null default 0,
  headshots int not null default 0,
  teamkills int not null default 0,
  team_hits int not null default 0,
  team_damage bigint not null default 0,
  melee_damage bigint not null default 0,
  mounted_damage bigint not null default 0,
  ranged_damage bigint not null default 0,
  rounds_as_infantry int not null default 0,
  rounds_as_ranged int not null default 0,
  rounds_as_cavalry int not null default 0,
  updated_at timestamptz not null default now(),

  win_rate numeric generated always as (
    case when rounds_played > 0 then round((rounds_won::numeric / rounds_played::numeric) * 100, 2) else 0 end
  ) stored,
  avg_score_per_round numeric generated always as (
    case when rounds_played > 0 then round(total_score::numeric / rounds_played::numeric, 2) else 0 end
  ) stored,
  avg_kills_per_round numeric generated always as (
    case when rounds_played > 0 then round(total_kills::numeric / rounds_played::numeric, 2) else 0 end
  ) stored,
  avg_deaths_per_round numeric generated always as (
    case when rounds_played > 0 then round(total_deaths::numeric / rounds_played::numeric, 2) else 0 end
  ) stored,
  avg_assists_per_round numeric generated always as (
    case when rounds_played > 0 then round(total_assists::numeric / rounds_played::numeric, 2) else 0 end
  ) stored,
  mvp_rate numeric generated always as (
    case when rounds_played > 0 then round((mvp_count::numeric / rounds_played::numeric) * 100, 2) else 0 end
  ) stored,
  hit_pct numeric generated always as (
    case when shots > 0 then round((hits::numeric / shots::numeric) * 100, 2) else 0 end
  ) stored,
  pct_infantry numeric generated always as (
    case when rounds_played > 0 then round((rounds_as_infantry::numeric / rounds_played::numeric) * 100, 2) else 0 end
  ) stored,
  pct_ranged numeric generated always as (
    case when rounds_played > 0 then round((rounds_as_ranged::numeric / rounds_played::numeric) * 100, 2) else 0 end
  ) stored,
  pct_cavalry numeric generated always as (
    case when rounds_played > 0 then round((rounds_as_cavalry::numeric / rounds_played::numeric) * 100, 2) else 0 end
  ) stored
);

-- ---------------------------------------------------------------------------
-- Atomic round insert + career increment (idempotent on PK)
-- Returns true when the round row was newly inserted.
-- ---------------------------------------------------------------------------
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
  p_ranged_damage int
)
returns boolean
language plpgsql
security definer
as $$
declare
  rows_inserted int := 0;
  class_key text;
begin
  insert into public.players (steam_id, display_name, updated_at)
  values (p_steam_id, coalesce(p_display_name, ''), now())
  on conflict (steam_id) do update
    set display_name = excluded.display_name,
        updated_at = now();

  insert into public.round_player_stats (
    match_id, round_number, steam_id, display_name, team_side, class_group,
    score, kills, deaths, assists, is_mvp, is_winner,
    first_kill, first_death, horse_damage, horse_kills, kicks, couches,
    shots, hits, headshots, teamkills, team_hits, team_damage,
    melee_damage, mounted_damage, ranged_damage
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
    coalesce(p_melee_damage, 0), coalesce(p_mounted_damage, 0), coalesce(p_ranged_damage, 0)
  )
  on conflict (match_id, round_number, steam_id) do nothing;

  get diagnostics rows_inserted = row_count;
  if rows_inserted = 0 then
    return false;
  end if;

  class_key := lower(coalesce(p_class_group, 'infantry'));

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

  return true;
end;
$$;

grant execute on function public.upsert_career_from_round to service_role;

-- RLS: service role bypasses; anon policies for a future public site (read-only).
alter table public.players enable row level security;
alter table public.matches enable row level security;
alter table public.round_player_stats enable row level security;
alter table public.player_career_stats enable row level security;

drop policy if exists players_public_read on public.players;
create policy players_public_read on public.players for select to anon using (true);

drop policy if exists matches_public_read on public.matches;
create policy matches_public_read on public.matches for select to anon using (true);

drop policy if exists round_player_stats_public_read on public.round_player_stats;
create policy round_player_stats_public_read on public.round_player_stats for select to anon using (true);

drop policy if exists player_career_stats_public_read on public.player_career_stats;
create policy player_career_stats_public_read on public.player_career_stats for select to anon using (true);
