-- Axsilog — order limits and delivery time on menus
-- Run this in the Supabase SQL editor (Dashboard -> SQL Editor -> New query).
-- Project: nstktluzwkdnewobjnep
--
-- Safe to re-run: every statement is guarded or replaces itself.
-- Until this runs, the app hides the limit / delivery-time UI (it probes for
-- menus.max_orders at boot), so deploying index.html first changes nothing.

-- 1) Columns -----------------------------------------------------------------
-- menus.max_orders     cap on how many orders a menu accepts (null = no cap)
-- menus.deliver_time   when the organizer expects to deliver (null = not set)
-- menu_items.max_qty   servings available for one dish (null = no cap)
alter table public.menus      add column if not exists max_orders   int  check (max_orders is null or max_orders > 0);
alter table public.menus      add column if not exists deliver_time time;
alter table public.menu_items add column if not exists max_qty      int  check (max_qty is null or max_qty > 0);

-- 2) Availability, readable by customers -------------------------------------
-- Customers can only read their own orders under RLS, so they cannot count
-- what is left themselves. This returns, per menu, how many orders it has and
-- how many servings of each dish are taken (keyed by lower(trim(name)), which
-- is how order_items rows are matched back to menu_items).
-- Ids are passed as text so this works whatever type menus.id is.
create or replace function public.get_menu_availability(menu_ids text[])
returns table(menu_id text, order_count int, sold jsonb)
language sql stable security definer set search_path = public as $$
  select m.id::text,
         (select count(*)::int from orders o where o.menu_id = m.id),
         coalesce((select jsonb_object_agg(s.k, s.q) from (
             select lower(trim(oi.name)) k, sum(coalesce(oi.qty, 1))::int q
             from order_items oi join orders o on o.id = oi.order_id
             where o.menu_id = m.id
             group by 1) s), '{}'::jsonb)
  from menus m
  where m.id::text = any(menu_ids);
$$;
grant execute on function public.get_menu_availability(text[]) to anon, authenticated;

-- 3) Enforcement --------------------------------------------------------------
-- The page checks availability before placing an order, but two customers can
-- order at the same moment, so the database has the final say. Both triggers
-- lock the menu row first, which makes simultaneous orders for one menu take
-- turns instead of both slipping under the limit.

create or replace function public.enforce_menu_order_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare lim int; n int;
begin
  select max_orders into lim from menus where id = new.menu_id for update;
  if lim is not null then
    select count(*) into n from orders where menu_id = new.menu_id;
    if n >= lim then
      raise exception 'Sorry, this menu is fully booked (% orders max).', lim;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists menu_order_limit on public.orders;
create trigger menu_order_limit before insert on public.orders
  for each row execute function public.enforce_menu_order_limit();

create or replace function public.enforce_menu_item_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare mid orders.menu_id%type; lim int; taken int;
begin
  select o.menu_id into mid from orders o where o.id = new.order_id;
  if mid is null then return new; end if;
  perform 1 from menus where id = mid for update;
  select min(mi.max_qty) into lim from menu_items mi
   where mi.menu_id = mid and lower(trim(mi.name)) = lower(trim(new.name));
  if lim is not null then
    select coalesce(sum(coalesce(oi.qty, 1)), 0) into taken
      from order_items oi join orders o on o.id = oi.order_id
     where o.menu_id = mid and lower(trim(oi.name)) = lower(trim(new.name));
    if taken + coalesce(new.qty, 1) > lim then
      raise exception 'Sorry, only % left of %.', greatest(lim - taken, 0), new.name;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists menu_item_limit on public.order_items;
create trigger menu_item_limit before insert on public.order_items
  for each row execute function public.enforce_menu_item_limit();
