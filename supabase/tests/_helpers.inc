-- Shared pgTAP helpers, included with `\ir _helpers.inc` at the top of each
-- test file (inside its transaction, so everything is rolled back).
create extension if not exists pgtap with schema extensions;

create schema if not exists tests;
grant usage on schema tests to anon, authenticated, service_role;

create or replace function tests.create_user(p_email text, p_name text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (
    v_id,
    p_email,
    case when p_name is null then '{}'::jsonb else jsonb_build_object('full_name', p_name) end
  );
  return v_id;
end;
$$;

create or replace function tests.make_platform_admin(p_user_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into private.platform_admins (user_id) values (p_user_id);
$$;

-- Act as a signed-in user for the rest of the transaction (or until switched).
create or replace function tests.authenticate_as(p_user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user_id, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create or replace function tests.authenticate_as_anon()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  perform set_config('role', 'anon', true);
end;
$$;

-- Back to the migration owner, still impersonating p_user_id for auth.uid().
create or replace function tests.as_owner(p_user_id uuid default null)
returns void
language plpgsql
as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims',
    case when p_user_id is null then ''
         else json_build_object('sub', p_user_id, 'role', 'authenticated')::text end,
    true);
end;
$$;

-- Simulates a finished upload to the sector-photos bucket (bypassing the
-- storage policy, which has its own tests) and returns the object name.
create or replace function tests.upload_sector_photo(p_gym_id uuid, p_sector_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := p_gym_id::text || '/' || p_sector_id::text || '/' || gen_random_uuid()::text || '.jpg';
begin
  insert into storage.objects (bucket_id, name) values ('sector-photos', v_name);
  return v_name;
end;
$$;

create or replace function tests.gym_id(p_slug text)
returns uuid
language sql
security definer
set search_path = ''
as $$
  select id from public.gyms where slug = p_slug;
$$;

create or replace function tests.grade_id(p_gym_id uuid, p_label text)
returns uuid
language sql
security definer
set search_path = ''
as $$
  select id from public.grades where gym_id = p_gym_id and label = p_label;
$$;

create or replace function tests.today(p_gym_id uuid)
returns date
language sql
security definer
set search_path = ''
as $$
  select private.climbing_date(now(), g.timezone) from public.gyms g where g.id = p_gym_id;
$$;

grant execute on all functions in schema tests to anon, authenticated, service_role;
