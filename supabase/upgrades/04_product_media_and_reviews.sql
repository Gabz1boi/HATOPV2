-- HATOP product media + verified buyer reviews.
-- For an EXISTING project after 001_hatop_core.sql. Review in a staging project first.
-- Does NOT enable real payments or change existing order/DP calculations.

create table if not exists public.listing_images (
 id uuid primary key default gen_random_uuid(),
 listing_id uuid not null references public.store_listings(id) on delete cascade,
 position smallint not null check (position between 1 and 5),
 image_path text not null unique,
 created_at timestamptz not null default now(),
 unique(listing_id,position),
 check (length(image_path) between 70 and 250)
);
alter table public.listing_images enable row level security;
grant select on public.listing_images to anon,authenticated;
grant insert,delete on public.listing_images to authenticated;
create policy listing_images_read on public.listing_images for select to anon,authenticated using(true);
create policy listing_images_insert on public.listing_images for insert to authenticated
with check (
 image_path like ((select auth.uid())::text || '/' || listing_id::text || '/%')
 and exists (select 1 from public.store_listings l join public.stores s on s.id=l.store_id
   where l.id=listing_id and s.owner_id=(select auth.uid()) and s.approved)
);
create policy listing_images_delete on public.listing_images for delete to authenticated
using (exists (select 1 from public.store_listings l join public.stores s on s.id=l.store_id
 where l.id=listing_id and s.owner_id=(select auth.uid()) and s.approved));

-- Public catalog assets; uploads and deletion require a verified store owner.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('hatop-products','hatop-products',true,4194304,array['image/jpeg','image/png','image/webp'])
 on conflict(id) do update set public=true,file_size_limit=4194304,
 allowed_mime_types=excluded.allowed_mime_types;

create policy hatop_storage_upload on storage.objects for insert to authenticated
with check (
 bucket_id='hatop-products'
 and (storage.foldername(name))[1]=(select auth.uid())::text
 and exists (select 1 from public.store_listings l join public.stores s on s.id=l.store_id
  where l.id::text=(storage.foldername(name))[2] and s.owner_id=(select auth.uid()) and s.approved)
);
create policy hatop_storage_owner_read on storage.objects for select to authenticated
using (
 bucket_id='hatop-products'
 and (storage.foldername(name))[1]=(select auth.uid())::text
 and exists (select 1 from public.store_listings l join public.stores s on s.id=l.store_id
  where l.id::text=(storage.foldername(name))[2] and s.owner_id=(select auth.uid()) and s.approved)
);
create policy hatop_storage_remove on storage.objects for delete to authenticated
using (
 bucket_id='hatop-products'
 and (storage.foldername(name))[1]=(select auth.uid())::text
 and exists (select 1 from public.store_listings l join public.stores s on s.id=l.store_id
  where l.id::text=(storage.foldername(name))[2] and s.owner_id=(select auth.uid()) and s.approved)
);

-- Rating is only allowed for items belonging to a completed order.
-- One review per purchased item; sellers cannot create arbitrary ratings.
create table if not exists public.product_reviews (
 id uuid primary key default gen_random_uuid(),
 listing_id uuid not null references public.store_listings(id),
 order_item_id uuid not null unique references public.order_items(id),
 customer_id uuid not null references auth.users(id),
 rating smallint not null check (rating between 1 and 5),
 comment text not null default '' check (char_length(comment)<=500),
 created_at timestamptz not null default now()
);
alter table public.product_reviews enable row level security;
grant select on public.product_reviews to anon,authenticated;
grant insert on public.product_reviews to authenticated;
create policy product_reviews_read on public.product_reviews for select to anon,authenticated using(true);
create policy product_reviews_verified_purchase on public.product_reviews for insert to authenticated
with check (
 customer_id=(select auth.uid())
 and exists (
  select 1 from public.order_items oi
  join public.store_orders so on so.id=oi.store_order_id
  join public.orders o on o.id=so.order_id
  where oi.id=order_item_id and oi.listing_id=product_reviews.listing_id
  and o.customer_id=(select auth.uid()) and o.status='completed'
 )
);

-- Optional index for listing-based product pages.
create index if not exists listing_images_by_product on public.listing_images(listing_id,position);
create index if not exists product_reviews_by_listing on public.product_reviews(listing_id,created_at desc);
