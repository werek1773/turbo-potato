-- =============================================================================
-- Wspinaczka — anonymous gym statistics and personal data export
--
-- Gym statistics are a daily snapshot, never a live query:
--   * only ascents at least 3 climbing days old are counted;
--   * staff of the gym, platform admins and opted-out climbers are excluded;
--   * every published number is counted in distinct climbers, shown only when
--     it reaches 5 and rounded down to a multiple of 5.
-- The snapshot has no query parameters, so it cannot be sliced down to a
-- single visit.
-- =============================================================================

create table public.problem_stats (
  problem_id uuid primary key,
  gym_id uuid not null,
  computed_at timestamptz not null,
  climbers integer,
  tops integer,
  flashes integer,
  perceived_soft integer,
  perceived_ok integer,
  perceived_hard integer,
  -- {"finger_strength": 10, ...}: only limiters reported by >= 5 climbers.
  limiters jsonb not null default '{}'::jsonb,
  foreign key (problem_id, gym_id) references public.problems (id, gym_id) on delete cascade
);

create index problem_stats_gym_idx on public.problem_stats (gym_id);
create index problem_stats_problem_gym_idx on public.problem_stats (problem_id, gym_id);

alter table public.problem_stats enable row level security;

create policy problem_stats_select_visible on public.problem_stats
  for select to authenticated
  using (private.can_view_gym(gym_id));

revoke all on public.problem_stats from anon, authenticated;
grant select on public.problem_stats to authenticated;
grant select, insert, update, delete on public.problem_stats to service_role;

create function private.k_anonymous_count(p_count bigint)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case when p_count >= 5 then ((p_count / 5) * 5)::integer else null end;
$$;

create function private.refresh_problem_stats()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := now();
begin
  delete from public.problem_stats where true;

  insert into public.problem_stats (
    problem_id, gym_id, computed_at, climbers, tops, flashes,
    perceived_soft, perceived_ok, perceived_hard, limiters
  )
  with eligible as (
    select a.*
      from public.ascents a
      join public.profiles pr on pr.id = a.user_id and not pr.stats_opt_out
      join public.gyms g on g.id = a.gym_id
     where a.local_date <= private.climbing_date(v_now, g.timezone) - 3
       and not exists (
         select 1 from public.gym_memberships m
         where m.gym_id = a.gym_id and m.user_id = a.user_id
       )
       and not exists (
         select 1 from private.platform_admins pa where pa.user_id = a.user_id
       )
  ),
  per_climber as (
    select e.problem_id,
           e.gym_id,
           e.user_id,
           bool_or(e.result in ('top', 'flash')) as topped,
           bool_or(e.result = 'flash') as flashed,
           (array_agg(e.perceived_grade order by e.local_date desc)
              filter (where e.perceived_grade is not null))[1] as perceived
      from eligible e
     group by e.problem_id, e.gym_id, e.user_id
  ),
  per_problem as (
    select c.problem_id,
           c.gym_id,
           count(*) as climbers,
           count(*) filter (where c.topped) as tops,
           count(*) filter (where c.flashed) as flashes,
           count(*) filter (where c.perceived = 'soft') as soft,
           count(*) filter (where c.perceived = 'ok') as ok,
           count(*) filter (where c.perceived = 'hard') as hard
      from per_climber c
     group by c.problem_id, c.gym_id
  ),
  limiter_counts as (
    select e.problem_id, l.limiter, count(distinct e.user_id) as climbers
      from eligible e
      cross join lateral unnest(e.limiters) as l (limiter)
     group by e.problem_id, l.limiter
  )
  select p.problem_id,
         p.gym_id,
         v_now,
         private.k_anonymous_count(p.climbers),
         private.k_anonymous_count(p.tops),
         private.k_anonymous_count(p.flashes),
         private.k_anonymous_count(p.soft),
         private.k_anonymous_count(p.ok),
         private.k_anonymous_count(p.hard),
         coalesce((
           select jsonb_object_agg(lc.limiter, private.k_anonymous_count(lc.climbers))
             from limiter_counts lc
            where lc.problem_id = p.problem_id and lc.climbers >= 5
         ), '{}'::jsonb)
    from per_problem p
   where p.climbers >= 5;
end;
$$;

create function private.daily_maintenance()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.refresh_problem_stats();
  delete from private.invite_attempts where attempted_at < now() - interval '30 days';
end;
$$;

revoke all on function private.k_anonymous_count(bigint) from public;
revoke all on function private.refresh_problem_stats() from public;
revoke all on function private.daily_maintenance() from public;

-- Daily at 02:17 UTC. pg_cron exists on Supabase; local test databases
-- without it simply skip the schedule.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron with schema pg_catalog;
    grant usage on schema cron to postgres;
    grant all privileges on all tables in schema cron to postgres;
    perform cron.schedule(
      'wspinaczka-daily-maintenance',
      '17 2 * * *',
      'select private.daily_maintenance()'
    );
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- Personal data export (GDPR art. 15 / 20)
-- -----------------------------------------------------------------------------
create function public.export_my_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
begin
  return jsonb_build_object(
    'exported_at', now(),
    'profile', (
      select to_jsonb(p) from public.profiles p where p.id = v_uid
    ),
    'gym_roles', coalesce((
      select jsonb_agg(jsonb_build_object('gym', g.name, 'role', m.role, 'since', m.created_at))
        from public.gym_memberships m
        join public.gyms g on g.id = m.gym_id
       where m.user_id = v_uid
    ), '[]'::jsonb),
    'sessions', coalesce((
      select jsonb_agg(
               (to_jsonb(s) - 'user_id')
               || jsonb_build_object(
                    'gym', g.name,
                    'wellbeing', (
                      select to_jsonb(w) - 'user_id' - 'session_id'
                        from public.session_wellbeing w
                       where w.session_id = s.id
                    )
                  )
               order by s.local_date
             )
        from public.sessions s
        join public.gyms g on g.id = s.gym_id
       where s.user_id = v_uid
    ), '[]'::jsonb),
    'ascents', coalesce((
      select jsonb_agg(
               (to_jsonb(a) - 'user_id')
               || jsonb_build_object(
                    'gym', g.name,
                    'sector', sc.name,
                    'grade', gr.label,
                    'hold_color', p.hold_color
                  )
               order by a.local_date
             )
        from public.ascents a
        join public.problems p on p.id = a.problem_id
        join public.sectors sc on sc.id = p.sector_id
        join public.gyms g on g.id = a.gym_id
        join public.grades gr on gr.id = a.grade_id_snapshot
       where a.user_id = v_uid
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.export_my_data() from public, anon;
grant execute on function public.export_my_data() to authenticated;

revoke execute on all functions in schema private from public;
