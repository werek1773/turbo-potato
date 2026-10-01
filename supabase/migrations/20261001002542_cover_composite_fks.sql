-- Covering indexes for the (sector_id, gym_id) composite foreign keys.
drop index if exists public.problems_sector_idx;
create index problems_sector_gym_idx on public.problems (sector_id, gym_id);
create index sector_photos_sector_gym_idx on public.sector_photos (sector_id, gym_id);
create index sector_resets_sector_gym_idx on public.sector_resets (sector_id, gym_id);
