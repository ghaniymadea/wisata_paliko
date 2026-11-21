

grant usage on schema public to anon, authenticated;
grant select on public.roles, public.users to authenticated;
grant select on public.kabupaten_kota, public.kecamatan to authenticated;
grant select (id, username, nama, foto_profil) on public.users to anon;
grant update (username, nama, foto_profil, id_kecamatan_asal) on public.users to authenticated;
grant execute on function public.update_user_role(uuid, bigint) to authenticated;

create or replace function public.upsert_category(p_nama text, p_slug text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nama text := trim(p_nama);
  v_slug text := lower(trim(p_slug));
  v_existing_id bigint;
begin
  if not public.is_admin() then
    raise exception 'Akses master hanya untuk admin';
  end if;
  if v_nama = '' or v_slug = '' then
    raise exception 'Nama dan slug kategori wajib diisi';
  end if;
  select k.id into v_existing_id
  from public.kategori k
  where k.slug = v_slug and k.nama <> v_nama
  limit 1;
  if v_existing_id is not null then
    v_slug := v_slug || '-' || v_existing_id::text;
  end if;
  insert into public.kategori(nama, slug)
  values (v_nama, v_slug)
  on conflict (nama) do update set slug = excluded.slug;
end;
$$;
grant execute on function public.upsert_category(text, text) to authenticated;

-- Pemilik dapat mengedit spot sendiri. Admin/Kurator dapat mengedit semua spot.
-- Setiap perubahan kembali ke status menunggu agar diverifikasi ulang.
drop policy if exists spots_moderator_update on public.spots;
create policy spots_moderator_update on public.spots
for update to authenticated
using (public.is_moderator())
with check (public.is_moderator() and id_status_verifikasi = 1);


create or replace function public.upsert_district(
  p_id_kota bigint,
  p_nama text,
  p_slug text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nama text := trim(p_nama);
  v_slug text := lower(trim(p_slug));
  v_existing_id bigint;
begin
  if not public.is_admin() then
    raise exception 'Akses master hanya untuk admin';
  end if;
  if v_nama = '' or v_slug = '' then
    raise exception 'Nama dan slug kecamatan wajib diisi';
  end if;
  if not exists (select 1 from public.kabupaten_kota where id = p_id_kota) then
    raise exception 'Kabupaten/kota tidak ditemukan';
  end if;

  select k.id into v_existing_id
  from public.kecamatan k
  where k.slug = v_slug
    and not (k.id_kabupaten_kota = p_id_kota and k.nama = v_nama)
  limit 1;

  if v_existing_id is not null then
    v_slug := v_slug || '-' || p_id_kota::text;
  end if;

  insert into public.kecamatan(id_kabupaten_kota, nama, slug)
  values (p_id_kota, v_nama, v_slug)
  on conflict (id_kabupaten_kota, nama) do update
    set slug = excluded.slug;
end;
$$;

grant execute on function public.upsert_district(bigint, text, text) to authenticated;

-- Koordinat awal untuk dua spot contoh yang sebelumnya masih kosong.
-- Hanya mengisi data yang belum memiliki koordinat agar tidak menimpa perubahan admin.
update public.spots
set latitude = -0.3241, longitude = 100.6732
where lower(trim(nama)) = 'gunung sago'
  and latitude is null and longitude is null;

update public.spots
set latitude = -0.2317231, longitude = 100.62785
where lower(trim(nama)) = 'taman sahati'
  and latitude is null and longitude is null;

insert into storage.buckets (id, name, public)
values ('media-spot', 'media-spot', true)
on conflict (id) do update set public = true;


drop policy if exists spots_owner_update on public.spots;
create policy spots_owner_update on public.spots
for update to authenticated
using (id_pembuat = auth.uid())
with check (id_pembuat = auth.uid() and id_status_verifikasi = 1);

drop policy if exists media_owner_update on public.media_spot;
create policy media_owner_update on public.media_spot
for update to authenticated
using (id_pengunggah = auth.uid())
with check (id_pengunggah = auth.uid());

drop policy if exists media_story_unggah on storage.objects;
create policy media_story_unggah on storage.objects
for insert to authenticated
with check (
  bucket_id = 'media-spot'
  and exists (
    select 1 from public.spots s
    where s.id::text = (storage.foldername(name))[1]
      and s.id_status_verifikasi = 2
  )
);

drop policy if exists users_profile_read on public.users;
create policy users_profile_read on public.users
for select to authenticated using (true);


insert into public.users (id, id_role, username, nama, email)
select
  a.id,
  1,
  'penjelajah_' || substr(a.id::text, 1, 8),
  coalesce(nullif(a.raw_user_meta_data ->> 'nama', ''), split_part(a.email, '@', 1)),
  a.email
from auth.users a
where a.email is not null
  and not exists (select 1 from public.users u where u.id = a.id)
on conflict (id) do nothing;
