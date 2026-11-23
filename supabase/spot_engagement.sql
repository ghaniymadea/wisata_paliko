-- Jalankan sekali di Supabase SQL Editor untuk mengaktifkan
-- like, jumlah komentar/tips, dan jumlah share pada spot.

create table if not exists public.spot_likes (
  id_spot uuid not null references public.spots(id) on delete cascade,
  id_user uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (id_spot, id_user)
);

create table if not exists public.spot_shares (
  id uuid primary key default gen_random_uuid(),
  id_spot uuid not null references public.spots(id) on delete cascade,
  id_user uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.spot_likes enable row level security;
alter table public.spot_shares enable row level security;

drop policy if exists spot_likes_read on public.spot_likes;
create policy spot_likes_read on public.spot_likes
for select to authenticated using (true);

drop policy if exists spot_likes_insert on public.spot_likes;
create policy spot_likes_insert on public.spot_likes
for insert to authenticated with check (id_user = auth.uid());

drop policy if exists spot_likes_delete on public.spot_likes;
create policy spot_likes_delete on public.spot_likes
for delete to authenticated using (id_user = auth.uid());

drop policy if exists spot_shares_read on public.spot_shares;
create policy spot_shares_read on public.spot_shares
for select to authenticated using (true);

drop policy if exists spot_shares_insert on public.spot_shares;
create policy spot_shares_insert on public.spot_shares
for insert to authenticated with check (id_user = auth.uid());

create or replace function public.toggle_spot_like(p_id_spot uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.spot_likes
    where id_spot = p_id_spot and id_user = auth.uid()
  ) then
    delete from public.spot_likes
    where id_spot = p_id_spot and id_user = auth.uid();
    return false;
  end if;

  insert into public.spot_likes (id_spot, id_user)
  values (p_id_spot, auth.uid());
  return true;
end;
$$;

grant select, insert, delete on public.spot_likes to authenticated;
grant select, insert on public.spot_shares to authenticated;
grant execute on function public.toggle_spot_like(uuid) to authenticated;

notify pgrst, 'reload schema';
