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
