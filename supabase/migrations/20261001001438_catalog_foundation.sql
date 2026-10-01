-- =============================================================================
-- Wspinaczka — catalog foundation
-- Gyms, grade scales, staff roles, invites, sectors, sector photos, resets,
-- problems and their pins. Every client-facing privilege is granted explicitly
-- at the bottom of this file; nothing is exposed by default.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. Exposure is opt-in
-- -----------------------------------------------------------------------------
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on functions from public, anon, authenticated, service_role;

-- Internal schema: never exposed through the Data API. Clients only need
-- USAGE so that RLS policies can call the helper functions defined here.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;
-- Note: PUBLIC's built-in EXECUTE on new functions cannot be revoked per
-- schema, so every migration ends with an explicit revoke for `private`.

-- -----------------------------------------------------------------------------
-- 1. Types
-- -----------------------------------------------------------------------------
create type public.gym_role as enum ('manager', 'routesetter');

create type public.hold_color as enum (
  'red', 'orange', 'yellow', 'green', 'blue', 'purple',
  'pink', 'black', 'white', 'grey', 'brown', 'multi'
);

create type public.style_tag as enum (
  'slab', 'vertical', 'overhang', 'roof',
  'crimps', 'slopers', 'pinches', 'pockets', 'jugs', 'volumes',
  'dynamic', 'static', 'coordination', 'compression', 'balance'
);

-- -----------------------------------------------------------------------------
-- 2. Shared trigger helpers
-- -----------------------------------------------------------------------------
create function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 3. People
-- -----------------------------------------------------------------------------
-- Platform admins live outside the exposed schema and have no client policies:
-- the only way to become one is a manual SQL insert by the project owner.
create table private.platform_admins (
  user_id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default 'Wspinacz'
    check (char_length(btrim(display_name)) between 1 and 40),
  -- Opt-out from anonymous community statistics (legitimate interest basis).
  stats_opt_out boolean not null default false,
  -- Explicit consent (GDPR art. 9) required to store wellbeing/pain data.
  health_data_consent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function private.touch_updated_at();

create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := btrim(coalesce(
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'name',
    ''
  ));
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(nullif(left(v_name, 40), ''), 'Wspinacz'))
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- -----------------------------------------------------------------------------
-- 4. Gyms and grade scales
-- -----------------------------------------------------------------------------
create table public.gyms (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique
    check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) <= 40),
  name text not null check (char_length(btrim(name)) between 1 and 80),
  city text check (char_length(city) <= 80),
  address text check (char_length(address) <= 160),
  timezone text not null default 'Europe/Warsaw',
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  geofence_radius_m integer not null default 150
    check (geofence_radius_m between 150 and 1000),
  -- Unpublished gyms are visible only to their staff and platform admins.
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((latitude is null) = (longitude is null))
);

create function private.validate_gym()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = new.timezone) then
    raise exception 'invalid_timezone' using errcode = '22023';
  end if;
  return new;
end;
$$;

create trigger gyms_validate
  before insert or update of timezone on public.gyms
  for each row execute function private.validate_gym();

create trigger gyms_touch_updated_at
  before update on public.gyms
  for each row execute function private.touch_updated_at();

-- A gym's own scale (Volt: 1..9). Grades are append-only: labels and order
-- never change once created, a grade can only be deactivated.
create table public.grades (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms (id) on delete cascade,
  label text not null check (char_length(btrim(label)) between 1 and 12),
  sort_order integer not null,
  -- Optional V-scale equivalent, only needed for cross-gym comparisons.
  v_equivalent numeric(4, 1) check (v_equivalent between 0 and 20),
  color text check (color ~ '^#[0-9A-Fa-f]{6}$'),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (gym_id, sort_order),
  unique (gym_id, label),
  unique (id, gym_id)
);

-- -----------------------------------------------------------------------------
-- 5. Staff roles and invites
-- -----------------------------------------------------------------------------
create table public.gym_memberships (
  gym_id uuid not null references public.gyms (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role public.gym_role not null,
  granted_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (gym_id, user_id)
);

create index gym_memberships_user_id_idx on public.gym_memberships (user_id);
create index gym_memberships_granted_by_idx on public.gym_memberships (granted_by);

create trigger gym_memberships_touch_updated_at
  before update on public.gym_memberships
  for each row execute function private.touch_updated_at();

-- A gym must never lose its last manager through a deliberate change.
-- Cascades (gym deleted, account deleted) are allowed through.
create function private.protect_last_manager()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.role = 'manager'
     and (tg_op = 'DELETE' or new.role <> 'manager')
     and exists (select 1 from public.gyms g where g.id = old.gym_id)
     and exists (select 1 from auth.users u where u.id = old.user_id)
     and not exists (
       select 1 from public.gym_memberships m
       where m.gym_id = old.gym_id and m.role = 'manager' and m.user_id <> old.user_id
     )
  then
    raise exception 'last_manager' using errcode = 'P0001';
  end if;
  return coalesce(new, old);
end;
$$;

create trigger gym_memberships_protect_last_manager
  before update of role or delete on public.gym_memberships
  for each row execute function private.protect_last_manager();

create table public.invites (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms (id) on delete cascade,
  role public.gym_role not null,
  -- SHA-256 of the normalized code; the plain code is shown once to its creator.
  code_hash bytea not null unique,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  max_uses integer not null default 1 check (max_uses between 1 and 50),
  used_count integer not null default 0 check (used_count between 0 and max_uses),
  revoked_at timestamptz,
  check (expires_at > created_at)
);

create index invites_gym_id_idx on public.invites (gym_id);
create index invites_created_by_idx on public.invites (created_by);

create table private.invite_redemptions (
  invite_id uuid not null references public.invites (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  redeemed_at timestamptz not null default now(),
  primary key (invite_id, user_id)
);

create index invite_redemptions_user_id_idx on private.invite_redemptions (user_id);

create table private.invite_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  succeeded boolean not null,
  attempted_at timestamptz not null default now()
);

create index invite_attempts_user_time_idx on private.invite_attempts (user_id, attempted_at desc);

-- -----------------------------------------------------------------------------
-- 6. Sectors, photos, resets
-- -----------------------------------------------------------------------------
create table public.sectors (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms (id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 60),
  sort_order integer not null default 0,
  current_photo_id uuid,
  last_reset_at timestamptz,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, gym_id)
);

create index sectors_gym_id_idx on public.sectors (gym_id, sort_order);

create trigger sectors_touch_updated_at
  before update on public.sectors
  for each row execute function private.touch_updated_at();

create table public.sector_photos (
  id uuid primary key default gen_random_uuid(),
  sector_id uuid not null,
  gym_id uuid not null,
  -- Object name in the `sector-photos` bucket: <gym_id>/<sector_id>/<uuid>.<ext>
  storage_path text not null unique,
  width integer not null check (width between 1 and 20000),
  height integer not null check (height between 1 and 20000),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (id, sector_id),
  unique (id, gym_id),
  foreign key (sector_id, gym_id) references public.sectors (id, gym_id) on delete cascade
);

create index sector_photos_sector_id_idx on public.sector_photos (sector_id);
create index sector_photos_gym_id_idx on public.sector_photos (gym_id);
create index sector_photos_created_by_idx on public.sector_photos (created_by);

alter table public.sectors
  add constraint sectors_current_photo_fkey
  foreign key (current_photo_id, id) references public.sector_photos (id, sector_id);

create index sectors_current_photo_idx on public.sectors (current_photo_id, id);

-- One row per photo change. removed_count = 0 means "new photo, same problems".
create table public.sector_resets (
  id uuid primary key default gen_random_uuid(),
  sector_id uuid not null,
  gym_id uuid not null,
  photo_id uuid not null,
  removed_count integer not null default 0 check (removed_count >= 0),
  note text check (char_length(note) <= 500),
  created_by uuid references auth.users (id) on delete set null,
  reset_at timestamptz not null default now(),
  unique (id, sector_id),
  foreign key (sector_id, gym_id) references public.sectors (id, gym_id) on delete cascade,
  foreign key (photo_id, sector_id) references public.sector_photos (id, sector_id) on delete cascade
);

create index sector_resets_sector_idx on public.sector_resets (sector_id, reset_at desc);
create index sector_resets_gym_idx on public.sector_resets (gym_id, reset_at desc);
create index sector_resets_photo_idx on public.sector_resets (photo_id, sector_id);
create index sector_resets_created_by_idx on public.sector_resets (created_by);

-- -----------------------------------------------------------------------------
-- 7. Problems and pins
-- -----------------------------------------------------------------------------
create table public.problems (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null,
  -- A problem never moves between sectors (it is physically on that wall).
  sector_id uuid not null,
  grade_id uuid not null,
  hold_color public.hold_color not null,
  name text check (char_length(btrim(name)) between 1 and 60),
  style_tags public.style_tag[] not null default '{}'
    check (cardinality(style_tags) <= 6),
  set_by uuid references auth.users (id) on delete set null,
  set_at timestamptz not null default now(),
  set_reset_id uuid,
  removed_at timestamptz,
  removed_reset_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, gym_id),
  unique (id, sector_id),
  foreign key (sector_id, gym_id) references public.sectors (id, gym_id) on delete cascade,
  foreign key (grade_id, gym_id) references public.grades (id, gym_id),
  foreign key (set_reset_id, sector_id) references public.sector_resets (id, sector_id),
  foreign key (removed_reset_id, sector_id) references public.sector_resets (id, sector_id),
  check (removed_reset_id is null or removed_at is not null)
);

create index problems_active_idx on public.problems (gym_id, sector_id) where removed_at is null;
create index problems_sector_idx on public.problems (sector_id);
create index problems_grade_idx on public.problems (grade_id, gym_id);
create index problems_set_by_idx on public.problems (set_by);
create index problems_set_reset_idx on public.problems (set_reset_id, sector_id);
create index problems_removed_reset_idx on public.problems (removed_reset_id, sector_id);

create trigger problems_touch_updated_at
  before update on public.problems
  for each row execute function private.touch_updated_at();

-- Pin of a problem on a specific sector photo. A reset copies surviving pins
-- onto the new photo, so every archived photo keeps its own pins.
create table public.problem_placements (
  problem_id uuid not null,
  photo_id uuid not null,
  sector_id uuid not null,
  gym_id uuid not null,
  pin_x real not null check (pin_x >= 0 and pin_x <= 1),
  pin_y real not null check (pin_y >= 0 and pin_y <= 1),
  created_at timestamptz not null default now(),
  primary key (problem_id, photo_id),
  foreign key (problem_id, sector_id) references public.problems (id, sector_id) on delete cascade,
  foreign key (photo_id, sector_id) references public.sector_photos (id, sector_id) on delete cascade,
  foreign key (sector_id, gym_id) references public.sectors (id, gym_id) on delete cascade
);

create index problem_placements_photo_idx on public.problem_placements (photo_id, sector_id);
create index problem_placements_problem_sector_idx on public.problem_placements (problem_id, sector_id);
create index problem_placements_sector_gym_idx on public.problem_placements (sector_id, gym_id);
create index problem_placements_gym_idx on public.problem_placements (gym_id);

create table public.problem_grade_history (
  id bigint generated always as identity primary key,
  problem_id uuid not null,
  gym_id uuid not null,
  old_grade_id uuid not null,
  new_grade_id uuid not null,
  changed_by uuid references auth.users (id) on delete set null,
  changed_at timestamptz not null default now(),
  foreign key (problem_id, gym_id) references public.problems (id, gym_id) on delete cascade,
  foreign key (old_grade_id, gym_id) references public.grades (id, gym_id),
  foreign key (new_grade_id, gym_id) references public.grades (id, gym_id)
);

create index problem_grade_history_problem_idx on public.problem_grade_history (problem_id, gym_id);
create index problem_grade_history_gym_idx on public.problem_grade_history (gym_id);
create index problem_grade_history_old_grade_idx on public.problem_grade_history (old_grade_id, gym_id);
create index problem_grade_history_new_grade_idx on public.problem_grade_history (new_grade_id, gym_id);
create index problem_grade_history_changed_by_idx on public.problem_grade_history (changed_by);

create function private.on_problem_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.grade_id is distinct from old.grade_id then
    if not exists (
      select 1 from public.grades g
      where g.id = new.grade_id and g.gym_id = new.gym_id and g.is_active
    ) then
      raise exception 'invalid_grade' using errcode = 'P0001';
    end if;

    insert into public.problem_grade_history (problem_id, gym_id, old_grade_id, new_grade_id, changed_by)
    values (new.id, new.gym_id, old.grade_id, new.grade_id, auth.uid());
  end if;
  return new;
end;
$$;

create trigger problems_on_update
  before update on public.problems
  for each row execute function private.on_problem_update();

-- -----------------------------------------------------------------------------
-- 8. Authorization helpers (used by RLS policies and RPCs)
-- -----------------------------------------------------------------------------
create function private.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from private.platform_admins a where a.user_id = (select auth.uid())
  );
$$;

-- True when the caller holds one of the roles in the gym, or is a platform admin.
create function private.has_gym_role(
  p_gym_id uuid,
  p_roles public.gym_role[] default array['manager', 'routesetter']::public.gym_role[]
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_platform_admin()
      or exists (
        select 1 from public.gym_memberships m
        where m.gym_id = p_gym_id
          and m.user_id = (select auth.uid())
          and m.role = any (p_roles)
      );
$$;

create function private.can_view_gym(p_gym_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
           select 1 from public.gyms g
           where g.id = p_gym_id and g.published_at is not null
         )
      or private.has_gym_role(p_gym_id);
$$;

revoke all on function private.is_platform_admin() from public;
revoke all on function private.has_gym_role(uuid, public.gym_role[]) from public;
revoke all on function private.can_view_gym(uuid) from public;
grant execute on function private.is_platform_admin() to authenticated, service_role;
grant execute on function private.has_gym_role(uuid, public.gym_role[]) to authenticated, service_role;
grant execute on function private.can_view_gym(uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 9. Row level security
-- -----------------------------------------------------------------------------
alter table private.platform_admins enable row level security;
alter table private.invite_redemptions enable row level security;
alter table private.invite_attempts enable row level security;

alter table public.profiles enable row level security;
alter table public.gyms enable row level security;
alter table public.grades enable row level security;
alter table public.gym_memberships enable row level security;
alter table public.invites enable row level security;
alter table public.sectors enable row level security;
alter table public.sector_photos enable row level security;
alter table public.sector_resets enable row level security;
alter table public.problems enable row level security;
alter table public.problem_placements enable row level security;
alter table public.problem_grade_history enable row level security;

-- profiles: strictly own row
create policy profiles_select_own on public.profiles
  for select to authenticated
  using (id = (select auth.uid()));

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- gyms
create policy gyms_select_visible on public.gyms
  for select to authenticated
  using (published_at is not null or private.has_gym_role(id));

create policy gyms_update_manager on public.gyms
  for update to authenticated
  using (private.has_gym_role(id, array['manager']::public.gym_role[]))
  with check (private.has_gym_role(id, array['manager']::public.gym_role[]));

-- grades
create policy grades_select_visible on public.grades
  for select to authenticated
  using (private.can_view_gym(gym_id));

create policy grades_insert_manager on public.grades
  for insert to authenticated
  with check (private.has_gym_role(gym_id, array['manager']::public.gym_role[]));

create policy grades_update_manager on public.grades
  for update to authenticated
  using (private.has_gym_role(gym_id, array['manager']::public.gym_role[]))
  with check (private.has_gym_role(gym_id, array['manager']::public.gym_role[]));

-- memberships: own roles + staff of the same gym see each other. Writes: RPC only.
create policy gym_memberships_select on public.gym_memberships
  for select to authenticated
  using (user_id = (select auth.uid()) or private.has_gym_role(gym_id));

-- invites: managers of the gym. Writes: RPC only.
create policy invites_select_manager on public.invites
  for select to authenticated
  using (private.has_gym_role(gym_id, array['manager']::public.gym_role[]));

-- sectors
create policy sectors_select_visible on public.sectors
  for select to authenticated
  using (private.can_view_gym(gym_id));

create policy sectors_insert_manager on public.sectors
  for insert to authenticated
  with check (private.has_gym_role(gym_id, array['manager']::public.gym_role[]));

create policy sectors_update_manager on public.sectors
  for update to authenticated
  using (private.has_gym_role(gym_id, array['manager']::public.gym_role[]))
  with check (private.has_gym_role(gym_id, array['manager']::public.gym_role[]));

-- photos / resets / pins: read-only for clients, written by RPCs
create policy sector_photos_select_visible on public.sector_photos
  for select to authenticated
  using (private.can_view_gym(gym_id));

create policy sector_resets_select_visible on public.sector_resets
  for select to authenticated
  using (private.can_view_gym(gym_id));

create policy problem_placements_select_visible on public.problem_placements
  for select to authenticated
  using (private.can_view_gym(gym_id));

-- problems: everyone who can see the gym reads; staff edit attributes
create policy problems_select_visible on public.problems
  for select to authenticated
  using (private.can_view_gym(gym_id));

create policy problems_update_staff on public.problems
  for update to authenticated
  using (private.has_gym_role(gym_id))
  with check (private.has_gym_role(gym_id));

create policy problem_grade_history_select_staff on public.problem_grade_history
  for select to authenticated
  using (private.has_gym_role(gym_id));

-- -----------------------------------------------------------------------------
-- 10. Convenience view: active problems with their pin on the current photo
-- -----------------------------------------------------------------------------
create view public.active_problems
with (security_invoker = true)
as
select
  p.id,
  p.gym_id,
  p.sector_id,
  p.grade_id,
  p.hold_color,
  p.name,
  p.style_tags,
  p.set_at,
  p.set_reset_id,
  pl.photo_id,
  pl.pin_x,
  pl.pin_y
from public.problems p
join public.sectors s on s.id = p.sector_id
join public.problem_placements pl
  on pl.problem_id = p.id and pl.photo_id = s.current_photo_id
where p.removed_at is null;

-- -----------------------------------------------------------------------------
-- 11. Grants (column lists define exactly what a client may write)
-- -----------------------------------------------------------------------------
revoke all on all tables in schema public from anon, authenticated;
revoke all on all tables in schema private from anon, authenticated;

grant select on public.profiles to authenticated;
grant update (display_name) on public.profiles to authenticated;

grant select on public.gyms to authenticated;
grant update (name, city, address, latitude, longitude, geofence_radius_m) on public.gyms to authenticated;

grant select on public.grades to authenticated;
grant insert (gym_id, label, sort_order, v_equivalent, color, is_active) on public.grades to authenticated;
grant update (v_equivalent, color, is_active) on public.grades to authenticated;

grant select on public.gym_memberships to authenticated;

grant select (id, gym_id, role, created_by, created_at, expires_at, max_uses, used_count, revoked_at)
  on public.invites to authenticated;

grant select on public.sectors to authenticated;
grant insert (id, gym_id, name, sort_order) on public.sectors to authenticated;
grant update (name, sort_order, archived_at) on public.sectors to authenticated;

grant select on public.sector_photos to authenticated;
grant select on public.sector_resets to authenticated;

grant select on public.problems to authenticated;
grant update (grade_id, hold_color, name, style_tags) on public.problems to authenticated;

grant select on public.problem_placements to authenticated;
grant select on public.problem_grade_history to authenticated;
grant select on public.active_problems to authenticated;

grant select, insert, update, delete on all tables in schema public to service_role;
grant select, insert, update, delete on all tables in schema private to service_role;

revoke execute on all functions in schema private from public;
