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

This first committed milestone establishes the premium responsive dashboard, marketplace browsing, category filtering, search and an interactive create-listing preview. Production authentication, live database writes, payments, maps and logistics integrations require configuration and subsequent implementation.


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
