-- Skirmish Club: flag rounds/matches + separate career totals table.
-- Apply after 001_stats.sql

alter table public.matches
  add column if not exists is_skirmish_club boolean not null default false;

alter table public.round_player_stats
  add column if not exists is_skirmish_club boolean not null default false;

create index if not exists idx_round_player_stats_skirmish_club
  on public.round_player_stats (is_skirmish_club);

create index if not exists idx_matches_skirmish_club
  on public.matches (is_skirmish_club);

-- Same shape as player_career_stats, used only while Skirmish Club is active.
create table if not exists public.player_career_stats_skirmish (
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

alter table public.player_career_stats_skirmish enable row level security;

drop policy if exists player_career_stats_skirmish_public_read on public.player_career_stats_skirmish;
create policy player_career_stats_skirmish_public_read
  on public.player_career_stats_skirmish for select to anon using (true);

-- Replace RPC: routes career increments to the correct table.
drop function if exists public.upsert_career_from_round(
  uuid, int, text, text, text, text,
  int, int, int, int, boolean, boolean, boolean, boolean,
  int, int, int, int, int, int, int, int, int, int, int, int, int
);

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
  p_is_skirmish_club boolean default false
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
