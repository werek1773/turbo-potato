-- Visual floor plan of a gym, drawn like the gym's own reset board:
--   gyms.floor_plan  = {"aspect": w/h, "walls": [[[x,y],...]], "outlines": [...],
--                       "labels": [{"text","x","y"}]}   (coordinates 0..1)
--   sectors.map_path = [[x,y], ...]  the sector's stretch of wall on that plan
alter table public.gyms
  add column floor_plan jsonb check (floor_plan is null or jsonb_typeof(floor_plan) = 'object');

alter table public.sectors
  add column map_path jsonb check (map_path is null or jsonb_typeof(map_path) = 'array');

grant update (floor_plan) on public.gyms to authenticated;
grant insert (map_path) on public.sectors to authenticated;
grant update (map_path) on public.sectors to authenticated;
