begin;
\ir _helpers.inc
select no_plan();

select tests.create_user('owner@example.com') as owner \gset
select tests.create_user('setter@example.com') as setter \gset
select tests.make_platform_admin(:'owner');
select tests.gym_id('volt-lodz') as volt \gset

select tests.authenticate_as(:'owner');
select public.admin_set_gym_role(:'volt', :'setter', 'routesetter');
select is((public.my_access() ->> 'is_platform_admin')::boolean, true, 'admins learn they are admins');

select tests.authenticate_as(:'setter');
select is((public.my_access() ->> 'is_platform_admin')::boolean, false, 'others are not admins');
select is(
  public.my_access() -> 'gym_roles' -> 0 ->> 'role',
  'routesetter',
  'staff see their own gym roles'
);

select tests.authenticate_as_anon();
select throws_ok('select public.my_access()', '42501', null, 'anon cannot ask');

select tests.as_owner();
select * from finish();
rollback;
