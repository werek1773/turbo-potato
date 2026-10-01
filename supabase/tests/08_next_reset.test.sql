begin;
\ir _helpers.inc
select no_plan();

select tests.create_user('owner@example.com') as owner \gset
select tests.create_user('setter@example.com') as setter \gset
select tests.create_user('climber@example.com') as climber \gset
select tests.make_platform_admin(:'owner');
select tests.gym_id('volt-lodz') as volt \gset
select tests.today(:'volt') as today \gset

select tests.authenticate_as(:'owner');
select public.admin_set_gym_role(:'volt', :'setter', 'routesetter');
select public.set_gym_published(:'volt', true);
insert into public.sectors (gym_id, name) values (:'volt', 'Połóg') returning id as sector \gset

select tests.authenticate_as(:'setter');
select lives_ok(
  format('select public.set_next_reset(%L, %L)', :'sector', :'today'::date + 1),
  'a routesetter announces the next reset'
);
select throws_ok(
  format('select public.set_next_reset(%L, %L)', :'sector', :'today'::date - 1),
  'P0001', 'date_in_past',
  'the announced date cannot be in the past'
);

select tests.authenticate_as(:'climber');
select is(
  (select next_reset_on from public.sectors where id = :'sector'),
  :'today'::date + 1,
  'climbers see the announced date'
);
select throws_ok(
  format('select public.set_next_reset(%L, null)', :'sector'),
  '42501', 'forbidden',
  'climbers cannot change it'
);
select throws_ok(
  format('update public.sectors set next_reset_on = null where id = %L', :'sector'),
  '42501', null,
  'not even with a plain update'
);

-- Doing the reset clears the announcement.
select tests.upload_sector_photo(:'volt', :'sector') as path1 \gset
select tests.upload_sector_photo(:'volt', :'sector') as path2 \gset
select tests.grade_id(:'volt', '4') as grade \gset
select tests.authenticate_as(:'setter');
select public.reset_sector(:'sector', null, :'path1', 100, 100);
select current_photo_id as photo from public.sectors where id = :'sector' \gset
select public.add_problem(:'sector', :'photo', 0.5, 0.5, :'grade', 'red') as problem \gset
select is(
  (select next_reset_on from public.sectors where id = :'sector'),
  :'today'::date + 1,
  'a first photo is not a reset'
);
select public.reset_sector(:'sector', :'photo', :'path2', 100, 100, array[:'problem']::uuid[]);
select is(
  (select next_reset_on from public.sectors where id = :'sector'),
  null,
  'the reset clears the announced date'
);

select tests.as_owner();
select * from finish();
rollback;
