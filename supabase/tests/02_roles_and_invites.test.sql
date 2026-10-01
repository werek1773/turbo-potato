begin;
\ir _helpers.inc
select no_plan();

-- Cast ------------------------------------------------------------------------
select tests.create_user('owner@example.com', 'Owner') as owner \gset
select tests.create_user('kasia@example.com', 'Kasia') as kasia \gset
select tests.create_user('setter@example.com', 'Setter') as setter \gset
select tests.create_user('setter2@example.com', 'Setter Two') as setter2 \gset
select tests.create_user('climber@example.com', 'Climber') as climber \gset
select tests.make_platform_admin(:'owner');
select tests.gym_id('volt-lodz') as volt \gset

-- Gym visibility before publishing --------------------------------------------
select tests.authenticate_as(:'climber');
select is_empty('select id from public.gyms', 'an unpublished gym is invisible to climbers');
select is_empty('select id from public.grades', 'grades of an unpublished gym are invisible too');

select tests.authenticate_as(:'owner');
select results_eq(
  'select slug from public.gyms',
  $$ values ('volt-lodz') $$,
  'platform admins see unpublished gyms'
);
select is(
  (select count(*)::int from public.grades where gym_id = tests.gym_id('volt-lodz')),
  9,
  'Volt has grades 1-9'
);

-- Manager appointment through an admin-created invite -------------------------
select tests.authenticate_as(:'kasia');
select throws_ok(
  format($$ select * from public.create_invite(%L, 'manager') $$, :'volt'),
  '42501', 'forbidden',
  'nobody but a platform admin can create manager invites'
);

select tests.authenticate_as(:'owner');
select code as manager_code from public.create_invite(:'volt', 'manager') \gset
select ok(:'manager_code' ~ '^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$',
  'invite codes are 12 Crockford base32 symbols');

select tests.authenticate_as(:'kasia');
select is(
  public.accept_invite(lower(replace(:'manager_code', '-', ' ')))->>'status',
  'ok',
  'codes are accepted case- and separator-insensitively'
);
select results_eq(
  'select role::text from public.gym_memberships where user_id = auth.uid()',
  $$ values ('manager') $$,
  'Kasia became the manager of Volt'
);
select is(
  public.accept_invite(:'manager_code')->>'status',
  'invalid',
  'a single-use invite cannot be used twice'
);

-- Routesetter invites -----------------------------------------------------------
select code as setter_code from public.create_invite(:'volt', 'routesetter', 2) \gset

select tests.authenticate_as(:'setter');
select is(public.accept_invite(:'setter_code')->>'role', 'routesetter', 'a setter joins with the invite');
select is(public.accept_invite(:'setter_code')->>'status', 'invalid', 'the same person cannot redeem an invite twice');
select throws_ok(
  format($$ select * from public.create_invite(%L, 'routesetter') $$, :'volt'),
  '42501', 'forbidden',
  'routesetters cannot invite'
);
select results_eq(
  'select slug from public.gyms',
  $$ values ('volt-lodz') $$,
  'staff see their unpublished gym'
);

select tests.authenticate_as(:'setter2');
select is(public.accept_invite(:'setter_code')->>'status', 'ok', 'a two-use invite admits a second person');

select tests.authenticate_as(:'climber');
select is(public.accept_invite(:'setter_code')->>'status', 'invalid', 'an exhausted invite is rejected');

-- A manager redeeming a routesetter invite is not downgraded.
select tests.authenticate_as(:'kasia');
select code as another_code from public.create_invite(:'volt', 'routesetter') \gset
select is(public.accept_invite(:'another_code')->>'role', 'manager', 'accepting an invite never downgrades a manager');

-- Expired and revoked invites
select invite_id as expired_id, code as expired_code from public.create_invite(:'volt') \gset
select invite_id as revoked_id, code as revoked_code from public.create_invite(:'volt') \gset
select public.revoke_invite(:'revoked_id');

select tests.as_owner();
update public.invites
   set created_at = now() - interval '10 days', expires_at = now() - interval '1 day'
 where id = :'expired_id';

select tests.authenticate_as(:'climber');
select is(public.accept_invite(:'expired_code')->>'status', 'invalid', 'an expired invite is rejected');
select is(public.accept_invite(:'revoked_code')->>'status', 'invalid', 'a revoked invite is rejected');

select tests.authenticate_as(:'setter');
select throws_ok(
  format('select public.revoke_invite(%L)', :'expired_id'),
  '42501', 'forbidden',
  'routesetters cannot revoke invites'
);

-- Brute force protection: 10 failures per hour, then rate limited --------------
select tests.authenticate_as(:'climber');
do $$ begin perform public.accept_invite('WRONG-' || n) from generate_series(1, 7) n; end $$;
select is(
  public.accept_invite('WRNG-WRNG-WRNG')->>'status',
  'rate_limited',
  'after 10 failed attempts within an hour further guesses are refused'
);

-- Memberships cannot be written directly ---------------------------------------
select throws_ok(
  format($$ insert into public.gym_memberships (gym_id, user_id, role) values (%L, %L, 'manager') $$, :'volt', :'climber'),
  '42501', null,
  'a climber cannot insert a membership'
);

select tests.authenticate_as(:'setter');
select throws_ok(
  format($$ update public.gym_memberships set role = 'manager' where user_id = %L $$, :'setter'),
  '42501', null,
  'a routesetter cannot promote themselves'
);

-- Staff list --------------------------------------------------------------------
select is(
  (select count(*)::int from public.gym_staff(:'volt')),
  3,
  'staff see the staff list (Kasia + two setters)'
);

select tests.authenticate_as(:'climber');
select throws_ok(
  format('select * from public.gym_staff(%L)', :'volt'),
  '42501', 'forbidden',
  'climbers cannot list staff'
);
select is_empty(
  'select * from public.gym_memberships',
  'climbers see no memberships of others'
);

-- Removing people ---------------------------------------------------------------
select tests.authenticate_as(:'setter');
select throws_ok(
  format('select public.remove_gym_member(%L, %L)', :'volt', :'setter2'),
  '42501', 'forbidden',
  'a routesetter cannot remove another routesetter'
);

select tests.authenticate_as(:'kasia');
select lives_ok(
  format('select public.remove_gym_member(%L, %L)', :'volt', :'setter2'),
  'the manager removes a routesetter'
);
select throws_ok(
  format('select public.remove_gym_member(%L, %L)', :'volt', :'kasia'),
  'P0001', 'last_manager',
  'the last manager cannot leave the gym'
);

select tests.authenticate_as(:'setter');
select lives_ok(
  format('select public.remove_gym_member(%L, %L)', :'volt', :'setter'),
  'a routesetter can leave'
);

select tests.authenticate_as(:'owner');
select public.admin_set_gym_role(:'volt', :'climber', 'manager');
select tests.authenticate_as(:'kasia');
select lives_ok(
  format('select public.remove_gym_member(%L, %L)', :'volt', :'kasia'),
  'a manager can leave once another manager exists'
);

-- Account deletion is never blocked by the last-manager rule.
select tests.as_owner();
delete from auth.users where id = :'climber';
select is_empty(
  format('select 1 from public.gym_memberships where user_id = %L', :'climber'),
  'deleting the account of the last manager removes the membership'
);

-- Publishing ---------------------------------------------------------------------
select tests.authenticate_as(:'owner');
select public.admin_set_gym_role(:'volt', :'kasia', 'manager');

select tests.authenticate_as(:'setter2');
select throws_ok(
  format('select public.set_gym_published(%L, true)', :'volt'),
  '42501', 'forbidden',
  'only managers publish a gym'
);

select tests.authenticate_as(:'kasia');
select public.set_gym_published(:'volt', true);

select tests.authenticate_as(:'setter2');
select results_eq(
  'select slug from public.gyms',
  $$ values ('volt-lodz') $$,
  'a published gym is visible to every signed-in climber'
);
select throws_ok(
  format($$ update public.gyms set published_at = null where id = %L $$, :'volt'),
  '42501', null,
  'publishing state cannot be changed with a plain update'
);

select tests.as_owner();
select * from finish();
rollback;
