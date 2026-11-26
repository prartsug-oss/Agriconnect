# AgriConnect

A premium agricultural commerce platform connecting farmers, buyers, suppliers and logistics partners, starting in Uganda.

## Stack

- Next.js App Router + TypeScript
- Tailwind CSS v4
- Supabase (optional backend integration; configure environment variables to enable it)

## Getting started

1. Install dependencies with npm install.
2. Copy .env.example to .env.local and add your Supabase project values.
3. Run npm run dev and open http://localhost:3000.

The dashboard includes a local interactive preview mode so the interface can be explored before Supabase credentials are configured. Listings created in preview mode are held in browser state and are not shared or persisted to a production database.

## Supabase setup

1. Create a Supabase project.
2. Add NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY to .env.local.
3. Run supabase/schema.sql in the Supabase SQL Editor.
4. Enable email/password authentication in Supabase Auth.

The schema includes profiles, produce listings, orders and row-level security policies. Never expose a service-role key in browser environment variables.

## Scripts

- npm run dev - local development
- npm run build - production build
- npm run start - production server
- npm run lint - ESLint

## Current scope

The current milestone includes the responsive dashboard, Supabase authentication, live produce listings, order requests, seller order management and database-backed inventory controls. Payments, maps, delivery-provider integrations and production analytics are not implemented yet.


## Live authentication and marketplace API

1. Create a Supabase project and add `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` to `.env.local`.
2. Run `supabase/schema.sql` in the Supabase SQL Editor.
3. Enable email/password authentication in Supabase Auth.
4. In Supabase Auth URL Configuration, set the Site URL and add `http://localhost:3000/auth/callback` and your deployed domain's `/auth/callback` as allowed redirect URLs.
5. Add the same public Supabase values to your hosting provider's environment variables.

The Next.js proxy refreshes Supabase sessions. The server API exposes:

- `GET /api/listings` - active marketplace listings, with optional `q` and `category` filters.
- `POST /api/listings` - create a listing for the signed-in user.
- `GET /api/me` - read the signed-in user's profile.
- `DELETE /api/me` - sign out.

Without Supabase credentials, the dashboard uses illustrative sample listings. It does not create real accounts or save listings to a shared database. Sales, order and market analytics remain placeholders until those modules are implemented.

- `GET /api/orders` - list orders for the signed-in buyer or seller.
- `POST /api/orders` - submit an order request using the listing's server-verified seller and current price. Payment is not collected yet.


## Order management and inventory

The order workflow uses two PostgreSQL RPC functions defined in `supabase/schema.sql`:

- `create_order_request` locks the selected listing, checks available stock, decrements inventory and creates the order in one transaction. Concurrent requests cannot reserve more stock than is available.
- `update_order_status` enforces role-aware transitions: sellers can accept or reject pending orders and mark accepted orders as dispatched; buyers can confirm receipt after dispatch. Rejecting a pending order restores its reserved quantity.

The API exposes `PATCH /api/orders` for status changes. Order updates are performed through the constrained database function rather than direct client-side table updates.

**Database setup note:** use the current `supabase/schema.sql` when setting up a fresh Supabase project. If you already ran an earlier version of the schema, do not blindly rerun the full file because the initial type and table declarations are not a migration. Apply the new functions and inventory constraint as a reviewed migration first.


## Supplier and logistics partner directory

Supplier and logistics accounts can publish a business profile from the matching dashboard section. Profiles include business name, contact phone, base district, service description and districts covered. Signed-in users can browse the supplier and logistics directories. Verification is an administrative field and is not self-awarded by businesses.

The directory API provides `GET /api/directory?role=supplier`, `GET /api/directory?role=logistics`, and authenticated `PATCH /api/directory` for a user's own partner profile.


## Delivery management

Apply `supabase/delivery-management.sql` in the Supabase SQL Editor when upgrading an existing database. Fresh installations can use the complete `supabase/schema.sql` file.

The delivery API exposes:
- `GET /api/deliveries` - view delivery requests permitted by database row-level security.
- `POST /api/deliveries` with `action: "request"` - a buyer requests delivery for an accepted order.
- `POST /api/deliveries` with `action: "quote"` - a logistics account submits or updates its fee quote.
- `POST /api/deliveries` with `action: "choose"` - the buyer selects a quote and assigns the transporter.
- `POST /api/deliveries` with `action: "status"` - the assigned transporter marks pickup or delivery; the buyer may cancel an unassigned request.

Database functions enforce order ownership, account role, quote selection and delivery status transitions. Delivery fees are stored separately from the produce order total; checkout and payment collection are not yet implemented.


## In-app notifications

For an existing database, apply `supabase/delivery-management.sql` first, then `supabase/notifications.sql` to add the notifications table, secure read access and database event triggers. Fresh installations use the updated `supabase/schema.sql`.

Notifications are generated automatically for new order requests, seller decisions, dispatch and completion, open delivery requests, transporter quotes, transporter assignment, pickup, delivery completion and cancellation. The dashboard bell opens the notification centre; users can mark individual notifications or all notifications as read.

The API exposes `GET /api/notifications` and `PATCH /api/notifications`. Notification content is written by database triggers; the authenticated user can only mark their own notifications as read.


## Financial overview

The signed-in dashboard includes a Finance section backed by `GET /api/finance`. It summarises completed and open produce order values, delivery-fee values and recent order/delivery activity. Results are scoped to the signed-in user's role and records visible under Supabase row-level security.

**Important:** these figures represent order values and agreed delivery fees, not money received or paid. The platform does not yet collect payments, verify mobile-money transfers, calculate a platform commission or issue seller payouts. Payment-provider integration and a properly controlled settlement ledger remain separate work.


## Mobile-money payment preparation

For an existing Supabase database, apply `supabase/mobile-money-payments.sql` after the current schema, delivery and notifications migrations. Fresh installations can use the updated `supabase/schema.sql`.

The payment API provides:
- `GET /api/payments` - list the signed-in buyer's own payment attempts.
- `POST /api/payments` - prepare an attempt for an accepted order using `mtn_momo` or `airtel_money` and a Uganda mobile number.

The database snapshots the order amount in UGX, checks that the signed-in user is the buyer, and prevents duplicate active or successful attempts for the same order. Payment records are buyer-readable only; mobile-money numbers are not exposed to sellers. Clients cannot directly insert or update payment records or mark a payment successful.

**Gateway status:** this is a secure payment-record foundation only. It does not yet call MTN MoMo or Airtel Money, send a USSD/mobile prompt, verify provider callbacks, collect money, or settle sellers. Records remain `awaiting_provider` until a verified provider integration is added. Do not treat this status as proof of payment. Never enter or store a mobile-money PIN.
