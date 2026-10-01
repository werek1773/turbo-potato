-- Announced date of the next reset of a sector ("przykrętka 2.10"), so that
-- climbers can finish their projects in time. Set by managers and setters.
alter table public.sectors add column next_reset_on date;

create function public.set_next_reset(p_sector_id uuid, p_date date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sector public.sectors%rowtype;
  v_today date;
begin
  perform private.require_uid();

  select * into v_sector from public.sectors where id = p_sector_id for update;
  if not found or not private.has_gym_role(v_sector.gym_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select private.climbing_date(now(), g.timezone) into v_today
    from public.gyms g where g.id = v_sector.gym_id;
  if p_date is not null and p_date < v_today then
    raise exception 'date_in_past' using errcode = 'P0001';
  end if;

  update public.sectors set next_reset_on = p_date where id = p_sector_id;
end;
$$;

revoke all on function public.set_next_reset(uuid, date) from public, anon;
grant execute on function public.set_next_reset(uuid, date) to authenticated;

-- A reset that takes problems down fulfils the announcement.
create or replace function private.clear_announced_reset()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.last_reset_at is distinct from old.last_reset_at then
    new.next_reset_on := null;
  end if;
  return new;
end;
$$;

create trigger sectors_clear_announced_reset
  before update of last_reset_at on public.sectors
  for each row execute function private.clear_announced_reset();

revoke execute on all functions in schema private from public;
