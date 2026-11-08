-- =====================================================================
--  BUYFIRST  ·  Supabase schema, Row Level Security, RPCs & Storage
--  Run this ONCE in: Supabase Dashboard → SQL Editor → New query → Run
--  Safe to re-run (uses IF NOT EXISTS / CREATE OR REPLACE / DROP POLICY IF EXISTS).
-- =====================================================================

-- ---------- 0. Helpers ------------------------------------------------
create table if not exists public.admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security;          -- no policies => nobody can read it directly

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.admins a where a.user_id = auth.uid()) $$;

-- ---------- 1. Products ----------------------------------------------
create table if not exists public.products (
  id            bigint generated always as identity primary key,       -- product ID
  name          text    not null check (char_length(name) between 1 and 200),
  description   text    not null default '' check (char_length(description) <= 5000),
  category      text    not null default 'General' check (char_length(category) <= 80),
  image_url     text,                                                   -- cover image
  images        text[]  not null default '{}',                          -- gallery (cover first)
  price         numeric(10,2) not null check (price > 0),
  mrp           numeric(10,2) not null check (mrp > 0),
  stock         integer not null default 0 check (stock >= 0),
  dispatch_days integer not null default 3 check (dispatch_days >= 0),
  rating        numeric(2,1) not null default 4.5 check (rating between 0 and 5),
  hot           boolean not null default false,
  tags          text    not null default '',
  variants      text[]  not null default '{}',
  is_digital    boolean not null default false,
  is_live       boolean not null default true,
  return_type   text    not null default 'both' check (return_type in ('both','exch','ret','none')),
  return_days   integer not null default 7 check (return_days between 1 and 60),
  return_note   text    not null default '',
  pages         integer not null default 0,
  emoji         text    not null default '🛍️',
  hue           integer not null default floor(random()*360)::int,
  created_at    timestamptz not null default now(),
  check (mrp >= price)
);

-- Private product data: NEVER readable by customers (cost price, supplier, download file)
create table if not exists public.product_private (
  product_id    bigint primary key references public.products(id) on delete cascade,
  cost          numeric(10,2) not null default 0 check (cost >= 0),
  supplier      text not null default '',
  supplier_link text not null default '',
  sku           text not null default '',
  download_url  text,         -- https link OR a path inside the private 'downloads' storage bucket
  file_name     text
);

-- ---------- 2. Customers ---------------------------------------------
create table if not exists public.customers (
  id         uuid primary key references auth.users(id) on delete cascade,
  name       text not null default '',
  phone      text not null default '',
  email      text not null default '',
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.customers (id, name, phone, email)
  values (new.id,
          left(coalesce(new.raw_user_meta_data->>'name',  ''), 120),
          left(coalesce(new.raw_user_meta_data->>'phone', ''), 20),
          coalesce(new.email, ''))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- 3. Orders -------------------------------------------------
create sequence if not exists public.order_seq start 1001;

create table if not exists public.orders (
  id                 text primary key,                                  -- unique order ID, e.g. BF1001
  user_id            uuid not null references auth.users(id) on delete restrict,
  customer_name      text not null check (char_length(customer_name) between 1 and 120),
  email              text not null default '',
  phone              text not null check (phone ~ '^[0-9]{10}$'),
  address            text not null default '',
  items              jsonb not null,                                    -- [{id,t,v,q,price}]  (no cost data)
  total              numeric(12,2) not null check (total >= 0),
  payment_method     text not null check (payment_method in ('UPI','Card')),
  payment_status     text not null default 'pending' check (payment_status in ('pending','paid','rejected')),
  utr                text not null default '',                          -- UPI transaction reference (not sensitive)
  status             text not null default 'Pending'
                     check (status in ('Pending','Processing','Shipped','Out for Delivery','Delivered')),
  cancelled_at       timestamptz,
  cancel_reason      text,
  hidden_by_customer boolean not null default false,
  created_at         timestamptz not null default now()                 -- order date
);
create index if not exists orders_user_idx    on public.orders (user_id, created_at desc);
create index if not exists orders_created_idx on public.orders (created_at desc);
create unique index if not exists orders_utr_uniq on public.orders (utr) where utr <> '';

-- Cost of goods per order: admin only (kept out of the customer-readable orders table)
create table if not exists public.order_costs (
  order_id text primary key references public.orders(id) on delete cascade,
  cogs     numeric(12,2) not null default 0
);

-- ---------- 4. Enquiries (contact form) -------------------------------
create table if not exists public.enquiries (
  id         bigint generated always as identity primary key,
  name       text not null check (char_length(name) between 1 and 120),
  contact    text check (contact is null or char_length(contact) <= 200),
  message    text not null check (char_length(message) between 1 and 3000),
  user_id    uuid references auth.users(id) on delete set null,
  status     text not null default 'new' check (status in ('new','done')),
  created_at timestamptz not null default now()
);

-- ---------- 5. Reviews, banners, policies, settings, promo codes ------
create table if not exists public.reviews (
  id         bigint generated always as identity primary key,
  product_id bigint not null references public.products(id) on delete cascade,
  user_id    uuid   not null references auth.users(id) on delete cascade,
  name       text   not null check (char_length(name) between 1 and 120),
  stars      integer not null check (stars between 1 and 5),
  title      text   not null default '' check (char_length(title) <= 120),
  body       text   not null default '' check (char_length(body) <= 2000),
  images     text[] not null default '{}' check (cardinality(images) <= 5),
  video_url  text,
  video_name text,
  video_size bigint,
  verified   boolean not null default false,
  hidden     boolean not null default false,
  created_at timestamptz not null default now(),
  unique (product_id, user_id)
);

create or replace function public.reviews_before_insert()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  new.user_id  := auth.uid();
  new.hidden   := false;
  new.verified := exists (select 1 from public.orders o
                          where o.user_id = new.user_id and o.cancelled_at is null
                            and o.items @> jsonb_build_array(jsonb_build_object('id', new.product_id)));
  return new;
end $$;
drop trigger if exists reviews_bi on public.reviews;
create trigger reviews_bi before insert on public.reviews
  for each row execute function public.reviews_before_insert();

create table if not exists public.ads (
  id          bigint generated always as identity primary key,
  title       text not null default '',
  subtitle    text not null default '',
  button_text text not null default '',
  link        text not null default '',
  color1      text not null default '#6c4cff' check (color1 ~ '^#[0-9a-fA-F]{6}$'),
  color2      text not null default '#ff4c8b' check (color2 ~ '^#[0-9a-fA-F]{6}$'),
  image_url   text,
  is_live     boolean not null default true,
  position    integer not null default 0
);

create table if not exists public.policies (
  key        text primary key check (key in ('terms','refund','ret')),
  body       text not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.settings (
  key   text primary key check (key in ('wa','waAuto','adauto','adsec','shl')),
  value jsonb not null
);

create table if not exists public.promo_codes (
  code    text primary key check (code = upper(code)),
  percent integer not null check (percent between 1 and 90),
  active  boolean not null default true
);

-- ---------- 6. Row Level Security ------------------------------------
alter table public.products        enable row level security;
alter table public.product_private enable row level security;
alter table public.customers       enable row level security;
alter table public.orders          enable row level security;
alter table public.order_costs     enable row level security;
alter table public.enquiries       enable row level security;
alter table public.reviews         enable row level security;
alter table public.ads             enable row level security;
alter table public.policies        enable row level security;
alter table public.settings        enable row level security;
alter table public.promo_codes     enable row level security;

-- products: the public sees live products; only admins write
drop policy if exists products_read   on public.products;
drop policy if exists products_admin  on public.products;
create policy products_read  on public.products for select to anon, authenticated
  using (is_live or public.is_admin());
create policy products_admin on public.products for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- product_private: admin only (cost price, supplier, download links)
drop policy if exists pprivate_admin on public.product_private;
create policy pprivate_admin on public.product_private for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- customers: each customer sees / edits only their own row; admins see all
drop policy if exists customers_read   on public.customers;
drop policy if exists customers_update on public.customers;
create policy customers_read   on public.customers for select to authenticated
  using (id = auth.uid() or public.is_admin());
create policy customers_update on public.customers for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- orders: customers read their own; admins read/update all.
-- Customers CANNOT insert/update/delete directly: they use the secure RPCs below.
drop policy if exists orders_read         on public.orders;
drop policy if exists orders_admin_update on public.orders;
create policy orders_read on public.orders for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy orders_admin_update on public.orders for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists order_costs_admin on public.order_costs;
create policy order_costs_admin on public.order_costs for select to authenticated
  using (public.is_admin());

-- enquiries: anyone may submit; only admins read / manage
drop policy if exists enquiries_insert on public.enquiries;
drop policy if exists enquiries_admin  on public.enquiries;
create policy enquiries_insert on public.enquiries for insert to anon, authenticated
  with check (user_id is null or user_id = auth.uid());
create policy enquiries_admin on public.enquiries for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- reviews: public reads visible ones; logged-in users write their own; admin moderates
drop policy if exists reviews_read   on public.reviews;
drop policy if exists reviews_insert on public.reviews;
drop policy if exists reviews_delete on public.reviews;
drop policy if exists reviews_admin  on public.reviews;
create policy reviews_read   on public.reviews for select to anon, authenticated
  using (not hidden or user_id = auth.uid() or public.is_admin());
create policy reviews_insert on public.reviews for insert to authenticated
  with check (user_id = auth.uid());
create policy reviews_delete on public.reviews for delete to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy reviews_admin  on public.reviews for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ads / policies / settings / promo_codes: public read, admin write
drop policy if exists ads_read  on public.ads;
drop policy if exists ads_admin on public.ads;
create policy ads_read  on public.ads for select to anon, authenticated using (is_live or public.is_admin());
create policy ads_admin on public.ads for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists policies_read  on public.policies;
drop policy if exists policies_admin on public.policies;
create policy policies_read  on public.policies for select to anon, authenticated using (true);
create policy policies_admin on public.policies for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists settings_read  on public.settings;
drop policy if exists settings_admin on public.settings;
create policy settings_read  on public.settings for select to anon, authenticated using (true);
create policy settings_admin on public.settings for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists promo_read  on public.promo_codes;
drop policy if exists promo_admin on public.promo_codes;
create policy promo_read  on public.promo_codes for select to anon, authenticated using (active or public.is_admin());
create policy promo_admin on public.promo_codes for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------- 7. Secure RPC functions ----------------------------------
-- 7a. place_order: price, stock, discount and total are all computed ON THE SERVER.
create or replace function public.place_order(
  p_name text, p_phone text, p_email text, p_address text,
  p_items jsonb, p_method text, p_utr text, p_promo text)
returns text language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_id text; v_it jsonb; v_p public.products; v_cost numeric;
  v_q int; v_var text;
  v_sub numeric := 0; v_cogs numeric := 0; v_all_digital boolean := true;
  v_pct numeric := 0; v_disc numeric; v_ship numeric; v_total numeric;
  v_lines jsonb := '[]'::jsonb;
begin
  if v_uid is null then raise exception 'Please login to place an order'; end if;
  if coalesce(length(trim(p_name)),0) not between 1 and 120 then raise exception 'Enter your name'; end if;
  if p_phone !~ '^[0-9]{10}$' then raise exception 'Enter a valid 10-digit mobile number'; end if;
  if p_method not in ('UPI','Card') then raise exception 'Invalid payment method'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 50 then
    raise exception 'Your cart is empty'; end if;
  if coalesce(p_utr,'') <> '' and p_utr !~ '^[0-9]{12}$' then raise exception 'Invalid transaction ID'; end if;

  for v_it in select * from jsonb_array_elements(p_items) loop
    v_q   := (v_it->>'q')::int;
    v_var := coalesce(v_it->>'v','');
    if v_q is null or v_q < 1 or v_q > 20 then raise exception 'Invalid quantity'; end if;

    select * into v_p from public.products where id = (v_it->>'id')::bigint and is_live for update;
    if not found then raise exception 'A product in your cart is no longer available'; end if;
    if cardinality(v_p.variants) > 0 and not (v_var = any (v_p.variants)) then
      raise exception 'Please choose a valid option for %', v_p.name; end if;

    if not v_p.is_digital then
      v_all_digital := false;
      update public.products set stock = stock - v_q where id = v_p.id and stock >= v_q;
      if not found then raise exception 'Sorry, % is out of stock (or fewer units are left)', v_p.name; end if;
    end if;

    select coalesce(pp.cost,0) into v_cost from public.product_private pp where pp.product_id = v_p.id;
    v_sub  := v_sub  + v_p.price * v_q;
    v_cogs := v_cogs + coalesce(v_cost,0) * v_q;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
                 'id', v_p.id, 't', v_p.name, 'v', v_var, 'q', v_q, 'price', v_p.price));
  end loop;

  if v_all_digital and p_method <> 'UPI' then raise exception 'E-books can be paid by UPI only'; end if;

  if coalesce(p_promo,'') <> '' then
    select percent / 100.0 into v_pct from public.promo_codes where code = upper(trim(p_promo)) and active;
    v_pct := coalesce(v_pct, 0);
  end if;
  v_disc  := round(v_sub * v_pct);
  v_ship  := case when v_all_digital or v_sub - v_disc >= 499 then 0 else 49 end;
  v_total := v_sub - v_disc + v_ship;

  v_id := 'BF' || nextval('public.order_seq');
  insert into public.orders (id, user_id, customer_name, email, phone, address, items, total,
                             payment_method, utr)
  values (v_id, v_uid, trim(p_name), left(coalesce(p_email,''),200), p_phone,
          left(coalesce(p_address,''),500), v_lines, v_total, p_method, coalesce(p_utr,''));
  insert into public.order_costs (order_id, cogs) values (v_id, v_cogs);
  return v_id;
end $$;

-- helper: put stock back for the non-digital lines of an order
create or replace function public._restock(p_items jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare e jsonb;
begin
  for e in select * from jsonb_array_elements(p_items) loop
    update public.products set stock = stock + (e->>'q')::int
     where id = (e->>'id')::bigint and not is_digital;
  end loop;
end $$;

-- 7b. cancel_order: customer may cancel until the order ships (never an approved e-book)
create or replace function public.cancel_order(p_id text, p_reason text)
returns void language plpgsql security definer set search_path = ''
as $$
declare o public.orders; v_has_digital boolean;
begin
  select * into o from public.orders where id = p_id and user_id = auth.uid() for update;
  if not found then raise exception 'Order not found'; end if;
  if o.cancelled_at is not null or o.status not in ('Pending','Processing') then
    raise exception 'This order can no longer be cancelled'; end if;
  select exists (select 1 from jsonb_array_elements(o.items) e
                 join public.products p on p.id = (e->>'id')::bigint where p.is_digital)
    into v_has_digital;
  if v_has_digital and o.payment_status = 'paid' then
    raise exception 'Approved e-books can’t be cancelled'; end if;
  update public.orders set cancelled_at = now(), cancel_reason = left(coalesce(nullif(p_reason,''),'Other'),200)
   where id = p_id;
  perform public._restock(o.items);
end $$;

-- 7c. hide_order: customer removes a finished order from THEIR history (the seller keeps it)
create or replace function public.hide_order(p_id text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  update public.orders set hidden_by_customer = true
   where id = p_id and user_id = auth.uid()
     and (cancelled_at is not null or payment_status = 'rejected' or status = 'Delivered');
  if not found then raise exception 'This order can’t be deleted'; end if;
end $$;

-- 7d. admin_delete_order: admin only; returns stock for open physical orders
create or replace function public.admin_delete_order(p_id text)
returns void language plpgsql security definer set search_path = ''
as $$
declare o public.orders;
begin
  if not public.is_admin() then raise exception 'Not authorised'; end if;
  select * into o from public.orders where id = p_id for update;
  if not found then raise exception 'Order not found'; end if;
  if o.cancelled_at is null and o.status <> 'Delivered' then perform public._restock(o.items); end if;
  delete from public.orders where id = p_id;
end $$;

-- 7e. track_order: guests can look up status with Order ID + phone (no address / email returned)
create or replace function public.track_order(p_id text, p_phone text)
returns jsonb language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object('id', o.id, 'total', o.total, 'payment_method', o.payment_method,
           'payment_status', o.payment_status, 'status', o.status, 'utr', o.utr,
           'cancelled_at', o.cancelled_at, 'cancel_reason', o.cancel_reason,
           'items', o.items, 'created_at', o.created_at)
    from public.orders o where upper(o.id) = upper(trim(p_id)) and o.phone = p_phone
$$;

-- 7f. get_download_url: returns the private download link ONLY to the admin or a customer whose payment was approved
create or replace function public.get_download_url(p_product_id bigint)
returns text language plpgsql stable security definer set search_path = ''
as $$
declare v text;
begin
  if auth.uid() is null then raise exception 'Please login to download'; end if;
  select pp.download_url into v from public.product_private pp
    join public.products p on p.id = pp.product_id and p.is_digital
   where pp.product_id = p_product_id;
  if v is null or v = '' then return null; end if;
  if public.is_admin() or exists (
       select 1 from public.orders o
        where o.user_id = auth.uid() and o.payment_status = 'paid' and o.cancelled_at is null
          and o.items @> jsonb_build_array(jsonb_build_object('id', p_product_id))) then
    return v;
  end if;
  raise exception 'Your download unlocks once the seller approves your payment';
end $$;

-- storage helper (used by the private 'downloads' bucket policy)
create or replace function public.can_download(p_path text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select public.is_admin() or exists (
    select 1 from public.product_private pp
     where pp.download_url = p_path
       and exists (select 1 from public.orders o
                    where o.user_id = auth.uid() and o.payment_status = 'paid' and o.cancelled_at is null
                      and o.items @> jsonb_build_array(jsonb_build_object('id', pp.product_id))))
$$;

-- ---------- 8. Grants (least privilege on top of RLS) ----------------
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;

grant usage on schema public to anon, authenticated;

grant select on public.products, public.ads, public.policies, public.settings,
                public.promo_codes, public.reviews                    to anon, authenticated;
grant insert, update, delete on public.products, public.product_private, public.ads,
                public.policies, public.settings, public.promo_codes   to authenticated;
grant select on public.product_private, public.customers, public.orders,
                public.order_costs                                     to authenticated;
grant update (name, phone) on public.customers                         to authenticated;
grant update (payment_status, status) on public.orders                 to authenticated;
grant insert on public.enquiries                                       to anon, authenticated;
grant select, update (status), delete on public.enquiries              to authenticated;
grant insert, delete on public.reviews                                 to authenticated;
grant update (hidden) on public.reviews                                to authenticated;

grant execute on function public.is_admin()                  to anon, authenticated;
grant execute on function public.track_order(text, text)     to anon, authenticated;
grant execute on function public.place_order(text,text,text,text,jsonb,text,text,text) to authenticated;
grant execute on function public.cancel_order(text, text)    to authenticated;
grant execute on function public.hide_order(text)            to authenticated;
grant execute on function public.admin_delete_order(text)    to authenticated;
grant execute on function public.get_download_url(bigint)    to authenticated;
grant execute on function public.can_download(text)          to authenticated;

-- ---------- 9. Default configuration ---------------------------------
insert into public.promo_codes (code, percent) values ('BUYFIRST10', 10), ('INDIA5', 5)
  on conflict (code) do nothing;
insert into public.settings (key, value) values
  ('wa', '"6304389144"'), ('waAuto', '1'), ('adauto', '1'), ('adsec', '5')
  on conflict (key) do nothing;

-- ---------- 10. Storage buckets & policies ---------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('product-images', 'product-images', true,  10485760,
     array['image/jpeg','image/png','image/webp','image/gif','image/avif']),
  ('media',          'media',          true,  52428800,
     array['image/jpeg','image/png','image/webp','image/gif','image/avif','video/mp4','video/webm','video/quicktime']),
  ('downloads',      'downloads',      false, 52428800, null)
on conflict (id) do update set public = excluded.public,
  file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "bf product images admin" on storage.objects;
create policy "bf product images admin" on storage.objects for all to authenticated
  using (bucket_id = 'product-images' and public.is_admin())
  with check (bucket_id = 'product-images' and public.is_admin());

drop policy if exists "bf media admin" on storage.objects;
create policy "bf media admin" on storage.objects for all to authenticated
  using (bucket_id = 'media' and public.is_admin())
  with check (bucket_id = 'media' and public.is_admin());

drop policy if exists "bf media review upload" on storage.objects;
create policy "bf media review upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and (storage.foldername(name))[1] = 'reviews'
              and (storage.foldername(name))[2] = auth.uid()::text);

drop policy if exists "bf media review delete" on storage.objects;
create policy "bf media review delete" on storage.objects for delete to authenticated
  using (bucket_id = 'media' and (storage.foldername(name))[1] = 'reviews'
         and (storage.foldername(name))[2] = auth.uid()::text);

drop policy if exists "bf downloads admin" on storage.objects;
create policy "bf downloads admin" on storage.objects for all to authenticated
  using (bucket_id = 'downloads' and public.is_admin())
  with check (bucket_id = 'downloads' and public.is_admin());

drop policy if exists "bf downloads buyers" on storage.objects;
create policy "bf downloads buyers" on storage.objects for select to authenticated
  using (bucket_id = 'downloads' and public.can_download(name));

-- =====================================================================
-- AFTER RUNNING: make yourself the owner (see README step 4):
--   insert into public.admins (user_id) select id from auth.users where email = 'YOU@EXAMPLE.COM';
-- =====================================================================
