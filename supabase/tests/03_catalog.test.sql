begin;
\ir _helpers.inc
select no_plan();

-- Cast and a second gym -------------------------------------------------------
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
select public.set_gym_published(:'other', true);

select tests.as_owner();
insert into public.grades (gym_id, label, sort_order) values (:'other', '6a', 1);
select tests.grade_id(:'volt', '4') as volt_4 \gset
select tests.grade_id(:'volt', '5') as volt_5 \gset
select tests.grade_id(:'other', '6a') as other_6a \gset

-- Sectors -----------------------------------------------------------------------
select tests.authenticate_as(:'setter');
select throws_ok(
  format($$ insert into public.sectors (gym_id, name) values (%L, 'Hack') $$, :'volt'),
  '42501', null,
  'routesetters do not create sectors'
);

select tests.authenticate_as(:'kasia');
insert into public.sectors (gym_id, name, sort_order) values (:'volt', 'Grota', 1);
select id as grota from public.sectors where name = 'Grota' \gset

select throws_ok(
  format($$ insert into public.sectors (gym_id, name) values (%L, 'Foreign') $$, :'other'),
  '42501', null,
  'a manager cannot create sectors in another gym'
);

-- Storage policy ----------------------------------------------------------------
select :'volt' || '/' || :'grota' || '/' || gen_random_uuid() || '.jpg' as good_path \gset

select tests.authenticate_as(:'setter');
select lives_ok(
  format($$ insert into storage.objects (bucket_id, name) values ('sector-photos', %L) $$, :'good_path'),
  'a routesetter uploads a sector photo into their gym'
);
select throws_ok(
  format($$ insert into storage.objects (bucket_id, name) values ('sector-photos', %L) $$,
         :'volt' || '/' || :'grota' || '/not-a-uuid.jpg'),
  '42501', null,
  'malformed object names are rejected'
);
select throws_ok(
  format($$ insert into storage.objects (bucket_id, name) values ('sector-photos', %L) $$,
         :'other' || '/' || :'grota' || '/' || gen_random_uuid() || '.jpg'),
  '42501', null,
  'a sector cannot be smuggled under another gym id'
);
-- Either RLS silently matches nothing or Supabase's storage guard raises:
-- both are fine, the object must survive.
do $$
begin
  begin
    update storage.objects set name = name || '.bak' where bucket_id = 'sector-photos';
  exception when others then null;
  end;
  begin
    delete from storage.objects where bucket_id = 'sector-photos';
  exception when others then null;
  end;
end;
$$;

select tests.authenticate_as(:'rival');
select throws_ok(
  format($$ insert into storage.objects (bucket_id, name) values ('sector-photos', %L) $$,
         :'volt' || '/' || :'grota' || '/' || gen_random_uuid() || '.jpg'),
  '42501', null,
  'staff of another gym cannot upload into Volt'
);

select tests.authenticate_as(:'climber');
select throws_ok(
  format($$ insert into storage.objects (bucket_id, name) values ('sector-photos', %L) $$,
         :'volt' || '/' || :'grota' || '/' || gen_random_uuid() || '.jpg'),
  '42501', null,
  'climbers cannot upload'
);

select tests.as_owner();
select is(
  (select count(*)::int from storage.objects where name = :'good_path'),
  1,
  'uploaded photos cannot be renamed or deleted by clients'
);

-- First photo of the sector ----------------------------------------------------
select tests.authenticate_as(:'setter');
select throws_ok(
  format($$ select public.add_problem(%L, null, 0.5, 0.5, %L, 'yellow') $$, :'grota', :'volt_4'),
  'P0001', 'sector_has_no_photo',
  'problems need a sector photo first'
);
select throws_ok(
  format($$ select public.reset_sector(%L, null, %L, 4000, 3000) $$,
         :'grota', :'volt' || '/' || :'grota' || '/' || gen_random_uuid() || '.jpg'),
  'P0001', 'photo_not_uploaded',
  'a photo must exist in storage before it is registered'
);
select throws_ok(
  format($$ select public.reset_sector(%L, null, %L, 4000, 3000) $$, :'grota', 'elsewhere/photo.jpg'),
  'P0001', 'invalid_photo_path',
  'photo paths must belong to the sector'
);

select public.reset_sector(:'grota', null, :'good_path', 4000, 3000) as first_reset \gset
select current_photo_id as photo1 from public.sectors where id = :'grota' \gset
select is(
  (select storage_path from public.sector_photos where id = :'photo1'),
  :'good_path',
  'the first photo becomes the current photo'
);

-- Problems ---------------------------------------------------------------------
select public.add_problem(:'grota', :'photo1', 0.2, 0.3, :'volt_4', 'yellow', '{overhang,crimps}', null,
                          'aaaaaaaa-0000-4000-8000-000000000001') as p1 \gset
select public.add_problem(:'grota', :'photo1', 0.6, 0.4, :'volt_5', 'blue') as p2 \gset

select is(
  public.add_problem(:'grota', :'photo1', 0.2, 0.3, :'volt_4', 'yellow', '{overhang,crimps}', null,
                     'aaaaaaaa-0000-4000-8000-000000000001'),
  'aaaaaaaa-0000-4000-8000-000000000001'::uuid,
  'adding a problem is idempotent for the app outbox'
);
select is(
  (select count(*)::int from public.problems where sector_id = :'grota'),
  2,
  'the retry did not create a duplicate'
);
select throws_ok(
  format($$ select public.add_problem(%L, %L, 0.5, 0.5, %L, 'red') $$, :'grota', :'photo1', :'other_6a'),
  'P0001', 'invalid_grade',
  'a grade of another gym is rejected'
);
select throws_ok(
  format($$ select public.add_problem(%L, %L, 1.5, 0.5, %L, 'red') $$, :'grota', :'photo1', :'volt_4'),
  '23514', null,
  'pins must lie on the photo'
);

select tests.authenticate_as(:'rival');
select throws_ok(
  format($$ select public.add_problem(%L, %L, 0.5, 0.5, %L, 'red') $$, :'grota', :'photo1', :'volt_4'),
  '42501', 'forbidden',
  'staff of another gym cannot add problems to Volt'
);

select tests.authenticate_as(:'climber');
select throws_ok(
  format($$ select public.add_problem(%L, %L, 0.5, 0.5, %L, 'red') $$, :'grota', :'photo1', :'volt_4'),
  '42501', 'forbidden',
  'climbers cannot add problems'
);
select results_eq(
  'select id from public.active_problems order by pin_x',
  format('values (%L::uuid), (%L::uuid)', :'p1', :'p2'),
  'climbers see active problems with pins on the current photo'
);
update public.problems set grade_id = :'volt_5' where id = :'p1';
select tests.as_owner();
select is(
  (select grade_id from public.problems where id = :'p1'),
  :'volt_4'::uuid,
  'climbers cannot regrade problems'
);

-- Regrading by staff is recorded -------------------------------------------------
select tests.authenticate_as(:'setter');
update public.problems set grade_id = :'volt_5' where id = :'p1';
select results_eq(
  'select old_grade_id, new_grade_id from public.problem_grade_history',
  format('values (%L::uuid, %L::uuid)', :'volt_4', :'volt_5'),
  'grade changes are kept in history'
);

select tests.as_owner();
update public.grades set is_active = false where id = :'volt_4';
select tests.authenticate_as(:'setter');
select throws_ok(
  format('update public.problems set grade_id = %L where id = %L', :'volt_4', :'p1'),
  'P0001', 'invalid_grade',
  'a deactivated grade cannot be assigned'
);
select throws_ok(
  format('update public.problems set gym_id = %L where id = %L', :'other', :'p1'),
  '42501', null,
  'a problem cannot be moved to another gym'
);

-- Pins and single removals ----------------------------------------------------------
select public.move_problem_pin(:'p2', 0.65, 0.45);
select is(
  (select pin_x from public.active_problems where id = :'p2'),
  0.65::real,
  'staff move pins on the current photo'
);

select public.set_problem_removed(:'p2', true);
select is_empty(
  format('select 1 from public.active_problems where id = %L', :'p2'),
  'a removed problem disappears from the catalog'
);
select public.set_problem_removed(:'p2', false);
select isnt_empty(
  format('select 1 from public.active_problems where id = %L', :'p2'),
  'an accidental removal can be undone'
);

-- Reset: one problem goes, one stays -------------------------------------------------
select tests.upload_sector_photo(:'volt', :'grota') as path2 \gset

select tests.authenticate_as(:'setter');
select throws_ok(
  format($$ select public.reset_sector(%L, null, %L, 4000, 3000, array[%L]::uuid[]) $$, :'grota', :'path2', :'p1'),
  'P0001', 'stale_photo',
  'a reset based on an outdated photo is rejected'
);
select throws_ok(
  format($$ select public.reset_sector(%L, %L, %L, 4000, 3000, array[%L]::uuid[]) $$,
         :'grota', :'photo1', :'path2', gen_random_uuid()),
  'P0001', 'unknown_problem',
  'unknown problem ids abort the whole reset'
);
select is(
  (select current_photo_id from public.sectors where id = :'grota'),
  :'photo1'::uuid,
  'an aborted reset changes nothing'
);

select public.reset_sector(:'grota', :'photo1', :'path2', 4000, 3000, array[:'p1']::uuid[], 'Przykrętka') as reset2 \gset
select current_photo_id as photo2 from public.sectors where id = :'grota' \gset

select results_eq(
  'select id from public.active_problems',
  format('values (%L::uuid)', :'p2'),
  'after the reset only the surviving problem is active'
);
select is(
  (select photo_id from public.active_problems where id = :'p2'),
  :'photo2'::uuid,
  'the survivor''s pin was carried onto the new photo'
);
select is(
  (select count(*)::int from public.problem_placements where photo_id = :'photo1'),
  2,
  'the archived photo keeps both of its pins'
);
select results_eq(
  format('select removed_reset_id, removed_count from public.problems p join public.sector_resets r on r.id = p.removed_reset_id where p.id = %L', :'p1'),
  format('values (%L::uuid, 1)', :'reset2'),
  'the removed problem points at the reset that took it down'
);
select isnt(
  (select last_reset_at from public.sectors where id = :'grota'),
  null,
  'the sector remembers when it was last reset'
);
select throws_ok(
  format('select public.set_problem_removed(%L, false)', :'p1'),
  'P0001', 'cannot_restore',
  'a problem taken down by a reset cannot be restored onto the new photo'
);

select public.add_problem(:'grota', :'photo2', 0.1, 0.1, :'volt_5', 'green') as p3 \gset
select is(
  (select set_reset_id from public.problems where id = :'p3'),
  :'reset2'::uuid,
  'new problems remember the reset they were set in'
);
select throws_ok(
  format($$ select public.add_problem(%L, %L, 0.5, 0.5, %L, 'red') $$, :'grota', :'photo1', :'volt_5'),
  'P0001', 'stale_photo',
  'adding a pin to an outdated photo is rejected'
);

-- Archived sectors ----------------------------------------------------------------
select tests.authenticate_as(:'kasia');
update public.sectors set archived_at = now() where id = :'grota';
select tests.authenticate_as(:'setter');
select throws_ok(
  format($$ select public.add_problem(%L, %L, 0.5, 0.5, %L, 'red') $$, :'grota', :'photo2', :'volt_5'),
  'P0001', 'sector_archived',
  'archived sectors take no new problems'
);

select tests.as_owner();
select * from finish();
rollback;
