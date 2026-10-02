-- Each sector's patch of floor on the plan, like the fields on the gym's
-- reset board: a closed polygon from its wall to the far edge of the mat.
-- Tapping anywhere in it picks the sector.
--   sectors.map_zone = [[x,y], ...]  (coordinates 0..1, same plan as map_path)
alter table public.sectors
  add column map_zone jsonb check (map_zone is null or jsonb_typeof(map_zone) = 'array');

grant insert (map_zone) on public.sectors to authenticated;
grant update (map_zone) on public.sectors to authenticated;
