begin;
\ir _helpers.inc
select no_plan();

-- Cast -------------------------------------------------------------------------
select tests.create_user('owner@example.com', 'Owner') as owner \gset
select tests.create_user('kasia@example.com', 'Kasia') as kasia \gset
select tests.create_user('setter@example.com', 'Setter') as setter \gset
select tests.create_user('climber@example.com', 'Climber') as climber \gset
select tests.create_user('rival@example.com', 'Rival setter') as rival \gset
select tests.make_platform_admin(:'owner');
select tests.gym_id('volt-lodz') as volt \gset

select tests.authenticate_as(:'owner');
select public.admin_create_gym('other-gym', 'Other Gym', 'Kraków') as other \gset
select public.admin_set_gym_role(:'volt', :'kasia', 'manager');
select public.admin_set_gym_role(:'volt', :'setter', 'routesetter');
select public.admin_set_gym_role(:'other', :'rival', 'routesetter');
select public.set_gym_published(:'volt', true);

select tests.grade_id(:'volt', '4') as volt_4 \gset
select tests.grade_id(:'volt', '5') as volt_5 \gset

select tests.authenticate_as(:'kasia');
insert into public.sectors (gym_id, name, sort_order) values (:'volt', 'Grota', 1);
select id as grota from public.sectors where name = 'Grota' \gset

select tests.authenticate_as(:'setter');
select public.reset_sector(:'grota', null, tests.upload_sector_photo(:'volt', :'grota'), 2560, 1920);
select current_photo_id as photo1 from public.sectors where id = :'grota' \gset

-- Auto holds -------------------------------------------------------------------
select is(
  public.replace_auto_holds(:'photo1', jsonb_build_array(
    jsonb_build_object('id', 'bbbbbbbb-0000-4000-8000-000000000001', 'x', 0.20, 'y', 0.80, 'r', 0.02, 'color', 'green'),
    jsonb_build_object('id', 'bbbbbbbb-0000-4000-8000-000000000002', 'x', 0.30, 'y', 0.60, 'r', 0.02, 'color', 'green'),
    jsonb_build_object('id', 'bbbbbbbb-0000-4000-8000-000000000003', 'x', 0.40, 'y', 0.20, 'r', 0.03, 'color', 'green'),
    jsonb_build_object('id', 'bbbbbbbb-0000-4000-8000-000000000004', 'x', 0.70, 'y', 0.70, 'r', 0.02, 'color', 'red'),
    jsonb_build_object('id', 'bbbbbbbb-0000-4000-8000-000000000005', 'x', 0.75, 'y', 0.75, 'r', 0.02)
  )),
  5,
  'a routesetter stores detected holds'
);
select 'bbbbbbbb-0000-4000-8000-000000000001' as h1 \gset
select 'bbbbbbbb-0000-4000-8000-000000000002' as h2 \gset
select 'bbbbbbbb-0000-4000-8000-000000000003' as h3 \gset
select 'bbbbbbbb-0000-4000-8000-000000000004' as h4 \gset
select 'bbbbbbbb-0000-4000-8000-000000000005' as h5 \gset

select throws_ok(
  format($$ select public.replace_auto_holds(%L, '[{"x": 1.5, "y": 0.5, "r": 0.02}]') $$, :'photo1'),
  '23514', null,
  'holds must lie on the photo'
);
select throws_ok(
  format($$ select public.replace_auto_holds(%L, '[{"x": 0.5, "y": 0.5, "r": 0.02, "color": "teal"}]') $$, :'photo1'),
  'P0001', 'invalid_holds',
  'unknown colors are rejected'
);

select tests.authenticate_as(:'rival');
select throws_ok(
  format($$ select public.replace_auto_holds(%L, '[]') $$, :'photo1'),
  '42501', 'forbidden',
  'staff of another gym cannot store holds'
);
select tests.authenticate_as(:'climber');
select throws_ok(
  format($$ select public.replace_auto_holds(%L, '[]') $$, :'photo1'),
  '42501', 'forbidden',
  'climbers cannot store holds'
);
select is(
  (select count(*)::int from public.photo_holds where photo_id = :'photo1'),
  5,
  'climbers see the holds of a published gym'
);
select throws_ok(
  format($$ insert into public.photo_holds (photo_id, sector_id, gym_id, x, y, r) values (%L, %L, %L, 0.5, 0.5, 0.02) $$,
         :'photo1', :'grota', :'volt'),
  '42501', null,
  'holds are written only through the RPCs'
);

-- A problem with its route -----------------------------------------------------
select tests.authenticate_as(:'setter');
select public.add_problem(:'grota', :'photo1', 0.5, 0.5, :'volt_4', 'green', '{}', null, null,
  jsonb_build_array(
    jsonb_build_object('hold_id', :'h1', 'role', 'start'),
    jsonb_build_object('hold_id', :'h2', 'role', 'hand'),
    jsonb_build_object('hold_id', :'h3', 'role', 'top')
  )) as p1 \gset

select results_eq(
  format($$ select hold_id, role::text from public.current_routes where problem_id = %L order by hold_id $$, :'p1'),
  format($$ values (%L::uuid, 'start'), (%L::uuid, 'hand'), (%L::uuid, 'top') $$, :'h1', :'h2', :'h3'),
  'the route is stored with the problem'
);
select results_eq(
  format($$ select round(pin_x::numeric, 2), round(pin_y::numeric, 2) from public.active_problems where id = %L $$, :'p1'),
  $$ values (0.20, 0.80) $$,
  'the pin moves to the start hold'
);
select is(
  (select changed_at from public.active_problems where id = :'p1'),
  null,
  'a new problem is not marked as changed'
);

-- Validation
select throws_ok(
  format($$ select public.set_problem_route(%L, %L, %L) $$, :'p1', :'photo1',
         jsonb_build_array(jsonb_build_object('hold_id', :'h2', 'role', 'hand'))),
  'P0001', 'invalid_route_roles',
  'a route needs a start hold'
);
select throws_ok(
  format($$ select public.set_problem_route(%L, %L, %L) $$, :'p1', :'photo1',
         jsonb_build_array(
           jsonb_build_object('hold_id', :'h1', 'role', 'start'),
           jsonb_build_object('hold_id', :'h2', 'role', 'start'),
           jsonb_build_object('hold_id', :'h3', 'role', 'start'))),
  'P0001', 'invalid_route_roles',
  'at most two start holds'
);
select throws_ok(
  format($$ select public.set_problem_route(%L, %L, %L) $$, :'p1', :'photo1',
         jsonb_build_array(
           jsonb_build_object('hold_id', :'h1', 'role', 'start'),
           jsonb_build_object('hold_id', :'h1', 'role', 'top'))),
  'P0001', 'invalid_route',
  'a hold is used once per route'
);
select throws_ok(
  format($$ select public.set_problem_route(%L, %L, %L) $$, :'p1', :'photo1',
         jsonb_build_array(jsonb_build_object('hold_id', :'h1', 'role', 'heel'))),
  'P0001', 'invalid_route',
  'unknown roles are rejected'
);
select throws_ok(
  format($$ select public.set_problem_route(%L, %L, %L) $$, :'p1', :'photo1',
         jsonb_build_array(jsonb_build_object('hold_id', gen_random_uuid(), 'role', 'start'))),
  'P0001', 'unknown_hold',
  'holds must be on the current photo'
);

select tests.authenticate_as(:'climber');
select throws_ok(
  format($$ select public.set_problem_route(%L, %L, '[]') $$, :'p1', :'photo1'),
  '42501', 'forbidden',
  'climbers cannot change routes'
);
select tests.authenticate_as(:'rival');
select throws_ok(
  format($$ select public.set_problem_route(%L, %L, '[]') $$, :'p1', :'photo1'),
  '42501', 'forbidden',
  'staff of another gym cannot change routes'
);

-- Holds in use
select tests.authenticate_as(:'setter');
select throws_ok(
  format($$ select public.delete_photo_hold(%L) $$, :'h2'),
  'P0001', 'hold_in_use',
  'a hold used by a route cannot be deleted'
);
select lives_ok(
  format($$ select public.delete_photo_hold(%L) $$, :'h5'),
  'an unused hold can be deleted'
);
select is(
  public.upsert_photo_hold(:'h4', :'photo1', 0.71, 0.69, 0.025, 'orange'),
  :'h4'::uuid,
  'a hold can be fixed by hand'
);
select results_eq(
  format($$ select source::text, color::text from public.photo_holds where id = %L $$, :'h4'),
  $$ values ('manual', 'orange') $$,
  'a fixed hold becomes manual'
);
select public.upsert_photo_hold(null, :'photo1', 0.10, 0.10, 0.02, 'green') as h6 \gset

select is(
  public.replace_auto_holds(:'photo1', '[{"x": 0.9, "y": 0.9, "r": 0.02, "color": "blue"}]'),
  1,
  'detecting again stores the new holds'
);
select set_eq(
  format($$ select id from public.photo_holds where photo_id = %L and id in (%L, %L, %L, %L, %L) $$,
         :'photo1', :'h1', :'h2', :'h3', :'h4', :'h6'),
  format($$ values (%L::uuid), (%L::uuid), (%L::uuid), (%L::uuid), (%L::uuid) $$, :'h1', :'h2', :'h3', :'h4', :'h6'),
  'detecting again keeps holds used by routes and manual holds'
);

-- Freshness --------------------------------------------------------------------
select public.set_problem_route(:'p1', :'photo1',
  jsonb_build_array(
    jsonb_build_object('hold_id', :'h1', 'role', 'start'),
    jsonb_build_object('hold_id', :'h2', 'role', 'hand'),
    jsonb_build_object('hold_id', :'h3', 'role', 'top')
  ));
select is(
  (select changed_at from public.active_problems where id = :'p1'),
  null,
  'saving the same route is not a change'
);

select public.set_problem_route(:'p1', :'photo1',
  jsonb_build_array(
    jsonb_build_object('hold_id', :'h1', 'role', 'start'),
    jsonb_build_object('hold_id', :'h6', 'role', 'hand'),
    jsonb_build_object('hold_id', :'h3', 'role', 'top')
  ));
select is(
  (select change_kind from public.active_problems where id = :'p1'),
  'route',
  'a changed route marks the problem'
);

update public.problems set grade_id = :'volt_5' where id = :'p1';
select is(
  (select change_kind from public.active_problems where id = :'p1'),
  'both',
  'a regrade right after a route change reads as both'
);

-- A legacy problem gets its first route: not a change for climbers.
select public.add_problem(:'grota', :'photo1', 0.7, 0.7, :'volt_4', 'orange') as p2 \gset
select public.set_problem_route(:'p2', :'photo1',
  jsonb_build_array(jsonb_build_object('hold_id', :'h4', 'role', 'start')));
select is(
  (select changed_at from public.active_problems where id = :'p2'),
  null,
  'a first route on an existing problem is not a change'
);
select is(
  (select count(*)::int from public.current_routes where problem_id = :'p2'),
  1,
  'the first route is visible'
);

select tests.authenticate_as(:'climber');
select throws_ok(
  format($$ update public.problems set changed_at = now(), change_kind = 'grade' where id = %L $$, :'p2'),
  '42501', null,
  'clients cannot set freshness themselves'
);

-- Reset: archive and carry-over -------------------------------------------------
select tests.authenticate_as(:'setter');
select public.reset_sector(:'grota', :'photo1', tests.upload_sector_photo(:'volt', :'grota'), 2560, 1920, array[:'p2']::uuid[]);
select current_photo_id as photo2 from public.sectors where id = :'grota' \gset

select is(
  (select count(*)::int from public.current_routes where problem_id = :'p1'),
  0,
  'after a reset the route waits for the new photo'
);
select is(
  (select count(*)::int from public.problem_holds where problem_id = :'p1' and photo_id = :'photo1'),
  3,
  'the old photo keeps its route as an archive'
);
select throws_ok(
  format($$ select public.set_problem_route(%L, %L, '[]') $$, :'p1', :'photo1'),
  'P0001', 'stale_photo',
  'routes are set on the current photo only'
);
select throws_ok(
  format($$ select public.upsert_photo_hold(null, %L, 0.5, 0.5, 0.02, 'red') $$, :'photo1'),
  'P0001', 'stale_photo',
  'archived photos keep their holds'
);

select public.replace_auto_holds(:'photo2', jsonb_build_array(
  jsonb_build_object('id', 'cccccccc-0000-4000-8000-000000000001', 'x', 0.21, 'y', 0.79, 'r', 0.02, 'color', 'green'),
  jsonb_build_object('id', 'cccccccc-0000-4000-8000-000000000002', 'x', 0.41, 'y', 0.21, 'r', 0.03, 'color', 'green')
));
select public.set_problem_route(:'p1', :'photo2',
  jsonb_build_array(
    jsonb_build_object('hold_id', 'cccccccc-0000-4000-8000-000000000001', 'role', 'start'),
    jsonb_build_object('hold_id', 'cccccccc-0000-4000-8000-000000000002', 'role', 'top')
  ), true);
select is(
  (select count(*)::int from public.current_routes where problem_id = :'p1'),
  2,
  'the route is carried over to the new photo'
);
select is(
  (select change_kind from public.active_problems where id = :'p1'),
  'both',
  'carrying a route over does not touch freshness'
);

select throws_ok(
  format($$ select public.set_problem_route(%L, %L, '[]') $$, :'p2', :'photo2'),
  'P0001', 'problem_removed',
  'removed problems keep their route'
);

select * from finish();
rollback;
