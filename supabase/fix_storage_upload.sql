-- Perbaikan upload foto usulan spot dan cerita ke bucket media-spot.
-- Jalankan sekali di Supabase SQL Editor.

insert into storage.buckets (id, name, public)
values ('media-spot', 'media-spot', true)
on conflict (id) do update set public = true;

drop policy if exists media_spot_unggah on storage.objects;
create policy media_spot_unggah on storage.objects
for insert to authenticated
with check (
  bucket_id = 'media-spot'
  and exists (
    select 1
    from public.spots s
    where s.id::text = (storage.foldername(name))[1]
      and (s.id_pembuat = auth.uid() or public.is_admin())
  )
);

drop policy if exists media_story_unggah on storage.objects;
create policy media_story_unggah on storage.objects
for insert to authenticated
with check (
  bucket_id = 'media-spot'
  and exists (
    select 1
    from public.spots s
    where s.id::text = (storage.foldername(name))[1]
      and s.id_status_verifikasi = 2
  )
);

drop policy if exists media_spot_baca on storage.objects;
create policy media_spot_baca on storage.objects
for select to anon, authenticated
using (bucket_id = 'media-spot');
