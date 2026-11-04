# Buyfirst — Supabase setup

This branch adds the Supabase client wrapper and database/storage schema for the Buyfirst storefront.

## Files
- `supabase.js`: browser client using your project's publishable key. It contains no secret key.
- `supabase-schema.sql`: tables, order-creation RPC, RLS policies, and Storage buckets/policies.
- `index.html`: original storefront is retained on this setup branch pending the UI migration.

## Setup
1. Open your Supabase project dashboard: https://supabase.com/dashboard/project/tnghetxuxxbfrhdfcugy
2. Open **SQL Editor**, create a new query, paste all of `supabase-schema.sql`, and run it.
3. In **Authentication → URL Configuration**, set the Site URL to your GitHub Pages site URL and add that URL (plus its password-reset/callback routes if used) to Redirect URLs.
4. In **Authentication → Providers → Email**, enable email/password sign-in. For testing, decide whether to require email confirmation; production should keep confirmation enabled.
5. Create your first account through the storefront once its Supabase Auth UI is wired. Then run the final admin-promotion SQL shown at the bottom of the schema, replacing the email with the email you used. Do not promote arbitrary users.
6. Check **Storage** and confirm that `product-images` is public and `digital-files` is private.

## Security notes
- A publishable key is designed for public browser code. It does not grant database access by itself; RLS and SQL grants determine what each user can access.
- Never place a Supabase secret key or legacy service-role key in this repository.
- Customers can read only their own orders and order items. Admin operations require a profile whose role is `admin`.
- Orders are created through `create_customer_order`, which recalculates prices and shipping and decrements stock inside Postgres.
- UPI references are stored as unverified references. Payment status stays `pending` until an admin verifies it. This is not a payment gateway.
- The existing demo card form is not a real payment integration. Do not collect or store card numbers, expiry dates, or CVVs. Add a supported payment provider and server-side webhook before offering real card payments.
- Digital files are stored in a private bucket and are accessible only to admins or customers with a paid order for that product.

## Important current status
This is the **database/client foundation**, not yet a completed storefront migration. The current `index.html` still contains its legacy localStorage authentication and storefront state. Do not treat the site as Supabase-integrated or deploy this branch as production until the HTML UI is migrated to call `window.BuyfirstSupabase` and the SQL has been run and tested in your project.

## Client usage
Load Supabase JS v2 before `supabase.js`:
```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
<script src="./supabase.js"></script>
```
Then use `window.BuyfirstSupabase` from the app code. See the methods in `supabase.js`.
