-- OPTIONAL: sample catalogue + banner (the 6 demo products from the old site).
-- Run once in the SQL Editor if you want something to show on day one.
-- You can edit or delete all of it later from the Owner dashboard.
with ins as (
  insert into public.products (name, category, emoji, hue, image_url, images, price, mrp, stock, dispatch_days, rating, hot, tags, description, variants, is_digital, return_type)
  values
  ('Wireless Neckband Earphones','Electronics','🎧',255,'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=900',array['https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=900'],899,1999,42,2,4.4,true,'bluetooth,audio','30-hour battery, deep bass, IPX5 sweat resistance and fast charging.',array['Black','Blue','Red'],false,'both'),
  ('Sunset Projection Lamp','Home Decor','🌅',20,'https://images.unsplash.com/photo-1513506003901-1e6a229e2d15?w=900',array['https://images.unsplash.com/photo-1513506003901-1e6a229e2d15?w=900'],599,1299,25,2,4.6,true,'lamp,decor','USB rainbow and sunset glow lamp with 180° rotation. Perfect for reels and room vibes.',array['Orange','Pink','Rainbow'],false,'both'),
  ('Orthopedic Memory Foam Pillow','Wellness','😴',200,'https://images.unsplash.com/photo-1584100936595-c0654b55a2e6?w=900',array['https://images.unsplash.com/photo-1584100936595-c0654b55a2e6?w=900'],999,2199,18,3,4.5,false,'sleep,pillow','Contour cervical pillow that supports neck and spine alignment for pain-free sleep.',array['Standard','Large'],false,'both'),
  ('Mini Car Vacuum Cleaner','Auto','🚗',150,'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=900',array['https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=900'],799,1799,8,2,4.2,true,'car,cleaner','Portable 120W cordless vacuum with strong suction for car seats and keyboards.',array[]::text[],false,'both'),
  ('Stainless Steel Thermal Flask','Kitchen','🥤',330,'https://images.unsplash.com/photo-1602143407151-7111542de6e8?w=900',array['https://images.unsplash.com/photo-1602143407151-7111542de6e8?w=900'],649,1299,60,2,4.7,false,'bottle,steel','Double-wall vacuum flask keeps drinks hot 12 hrs and cold 24 hrs. Leak-proof.',array['500 ml','750 ml','1 L'],false,'both'),
  ('Dropshipping Playbook India (E-book)','Digital','📘',280,'https://images.unsplash.com/photo-1544947950-fa07a98d237f?w=900',array['https://images.unsplash.com/photo-1544947950-fa07a98d237f?w=900'],299,999,999,0,4.8,true,'ebook,digital','120-page PDF: find winning products, run profitable ads and scale a store in India. Instant download.',array[]::text[],true,'none')
  returning id, name
)
insert into public.product_private (product_id, cost)
select id, case name when 'Wireless Neckband Earphones' then 450 when 'Sunset Projection Lamp' then 280
  when 'Orthopedic Memory Foam Pillow' then 520 when 'Mini Car Vacuum Cleaner' then 390
  when 'Stainless Steel Thermal Flask' then 310 else 20 end from ins;

insert into public.ads (title, subtitle, button_text, link, color1, color2, position)
values ('Extra 10% off your first order','Use code BUYFIRST10 at checkout','Shop now','shop','#0f9d58','#00b9f1',0);
