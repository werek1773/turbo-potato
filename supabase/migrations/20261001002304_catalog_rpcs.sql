-- =============================================================================
-- Wspinaczka — catalog RPCs
-- Gym administration, staff roles, invites, sector photos/resets, problems,
-- and the storage bucket for sector photos.
--
-- Conventions for every public function below:
--   * SECURITY DEFINER with an empty search_path, fully qualified names;
--   * the caller must be authenticated, authorization is checked explicitly;
--   * business errors are raised with SQLSTATE P0001 and a machine-readable
--     message key (translated in the app), permission errors with 42501;
--   * EXECUTE is granted to `authenticated` only.
-- =============================================================================

create function private.require_uid()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  return v_uid;
end;
$$;

-- -----------------------------------------------------------------------------
-- 1. Platform administration
-- -----------------------------------------------------------------------------
create function public.admin_create_gym(
  p_slug text,
  p_name text,
  p_city text default null,
  p_address text default null,
  p_timezone text default 'Europe/Warsaw',
  p_latitude double precision default null,
  p_longitude double precision default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  perform private.require_uid();
  if not private.is_platform_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  insert into public.gyms (slug, name, city, address, timezone, latitude, longitude)
  values (p_slug, p_name, p_city, p_address, p_timezone, p_latitude, p_longitude)
  returning id into v_id;

  return v_id;
end;
$$;

-- Directly assign or change a staff role (admin only). Managers are normally
-- appointed with an admin-created manager invite instead.
create function public.admin_set_gym_role(p_gym_id uuid, p_user_id uuid, p_role public.gym_role)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
begin
  if not private.is_platform_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  insert into public.gym_memberships (gym_id, user_id, role, granted_by)
  values (p_gym_id, p_user_id, p_role, v_uid)
  on conflict (gym_id, user_id)
  do update set role = excluded.role, granted_by = excluded.granted_by;
end;
$$;

-- Publishing makes the gym visible to every climber.
create function public.set_gym_published(p_gym_id uuid, p_published boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_uid();
  if not private.has_gym_role(p_gym_id, array['manager']::public.gym_role[]) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  update public.gyms
     set published_at = case
           when p_published then coalesce(published_at, now())
           else null
         end
   where id = p_gym_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 2. Staff
-- -----------------------------------------------------------------------------
create function public.gym_staff(p_gym_id uuid)
returns table (user_id uuid, display_name text, role public.gym_role, member_since timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_uid();
  if not private.has_gym_role(p_gym_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  return query
    select m.user_id, p.display_name, m.role, m.created_at
      from public.gym_memberships m
      join public.profiles p on p.id = m.user_id
     where m.gym_id = p_gym_id
     order by m.role, p.display_name;
end;
$$;

-- Managers remove routesetters; anyone may leave; admins may remove anyone.
-- The last manager of a gym is protected by a trigger.
create function public.remove_gym_member(p_gym_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
  v_target_role public.gym_role;
begin
  select m.role into v_target_role
    from public.gym_memberships m
   where m.gym_id = p_gym_id and m.user_id = p_user_id
   for update;

  if not found then
    raise exception 'not_a_member' using errcode = 'P0001';
  end if;

  if not (
       p_user_id = v_uid
    or private.is_platform_admin()
    or (v_target_role = 'routesetter'
        and private.has_gym_role(p_gym_id, array['manager']::public.gym_role[]))
  ) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  delete from public.gym_memberships
   where gym_id = p_gym_id and user_id = p_user_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 3. Invites
-- -----------------------------------------------------------------------------
-- Crockford base32 without I, L, O, U.
create function private.normalize_invite_code(p_code text)
returns text
language sql
immutable
set search_path = ''
as $$
  select translate(
    regexp_replace(upper(coalesce(p_code, '')), '[^0-9A-Z]', '', 'g'),
    'OIL',
    '011'
  );
$$;

create function private.hash_invite_code(p_code text)
returns bytea
language sql
immutable
set search_path = ''
as $$
  select sha256(convert_to(private.normalize_invite_code(p_code), 'UTF8'));
$$;

-- 12 symbols x 5 bits = 60 bits from the CSPRNG behind gen_random_uuid().
-- Only the fully random bytes of the UUIDv4 are used (skips version/variant).
create function private.generate_invite_code()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_alphabet constant text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  v_bytes bytea := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
  v_code text := '';
  v_index integer;
begin
  foreach v_index in array array[0, 1, 2, 3, 4, 5, 7, 9, 10, 11, 12, 13] loop
    v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, v_index) % 32) + 1, 1);
  end loop;
  return v_code;
end;
$$;

create function public.create_invite(
  p_gym_id uuid,
  p_role public.gym_role default 'routesetter',
  p_max_uses integer default 1,
  p_valid_days integer default 7
)
returns table (invite_id uuid, code text, expires_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
  v_code text;
  v_id uuid;
  v_expires timestamptz;
begin
  if p_role = 'manager' then
    if not private.is_platform_admin() then
      raise exception 'forbidden' using errcode = '42501';
    end if;
  elsif not private.has_gym_role(p_gym_id, array['manager']::public.gym_role[]) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if p_valid_days is null or p_valid_days not between 1 and 30 then
    raise exception 'invalid_valid_days' using errcode = 'P0001';
  end if;

  v_code := private.generate_invite_code();
  v_expires := now() + make_interval(days => p_valid_days);

  insert into public.invites (gym_id, role, code_hash, created_by, expires_at, max_uses)
  values (p_gym_id, p_role, private.hash_invite_code(v_code), v_uid, v_expires, coalesce(p_max_uses, 1))
  returning id into v_id;

  return query
    select v_id,
           substr(v_code, 1, 4) || '-' || substr(v_code, 5, 4) || '-' || substr(v_code, 9, 4),
           v_expires;
end;
$$;

create function public.revoke_invite(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invite public.invites%rowtype;
begin
  perform private.require_uid();

  select * into v_invite from public.invites where id = p_invite_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;

  if not (
       private.is_platform_admin()
    or (v_invite.role = 'routesetter'
        and private.has_gym_role(v_invite.gym_id, array['manager']::public.gym_role[]))
  ) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  update public.invites set revoked_at = coalesce(revoked_at, now()) where id = p_invite_id;
end;
$$;

-- Returns {"status": "ok", "gym_id": ..., "role": ...} | {"status": "invalid"}
-- | {"status": "rate_limited"}. Failures are returned (not raised) so that the
-- failed attempt is committed and counts towards the rate limit.
create function public.accept_invite(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
  v_invite public.invites%rowtype;
  v_current_role public.gym_role;
  v_failures integer;
begin
  select count(*) into v_failures
    from private.invite_attempts a
   where a.user_id = v_uid
     and not a.succeeded
     and a.attempted_at > now() - interval '1 hour';

  if v_failures >= 10 then
    return jsonb_build_object('status', 'rate_limited');
  end if;

  -- Atomic consumption: concurrent accepts re-check used_count under the row lock.
  update public.invites i
     set used_count = i.used_count + 1
   where i.code_hash = private.hash_invite_code(p_code)
     and i.revoked_at is null
     and i.expires_at > now()
     and i.used_count < i.max_uses
     and not exists (
       select 1 from private.invite_redemptions r
       where r.invite_id = i.id and r.user_id = v_uid
     )
  returning i.* into v_invite;

  if not found then
    insert into private.invite_attempts (user_id, succeeded) values (v_uid, false);
    return jsonb_build_object('status', 'invalid');
  end if;

  insert into private.invite_redemptions (invite_id, user_id) values (v_invite.id, v_uid);
  insert into private.invite_attempts (user_id, succeeded) values (v_uid, true);

  select m.role into v_current_role
    from public.gym_memberships m
   where m.gym_id = v_invite.gym_id and m.user_id = v_uid
   for update;

  -- Never downgrade: a manager accepting a routesetter invite stays a manager.
  if v_current_role is distinct from 'manager' then
    insert into public.gym_memberships (gym_id, user_id, role, granted_by)
    values (v_invite.gym_id, v_uid, v_invite.role, v_invite.created_by)
    on conflict (gym_id, user_id)
    do update set role = excluded.role, granted_by = excluded.granted_by;
    v_current_role := v_invite.role;
  end if;

  return jsonb_build_object(
    'status', 'ok',
    'gym_id', v_invite.gym_id,
    'role', v_current_role
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 4. Sector photos and resets
-- -----------------------------------------------------------------------------
-- Object names: <gym_id>/<sector_id>/<uuid>.<jpg|jpeg|png|heic>, lowercase.
create function private.sector_photo_path_pattern(p_gym_id uuid, p_sector_id uuid)
returns text
language sql
immutable
set search_path = ''
as $$
  select '^' || p_gym_id::text || '/' || p_sector_id::text
      || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|jpeg|png|heic)$';
$$;

-- Storage INSERT policy helper: staff may upload into active sectors of their gym.
create function private.can_upload_sector_photo(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_parts text[] := string_to_array(p_name, '/');
  v_gym_id uuid;
  v_sector_id uuid;
begin
  if coalesce(array_length(v_parts, 1), 0) <> 3 then
    return false;
  end if;

  begin
    v_gym_id := v_parts[1]::uuid;
    v_sector_id := v_parts[2]::uuid;
  exception when invalid_text_representation then
    return false;
  end;

  return p_name ~ private.sector_photo_path_pattern(v_gym_id, v_sector_id)
     and exists (
       select 1 from public.sectors s
       where s.id = v_sector_id and s.gym_id = v_gym_id and s.archived_at is null
     )
     and private.has_gym_role(v_gym_id);
end;
$$;

revoke all on function private.can_upload_sector_photo(text) from public;
grant execute on function private.can_upload_sector_photo(text) to authenticated;

-- Registers an uploaded photo as the sector's new current photo.
--   * p_expected_photo_id: the photo the setter was looking at (null for the
--     first photo). A concurrent reset makes the call fail with stale_photo.
--   * p_remove_problem_ids: active problems taken down in this reset (may be
--     empty: then it is just a better photo of the same problems).
-- Surviving problems get their pins copied onto the new photo.
create function public.reset_sector(
  p_sector_id uuid,
  p_expected_photo_id uuid,
  p_storage_path text,
  p_width integer,
  p_height integer,
  p_remove_problem_ids uuid[] default '{}',
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
  v_sector public.sectors%rowtype;
  v_photo_id uuid;
  v_reset_id uuid;
  v_requested integer;
  v_removed integer;
begin
  select * into v_sector from public.sectors where id = p_sector_id for update;

  if not found or not private.has_gym_role(v_sector.gym_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if v_sector.archived_at is not null then
    raise exception 'sector_archived' using errcode = 'P0001';
  end if;
  if v_sector.current_photo_id is distinct from p_expected_photo_id then
    raise exception 'stale_photo' using errcode = 'P0001';
  end if;
  if p_storage_path is null
     or p_storage_path !~ private.sector_photo_path_pattern(v_sector.gym_id, v_sector.id) then
    raise exception 'invalid_photo_path' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'sector-photos' and o.name = p_storage_path
  ) then
    raise exception 'photo_not_uploaded' using errcode = 'P0001';
  end if;

  insert into public.sector_photos (sector_id, gym_id, storage_path, width, height, created_by)
  values (v_sector.id, v_sector.gym_id, p_storage_path, p_width, p_height, v_uid)
  returning id into v_photo_id;

  insert into public.sector_resets (sector_id, gym_id, photo_id, note, created_by)
  values (v_sector.id, v_sector.gym_id, v_photo_id, nullif(btrim(p_note), ''), v_uid)
  returning id into v_reset_id;

  select count(distinct x) into v_requested
    from unnest(coalesce(p_remove_problem_ids, '{}'::uuid[])) as x;

  update public.problems p
     set removed_at = now(),
         removed_reset_id = v_reset_id
   where p.sector_id = v_sector.id
     and p.removed_at is null
     and p.id = any (coalesce(p_remove_problem_ids, '{}'::uuid[]));
  get diagnostics v_removed = row_count;

  if v_removed <> v_requested then
    raise exception 'unknown_problem' using errcode = 'P0001';
  end if;

  if v_sector.current_photo_id is not null then
    insert into public.problem_placements (problem_id, photo_id, sector_id, gym_id, pin_x, pin_y)
    select pl.problem_id, v_photo_id, pl.sector_id, pl.gym_id, pl.pin_x, pl.pin_y
      from public.problem_placements pl
      join public.problems p on p.id = pl.problem_id
     where pl.photo_id = v_sector.current_photo_id
       and p.removed_at is null;
  end if;

  update public.sector_resets set removed_count = v_removed where id = v_reset_id;

  update public.sectors
     set current_photo_id = v_photo_id,
         last_reset_at = case when v_removed > 0 then now() else last_reset_at end
   where id = v_sector.id;

  return v_reset_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 5. Problems
-- -----------------------------------------------------------------------------
-- Idempotent: the app generates p_problem_id, so a retried call returns the
-- same problem instead of creating a duplicate.
create function public.add_problem(
  p_sector_id uuid,
  p_expected_photo_id uuid,
  p_pin_x real,
  p_pin_y real,
  p_grade_id uuid,
  p_hold_color public.hold_color,
  p_style_tags public.style_tag[] default '{}',
  p_name text default null,
  p_problem_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
  v_sector public.sectors%rowtype;
  v_id uuid := coalesce(p_problem_id, gen_random_uuid());
  v_existing_sector uuid;
  v_reset_id uuid;
begin
  -- FOR SHARE: concurrent adds are fine, a concurrent reset is serialized.
  select * into v_sector from public.sectors where id = p_sector_id for share;

  if not found or not private.has_gym_role(v_sector.gym_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select p.sector_id into v_existing_sector from public.problems p where p.id = v_id;
  if found then
    if v_existing_sector = v_sector.id then
      return v_id;
    end if;
    raise exception 'conflict' using errcode = 'P0001';
  end if;

  if v_sector.archived_at is not null then
    raise exception 'sector_archived' using errcode = 'P0001';
  end if;
  if v_sector.current_photo_id is null then
    raise exception 'sector_has_no_photo' using errcode = 'P0001';
  end if;
  if v_sector.current_photo_id is distinct from p_expected_photo_id then
    raise exception 'stale_photo' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.grades g
    where g.id = p_grade_id and g.gym_id = v_sector.gym_id and g.is_active
  ) then
    raise exception 'invalid_grade' using errcode = 'P0001';
  end if;

  select r.id into v_reset_id
    from public.sector_resets r
   where r.sector_id = v_sector.id and r.photo_id = v_sector.current_photo_id
   order by r.reset_at desc
   limit 1;

  insert into public.problems (
    id, gym_id, sector_id, grade_id, hold_color, name, style_tags, set_by, set_reset_id
  ) values (
    v_id, v_sector.gym_id, v_sector.id, p_grade_id, p_hold_color,
    nullif(btrim(p_name), ''), coalesce(p_style_tags, '{}'), v_uid, v_reset_id
  );

  insert into public.problem_placements (problem_id, photo_id, sector_id, gym_id, pin_x, pin_y)
  values (v_id, v_sector.current_photo_id, v_sector.id, v_sector.gym_id, p_pin_x, p_pin_y);

  return v_id;
end;
$$;

create function public.move_problem_pin(p_problem_id uuid, p_pin_x real, p_pin_y real)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_problem public.problems%rowtype;
  v_current_photo uuid;
begin
  perform private.require_uid();

  select * into v_problem from public.problems where id = p_problem_id;
  if not found or not private.has_gym_role(v_problem.gym_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if v_problem.removed_at is not null then
    raise exception 'problem_removed' using errcode = 'P0001';
  end if;

  select s.current_photo_id into v_current_photo
    from public.sectors s where s.id = v_problem.sector_id for share;

  update public.problem_placements
     set pin_x = p_pin_x, pin_y = p_pin_y
   where problem_id = p_problem_id and photo_id = v_current_photo;

  if not found then
    raise exception 'no_placement' using errcode = 'P0001';
  end if;
end;
$$;

-- Take a single problem down (e.g. broken hold) or undo that. A problem can
-- only be restored while its pin is still on the sector's current photo.
create function public.set_problem_removed(p_problem_id uuid, p_removed boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_problem public.problems%rowtype;
begin
  perform private.require_uid();

  select * into v_problem from public.problems where id = p_problem_id for update;
  if not found or not private.has_gym_role(v_problem.gym_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if p_removed then
    update public.problems
       set removed_at = coalesce(removed_at, now())
     where id = p_problem_id;
  else
    if not exists (
      select 1
        from public.problem_placements pl
        join public.sectors s on s.id = pl.sector_id and s.current_photo_id = pl.photo_id
       where pl.problem_id = p_problem_id
    ) then
      raise exception 'cannot_restore' using errcode = 'P0001';
    end if;

    update public.problems
       set removed_at = null, removed_reset_id = null
     where id = p_problem_id;
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- 6. Storage: public read (no listing), staff insert-only uploads
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'sector-photos',
  'sector-photos',
  true,
  10485760,
  array['image/jpeg', 'image/png', 'image/heic']
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- No SELECT/UPDATE/DELETE policies: objects cannot be listed, overwritten or
-- deleted by clients. Public URLs serve the images.
create policy sector_photos_staff_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'sector-photos'
    and private.can_upload_sector_photo(name)
  );

-- -----------------------------------------------------------------------------
-- 7. Function privileges
-- -----------------------------------------------------------------------------
revoke all on function private.require_uid() from public;
revoke all on function private.normalize_invite_code(text) from public;
revoke all on function private.hash_invite_code(text) from public;
revoke all on function private.generate_invite_code() from public;
revoke all on function private.sector_photo_path_pattern(uuid, uuid) from public;

revoke all on function public.admin_create_gym(text, text, text, text, text, double precision, double precision) from public, anon;
revoke all on function public.admin_set_gym_role(uuid, uuid, public.gym_role) from public, anon;
revoke all on function public.set_gym_published(uuid, boolean) from public, anon;
revoke all on function public.gym_staff(uuid) from public, anon;
revoke all on function public.remove_gym_member(uuid, uuid) from public, anon;
revoke all on function public.create_invite(uuid, public.gym_role, integer, integer) from public, anon;
revoke all on function public.revoke_invite(uuid) from public, anon;
revoke all on function public.accept_invite(text) from public, anon;
revoke all on function public.reset_sector(uuid, uuid, text, integer, integer, uuid[], text) from public, anon;
revoke all on function public.add_problem(uuid, uuid, real, real, uuid, public.hold_color, public.style_tag[], text, uuid) from public, anon;
revoke all on function public.move_problem_pin(uuid, real, real) from public, anon;
revoke all on function public.set_problem_removed(uuid, boolean) from public, anon;

grant execute on function public.admin_create_gym(text, text, text, text, text, double precision, double precision) to authenticated;
grant execute on function public.admin_set_gym_role(uuid, uuid, public.gym_role) to authenticated;
grant execute on function public.set_gym_published(uuid, boolean) to authenticated;
grant execute on function public.gym_staff(uuid) to authenticated;
grant execute on function public.remove_gym_member(uuid, uuid) to authenticated;
grant execute on function public.create_invite(uuid, public.gym_role, integer, integer) to authenticated;
grant execute on function public.revoke_invite(uuid) to authenticated;
grant execute on function public.accept_invite(text) to authenticated;
grant execute on function public.reset_sector(uuid, uuid, text, integer, integer, uuid[], text) to authenticated;
grant execute on function public.add_problem(uuid, uuid, real, real, uuid, public.hold_color, public.style_tag[], text, uuid) to authenticated;
grant execute on function public.move_problem_pin(uuid, real, real) to authenticated;
grant execute on function public.set_problem_removed(uuid, boolean) to authenticated;

revoke execute on all functions in schema private from public;
