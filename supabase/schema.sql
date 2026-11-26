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
