begin;
\ir _helpers.inc
select no_plan();

select tests.create_user('kasia@example.com') as kasia \gset
select tests.create_user('owner@example.com') as owner \gset
select tests.make_platform_admin(:'owner');
select tests.gym_id('volt-lodz') as volt \gset

select tests.authenticate_as(:'owner');
select public.admin_set_gym_role(:'volt', :'kasia', 'manager');

select tests.authenticate_as(:'kasia');
select lives_ok(
  format($$ insert into public.sectors (gym_id, name, area, sort_order) values (%L, 'Slab', 'Mała sala', 1) $$, :'volt'),
  'managers create sectors inside an area'
);
select lives_ok(
  format($$ update public.sectors set area = 'Duża sala' where gym_id = %L $$, :'volt'),
  'managers move sectors between areas'
);
select results_eq(
  'select area from public.sectors',
  $$ values ('Duża sala') $$,
  'the area is stored'
);
select throws_ok(
  format($$ insert into public.sectors (gym_id, name, area) values (%L, 'X', '  ') $$, :'volt'),
  '23514', null,
  'blank area names are rejected'
);

select tests.as_owner();
select * from finish();
rollback;
