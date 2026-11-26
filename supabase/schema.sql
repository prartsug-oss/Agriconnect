-- AgriConnect initial database schema
-- Run this file in the Supabase SQL Editor.

create extension if not exists pgcrypto;

create type public.account_role as enum ('farmer', 'buyer', 'supplier', 'logistics', 'admin');
create type public.listing_status as enum ('active', 'sold', 'paused');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role public.account_role not null default 'farmer',
  phone text,
  district text,
  business_name text,
  service_description text,
  coverage_districts text,
  is_verified boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.produce_listings (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  category text not null,
  description text,
  quantity numeric(12,2) not null check (quantity >= 0),
  unit text not null default 'kg',
  price_per_unit numeric(12,2) not null check (price_per_unit >= 0),
  district text not null,
  image_url text,
  status public.listing_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.produce_listings(id),
  buyer_id uuid not null references public.profiles(id),
  seller_id uuid not null references public.profiles(id),
  quantity numeric(12,2) not null check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  total_amount numeric(14,2) generated always as (quantity * unit_price) stored,
  status text not null default 'pending' check (status in ('pending','accepted','in_transit','completed','cancelled')),
  delivery_district text,
  notes text,
  created_at timestamptz not null default now()
);

create index produce_listings_status_created_idx on public.produce_listings(status, created_at desc);
create index produce_listings_district_idx on public.produce_listings(district);
create index orders_buyer_created_idx on public.orders(buyer_id, created_at desc);
create index orders_seller_created_idx on public.orders(seller_id, created_at desc);

alter table public.profiles enable row level security;
alter table public.produce_listings enable row level security;
alter table public.orders enable row level security;

create policy "Profiles are viewable by authenticated users"
  on public.profiles for select to authenticated using (true);
create policy "Users can create their own profile"
  on public.profiles for insert to authenticated with check (auth.uid() = id);
create policy "Users can update their own profile"
  on public.profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

create policy "Active listings are visible to everyone"
  on public.produce_listings for select using (status = 'active' or auth.uid() = seller_id);
create policy "Farmers and suppliers can create listings"
  on public.produce_listings for insert to authenticated
  with check (
    auth.uid() = seller_id
    and exists (
      select 1 from public.profiles
      where id = auth.uid() and role in ('farmer', 'supplier')
    )
  );
create policy "Owners can update their listings"
  on public.produce_listings for update to authenticated
  using (auth.uid() = seller_id and exists (select 1 from public.profiles where id = auth.uid() and role in ('farmer','supplier')))
  with check (auth.uid() = seller_id and exists (select 1 from public.profiles where id = auth.uid() and role in ('farmer','supplier')));
create policy "Owners can remove their listings"
  on public.produce_listings for delete to authenticated
  using (auth.uid() = seller_id and exists (select 1 from public.profiles where id = auth.uid() and role in ('farmer','supplier')));

create policy "Buyers and sellers can view their orders"
  on public.orders for select to authenticated using (auth.uid() = buyer_id or auth.uid() = seller_id);
-- Orders are created atomically: lock the listing, verify stock, decrement it,
-- and create the order in one transaction. This prevents overselling.
create or replace function public.create_order_request(
  p_listing_id uuid,
  p_quantity numeric,
  p_delivery_district text,
  p_notes text default null
)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $agri$
declare
  v_user_id uuid := auth.uid();
  v_listing public.produce_listings%rowtype;
  v_order public.orders%rowtype;
begin
  if v_user_id is null then
    raise exception 'Sign in to place an order.';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Enter a valid order quantity.';
  end if;
  if p_delivery_district is null or length(trim(p_delivery_district)) = 0 or length(trim(p_delivery_district)) > 80 then
    raise exception 'Enter a valid delivery district.';
  end if;

  select * into v_listing
  from public.produce_listings
  where id = p_listing_id
  for update;

  if not found or v_listing.status <> 'active' then
    raise exception 'This listing is no longer available.';
  end if;
  if v_listing.seller_id = v_user_id then
    raise exception 'You cannot order your own listing.';
  end if;
  if p_quantity > v_listing.quantity then
    raise exception 'Requested quantity exceeds the available stock.';
  end if;

  update public.produce_listings
  set quantity = quantity - p_quantity,
      status = case when quantity - p_quantity = 0 then 'sold'::public.listing_status else status end,
      updated_at = now()
  where id = p_listing_id;

  insert into public.orders (
    listing_id, buyer_id, seller_id, quantity, unit_price, delivery_district, notes
  ) values (
    v_listing.id, v_user_id, v_listing.seller_id, p_quantity, v_listing.price_per_unit,
    trim(p_delivery_district), nullif(left(coalesce(p_notes, ''), 500), '')
  ) returning * into v_order;

  return v_order;
end;
$agri$;

-- Only the seller can accept, reject or dispatch. The buyer can confirm
-- completion after dispatch. Rejected stock is returned to the listing.
create or replace function public.update_order_status(
  p_order_id uuid,
  p_status text
)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $agri$
declare
  v_user_id uuid := auth.uid();
  v_order public.orders%rowtype;
begin
  if v_user_id is null then
    raise exception 'Sign in to update an order.';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found.';
  end if;

  if v_user_id = v_order.seller_id then
    if p_status = 'accepted' and v_order.status = 'pending' then
      update public.orders set status = 'accepted' where id = p_order_id returning * into v_order;
    elsif p_status = 'in_transit' and v_order.status = 'accepted' then
      update public.orders set status = 'in_transit' where id = p_order_id returning * into v_order;
    elsif p_status = 'cancelled' and v_order.status = 'pending' then
      update public.orders set status = 'cancelled' where id = p_order_id returning * into v_order;
      update public.produce_listings
      set quantity = quantity + v_order.quantity,
          status = case when status = 'sold' then 'active'::public.listing_status else status end,
          updated_at = now()
      where id = v_order.listing_id;
    else
      raise exception 'This seller action is not allowed for the current order status.';
    end if;
  elsif v_user_id = v_order.buyer_id then
    if p_status = 'completed' and v_order.status = 'in_transit' then
      update public.orders set status = 'completed' where id = p_order_id returning * into v_order;
    else
      raise exception 'Buyers can confirm completion only after dispatch.';
    end if;
  else
    raise exception 'You are not authorised to update this order.';
  end if;

  return v_order;
end;
$agri$;

revoke all on function public.create_order_request(uuid, numeric, text, text) from public;
revoke all on function public.update_order_status(uuid, text) from public;
grant execute on function public.create_order_request(uuid, numeric, text, text) to authenticated;
grant execute on function public.update_order_status(uuid, text) to authenticated;

-- Create a profile automatically when a new auth user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $agri$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    case
      when new.raw_user_meta_data ->> 'role' in ('farmer','buyer','supplier','logistics','admin')
        then (new.raw_user_meta_data ->> 'role')::public.account_role
      else 'farmer'::public.account_role
    end
  );
  return new;
end;
$agri$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- AgriConnect delivery management
-- Safe to apply to an existing database after the original schema.

create table if not exists public.delivery_requests (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id) on delete cascade,
  buyer_id uuid not null references public.profiles(id),
  seller_id uuid not null references public.profiles(id),
  transporter_id uuid references public.profiles(id),
  pickup_district text not null,
  delivery_district text not null,
  delivery_fee numeric(14,2),
  status text not null default 'requested'
    check (status in ('requested','assigned','picked_up','delivered','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.delivery_quotes (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references public.delivery_requests(id) on delete cascade,
  transporter_id uuid not null references public.profiles(id),
  fee numeric(14,2) not null check (fee >= 0),
  notes text,
  status text not null default 'pending' check (status in ('pending','accepted','declined')),
  created_at timestamptz not null default now(),
  unique (delivery_id, transporter_id)
);

create index if not exists delivery_requests_buyer_created_idx on public.delivery_requests(buyer_id, created_at desc);
create index if not exists delivery_requests_transporter_status_idx on public.delivery_requests(transporter_id, status);
create index if not exists delivery_quotes_delivery_idx on public.delivery_quotes(delivery_id, created_at);

alter table public.delivery_requests enable row level security;
alter table public.delivery_quotes enable row level security;

drop policy if exists "Related users can view delivery requests" on public.delivery_requests;
create policy "Related users can view delivery requests"
on public.delivery_requests for select to authenticated
using (
  auth.uid() = buyer_id or auth.uid() = seller_id or auth.uid() = transporter_id
  or (status = 'requested' and exists (
    select 1 from public.profiles p where p.id = auth.uid() and p.role = 'logistics'
  ))
);

drop policy if exists "Related users can view delivery quotes" on public.delivery_quotes;
create policy "Related users can view delivery quotes"
on public.delivery_quotes for select to authenticated
using (
  transporter_id = auth.uid()
  or exists (
    select 1 from public.delivery_requests d
    where d.id = delivery_id and (d.buyer_id = auth.uid() or d.seller_id = auth.uid())
  )
);

create or replace function public.create_delivery_request(p_order_id uuid, p_pickup_district text default null)
returns public.delivery_requests
language plpgsql security definer set search_path = ''
as $agri$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_delivery public.delivery_requests%rowtype;
  v_pickup text;
begin
  if v_uid is null then raise exception 'Sign in to request delivery.'; end if;
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'Order not found.'; end if;
  if v_order.buyer_id <> v_uid then raise exception 'Only the buyer can request delivery.'; end if;
  if v_order.status <> 'accepted' then raise exception 'Delivery can be requested after the seller accepts the order.'; end if;
  if exists (select 1 from public.delivery_requests where order_id = p_order_id) then
    raise exception 'A delivery request already exists for this order.';
  end if;
  select district into v_pickup from public.produce_listings where id = v_order.listing_id;
  if p_pickup_district is not null and length(trim(p_pickup_district)) > 80 then
    raise exception 'Pickup district is too long.';
  end if;
  insert into public.delivery_requests(order_id,buyer_id,seller_id,pickup_district,delivery_district)
  values (p_order_id,v_uid,v_order.seller_id,coalesce(nullif(trim(p_pickup_district),''),coalesce(v_pickup,'Not specified')),v_order.delivery_district)
  returning * into v_delivery;
  return v_delivery;
end;
$agri$;

create or replace function public.submit_delivery_quote(p_delivery_id uuid, p_fee numeric, p_notes text default null)
returns public.delivery_quotes
language plpgsql security definer set search_path = ''
as $agri$
declare
  v_uid uuid := auth.uid();
  v_delivery public.delivery_requests%rowtype;
  v_quote public.delivery_quotes%rowtype;
begin
  if v_uid is null then raise exception 'Sign in to submit a delivery quote.'; end if;
  if p_fee is null or p_fee < 0 or p_fee > 100000000 then raise exception 'Enter a valid delivery fee.'; end if;
  if not exists (select 1 from public.profiles where id = v_uid and role = 'logistics') then
    raise exception 'Only logistics accounts can submit delivery quotes.';
  end if;
  select * into v_delivery from public.delivery_requests where id = p_delivery_id for update;
  if not found or v_delivery.status <> 'requested' then raise exception 'This delivery is no longer accepting quotes.'; end if;
  if v_delivery.buyer_id = v_uid or v_delivery.seller_id = v_uid then raise exception 'You cannot quote on your own delivery.'; end if;
  insert into public.delivery_quotes(delivery_id,transporter_id,fee,notes)
  values (p_delivery_id,v_uid,p_fee,nullif(left(coalesce(p_notes,''),300),''))
  on conflict (delivery_id,transporter_id) do update
    set fee = excluded.fee, notes = excluded.notes, status = 'pending', created_at = now()
  returning * into v_quote;
  return v_quote;
end;
$agri$;

create or replace function public.choose_delivery_quote(p_quote_id uuid)
returns public.delivery_requests
language plpgsql security definer set search_path = ''
as $agri$
declare
  v_uid uuid := auth.uid();
  v_quote public.delivery_quotes%rowtype;
  v_delivery public.delivery_requests%rowtype;
begin
  if v_uid is null then raise exception 'Sign in to choose a transporter.'; end if;
  select * into v_quote from public.delivery_quotes where id = p_quote_id;
  if not found then raise exception 'Delivery quote not found.'; end if;
  select * into v_delivery from public.delivery_requests where id = v_quote.delivery_id for update;
  if v_delivery.buyer_id <> v_uid then raise exception 'Only the buyer can choose a transporter.'; end if;
  if v_delivery.status <> 'requested' or v_quote.status <> 'pending' then raise exception 'This quote is no longer available.'; end if;
  update public.delivery_requests
    set transporter_id = v_quote.transporter_id, delivery_fee = v_quote.fee,
        status = 'assigned', updated_at = now()
    where id = v_delivery.id returning * into v_delivery;
  update public.delivery_quotes set status = case when id = p_quote_id then 'accepted' else 'declined' end
    where delivery_id = v_delivery.id;
  return v_delivery;
end;
$agri$;

create or replace function public.update_delivery_status(p_delivery_id uuid, p_status text)
returns public.delivery_requests
language plpgsql security definer set search_path = ''
as $agri$
declare
  v_uid uuid := auth.uid();
  v_delivery public.delivery_requests%rowtype;
begin
  if v_uid is null then raise exception 'Sign in to update delivery progress.'; end if;
  select * into v_delivery from public.delivery_requests where id = p_delivery_id for update;
  if not found then raise exception 'Delivery request not found.'; end if;
  if v_uid = v_delivery.transporter_id then
    if p_status = 'picked_up' and v_delivery.status = 'assigned' then
      update public.delivery_requests set status = 'picked_up', updated_at = now() where id = p_delivery_id returning * into v_delivery;
    elsif p_status = 'delivered' and v_delivery.status = 'picked_up' then
      update public.delivery_requests set status = 'delivered', updated_at = now() where id = p_delivery_id returning * into v_delivery;
    else raise exception 'This transporter action is not allowed for the current delivery status.';
    end if;
  elsif v_uid = v_delivery.buyer_id and p_status = 'cancelled' and v_delivery.status = 'requested' then
    update public.delivery_requests set status = 'cancelled', updated_at = now() where id = p_delivery_id returning * into v_delivery;
  else
    raise exception 'You are not authorised to make this delivery update.';
  end if;
  return v_delivery;
end;
$agri$;

revoke all on function public.create_delivery_request(uuid,text) from public;
revoke all on function public.submit_delivery_quote(uuid,numeric,text) from public;
revoke all on function public.choose_delivery_quote(uuid) from public;
revoke all on function public.update_delivery_status(uuid,text) from public;
grant execute on function public.create_delivery_request(uuid,text) to authenticated;
grant execute on function public.submit_delivery_quote(uuid,numeric,text) to authenticated;
grant execute on function public.choose_delivery_quote(uuid) to authenticated;
grant execute on function public.update_delivery_status(uuid,text) to authenticated;


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
