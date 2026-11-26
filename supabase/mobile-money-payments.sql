-- AgriConnect mobile-money payment preparation.
-- Safe to apply to an existing database after the current schema and notifications migrations.
-- This records payment attempts only. It does not contact MTN or Airtel or confirm a transfer.

create table if not exists public.payment_attempts (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete restrict,
  buyer_id uuid not null references public.profiles(id),
  seller_id uuid not null references public.profiles(id),
  provider text not null check (provider in ('mtn_momo','airtel_money')),
  phone_number text not null check (phone_number ~ '^\+2567[0-9]{8}$'),
  amount numeric(14,2) not null check (amount > 0),
  currency text not null default 'UGX' check (currency = 'UGX'),
  status text not null default 'awaiting_provider'
    check (status in ('awaiting_provider','processing','succeeded','failed','cancelled','refunded')),
  provider_reference text unique,
  provider_transaction_id text unique,
  failure_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists payment_attempts_buyer_created_idx
  on public.payment_attempts(buyer_id, created_at desc);
create index if not exists payment_attempts_order_created_idx
  on public.payment_attempts(order_id, created_at desc);

create unique index if not exists payment_attempts_one_open_or_paid_per_order_idx
  on public.payment_attempts(order_id)
  where status in ('awaiting_provider','processing','succeeded');

alter table public.payment_attempts enable row level security;

drop policy if exists "Buyers can view their own payment attempts" on public.payment_attempts;
create policy "Buyers can view their own payment attempts"
on public.payment_attempts for select to authenticated
using (auth.uid() = buyer_id);

-- No client insert/update/delete policies. All new attempts go through this RPC.
create or replace function public.create_mobile_money_payment(
  p_order_id uuid,
  p_provider text,
  p_phone_number text
)
returns public.payment_attempts
language plpgsql
security definer
set search_path = ''
as $agri$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_payment public.payment_attempts%rowtype;
begin
  if v_uid is null then raise exception 'Sign in to prepare a payment.'; end if;
  if p_provider not in ('mtn_momo','airtel_money') then
    raise exception 'Choose MTN Mobile Money or Airtel Money.';
  end if;
  if p_phone_number is null or p_phone_number !~ '^\+2567[0-9]{8}$' then
    raise exception 'Enter a valid Uganda mobile-money number.';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'Order not found.'; end if;
  if v_order.buyer_id <> v_uid then raise exception 'Only the buyer can prepare this payment.'; end if;
  if v_order.status <> 'accepted' then
    raise exception 'Payment can be prepared after the seller accepts the order and before dispatch.';
  end if;
  if v_order.total_amount <= 0 then raise exception 'This order has no payable amount.'; end if;

  if exists (
    select 1 from public.payment_attempts
    where order_id = p_order_id and status in ('awaiting_provider','processing','succeeded')
  ) then
    raise exception 'An active or successful payment attempt already exists for this order.';
  end if;

  insert into public.payment_attempts(order_id,buyer_id,seller_id,provider,phone_number,amount,currency,status)
  values (v_order.id,v_order.buyer_id,v_order.seller_id,p_provider,p_phone_number,v_order.total_amount,'UGX','awaiting_provider')
  returning * into v_payment;

  return v_payment;
end;
$agri$;

revoke all on function public.create_mobile_money_payment(uuid,text,text) from public;
grant execute on function public.create_mobile_money_payment(uuid,text,text) to authenticated;
