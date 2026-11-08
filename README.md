# buyfirst + Supabase

Your existing storefront, unchanged in look and behaviour, now backed by a real Supabase (Postgres) database.

## What changed (and what didn't)

| File | What it is |
|---|---|
| `index.html` | Same page shell; CSS/JS moved to their own files. |
| `css/style.css` | **Your original CSS, untouched**, plus a few lines for the loading bar / spinner / error toast. |
| `js/app.js` | Your original app. The `localStorage`/IndexedDB "database" was replaced by Supabase calls. UI code is untouched. |
| `js/config.js` | **The only file you edit**: Supabase URL + anon key. |
| `js/vendor/supabase.js` | supabase-js 2.45.4 (copied locally so GitHub Pages needs no CDN for it). |
| `supabase/schema.sql` | Tables, Row Level Security, secure functions, storage buckets. Run once. |
| `supabase/seed.sql` | Optional: your 6 demo products + banner. |

**Removed on purpose:** the browser-PIN admin lock (replaced by Supabase Auth), mock orders, and `localStorage` as a database.
`localStorage` still holds only the cart and light/dark theme (per-device preferences).

## 1. Create the Supabase project
1. Go to https://supabase.com → **New project** (free plan is fine). Choose a region near your customers (e.g. Mumbai) and save the database password.
2. Wait ~2 minutes until it is ready.

## 2. Run the SQL
1. Dashboard → **SQL Editor → New query**.
2. Paste the whole of `supabase/schema.sql` → **Run**. (Safe to re-run.)
3. Optional: new query → paste `supabase/seed.sql` → **Run** to get sample products.

## 3. Connect your credentials
Dashboard → **Project Settings → API**. Copy:
* **Project URL** (`https://xxxx.supabase.co`)
* **anon public** key (newer projects call it **Publishable key**, `sb_publishable_…`)

Paste them into `js/config.js`. **Never** use the `service_role` / secret key anywhere in this repo.

## 4. Create your owner (admin) account
1. Dashboard → **Authentication → Users → Add user → Create new user**. Enter your email + a strong password, tick **Auto Confirm User**.
2. SQL Editor → run (with your email):
   ```sql
   insert into public.admins (user_id) select id from auth.users where email = 'YOU@EXAMPLE.COM';
   ```
3. On your site click **Owner login** (footer) and sign in. Only users listed in `public.admins` can open the dashboard, and the database itself enforces it (not just the page).

## 5. Authentication settings
Dashboard → **Authentication**:
* **URL Configuration → Site URL**: `https://harshavardhanreddy0005-ui.github.io/Buyfirst-website-/`
* **Providers → Email**: for instant sign-up turn **Confirm email** OFF. If you leave it ON, customers get a confirmation email first; the site already handles both.

## 6. Test locally (optional)
```bash
cd buyfirst-site
python3 -m http.server 8000      # then open http://localhost:8000
```

## 7. Publish on GitHub Pages
1. Open your repo `Buyfirst-website-` on GitHub → **Add file → Upload files**.
2. Drag in **everything inside this folder**: `index.html`, `css/`, `js/`, `supabase/` (keeping the folder structure), plus this README. Commit to `main`.
   (Replace your old `index.html`.) Keep a copy of your old one if you like.
3. Repo **Settings → Pages**: Source = *Deploy from a branch*, Branch = `main`, folder `/ (root)` → Save.
4. Wait ~1 minute, open `https://harshavardhanreddy0005-ui.github.io/Buyfirst-website-/`. Hard-refresh (Ctrl+Shift+R) if you still see the old site.

Also upload these via git if you prefer:
```bash
git add . && git commit -m "Connect Supabase" && git push
```

## How the data is organised
| Table | Who can read | Who can write |
|---|---|---|
| `products` | everyone (live ones) | admin |
| `product_private` (cost price, supplier, download link) | **admin only** | admin |
| `customers` | the customer themself, admin | created automatically at sign-up; customer can edit name/phone |
| `orders` | the customer's own, admin | **only via secure functions** (`place_order`, `cancel_order`, …); admin can change payment/shipping status |
| `order_costs` | admin only | server function |
| `enquiries` | admin only | anyone can submit (contact form) |
| `reviews` | everyone (non-hidden) | logged-in users (own), admin moderates |
| `ads`, `policies`, `settings`, `promo_codes` | everyone | admin |
| `admins` | nobody (checked server-side by `is_admin()`) | you, via SQL |

Security highlights
* RLS is **on for every table**; table privileges are also minimised.
* Prices, discounts, shipping, stock and the order total are **calculated by the database** in `place_order()`; a tampered browser cannot buy at ₹1.
* Order IDs (`BF1001`, `BF1002`, …) come from a database sequence → always unique.
* E-book links live in `product_private`; `get_download_url()` returns them only to the owner or a buyer whose payment you approved. Uploaded e-book files go to a private storage bucket.
* Cost price / supplier info never reaches customers' browsers.
* No card numbers or CVV are collected or stored. (The "Card" option in your original site is a non-functional demo; nothing typed there is read or saved.)

## Known limits / suggestions
* Customers log in with **email** (the old "email or mobile" login can't be done safely with Supabase Auth without exposing emails).
* No "forgot password" screen yet: reset users from Dashboard → Authentication → Users, or ask me to add it.
* UPI payments are still verified manually (UTR → *Approve payment*), as before. For automatic payments, integrate Razorpay/Cashfree later.
* "Track order" works with Order ID + phone for guests; add CAPTCHA/rate-limiting before heavy public traffic.
* After placing an order the WhatsApp tab may be blocked by the browser's pop-up blocker; the "Send order to the seller on WhatsApp" button on the confirmation page always works.
