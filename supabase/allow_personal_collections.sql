-- Jalankan sekali di Supabase SQL Editor agar semua pengguna dapat
-- membuat koleksi pribadi dan menambahkan spot ke koleksinya sendiri.

drop policy if exists collections_curator_insert on public.koleksi;
create policy collections_personal_insert on public.koleksi
for insert to authenticated
with check (id_kurator = auth.uid());

drop policy if exists collections_curator_update on public.koleksi;
create policy collections_personal_update on public.koleksi
for update to authenticated
using (id_kurator = auth.uid())
with check (id_kurator = auth.uid());

drop policy if exists collections_curator_delete on public.koleksi;
create policy collections_personal_delete on public.koleksi
for delete to authenticated
using (id_kurator = auth.uid());

drop policy if exists collection_details_owner_insert on public.detail_koleksi;
create policy collection_details_personal_insert on public.detail_koleksi
for insert to authenticated
with check (
  exists (
    select 1 from public.koleksi c
    where c.id = id_koleksi and c.id_kurator = auth.uid()
  )
  and exists (
    select 1 from public.spots s
    where s.id = id_spot and s.id_status_verifikasi = 2
  )
);

drop policy if exists collection_details_owner_delete on public.detail_koleksi;
create policy collection_details_personal_delete on public.detail_koleksi
for delete to authenticated
using (
  exists (
    select 1 from public.koleksi c
    where c.id = id_koleksi and c.id_kurator = auth.uid()
  )
);
