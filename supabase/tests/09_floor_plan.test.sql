begin;
\ir _helpers.inc
select no_plan();

select tests.create_user('owner@example.com') as owner \gset
select tests.create_user('kasia@example.com') as kasia \gset
select tests.create_user('climber@example.com') as climber \gset
select tests.make_platform_admin(:'owner');
select tests.gym_id('volt-lodz') as volt \gset

select tests.authenticate_as(:'owner');
select public.admin_set_gym_role(:'volt', :'kasia', 'manager');
select public.set_gym_published(:'volt', true);

select tests.authenticate_as(:'kasia');
select lives_ok(
  format($$ update public.gyms set floor_plan = '{"aspect": 0.75, "walls": []}' where id = %L $$, :'volt'),
  'managers draw the floor plan'
);
select lives_ok(
  format($$ insert into public.sectors (gym_id, name, map_path) values (%L, 'Połóg', '[[0.1,0.2],[0.3,0.2]]') $$, :'volt'),
  'sectors get their stretch of wall on the plan'
);
select throws_ok(
  format($$ update public.sectors set map_path = '{"x": 1}' where gym_id = %L $$, :'volt'),
  '23514', null,
  'a map path must be an array of points'
);

select tests.authenticate_as(:'climber');
select is(
  (select (floor_plan ->> 'aspect')::numeric from public.gyms where id = :'volt'),
  0.75,
  'climbers read the plan'
);
update public.gyms set floor_plan = null where id = :'volt';
select tests.as_owner();
select isnt(
  (select floor_plan from public.gyms where id = :'volt'),
  null,
  'climbers cannot change the plan'
);

select * from finish();
rollback;
