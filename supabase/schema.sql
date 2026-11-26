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
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.produce_listings (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  category text not null,
  description text,
  quantity numeric(12,2) not null check (quantity > 0),
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
create policy "Farmers can create listings"
  on public.produce_listings for insert to authenticated with check (auth.uid() = seller_id);
create policy "Owners can update their listings"
  on public.produce_listings for update to authenticated using (auth.uid() = seller_id) with check (auth.uid() = seller_id);
create policy "Owners can remove their listings"
  on public.produce_listings for delete to authenticated using (auth.uid() = seller_id);

create policy "Buyers and sellers can view their orders"
  on public.orders for select to authenticated using (auth.uid() = buyer_id or auth.uid() = seller_id);
create policy "Buyers can create valid orders"
  on public.orders for insert to authenticated
  with check (
    auth.uid() = buyer_id
    and exists (
      select 1 from public.produce_listings listing
      where listing.id = orders.listing_id
        and listing.seller_id = orders.seller_id
        and listing.status = 'active'
        and orders.quantity <= listing.quantity
    )
  );

-- Order status changes are intentionally disabled in this milestone.
-- Add a constrained seller-only RPC before enabling order updates.

-- Create a profile automatically when a new auth user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
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
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
