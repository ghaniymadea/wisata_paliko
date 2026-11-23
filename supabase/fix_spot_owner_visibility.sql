-- Spot yang sedang menunggu verifikasi tetap terlihat oleh pembuatnya.
-- Jalankan sekali di Supabase SQL Editor.

drop policy if exists spots_public_read on public.spots;
create policy spots_public_read on public.spots
for select to anon, authenticated
using (
  id_status_verifikasi = 2
  or (auth.uid() is not null and id_pembuat = auth.uid())
  or exists (
    select 1
    from public.users u
    join public.roles r on r.id = u.id_role
    where u.id = auth.uid()
      and r.nama in ('Kurator', 'Admin')
  )
);

drop policy if exists spots_owner_update on public.spots;
create policy spots_owner_update on public.spots
for update to authenticated
using (id_pembuat = auth.uid())
with check (id_pembuat = auth.uid() and id_status_verifikasi = 1);
