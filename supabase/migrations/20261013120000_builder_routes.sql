-- =============================================================================
-- Wspinaczka — wall builder: holds on sector photos and problem routes
--
-- After a photo is uploaded the app detects its holds (dots: centre, radius,
-- color) and stores them as `auto` holds; staff fix them by hand (`manual`).
-- A problem's route is a set of those holds, each a start, hand or top hold.
-- Holds and routes belong to one photo: a reset keeps the old photo's holds
-- and routes as its archive, and the app maps surviving routes onto the new
-- photo's holds.
--
-- Freshness: problems.changed_at / change_kind tell climbers that the grade
-- or the route of a problem changed. Set only by the database: a regrade
-- (trigger) or a changed route (set_problem_route). Adding a problem, a first
-- route on an existing problem and carrying a route over to a new photo do
-- not count as changes.
-- =============================================================================

create type public.hold_source as enum ('auto', 'manual');
create type public.route_role as enum ('start', 'hand', 'top');

-- -----------------------------------------------------------------------------
-- 1. Holds on a photo
-- -----------------------------------------------------------------------------
create table public.photo_holds (
  id uuid primary key default gen_random_uuid(),
  photo_id uuid not null,
  sector_id uuid not null,
  gym_id uuid not null,
  -- Centre (0..1 of the photo) and radius (share of the photo's width).
  x real not null check (x >= 0 and x <= 1),
  y real not null check (y >= 0 and y <= 1),
  r real not null check (r > 0 and r <= 0.25),
  color public.hold_color,
  source public.hold_source not null default 'manual',
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (id, photo_id),
  foreign key (photo_id, sector_id) references public.sector_photos (id, sector_id) on delete cascade,
  foreign key (sector_id, gym_id) references public.sectors (id, gym_id) on delete cascade
);

create index photo_holds_photo_idx on public.photo_holds (photo_id, sector_id);
create index photo_holds_sector_gym_idx on public.photo_holds (sector_id, gym_id);
create index photo_holds_gym_idx on public.photo_holds (gym_id);
create index photo_holds_created_by_idx on public.photo_holds (created_by);

-- -----------------------------------------------------------------------------
-- 2. Routes: which holds of a photo make a problem
-- -----------------------------------------------------------------------------
create table public.problem_holds (
  problem_id uuid not null,
  hold_id uuid not null,
  photo_id uuid not null,
  sector_id uuid not null,
  gym_id uuid not null,
  role public.route_role not null,
  primary key (problem_id, hold_id),
  foreign key (problem_id, sector_id) references public.problems (id, sector_id) on delete cascade,
  foreign key (hold_id, photo_id) references public.photo_holds (id, photo_id) on delete cascade,
  foreign key (photo_id, sector_id) references public.sector_photos (id, sector_id) on delete cascade,
  foreign key (sector_id, gym_id) references public.sectors (id, gym_id) on delete cascade
);

create index problem_holds_hold_idx on public.problem_holds (hold_id, photo_id);
create index problem_holds_photo_idx on public.problem_holds (photo_id, sector_id);
create index problem_holds_problem_sector_idx on public.problem_holds (problem_id, sector_id);
create index problem_holds_sector_gym_idx on public.problem_holds (sector_id, gym_id);
create index problem_holds_gym_idx on public.problem_holds (gym_id);

-- -----------------------------------------------------------------------------
-- 3. Freshness
-- -----------------------------------------------------------------------------
alter table public.problems
  add column changed_at timestamptz,
  add column change_kind text check (change_kind in ('grade', 'route', 'both')),
  add constraint problems_change_pair check ((changed_at is null) = (change_kind is null));

-- A new kind of change shortly after another one reads as both.
create function private.next_change_kind(p_old_at timestamptz, p_old_kind text, p_kind text)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when p_old_at > now() - interval '1 hour' and p_old_kind is distinct from p_kind then 'both'
    else p_kind
  end;
$$;

create or replace function private.on_problem_update()
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

    new.change_kind := private.next_change_kind(old.changed_at, old.change_kind, 'grade');
    new.changed_at := now();
  end if;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 4. Views
-- -----------------------------------------------------------------------------
create or replace view public.active_problems
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
  pl.pin_y,
  p.changed_at,
  p.change_kind
from public.problems p
join public.sectors s on s.id = p.sector_id
join public.problem_placements pl
  on pl.problem_id = p.id and pl.photo_id = s.current_photo_id
where p.removed_at is null;

-- Routes of active problems on their sector's current photo, hold geometry included.
create view public.current_routes
with (security_invoker = true)
as
select
  ph.problem_id,
  ph.hold_id,
  ph.role,
  ph.photo_id,
  ph.sector_id,
  ph.gym_id,
  h.x,
  h.y,
  h.r,
  h.color
from public.problem_holds ph
join public.photo_holds h on h.id = ph.hold_id and h.photo_id = ph.photo_id
join public.sectors s on s.id = ph.sector_id and s.current_photo_id = ph.photo_id
join public.problems p on p.id = ph.problem_id and p.removed_at is null;

-- -----------------------------------------------------------------------------
-- 5. Helpers
-- -----------------------------------------------------------------------------
-- The current photo of a sector, locked against a concurrent reset; staff only.
create function private.current_photo_for_staff(p_photo_id uuid)
returns public.sectors
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sector public.sectors%rowtype;
begin
  select s.* into v_sector
    from public.sector_photos ph
    join public.sectors s on s.id = ph.sector_id
   where ph.id = p_photo_id
     for share of s;

  if not found or not private.has_gym_role(v_sector.gym_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if v_sector.current_photo_id is distinct from p_photo_id then
    raise exception 'stale_photo' using errcode = 'P0001';
  end if;
  return v_sector;
end;
$$;

-- Validates and stores a route ([{hold_id, role}, ...]) for a problem on a
-- photo, replacing the route it had there, and moves the pin to the middle
-- of the start holds. Returns true when an existing route was changed.
create function private.apply_route(
  p_problem_id uuid,
  p_photo_id uuid,
  p_sector_id uuid,
  p_gym_id uuid,
  p_route jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
  v_roles public.route_role[];
  v_items integer;
  v_starts integer;
  v_tops integer;
  v_known integer;
  v_old text;
  v_new text;
begin
  if p_route is null or jsonb_typeof(p_route) <> 'array' then
    raise exception 'invalid_route' using errcode = 'P0001';
  end if;

  begin
    select coalesce(array_agg((t.e ->> 'hold_id')::uuid order by t.ord), '{}'),
           coalesce(array_agg((t.e ->> 'role')::public.route_role order by t.ord), '{}')
      into v_ids, v_roles
      from jsonb_array_elements(p_route) with ordinality as t(e, ord);
  exception when invalid_text_representation then
    raise exception 'invalid_route' using errcode = 'P0001';
  end;

  v_items := cardinality(v_ids);
  select count(*) filter (where r = 'start'), count(*) filter (where r = 'top')
    into v_starts, v_tops
    from unnest(v_roles) as r;

  if v_items > 60
     or array_position(v_ids, null) is not null
     or array_position(v_roles, null) is not null
     or (select count(distinct i) from unnest(v_ids) as i) <> v_items then
    raise exception 'invalid_route' using errcode = 'P0001';
  end if;
  if v_items > 0 and (v_starts not between 1 and 2 or v_tops > 2) then
    raise exception 'invalid_route_roles' using errcode = 'P0001';
  end if;

  select count(*) into v_known
    from public.photo_holds h
   where h.photo_id = p_photo_id and h.id = any (v_ids);
  if v_known <> v_items then
    raise exception 'unknown_hold' using errcode = 'P0001';
  end if;

  select string_agg(hold_id::text || ':' || role::text, ',' order by hold_id) into v_old
    from public.problem_holds
   where problem_id = p_problem_id and photo_id = p_photo_id;
  select string_agg(r.hold_id::text || ':' || r.role::text, ',' order by r.hold_id) into v_new
    from unnest(v_ids, v_roles) as r(hold_id, role);

  delete from public.problem_holds where problem_id = p_problem_id and photo_id = p_photo_id;
  insert into public.problem_holds (problem_id, hold_id, photo_id, sector_id, gym_id, role)
  select p_problem_id, r.hold_id, p_photo_id, p_sector_id, p_gym_id, r.role
    from unnest(v_ids, v_roles) as r(hold_id, role);

  if v_starts > 0 then
    update public.problem_placements pl
       set pin_x = c.x, pin_y = c.y
      from (
        select avg(h.x)::real as x, avg(h.y)::real as y
          from unnest(v_ids, v_roles) as r(hold_id, role)
          join public.photo_holds h on h.id = r.hold_id
         where r.role = 'start'
      ) c
     where pl.problem_id = p_problem_id and pl.photo_id = p_photo_id;
  end if;

  return v_old is not null and v_old is distinct from v_new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 6. RPCs: holds
-- -----------------------------------------------------------------------------
-- Stores what the app detected on a photo ([{id?, x, y, r, color?}, ...]).
-- Earlier auto holds that no route uses are replaced; holds used by routes
-- and manual holds stay. Returns the number of holds stored.
create function public.replace_auto_holds(p_photo_id uuid, p_holds jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
  v_sector public.sectors%rowtype;
  v_count integer;
begin
  v_sector := private.current_photo_for_staff(p_photo_id);

  if p_holds is null or jsonb_typeof(p_holds) <> 'array' or jsonb_array_length(p_holds) > 600 then
    raise exception 'invalid_holds' using errcode = 'P0001';
  end if;

  delete from public.photo_holds h
   where h.photo_id = p_photo_id
     and h.source = 'auto'
     and not exists (select 1 from public.problem_holds ph where ph.hold_id = h.id);

  begin
    insert into public.photo_holds (id, photo_id, sector_id, gym_id, x, y, r, color, source, created_by)
    select coalesce((e ->> 'id')::uuid, gen_random_uuid()),
           p_photo_id, v_sector.id, v_sector.gym_id,
           (e ->> 'x')::real, (e ->> 'y')::real, (e ->> 'r')::real,
           (e ->> 'color')::public.hold_color,
           'auto', v_uid
      from jsonb_array_elements(p_holds) e
    on conflict (id) do nothing;
  exception when invalid_text_representation or not_null_violation then
    raise exception 'invalid_holds' using errcode = 'P0001';
  end;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Adds a hold by hand, or moves/recolors one (it becomes manual).
create function public.upsert_photo_hold(
  p_hold_id uuid,
  p_photo_id uuid,
  p_x real,
  p_y real,
  p_r real,
  p_color public.hold_color
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
  v_sector public.sectors%rowtype;
  v_id uuid := coalesce(p_hold_id, gen_random_uuid());
begin
  v_sector := private.current_photo_for_staff(p_photo_id);

  if exists (select 1 from public.photo_holds where id = v_id and photo_id <> p_photo_id) then
    raise exception 'conflict' using errcode = 'P0001';
  end if;

  insert into public.photo_holds (id, photo_id, sector_id, gym_id, x, y, r, color, source, created_by)
  values (v_id, p_photo_id, v_sector.id, v_sector.gym_id, p_x, p_y, p_r, p_color, 'manual', v_uid)
  on conflict (id) do update
    set x = excluded.x, y = excluded.y, r = excluded.r, color = excluded.color, source = 'manual';

  return v_id;
end;
$$;

create function public.delete_photo_hold(p_hold_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_photo uuid;
begin
  perform private.require_uid();

  select photo_id into v_photo from public.photo_holds where id = p_hold_id;
  if not found then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  perform private.current_photo_for_staff(v_photo);

  if exists (
    select 1 from public.problem_holds ph
    join public.problems p on p.id = ph.problem_id and p.removed_at is null
    where ph.hold_id = p_hold_id
  ) then
    raise exception 'hold_in_use' using errcode = 'P0001';
  end if;

  delete from public.photo_holds where id = p_hold_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 7. RPCs: routes
-- -----------------------------------------------------------------------------
-- Sets a problem's route on the sector's current photo. An empty array
-- clears it. Changing an existing route marks the problem as changed;
-- p_carry_over (a reset mapping the route onto a new photo) never does.
create function public.set_problem_route(
  p_problem_id uuid,
  p_expected_photo_id uuid,
  p_route jsonb,
  p_carry_over boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_problem public.problems%rowtype;
  v_sector public.sectors%rowtype;
  v_changed boolean;
begin
  perform private.require_uid();

  select * into v_problem from public.problems where id = p_problem_id for update;
  if not found or not private.has_gym_role(v_problem.gym_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if v_problem.removed_at is not null then
    raise exception 'problem_removed' using errcode = 'P0001';
  end if;

  select * into v_sector from public.sectors where id = v_problem.sector_id for share;
  if v_sector.current_photo_id is distinct from p_expected_photo_id then
    raise exception 'stale_photo' using errcode = 'P0001';
  end if;

  v_changed := private.apply_route(p_problem_id, p_expected_photo_id, v_sector.id, v_sector.gym_id, p_route);

  if v_changed and not p_carry_over then
    update public.problems
       set change_kind = private.next_change_kind(changed_at, change_kind, 'route'),
           changed_at = now()
     where id = p_problem_id;
  end if;
end;
$$;

-- add_problem gains an optional route, stored with the problem in one call.
drop function public.add_problem(uuid, uuid, real, real, uuid, public.hold_color, public.style_tag[], text, uuid);

create function public.add_problem(
  p_sector_id uuid,
  p_expected_photo_id uuid,
  p_pin_x real,
  p_pin_y real,
  p_grade_id uuid,
  p_hold_color public.hold_color,
  p_style_tags public.style_tag[] default '{}',
  p_name text default null,
  p_problem_id uuid default null,
  p_route jsonb default null
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

  if p_route is not null then
    perform private.apply_route(v_id, v_sector.current_photo_id, v_sector.id, v_sector.gym_id, p_route);
  end if;

  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 8. Row level security and grants
-- -----------------------------------------------------------------------------
alter table public.photo_holds enable row level security;
alter table public.problem_holds enable row level security;

create policy photo_holds_select_visible on public.photo_holds
  for select to authenticated
  using (private.can_view_gym(gym_id));

create policy problem_holds_select_visible on public.problem_holds
  for select to authenticated
  using (private.can_view_gym(gym_id));

revoke all on public.photo_holds from anon, authenticated;
revoke all on public.problem_holds from anon, authenticated;
grant select on public.photo_holds to authenticated;
grant select on public.problem_holds to authenticated;
grant select on public.current_routes to authenticated;
grant select on public.active_problems to authenticated;
grant select, insert, update, delete on public.photo_holds, public.problem_holds to service_role;

revoke all on function public.replace_auto_holds(uuid, jsonb) from public, anon;
revoke all on function public.upsert_photo_hold(uuid, uuid, real, real, real, public.hold_color) from public, anon;
revoke all on function public.delete_photo_hold(uuid) from public, anon;
revoke all on function public.set_problem_route(uuid, uuid, jsonb, boolean) from public, anon;
revoke all on function public.add_problem(uuid, uuid, real, real, uuid, public.hold_color, public.style_tag[], text, uuid, jsonb) from public, anon;

grant execute on function public.replace_auto_holds(uuid, jsonb) to authenticated;
grant execute on function public.upsert_photo_hold(uuid, uuid, real, real, real, public.hold_color) to authenticated;
grant execute on function public.delete_photo_hold(uuid) to authenticated;
grant execute on function public.set_problem_route(uuid, uuid, jsonb, boolean) to authenticated;
grant execute on function public.add_problem(uuid, uuid, real, real, uuid, public.hold_color, public.style_tag[], text, uuid, jsonb) to authenticated;

revoke execute on all functions in schema private from public;
