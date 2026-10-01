-- What the signed-in user may do, so the app can show the right screens.
-- Reveals only the caller's own status.
create function public.my_access()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
begin
  return jsonb_build_object(
    'is_platform_admin', private.is_platform_admin(),
    'gym_roles', coalesce((
      select jsonb_agg(jsonb_build_object('gym_id', m.gym_id, 'role', m.role) order by m.created_at)
        from public.gym_memberships m
       where m.user_id = v_uid
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.my_access() from public, anon;
grant execute on function public.my_access() to authenticated;
