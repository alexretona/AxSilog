-- Axsilog — delivery date on menus
-- Run this in the Supabase SQL editor (Dashboard -> SQL Editor -> New query).
-- Project: nstktluzwkdnewobjnep
--
-- Safe to re-run. Needs 2026-10-26-order-limits-delivery.sql first.
-- menus.deliver_date is the day the organizer delivers (null = work it out:
-- the menu's date, or the next day when delivery is at or before the cutoff).
-- Until this runs the app hides the Same day / Next day picker and infers it.

alter table public.menus add column if not exists deliver_date date;
