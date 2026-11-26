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
