begin;
\ir _helpers.inc
select no_plan();

-- Setup: published Volt with one sector, two problems -------------------------
select tests.create_user('owner@example.com', 'Owner') as owner \gset
select tests.create_user('setter@example.com', 'Setter') as setter \gset
select tests.create_user('ala@example.com', 'Ala') as ala \gset
select tests.create_user('bartek@example.com', 'Bartek') as bartek \gset
select tests.make_platform_admin(:'owner');
select tests.gym_id('volt-lodz') as volt \gset
select tests.grade_id(:'volt', '4') as volt_4 \gset

select tests.authenticate_as(:'owner');
select public.admin_set_gym_role(:'volt', :'setter', 'routesetter');
select public.set_gym_published(:'volt', true);
insert into public.sectors (gym_id, name) values (:'volt', 'Płyta') returning id as sector \gset

select tests.upload_sector_photo(:'volt', :'sector') as path \gset
select tests.authenticate_as(:'setter');
select public.reset_sector(:'sector', null, :'path', 3000, 2000);
select current_photo_id as photo from public.sectors where id = :'sector' \gset
select public.add_problem(:'sector', :'photo', 0.3, 0.3, :'volt_4', 'yellow') as p1 \gset
select public.add_problem(:'sector', :'photo', 0.6, 0.6, :'volt_4', 'red') as p2 \gset

-- Problems were set 10 days ago so that older sessions can be logged.
select tests.as_owner();
update public.problems set set_at = now() - interval '10 days' where gym_id = :'volt';
select tests.today(:'volt') as today \gset

-- Logging ascents after the session -----------------------------------------------
select tests.authenticate_as(:'ala');

select throws_ok(
  format($$ insert into public.ascents (user_id, gym_id, problem_id, local_date, result, grade_id_snapshot)
            values (%L, %L, %L, %L, 'top', %L) $$, :'ala', :'volt', :'p1', :'today', :'volt_4'),
  '42501', null,
  'ascents are written through RPCs only'
);

select public.set_ascent(:'p1', :'today', 'top', '2-3') as a1 \gset
select is(
  (select count(*)::int from public.sessions where local_date = :'today'),
  1,
  'logging an ascent creates the session of that day'
);
select is(
  (select grade_id_snapshot from public.ascents where id = :'a1'),
  :'volt_4'::uuid,
  'the ascent remembers the grade at logging time'
);

select is(
  public.set_ascent(:'p1', :'today', 'project', '4-10', 'hard', '{finger_strength}'),
  :'a1'::uuid,
  'tapping the pin again updates the same record (idempotent upsert)'
);
select results_eq(
  'select result::text, attempts::text, limiters::text from public.ascents',
  $$ values ('project', '4-10', '{finger_strength}') $$,
  'the record holds the latest state'
);

select is(
  public.set_ascent(:'p1', :'today', null),
  null,
  'a null result clears the record'
);
select is_empty('select 1 from public.ascents', 'the record is gone');
select is(
  (select count(*)::int from public.sessions),
  1,
  'the session itself stays (it may hold wellbeing or a visit)'
);

select throws_ok(
  format($$ select public.set_ascent(%L, %L, 'flash', '2-3') $$, :'p1', :'today'),
  '23514', null,
  'a flash cannot take several attempts'
);
select throws_ok(
  format($$ select public.set_ascent(%L, %L, 'top') $$, :'p1', (:'today'::date + 1)),
  'P0001', 'future_date',
  'ascents cannot be logged for future days'
);
select throws_ok(
  format($$ select public.set_ascent(%L, %L, 'top') $$, :'p1', (:'today'::date - 30)),
  'P0001', 'before_problem_set',
  'ascents cannot predate the problem'
);

-- Flash rules -----------------------------------------------------------------------
select public.set_ascent(:'p2', :'today', 'flash');
select results_eq(
  format('select result::text from public.ascents where problem_id = %L', :'p2'),
  $$ values ('flash') $$,
  'a first logged ascent can be a flash'
);

select public.set_ascent(:'p2', (:'today'::date - 2), 'project', '4-10');
select results_eq(
  format('select local_date - %L::date, result::text from public.ascents where problem_id = %L order by local_date', :'today', :'p2'),
  $$ values (-2, 'project'), (0, 'top') $$,
  'logging an earlier attempt afterwards demotes the later flash to a top'
);
select throws_ok(
  format($$ select public.set_ascent(%L, %L, 'flash') $$, :'p2', :'today'),
  'P0001', 'flash_not_first_attempt',
  'a flash is impossible after an earlier attempt'
);

-- Removed problems ------------------------------------------------------------------
select tests.as_owner();
update public.problems set removed_at = now() - interval '3 days' where id = :'p1';
select tests.authenticate_as(:'ala');
select throws_ok(
  format($$ select public.set_ascent(%L, %L, 'top') $$, :'p1', :'today'),
  'P0001', 'problem_removed',
  'a problem cannot be logged after it was taken down'
);
select lives_ok(
  format($$ select public.set_ascent(%L, %L, 'top') $$, :'p1', (:'today'::date - 4)),
  'sessions before the removal can still be completed later'
);

-- Privacy ---------------------------------------------------------------------------
select tests.authenticate_as(:'bartek');
select is_empty('select 1 from public.ascents', 'other climbers cannot see my ascents');
select is_empty('select 1 from public.sessions', 'other climbers cannot see my sessions');
delete from public.ascents;
select tests.as_owner();
select is(
  (select count(*)::int from public.ascents where user_id = :'ala'),
  3,
  'other climbers cannot delete my ascents'
);

-- Sessions merge visit times ------------------------------------------------------------
select tests.authenticate_as(:'ala');
select public.upsert_session(:'volt', :'today', now() - interval '2 hours', now() - interval '1 hour', 'geofence') as s1 \gset
select is(
  public.upsert_session(:'volt', :'today', now() - interval '3 hours', now() - interval '90 minutes', 'manual', 'Dobra sesja'),
  :'s1'::uuid,
  'two devices converge on one session per climbing day'
);
select results_eq(
  format($$ select started_at = now() - interval '3 hours', ended_at = now() - interval '1 hour', source::text, note
              from public.sessions where id = %L $$, :'s1'),
  $$ values (true, true, 'geofence', 'Dobra sesja') $$,
  'visit times only widen and a geofence visit is remembered'
);

-- Wellbeing requires explicit consent ---------------------------------------------------
select throws_ok(
  format($$ select public.set_session_wellbeing(%L, 4, 7, 'ok', '{fingers}') $$, :'s1'),
  'P0001', 'health_consent_required',
  'no health data without explicit consent'
);
select public.set_health_data_consent(true);
select lives_ok(
  format($$ select public.set_session_wellbeing(%L, 4, 7, 'ok', '{fingers}') $$, :'s1'),
  'with consent wellbeing is stored'
);

select tests.authenticate_as(:'bartek');
select public.set_health_data_consent(true);
select throws_ok(
  format($$ select public.set_session_wellbeing(%L, 1, 1) $$, :'s1'),
  'P0001', 'not_found',
  'nobody can attach wellbeing to somebody else''s session'
);
select is_empty('select 1 from public.session_wellbeing', 'wellbeing of others is invisible');

select tests.authenticate_as(:'ala');
select public.set_health_data_consent(false);
select is_empty('select 1 from public.session_wellbeing', 'withdrawing consent deletes stored wellbeing');
select is(
  (select health_data_consent_at from public.profiles where id = auth.uid()),
  null,
  'consent is withdrawn'
);

-- Export -------------------------------------------------------------------------------
select is(
  jsonb_array_length(public.export_my_data() -> 'ascents'),
  3,
  'the export contains all my ascents'
);
select tests.authenticate_as(:'bartek');
select is(
  jsonb_array_length(public.export_my_data() -> 'ascents'),
  0,
  'the export never contains other people''s data'
);

-- Deleting a session removes its ascents -------------------------------------------------
select tests.authenticate_as(:'ala');
delete from public.sessions where local_date = :'today'::date - 2;
select is(
  (select count(*)::int from public.ascents),
  2,
  'deleting a session deletes its ascents'
);

-- Unpublished gyms ------------------------------------------------------------------------
select tests.authenticate_as(:'owner');
select public.set_gym_published(:'volt', false);
select tests.authenticate_as(:'bartek');
select throws_ok(
  format($$ select public.set_ascent(%L, %L, 'top') $$, :'p2', :'today'),
  '42501', 'forbidden',
  'climbers cannot log ascents in an unpublished gym'
);

-- Account deletion -------------------------------------------------------------------------
select tests.as_owner();
delete from auth.users where id = :'ala';
select is(
  (select count(*)::int from public.ascents where user_id = :'ala')
  + (select count(*)::int from public.sessions where user_id = :'ala')
  + (select count(*)::int from public.profiles where id = :'ala'),
  0,
  'deleting an account deletes the whole journal'
);

delete from auth.users where id = :'setter';
select is(
  (select count(*)::int from public.problems where set_by is null and gym_id = :'volt'),
  2,
  'deleting a routesetter keeps the gym catalog'
);

select * from finish();
rollback;
