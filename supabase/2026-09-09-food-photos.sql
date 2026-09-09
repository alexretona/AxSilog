-- Axsilog — food photos on menu items
-- Run this in the Supabase SQL editor (Dashboard -> SQL Editor -> New query).
-- Project: nstktluzwkdnewobjnep
--
-- Safe to re-run: every statement is guarded.
-- Until this runs, the app hides all photo UI (it probes for photo_url at boot),
-- so deploying the new index.html before running this changes nothing for users.

-- 1) Columns -----------------------------------------------------------------
alter table public.menu_items add column if not exists photo_url  text;
alter table public.menu_items add column if not exists photo_path text;

-- 2) Public storage bucket for food photos ------------------------------------
insert into storage.buckets (id, name, public)
values ('food', 'food', true)
on conflict (id) do update set public = true;

-- 3) Storage policies ----------------------------------------------------------
-- Read: anyone may view food photos (customers browse menus, some while signed
-- out). Write: a signed-in user may only touch files under their own <uid>/
-- prefix, which is how uploadFoodPhoto() names them.

drop policy if exists "food read"   on storage.objects;
drop policy if exists "food insert" on storage.objects;
drop policy if exists "food update" on storage.objects;
drop policy if exists "food delete" on storage.objects;

create policy "food read" on storage.objects
  for select using (bucket_id = 'food');

create policy "food insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'food' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "food update" on storage.objects
  for update to authenticated
  using       (bucket_id = 'food' and (storage.foldername(name))[1] = auth.uid()::text)
  with check  (bucket_id = 'food' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "food delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'food' and (storage.foldername(name))[1] = auth.uid()::text);

-- Note: menu_items itself needs no new RLS. Photos are written through the same
-- organizer paths that already insert/update menu_items, and read through the
-- same customer-facing select policy.
