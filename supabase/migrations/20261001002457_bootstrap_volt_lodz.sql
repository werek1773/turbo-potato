-- =============================================================================
-- Wspinaczka — first gym: VOLT Boulderownia Łódź (unpublished until ready)
-- Volt grades its problems with plain numbers 1–9 (a V-scale-like scale).
-- =============================================================================

insert into public.gyms (slug, name, city, address, timezone, latitude, longitude)
values (
  'volt-lodz',
  'VOLT Boulderownia',
  'Łódź',
  'ul. Siedlecka 3A, Łódź',
  'Europe/Warsaw',
  51.7411922,
  19.4807735
)
on conflict (slug) do nothing;

insert into public.grades (gym_id, label, sort_order)
select g.id, n::text, n
  from public.gyms g
 cross join generate_series(1, 9) as n
 where g.slug = 'volt-lodz'
on conflict (gym_id, sort_order) do nothing;
