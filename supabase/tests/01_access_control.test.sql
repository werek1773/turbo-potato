begin;
\ir _helpers.inc
select no_plan();

-- -----------------------------------------------------------------------------
-- Structural guarantees
-- -----------------------------------------------------------------------------
select is_empty(
  $$ select c.relname
       from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname in ('public', 'private') and c.relkind = 'r' and not c.relrowsecurity $$,
  'every table in public and private has row level security enabled'
);

select is_empty(
  $$ select c.relname
       from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relkind in ('r', 'v')
        and (has_table_privilege('anon', c.oid, 'select')
          or has_table_privilege('anon', c.oid, 'insert')
          or has_table_privilege('anon', c.oid, 'update')
          or has_table_privilege('anon', c.oid, 'delete')) $$,
  'anon has no table privileges in public'
);

select is_empty(
  $$ select p.oid::regprocedure::text
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname in ('public', 'private')
        and has_function_privilege('anon', p.oid, 'execute') $$,
  'anon cannot execute any function in public or private'
);

select is_empty(
  $$ select c.relname
       from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'private' and c.relkind = 'r'
        and (has_table_privilege('authenticated', c.oid, 'select')
          or has_table_privilege('authenticated', c.oid, 'insert')
          or has_table_privilege('authenticated', c.oid, 'update')
          or has_table_privilege('authenticated', c.oid, 'delete')) $$,
  'authenticated has no access to private tables (platform admins, invite bookkeeping)'
);

select is_empty(
  $$ select p.oid::regprocedure::text
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname in ('public', 'private')
        and p.prosecdef
        and not exists (
          select 1 from unnest(coalesce(p.proconfig, '{}')) cfg
          where cfg like 'search_path=%'
        ) $$,
  'every security definer function pins its search_path'
);

select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'stats_opt_out', 'update')
  and not has_column_privilege('authenticated', 'public.profiles', 'health_data_consent_at', 'update')
  and has_column_privilege('authenticated', 'public.profiles', 'display_name', 'update'),
  'clients may edit their display name only; consents change through RPCs'
);

select ok(
  not has_column_privilege('authenticated', 'public.invites', 'code_hash', 'select'),
  'invite code hashes are never readable by clients'
);

select ok(
  not has_column_privilege('authenticated', 'public.problems', 'gym_id', 'update')
  and not has_column_privilege('authenticated', 'public.problems', 'sector_id', 'update')
  and not has_column_privilege('authenticated', 'public.problems', 'removed_at', 'update'),
  'problems cannot be moved to another gym/sector or removed by a plain update'
);

-- -----------------------------------------------------------------------------
-- Profiles
-- -----------------------------------------------------------------------------
select tests.create_user('ala@example.com', 'Ala Wspinaczka') as ala \gset
select tests.create_user('bartek@example.com') as bartek \gset

select is(
  (select display_name from public.profiles where id = :'ala'),
  'Ala Wspinaczka',
  'a profile is created with the name from Sign in with Apple'
);
select is(
  (select display_name from public.profiles where id = :'bartek'),
  'Wspinacz',
  'a profile without a name gets the default display name'
);

select tests.authenticate_as(:'ala');

select results_eq(
  'select id from public.profiles',
  format('values (%L::uuid)', :'ala'),
  'a user sees only their own profile'
);

update public.profiles set display_name = 'Ala' where id = :'bartek';
update public.profiles set display_name = 'Ala' where id = :'ala';

select throws_ok(
  format('update public.profiles set stats_opt_out = true where id = %L', :'ala'),
  '42501',
  null,
  'consent flags cannot be changed with a plain update'
);

select tests.as_owner();
select is(
  (select display_name from public.profiles where id = :'bartek'),
  'Wspinacz',
  'a user cannot rename somebody else'
);
select is(
  (select display_name from public.profiles where id = :'ala'),
  'Ala',
  'a user can rename themselves'
);

-- -----------------------------------------------------------------------------
-- Platform admin cannot be self-granted
-- -----------------------------------------------------------------------------
select tests.authenticate_as(:'ala');

select throws_ok(
  format('insert into private.platform_admins (user_id) values (%L)', :'ala'),
  '42501',
  null,
  'a user cannot make themselves a platform admin'
);

select throws_ok(
  $$ select public.admin_create_gym('hack', 'Hack Gym') $$,
  '42501',
  'forbidden',
  'only platform admins create gyms'
);

-- -----------------------------------------------------------------------------
-- Anonymous visitors see nothing
-- -----------------------------------------------------------------------------
select tests.authenticate_as_anon();

select throws_ok(
  'select count(*) from public.gyms',
  '42501',
  null,
  'anon cannot read gyms'
);

select throws_ok(
  $$ select public.accept_invite('AAAA-BBBB-CCCC') $$,
  '42501',
  null,
  'anon cannot call RPCs'
);

select tests.as_owner();
select * from finish();
rollback;
