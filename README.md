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
