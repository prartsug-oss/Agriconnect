-- AgriConnect in-app notifications
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null,
  title text not null,
  message text not null,
  related_id uuid,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_created_idx on public.notifications(user_id, created_at desc);
alter table public.notifications enable row level security;
drop policy if exists "Users can read their own notifications" on public.notifications;
create policy "Users can read their own notifications" on public.notifications
for select to authenticated using (auth.uid() = user_id);
drop policy if exists "Users can mark their own notifications read" on public.notifications;
create policy "Users can mark their own notifications read" on public.notifications
for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

create or replace function public.notify_order_events()
returns trigger language plpgsql security definer set search_path = ''
as $agri$
begin
  if tg_op = 'INSERT' then
    insert into public.notifications(user_id,type,title,message,related_id)
    values (new.seller_id,'order_received','New order request','A buyer has placed an order. Review it in your Orders section.',new.id);
  elsif new.status is distinct from old.status then
    if new.status = 'accepted' then
      insert into public.notifications(user_id,type,title,message,related_id)
      values (new.buyer_id,'order_accepted','Order accepted','The seller accepted your order.',new.id);
    elsif new.status = 'cancelled' then
      insert into public.notifications(user_id,type,title,message,related_id)
      values (new.buyer_id,'order_cancelled','Order declined','The seller declined your order. Reserved stock has been returned.',new.id);
    elsif new.status = 'in_transit' then
      insert into public.notifications(user_id,type,title,message,related_id)
      values (new.buyer_id,'order_dispatched','Order dispatched','The seller marked your order as in transit.',new.id);
    elsif new.status = 'completed' then
      insert into public.notifications(user_id,type,title,message,related_id)
      values (new.seller_id,'order_completed','Order completed','The buyer confirmed receipt of the order.',new.id);
    end if;
  end if;
  return new;
end;
$agri$;
drop trigger if exists orders_notification_trigger on public.orders;
create trigger orders_notification_trigger after insert or update of status on public.orders
for each row execute function public.notify_order_events();

create or replace function public.notify_delivery_events()
returns trigger language plpgsql security definer set search_path = ''
as $agri$
declare v_profile record;
begin
  if tg_op = 'INSERT' then
    for v_profile in select id from public.profiles where role = 'logistics' loop
      insert into public.notifications(user_id,type,title,message,related_id)
      values (v_profile.id,'delivery_open','Delivery request available','A buyer is requesting transport. Submit a quote if you can serve this route.',new.id);
    end loop;
  else
    if new.transporter_id is distinct from old.transporter_id and new.transporter_id is not null then
      insert into public.notifications(user_id,type,title,message,related_id)
      values (new.transporter_id,'delivery_assigned','Delivery assigned to you','A buyer selected your transport quote. Coordinate pickup with the seller.',new.id);
    end if;
    if new.status is distinct from old.status then
      if new.status = 'picked_up' then
        insert into public.notifications(user_id,type,title,message,related_id)
        values (new.buyer_id,'delivery_picked_up','Produce picked up','Your transporter has picked up the produce.',new.id);
      elsif new.status = 'delivered' then
        insert into public.notifications(user_id,type,title,message,related_id)
        values (new.buyer_id,'delivery_delivered','Delivery completed','Your transporter marked the delivery as completed.',new.id);
        insert into public.notifications(user_id,type,title,message,related_id)
        values (new.seller_id,'delivery_delivered','Delivery completed','The transporter marked this delivery as completed.',new.id);
      elsif new.status = 'cancelled' then
        insert into public.notifications(user_id,type,title,message,related_id)
        values (new.seller_id,'delivery_cancelled','Delivery request cancelled','The buyer cancelled the delivery request.',new.id);
      end if;
    end if;
  end if;
  return new;
end;
$agri$;
drop trigger if exists delivery_notification_trigger on public.delivery_requests;
create trigger delivery_notification_trigger after insert or update of transporter_id,status on public.delivery_requests
for each row execute function public.notify_delivery_events();

create or replace function public.notify_delivery_quote()
returns trigger language plpgsql security definer set search_path = ''
as $agri$
declare v_buyer uuid;
begin
  select buyer_id into v_buyer from public.delivery_requests where id = new.delivery_id;
  insert into public.notifications(user_id,type,title,message,related_id)
  values (v_buyer,'delivery_quote','New delivery quote','A logistics partner submitted a delivery fee. Compare quotes in Deliveries.',new.delivery_id);
  return new;
end;
$agri$;
drop trigger if exists delivery_quote_notification_trigger on public.delivery_quotes;
create trigger delivery_quote_notification_trigger after insert or update of fee on public.delivery_quotes
for each row execute function public.notify_delivery_quote();
