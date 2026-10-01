-- Sectors are grouped into areas (e.g. Volt Łódź: "Mała sala", "Duża sala").
-- Display order is (area order, sector order); sort_order stays global, so
-- walking order across the whole gym is just sort_order.
alter table public.sectors
  add column area text check (char_length(btrim(area)) between 1 and 40);

grant insert (area) on public.sectors to authenticated;
grant update (area) on public.sectors to authenticated;
