-- =============================================================================
-- Wspinaczka — private climbing journal
-- Sessions, wellbeing (health data, explicit consent only) and ascents.
-- Every row is visible to its owner only. Writes go through RPCs so that the
-- app can replay its offline outbox idempotently.
-- =============================================================================

create type public.ascent_result as enum ('flash', 'top', 'project');
create type public.attempts_bucket as enum ('1', '2-3', '4-10', '10+');
create type public.perceived_grade as enum ('soft', 'ok', 'hard');
-- What stopped you. Deliberately non-medical: these are aggregated for gyms.
create type public.limiter as enum (
  'finger_strength', 'power', 'endurance', 'core', 'flexibility',
  'footwork', 'balance', 'coordination', 'beta',
  'fear', 'commitment', 'conditions'
);
create type public.session_source as enum ('geofence', 'manual');
create type public.skin_state as enum ('fresh', 'ok', 'thin', 'split');
create type public.body_area as enum (
  'fingers', 'wrists', 'elbows', 'shoulders', 'back', 'knees', 'ankles', 'other'
);

-- A climbing day ends at 04:00 local time: a late session belongs to the day
-- it started. The app uses the same rule (BoulderKit.ClimbingDay).
create function private.climbing_date(p_at timestamptz, p_timezone text)
returns date
language sql
immutable
set search_path = ''
as $$
  select ((p_at at time zone p_timezone) - interval '4 hours')::date;
$$;

-- -----------------------------------------------------------------------------
-- 1. Sessions: one per (user, gym, climbing day)
-- -----------------------------------------------------------------------------
create table public.sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  gym_id uuid not null references public.gyms (id) on delete cascade,
  local_date date not null,
  started_at timestamptz,
  ended_at timestamptz,
  source public.session_source not null default 'manual',
  note text check (char_length(note) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, gym_id, local_date),
  unique (id, user_id),
  check (started_at is null or ended_at is null or ended_at >= started_at)
);

create index sessions_user_date_idx on public.sessions (user_id, local_date desc);
create index sessions_gym_idx on public.sessions (gym_id);

create trigger sessions_touch_updated_at
  before update on public.sessions
  for each row execute function private.touch_updated_at();

create function private.validate_session()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_timezone text;
  v_published timestamptz;
begin
  select g.timezone, g.published_at into v_timezone, v_published
    from public.gyms g where g.id = new.gym_id;

  if tg_op = 'INSERT' and v_published is null and not private.has_gym_role(new.gym_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if new.local_date > private.climbing_date(now(), v_timezone) then
    raise exception 'future_date' using errcode = 'P0001';
  end if;
  if new.local_date < date '2020-01-01' then
    raise exception 'invalid_date' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger sessions_validate
  before insert or update of local_date, gym_id on public.sessions
  for each row execute function private.validate_session();

-- -----------------------------------------------------------------------------
-- 2. Wellbeing (health data — GDPR art. 9, explicit consent)
-- -----------------------------------------------------------------------------
create table public.session_wellbeing (
  session_id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  energy smallint check (energy between 1 and 5),
  rpe smallint check (rpe between 1 and 10),
  skin public.skin_state,
  pain_areas public.body_area[] not null default '{}' check (cardinality(pain_areas) <= 8),
  updated_at timestamptz not null default now(),
  foreign key (session_id, user_id) references public.sessions (id, user_id) on delete cascade
);

create index session_wellbeing_user_idx on public.session_wellbeing (user_id);
create index session_wellbeing_session_user_idx on public.session_wellbeing (session_id, user_id);

create trigger session_wellbeing_touch_updated_at
  before update on public.session_wellbeing
  for each row execute function private.touch_updated_at();

-- -----------------------------------------------------------------------------
-- 3. Ascents: one record per (user, problem, climbing day)
-- -----------------------------------------------------------------------------
create table public.ascents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  gym_id uuid not null,
  problem_id uuid not null,
  local_date date not null,
  result public.ascent_result not null,
  attempts public.attempts_bucket,
  perceived_grade public.perceived_grade,
  limiters public.limiter[] not null default '{}' check (cardinality(limiters) <= 5),
  note text check (char_length(note) <= 500),
  -- Grade of the problem when the ascent was first logged (regrades do not
  -- rewrite personal history).
  grade_id_snapshot uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, problem_id, local_date),
  foreign key (problem_id, gym_id) references public.problems (id, gym_id) on delete cascade,
  foreign key (user_id, gym_id, local_date)
    references public.sessions (user_id, gym_id, local_date) on delete cascade,
  foreign key (grade_id_snapshot, gym_id) references public.grades (id, gym_id),
  check (result <> 'flash' or attempts is null or attempts = '1')
);

create index ascents_user_date_idx on public.ascents (user_id, local_date desc);
create index ascents_problem_idx on public.ascents (problem_id, gym_id);
create index ascents_session_idx on public.ascents (user_id, gym_id, local_date);
create index ascents_gym_idx on public.ascents (gym_id, local_date);
create index ascents_grade_idx on public.ascents (grade_id_snapshot, gym_id);

create trigger ascents_touch_updated_at
  before update on public.ascents
  for each row execute function private.touch_updated_at();

create function private.prepare_ascent()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_problem record;
begin
  if tg_op = 'UPDATE' then
    if new.user_id <> old.user_id
       or new.problem_id <> old.problem_id
       or new.local_date <> old.local_date
       or new.gym_id <> old.gym_id then
      raise exception 'immutable_ascent_key' using errcode = 'P0001';
    end if;
    new.grade_id_snapshot := old.grade_id_snapshot;
  else
    select p.gym_id, p.grade_id, p.set_at, p.removed_at, g.timezone, g.published_at
      into v_problem
      from public.problems p
      join public.gyms g on g.id = p.gym_id
     where p.id = new.problem_id;

    if not found then
      raise exception 'unknown_problem' using errcode = 'P0001';
    end if;
    if v_problem.published_at is null and not private.has_gym_role(v_problem.gym_id) then
      raise exception 'forbidden' using errcode = '42501';
    end if;

    new.gym_id := v_problem.gym_id;
    new.grade_id_snapshot := v_problem.grade_id;

    if new.local_date < private.climbing_date(v_problem.set_at, v_problem.timezone) then
      raise exception 'before_problem_set' using errcode = 'P0001';
    end if;
    if v_problem.removed_at is not null
       and new.local_date > private.climbing_date(v_problem.removed_at, v_problem.timezone) then
      raise exception 'problem_removed' using errcode = 'P0001';
    end if;

    -- The session for that day is created on demand.
    insert into public.sessions (user_id, gym_id, local_date)
    values (new.user_id, new.gym_id, new.local_date)
    on conflict (user_id, gym_id, local_date) do nothing;
  end if;

  if new.result = 'flash' and exists (
    select 1 from public.ascents a
    where a.user_id = new.user_id
      and a.problem_id = new.problem_id
      and a.local_date < new.local_date
  ) then
    raise exception 'flash_not_first_attempt' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

create trigger ascents_prepare
  before insert or update on public.ascents
  for each row execute function private.prepare_ascent();

-- Logging an earlier day afterwards turns a later "flash" into a plain top.
create function private.demote_later_flashes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.ascents a
     set result = 'top'
   where a.user_id = new.user_id
     and a.problem_id = new.problem_id
     and a.local_date > new.local_date
     and a.result = 'flash';
  return null;
end;
$$;

create trigger ascents_demote_later_flashes
  after insert on public.ascents
  for each row execute function private.demote_later_flashes();

-- -----------------------------------------------------------------------------
-- 4. RLS: owner only. Clients read and delete directly, write through RPCs.
-- -----------------------------------------------------------------------------
alter table public.sessions enable row level security;
alter table public.session_wellbeing enable row level security;
alter table public.ascents enable row level security;

create policy sessions_select_own on public.sessions
  for select to authenticated using (user_id = (select auth.uid()));
create policy sessions_delete_own on public.sessions
  for delete to authenticated using (user_id = (select auth.uid()));

create policy session_wellbeing_select_own on public.session_wellbeing
  for select to authenticated using (user_id = (select auth.uid()));
create policy session_wellbeing_delete_own on public.session_wellbeing
  for delete to authenticated using (user_id = (select auth.uid()));

create policy ascents_select_own on public.ascents
  for select to authenticated using (user_id = (select auth.uid()));
create policy ascents_delete_own on public.ascents
  for delete to authenticated using (user_id = (select auth.uid()));

revoke all on public.sessions, public.session_wellbeing, public.ascents from anon, authenticated;
grant select, delete on public.sessions, public.session_wellbeing, public.ascents to authenticated;
grant select, insert, update, delete on public.sessions, public.session_wellbeing, public.ascents to service_role;

-- -----------------------------------------------------------------------------
-- 5. RPCs
-- -----------------------------------------------------------------------------
-- Creates or extends the session of a climbing day. Visit times only ever
-- widen, so geofence events and manual summaries from several devices merge.
create function public.upsert_session(
  p_gym_id uuid,
  p_local_date date,
  p_started_at timestamptz default null,
  p_ended_at timestamptz default null,
  p_source public.session_source default 'manual',
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
  v_id uuid;
begin
  insert into public.sessions as s (user_id, gym_id, local_date, started_at, ended_at, source, note)
  values (
    v_uid, p_gym_id, p_local_date, p_started_at, p_ended_at,
    coalesce(p_source, 'manual'), nullif(btrim(p_note), '')
  )
  on conflict (user_id, gym_id, local_date) do update
    set started_at = least(s.started_at, excluded.started_at),
        ended_at = greatest(s.ended_at, excluded.ended_at),
        source = case when excluded.source = 'geofence' then 'geofence'::public.session_source else s.source end,
        note = coalesce(excluded.note, s.note)
  returning s.id into v_id;

  return v_id;
end;
$$;

-- Tap-cycle friendly: pass p_result = null to clear the day's record.
create function public.set_ascent(
  p_problem_id uuid,
  p_local_date date,
  p_result public.ascent_result,
  p_attempts public.attempts_bucket default null,
  p_perceived_grade public.perceived_grade default null,
  p_limiters public.limiter[] default '{}',
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
  v_id uuid;
begin
  if p_result is null then
    delete from public.ascents
     where user_id = v_uid and problem_id = p_problem_id and local_date = p_local_date;
    return null;
  end if;

  insert into public.ascents as a (
    user_id, problem_id, local_date, result, attempts, perceived_grade, limiters, note
  ) values (
    v_uid, p_problem_id, p_local_date, p_result, p_attempts, p_perceived_grade,
    coalesce(p_limiters, '{}'), nullif(btrim(p_note), '')
  )
  on conflict (user_id, problem_id, local_date) do update
    set result = excluded.result,
        attempts = excluded.attempts,
        perceived_grade = excluded.perceived_grade,
        limiters = excluded.limiters,
        note = excluded.note
  returning a.id into v_id;

  return v_id;
end;
$$;

create function public.set_session_wellbeing(
  p_session_id uuid,
  p_energy integer default null,
  p_rpe integer default null,
  p_skin public.skin_state default null,
  p_pain_areas public.body_area[] default '{}'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
begin
  if not exists (
    select 1 from public.profiles p
    where p.id = v_uid and p.health_data_consent_at is not null
  ) then
    raise exception 'health_consent_required' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.sessions s where s.id = p_session_id and s.user_id = v_uid
  ) then
    raise exception 'not_found' using errcode = 'P0001';
  end if;

  if p_energy is null and p_rpe is null and p_skin is null
     and coalesce(cardinality(p_pain_areas), 0) = 0 then
    delete from public.session_wellbeing where session_id = p_session_id;
    return;
  end if;

  insert into public.session_wellbeing as w (session_id, user_id, energy, rpe, skin, pain_areas)
  values (p_session_id, v_uid, p_energy, p_rpe, p_skin, coalesce(p_pain_areas, '{}'))
  on conflict (session_id) do update
    set energy = excluded.energy,
        rpe = excluded.rpe,
        skin = excluded.skin,
        pain_areas = excluded.pain_areas;
end;
$$;

create function public.set_stats_opt_out(p_opt_out boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles
     set stats_opt_out = coalesce(p_opt_out, false)
   where id = private.require_uid();
end;
$$;

-- Withdrawing consent deletes every stored wellbeing entry.
create function public.set_health_data_consent(p_consent boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
begin
  if coalesce(p_consent, false) then
    update public.profiles
       set health_data_consent_at = coalesce(health_data_consent_at, now())
     where id = v_uid;
  else
    delete from public.session_wellbeing where user_id = v_uid;
    update public.profiles set health_data_consent_at = null where id = v_uid;
  end if;
end;
$$;

revoke all on function private.climbing_date(timestamptz, text) from public;

revoke all on function public.upsert_session(uuid, date, timestamptz, timestamptz, public.session_source, text) from public, anon;
revoke all on function public.set_ascent(uuid, date, public.ascent_result, public.attempts_bucket, public.perceived_grade, public.limiter[], text) from public, anon;
revoke all on function public.set_session_wellbeing(uuid, integer, integer, public.skin_state, public.body_area[]) from public, anon;
revoke all on function public.set_stats_opt_out(boolean) from public, anon;
revoke all on function public.set_health_data_consent(boolean) from public, anon;

grant execute on function public.upsert_session(uuid, date, timestamptz, timestamptz, public.session_source, text) to authenticated;
grant execute on function public.set_ascent(uuid, date, public.ascent_result, public.attempts_bucket, public.perceived_grade, public.limiter[], text) to authenticated;
grant execute on function public.set_session_wellbeing(uuid, integer, integer, public.skin_state, public.body_area[]) to authenticated;
grant execute on function public.set_stats_opt_out(boolean) to authenticated;
grant execute on function public.set_health_data_consent(boolean) to authenticated;

revoke execute on all functions in schema private from public;
