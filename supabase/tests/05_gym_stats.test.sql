begin;
\ir _helpers.inc
select no_plan();

-- Setup: published Volt, one problem set 30 days ago ---------------------------
select tests.create_user('owner@example.com', 'Owner') as owner \gset
select tests.create_user('setter@example.com', 'Setter') as setter \gset
select tests.make_platform_admin(:'owner');
select tests.gym_id('volt-lodz') as volt \gset
select tests.grade_id(:'volt', '5') as volt_5 \gset

select tests.authenticate_as(:'owner');
select public.admin_set_gym_role(:'volt', :'setter', 'routesetter');
select public.set_gym_published(:'volt', true);
insert into public.sectors (gym_id, name) values (:'volt', 'Okap') returning id as sector \gset
select tests.upload_sector_photo(:'volt', :'sector') as path \gset
select public.reset_sector(:'sector', null, :'path', 3000, 2000);
select current_photo_id as photo from public.sectors where id = :'sector' \gset
select public.add_problem(:'sector', :'photo', 0.5, 0.5, :'volt_5', 'black') as problem \gset

select tests.as_owner();
update public.problems set set_at = now() - interval '30 days' where id = :'problem';
select tests.today(:'volt') as today \gset

-- Seven climbers log the problem five days ago --------------------------------
create temporary table climbers (n int, id uuid);
grant select on climbers to authenticated;
insert into climbers
select n, tests.create_user('climber' || n || '@example.com') from generate_series(1, 7) n;

do $$
declare
  c record;
  v_problem uuid := (select id from public.problems where hold_color = 'black');
  v_day date := tests.today(tests.gym_id('volt-lodz')) - 5;
begin
  for c in select * from climbers order by n loop
    perform tests.authenticate_as(c.id);
    perform public.set_ascent(
      v_problem,
      v_day,
      case when c.n <= 2 then 'flash' when c.n <= 6 then 'top' else 'project' end::public.ascent_result,
      null,
      case when c.n <= 5 then 'hard' else 'ok' end::public.perceived_grade,
      case when c.n >= 2 then array['finger_strength']::public.limiter[] else '{}' end
    );
    perform tests.as_owner();
  end loop;
end;
$$;

-- A setter's own test burns and a recent ascent are never counted.
select tests.authenticate_as(:'setter');
select public.set_ascent(:'problem', :'today'::date - 5, 'top');
select tests.as_owner();
select tests.create_user('recent@example.com') as recent \gset
select tests.authenticate_as(:'recent');
select public.set_ascent(:'problem', :'today', 'top');

-- Climber 7 opts out of statistics.
select tests.authenticate_as(id) from climbers where n = 7;
select public.set_stats_opt_out(true);

select tests.as_owner();
select private.refresh_problem_stats();

select results_eq(
  format('select climbers, tops, flashes, perceived_soft, perceived_ok, perceived_hard, limiters from public.problem_stats where problem_id = %L', :'problem'),
  $$ values (5, 5, null::int, null::int, null::int, 5, '{"finger_strength": 5}'::jsonb) $$,
  '6 eligible climbers round down to 5; cells under 5 (2 flashes, 1 "ok") are suppressed'
);

-- Every climber who can see the gym can read the anonymous snapshot.
select tests.authenticate_as(:'recent');
select is(
  (select climbers from public.problem_stats where problem_id = :'problem'),
  5,
  'climbers read the community snapshot'
);
select is_empty(
  'select 1 from public.ascents where local_date < current_date - 1',
  'but never anybody''s raw ascents'
);

-- With fewer than five eligible climbers nothing is published at all.
select tests.as_owner();
update public.profiles set stats_opt_out = true
 where id in (select id from climbers where n in (1, 2));
select private.refresh_problem_stats();
select is_empty(
  format('select 1 from public.problem_stats where problem_id = %L', :'problem'),
  'a problem with fewer than 5 eligible climbers has no published statistics'
);

select * from finish();
rollback;
