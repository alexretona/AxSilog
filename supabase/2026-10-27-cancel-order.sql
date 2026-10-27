-- Axsilog — let customers cancel their own new orders
-- Run this in the Supabase SQL editor (Dashboard -> SQL Editor -> New query).
-- Project: nstktluzwkdnewobjnep
--
-- Safe to re-run.
-- Cancelling used to be two plain deletes (order_items, then orders). When RLS
-- does not allow a delete, Supabase returns no error and deletes nothing, so
-- the Cancel button appeared to do nothing. This function does the same thing
-- server-side, but only for the caller's own order while it is still 'new' and
-- not delivered, and raises a readable error otherwise. The page falls back to
-- the old deletes until this exists.

create or replace function public.cancel_my_order(p_order uuid)
returns void language plpgsql security definer set search_path = public as $$
declare o orders%rowtype;
begin
  select * into o from orders where id = p_order for update;
  if not found then
    raise exception 'Order not found (it may already be cancelled).';
  end if;
  if o.customer_id::text is distinct from auth.uid()::text then
    raise exception 'You can only cancel your own orders.';
  end if;
  if o.status is distinct from 'new' or coalesce(o.delivered, false) then
    raise exception 'This order can no longer be cancelled — the organizer has already confirmed it.';
  end if;
  delete from order_items where order_id = p_order;
  delete from orders where id = p_order;
end $$;

revoke execute on function public.cancel_my_order(uuid) from public, anon;
grant execute on function public.cancel_my_order(uuid) to authenticated;
