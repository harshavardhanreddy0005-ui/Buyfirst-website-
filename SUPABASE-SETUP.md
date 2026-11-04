# Buyfirst — Supabase integration

## Current project status

- Supabase project is connected to this repository.
- Email authentication is enabled.
- Site URL and Redirect URL have been configured in Supabase Authentication.
- The existing database already contains products and orders.
- Existing tables, policies, and the order-creation function have been detected.

**Do not run `supabase-schema.sql` or the initial migration against the existing project.** The schema script is a reference for the original proposed structure; it is not a migration to rerun. Preserve the current database and its records.

## Branch and deployment

- Work branch: `supabase-integration`
- Production branch: `main` (leave unchanged until testing is complete)
- Supabase project: `https://tnghetxuxxbfrhdfcugy.supabase.co`

## Browser configuration

`supabase.js` uses the Supabase project URL and a publishable key. A publishable key is intended for browser use, but database access must still be protected by correct Row Level Security (RLS) policies.

Never put a Supabase secret key or legacy service-role key in this repository or in browser code.

## Important payment notes

- UPI references must remain pending until the seller verifies the payment.
- The existing demo card form is not a real payment integration. Do not collect or store card numbers, expiry dates, or CVVs.
- A real card/UPI gateway requires a supported payment provider and server-side payment verification/webhooks.

## Digital files

Digital downloads should be stored in a private Supabase Storage bucket and issued only after a paid order is verified. Public product images can use a separate public bucket.

## Next development steps

1. Map the current storefront's product and order fields to the existing database.
2. Replace browser-only customer login with Supabase Auth.
3. Load products and customer orders from Supabase.
4. Create orders through the database order RPC so prices and stock are validated server-side.
5. Replace the browser PIN admin gate with Supabase Auth plus an admin role checked by RLS.
6. Test customer and admin permissions before merging or deploying.

The storefront migration is not complete yet. Do not treat the current website as Supabase-integrated until these steps have been implemented and tested.
