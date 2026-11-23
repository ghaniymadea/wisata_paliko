alter table public.spots add column if not exists catatan_verifikasi text;
alter table public.koleksi add column if not exists unggulan boolean not null default false;

create unique index if not exists media_spot_satu_cover
  on public.media_spot (id_spot) where is_cover;

create table if not exists public.laporan (
  id uuid primary key default gen_random_uuid(),
  id_pelapor uuid not null references public.users(id) on delete cascade,
  jenis_target text not null check (jenis_target in ('spot', 'tips', 'cerita', 'media')),
  id_target uuid not null,
  alasan text not null check (char_length(alasan) between 5 and 500),
  status text not null default 'baru' check (status in ('baru', 'diproses', 'selesai', 'ditolak')),
  ditangani_oleh uuid references public.users(id) on delete set null,
  catatan_admin text,
  created_at timestamptz not null default now(),
  unique (id_pelapor, jenis_target, id_target)
);

create table if not exists public.pengajuan_kurator (
  id uuid primary key default gen_random_uuid(),
  id_user uuid not null references public.users(id) on delete cascade,
  alasan text not null check (char_length(alasan) between 10 and 500),
  status text not null default 'menunggu' check (status in ('menunggu', 'disetujui', 'ditolak')),
  ditinjau_oleh uuid references public.users(id) on delete set null,
  catatan_admin text,
  ditinjau_pada timestamptz,
  created_at timestamptz not null default now()
);

create unique index if not exists pengajuan_kurator_satu_menunggu
  on public.pengajuan_kurator (id_user) where status = 'menunggu';

create table if not exists public.notifikasi (
  id uuid primary key default gen_random_uuid(),
  id_user uuid not null references public.users(id) on delete cascade,
  judul text not null,
  isi text not null,
  tautan_jenis text,
  tautan_id uuid,
  sudah_dibaca boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists notifikasi_user_idx
  on public.notifikasi (id_user, sudah_dibaca, created_at desc);
create index if not exists laporan_status_idx
  on public.laporan (status, created_at desc);

alter table public.laporan enable row level security;
alter table public.pengajuan_kurator enable row level security;
alter table public.notifikasi enable row level security;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_at = now();
  if public.is_admin() then
    if new.id_status_verifikasi is distinct from old.id_status_verifikasi then
      new.id_pemverifikasi := auth.uid();
    end if;
  elsif auth.uid() is not null then
    new.id_pemverifikasi := old.id_pemverifikasi;
    new.catatan_verifikasi := old.catatan_verifikasi;
  end if;
  return new;
end;
$$;

create or replace function public.jaga_unggulan()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    if tg_op = 'INSERT' then
      new.unggulan := false;
    else
      new.unggulan := old.unggulan;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists jaga_unggulan_koleksi on public.koleksi;
create trigger jaga_unggulan_koleksi
before insert or update on public.koleksi
for each row execute function public.jaga_unggulan();

create or replace function public.notif_status_spot()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.id_status_verifikasi is distinct from old.id_status_verifikasi
     and new.id_status_verifikasi in (2, 3) then
    insert into public.notifikasi (id_user, judul, isi, tautan_jenis, tautan_id)
    values (
      new.id_pembuat,
      case new.id_status_verifikasi when 2 then 'Spot disetujui' else 'Spot ditolak' end,
      case new.id_status_verifikasi
        when 2 then 'Spot "' || new.nama || '" sudah terverifikasi dan tampil untuk semua pengguna.'
        else 'Spot "' || new.nama || '" ditolak.' || coalesce(' Alasan: ' || new.catatan_verifikasi, '')
      end,
      'spot',
      new.id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists notif_spot_status on public.spots;
create trigger notif_spot_status
after update on public.spots
for each row execute function public.notif_status_spot();

create or replace function public.notif_admin_laporan()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifikasi (id_user, judul, isi, tautan_jenis, tautan_id)
  select u.id, 'Laporan baru', 'Ada laporan konten baru yang perlu ditinjau.', 'laporan', new.id
  from public.users u
  where u.id_role = 3;
  return new;
end;
$$;

drop trigger if exists notif_laporan_baru on public.laporan;
create trigger notif_laporan_baru
after insert on public.laporan
for each row execute function public.notif_admin_laporan();

create or replace function public.notif_admin_pengajuan()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifikasi (id_user, judul, isi, tautan_jenis, tautan_id)
  select u.id, 'Pengajuan kurator baru', 'Ada pengguna yang mengajukan diri sebagai Kurator.', 'pengajuan', new.id
  from public.users u
  where u.id_role = 3;
  return new;
end;
$$;

drop trigger if exists notif_pengajuan_baru on public.pengajuan_kurator;
create trigger notif_pengajuan_baru
after insert on public.pengajuan_kurator
for each row execute function public.notif_admin_pengajuan();

create or replace function public.verifikasi_spot(
  p_id uuid,
  p_status bigint,
  p_catatan text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Hanya admin yang boleh memverifikasi spot';
  end if;
  if p_status not in (1, 2, 3) then
    raise exception 'Status tidak valid';
  end if;
  update public.spots
  set id_status_verifikasi = p_status,
      catatan_verifikasi = p_catatan
  where id = p_id;
end;
$$;

create or replace function public.tinjau_pengajuan_kurator(
  p_id uuid,
  p_setuju boolean,
  p_catatan text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid;
begin
  if not public.is_admin() then
    raise exception 'Hanya admin yang boleh meninjau pengajuan';
  end if;

  update public.pengajuan_kurator
  set status = case when p_setuju then 'disetujui' else 'ditolak' end,
      ditinjau_oleh = auth.uid(),
      ditinjau_pada = now(),
      catatan_admin = p_catatan
  where id = p_id and status = 'menunggu'
  returning id_user into v_user;

  if v_user is null then
    raise exception 'Pengajuan tidak ditemukan atau sudah ditinjau';
  end if;

  if p_setuju then
    update public.users set id_role = 2 where id = v_user and id_role = 1;
  end if;

  insert into public.notifikasi (id_user, judul, isi, tautan_jenis, tautan_id)
  values (
    v_user,
    case when p_setuju then 'Pengajuan kurator disetujui' else 'Pengajuan kurator ditolak' end,
    case when p_setuju
      then 'Selamat, Anda sekarang berperan sebagai Kurator.'
      else 'Pengajuan Anda belum dapat disetujui.' || coalesce(' Catatan: ' || p_catatan, '')
    end,
    'pengajuan',
    p_id
  );
end;
$$;

create or replace function public.tandai_semua_notifikasi_dibaca()
returns void
language sql
security invoker
set search_path = public
as $$
  update public.notifikasi
  set sudah_dibaca = true
  where id_user = auth.uid() and sudah_dibaca = false;
$$;

create or replace function public.statistik_admin()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Hanya admin yang boleh melihat statistik';
  end if;
  return jsonb_build_object(
    'total_pengguna', (select count(*) from public.users),
    'total_kurator', (select count(*) from public.users where id_role = 2),
    'spot_menunggu', (select count(*) from public.spots where id_status_verifikasi = 1),
    'spot_terverifikasi', (select count(*) from public.spots where id_status_verifikasi = 2),
    'spot_ditolak', (select count(*) from public.spots where id_status_verifikasi = 3),
    'laporan_baru', (select count(*) from public.laporan where status = 'baru'),
    'pengajuan_kurator_menunggu', (select count(*) from public.pengajuan_kurator where status = 'menunggu')
  );
end;
$$;

drop policy if exists spots_owner_update on public.spots;
create policy spots_owner_update on public.spots
for update to authenticated
using (id_pembuat = auth.uid())
with check (id_pembuat = auth.uid() and id_status_verifikasi = 1);

drop policy if exists spots_moderator_update on public.spots;
drop policy if exists spots_moderator_delete on public.spots;
drop policy if exists spots_delete on public.spots;
create policy spots_delete on public.spots
for delete to authenticated
using (public.is_admin() or (id_pembuat = auth.uid() and id_status_verifikasi in (1, 3)));

drop policy if exists media_owner_update on public.media_spot;
create policy media_owner_update on public.media_spot
for update to authenticated
using (id_pengunggah = auth.uid())
with check (id_pengunggah = auth.uid());

drop policy if exists media_admin_update on public.media_spot;
create policy media_admin_update on public.media_spot
for update to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists media_admin_insert on public.media_spot;
create policy media_admin_insert on public.media_spot
for insert to authenticated
with check (public.is_admin());

drop policy if exists tips_admin_update on public.tips_warga;
create policy tips_admin_update on public.tips_warga
for update to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists stories_admin_update on public.cerita;
create policy stories_admin_update on public.cerita
for update to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists collections_admin_update on public.koleksi;
create policy collections_admin_update on public.koleksi
for update to authenticated
using (public.is_admin()) with check (public.is_admin());

create or replace function public.can_manage_collections()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.users
    where id = auth.uid() and id_role in (2, 3)
  );
$$;

drop policy if exists collections_owner_insert on public.koleksi;
drop policy if exists collections_owner_update on public.koleksi;
drop policy if exists collections_owner_delete on public.koleksi;
drop policy if exists collections_curator_insert on public.koleksi;
create policy collections_curator_insert on public.koleksi
for insert to authenticated
with check (id_kurator = auth.uid());

drop policy if exists collections_curator_update on public.koleksi;
create policy collections_curator_update on public.koleksi
for update to authenticated
using (id_kurator = auth.uid())
with check (id_kurator = auth.uid());

drop policy if exists collections_curator_delete on public.koleksi;
create policy collections_curator_delete on public.koleksi
for delete to authenticated
using (id_kurator = auth.uid());

drop policy if exists collection_details_owner_insert on public.detail_koleksi;
create policy collection_details_owner_insert on public.detail_koleksi
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
create policy collection_details_owner_delete on public.detail_koleksi
for delete to authenticated
using (
  exists (
    select 1 from public.koleksi c
    where c.id = id_koleksi and c.id_kurator = auth.uid()
  )
);

drop policy if exists laporan_insert on public.laporan;
create policy laporan_insert on public.laporan
for insert to authenticated
with check (id_pelapor = auth.uid() and status = 'baru');

drop policy if exists laporan_read on public.laporan;
create policy laporan_read on public.laporan
for select to authenticated
using (id_pelapor = auth.uid() or public.is_admin());

drop policy if exists laporan_admin_update on public.laporan;
create policy laporan_admin_update on public.laporan
for update to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists laporan_admin_delete on public.laporan;
create policy laporan_admin_delete on public.laporan
for delete to authenticated
using (public.is_admin());

drop policy if exists pengajuan_insert on public.pengajuan_kurator;
create policy pengajuan_insert on public.pengajuan_kurator
for insert to authenticated
with check (
  id_user = auth.uid()
  and status = 'menunggu'
  and exists (select 1 from public.users u where u.id = auth.uid() and u.id_role = 1)
);

drop policy if exists pengajuan_read on public.pengajuan_kurator;
create policy pengajuan_read on public.pengajuan_kurator
for select to authenticated
using (id_user = auth.uid() or public.is_admin());

drop policy if exists notifikasi_read on public.notifikasi;
create policy notifikasi_read on public.notifikasi
for select to authenticated
using (id_user = auth.uid());

drop policy if exists notifikasi_update on public.notifikasi;
create policy notifikasi_update on public.notifikasi
for update to authenticated
using (id_user = auth.uid()) with check (id_user = auth.uid());

drop policy if exists notifikasi_delete on public.notifikasi;
create policy notifikasi_delete on public.notifikasi
for delete to authenticated
using (id_user = auth.uid());

revoke all on public.laporan, public.pengajuan_kurator, public.notifikasi from anon, authenticated;

grant select, insert, update, delete on public.laporan to authenticated;
grant select, insert on public.pengajuan_kurator to authenticated;
grant select, delete on public.notifikasi to authenticated;
grant update (sudah_dibaca) on public.notifikasi to authenticated;

revoke execute on function public.verifikasi_spot(uuid, bigint, text) from public, anon;
revoke execute on function public.tinjau_pengajuan_kurator(uuid, boolean, text) from public, anon;
revoke execute on function public.tandai_semua_notifikasi_dibaca() from public, anon;
revoke execute on function public.statistik_admin() from public, anon;

grant execute on function public.verifikasi_spot(uuid, bigint, text) to authenticated;
grant execute on function public.tinjau_pengajuan_kurator(uuid, boolean, text) to authenticated;
grant execute on function public.tandai_semua_notifikasi_dibaca() to authenticated;
grant execute on function public.statistik_admin() to authenticated;

revoke execute on function public.set_spot_verification(uuid, boolean, uuid) from public, anon, authenticated;
revoke execute on function public.delete_spot_as_moderator(uuid) from public, anon, authenticated;

insert into storage.buckets (id, name, public)
values ('media-spot', 'media-spot', true)
on conflict (id) do update set public = true;

drop policy if exists media_spot_unggah on storage.objects;
create policy media_spot_unggah on storage.objects
for insert to authenticated
with check (
  bucket_id = 'media-spot'
  and exists (
    select 1 from public.spots s
    where s.id::text = (storage.foldername(name))[1]
      and (s.id_pembuat = (select auth.uid()) or public.is_admin())
  )
);

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
