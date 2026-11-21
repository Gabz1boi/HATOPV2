-- HATOP Cloud demo foundation. Run ONLY in a fresh HATOP-DEV project.
-- All payments are simulated. No actual QRIS, bank transfer or cash collection integration.
create extension if not exists pgcrypto;
create schema if not exists hatop_private;
revoke all on schema hatop_private from public, anon, authenticated;

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null default '', email text, created_at timestamptz not null default now()
);
create table public.user_roles (
 user_id uuid not null references auth.users(id) on delete cascade,
 role text not null check(role in ('farmer','store','driver','admin')),
 primary key(user_id, role)
);
create unique index one_primary_admin on public.user_roles (role) where role = 'admin';
create table public.stores (
 id uuid primary key default gen_random_uuid(), owner_id uuid unique references auth.users(id),
 name text not null, area text not null, demo boolean not null default true,
 approved boolean not null default false, created_at timestamptz default now()
);
create table public.drivers (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null unique references auth.users(id),
 name text not null, capacity_kg integer not null default 800 check(capacity_kg>0),
 approved boolean not null default false, available boolean not null default true
);
create table public.partner_applications (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id),
 desired_role text not null check(desired_role in ('store','driver')),
 display_name text not null, area text not null default 'Balige',
 target_store_id uuid references public.stores(id),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz default now(), reviewed_at timestamptz
);
create table public.categories (code text primary key,name text not null);
create table public.catalog_products (
 id text primary key, name text not null,category text not null references public.categories(code),
 brand text, unit text not null, image_url text, description text,
 source_url text, reference_price integer check(reference_price>=0),
 price_status text not null default 'reference', local_verified boolean not null default false
);
create table public.store_listings (
 id uuid primary key default gen_random_uuid(), store_id uuid not null references public.stores(id),
 catalog_id text not null references public.catalog_products(id),
 demo_price integer not null check(demo_price>=0), stock integer not null default 0 check(stock>=0),
 active boolean not null default true, unique(store_id,catalog_id)
);
create table public.platform_settings (
 id integer primary key default 1 check(id=1), pickup_cost integer not null default 400000 check(pickup_cost>=0),
 service_fee integer not null default 20000 check(service_fee>=0), dp_percent integer not null default 50 check(dp_percent=50),
 max_pool_size integer not null default 3 check(max_pool_size between 2 and 10)
);
insert into public.platform_settings(id) values(1);
create table public.pooling_groups (
 id uuid primary key default gen_random_uuid(), name text not null, destination_key text not null,
 scheduled_date date not null, approved_by uuid references auth.users(id), created_at timestamptz default now()
);
create table public.orders (
 id uuid primary key default gen_random_uuid(), code text unique not null,
 customer_id uuid not null references auth.users(id), destination text not null, destination_key text not null,
 scheduled_date date not null, notes text default '', status text not null default 'awaiting_stores'
 check(status in ('awaiting_stores','ready_for_quote','awaiting_dp','dp_submitted','dp_verified','delivery','inspection','cod_pending','cod_recorded','completed','cancelled')),
 subtotal integer not null default 0 check(subtotal>=0), shipping integer not null default 0 check(shipping>=0),
 service_fee integer not null default 0 check(service_fee>=0), dp integer not null default 0 check(dp>=0),
 cod integer not null default 0 check(cod>=0), total integer not null default 0 check(total>=0),
 pooling_group_id uuid references public.pooling_groups(id), created_at timestamptz default now(), updated_at timestamptz default now()
);
create table public.store_orders (
 id uuid primary key default gen_random_uuid(), order_id uuid not null references public.orders(id) on delete cascade,
 store_id uuid not null references public.stores(id), status text not null default 'pending'
 check(status in ('pending','accepted','rejected','ready')),
 unique(order_id,store_id)
);
create table public.order_items (
 id uuid primary key default gen_random_uuid(), store_order_id uuid not null references public.store_orders(id) on delete cascade,
 listing_id uuid not null references public.store_listings(id),
 name_snapshot text not null, unit_snapshot text not null, qty integer not null check(qty>0),
 unit_price integer not null check(unit_price>=0), total integer generated always as (qty*unit_price) stored
);
create table public.payments (
 id uuid primary key default gen_random_uuid(), order_id uuid not null references public.orders(id) on delete cascade,
 kind text not null check(kind in ('shipping_dp','cod_settlement')),
 amount integer not null check(amount>=0), status text not null default 'pending'
 check(status in ('pending','submitted','verified','rejected','recorded','confirmed')),
 note text, reviewed_by uuid references auth.users(id), reviewed_at timestamptz,
 updated_at timestamptz not null default now(), unique(order_id,kind)
);
create table public.shipments (
 id uuid primary key default gen_random_uuid(), pooling_group_id uuid references public.pooling_groups(id),
 driver_id uuid references public.drivers(id), status text not null default 'open'
 check(status in ('open','assigned','picked_up','arrived','completed')),
 created_at timestamptz not null default now()
);
create unique index one_shipment_per_pool on public.shipments(pooling_group_id) where pooling_group_id is not null;
create table public.shipment_orders (
 shipment_id uuid not null references public.shipments(id) on delete cascade,
 order_id uuid not null unique references public.orders(id),primary key(shipment_id,order_id)
);
create table public.delivery_events (
 id uuid primary key default gen_random_uuid(), shipment_id uuid not null references public.shipments(id),
 actor_id uuid references auth.users(id), kind text not null, detail text, created_at timestamptz default now()
);
create table public.audit_logs (
 id bigserial primary key, actor_id uuid references auth.users(id), entity text not null,
 entity_id uuid, action text not null, detail jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);

create function hatop_private.on_auth_user() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,full_name,email) values(new.id,coalesce(new.raw_user_meta_data->>'full_name',split_part(coalesce(new.email,''),'@',1)),new.email) on conflict(id) do nothing;
 insert into public.user_roles(user_id,role) values(new.id,'farmer') on conflict do nothing;
 return new;
end $$;
create trigger hatop_auth_created after insert on auth.users for each row execute function hatop_private.on_auth_user();

create function hatop_private.is_role(p_role text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.user_roles where user_id=(select auth.uid()) and role=p_role);
$$;
create function hatop_private.can_see_order(p_order uuid) returns boolean language sql stable security definer set search_path='' as $$
 select (select hatop_private.is_role('admin')) or exists(
   select 1 from public.orders o where o.id=p_order and (
     o.customer_id=(select auth.uid()) or
     exists(select 1 from public.store_orders so join public.stores s on s.id=so.store_id where so.order_id=o.id and s.owner_id=(select auth.uid())) or
     exists(select 1 from public.shipment_orders x join public.shipments sh on sh.id=x.shipment_id join public.drivers d on d.id=sh.driver_id where x.order_id=o.id and d.owner_id=(select auth.uid()))
   )
 );
$$;

-- RLS: only explicit read policies; ALL mutations go through validated RPC.
-- RPC functions use SECURITY DEFINER but check auth.uid and role/ownership for EVERY action.
do $$ declare t text; begin
 foreach t in array array['profiles','user_roles','stores','drivers','partner_applications','categories','catalog_products','store_listings','platform_settings','pooling_groups','orders','store_orders','order_items','payments','shipments','shipment_orders','delivery_events','audit_logs'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from anon, authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
 end loop;
end $$;
grant usage on schema public to anon,authenticated;
grant select on public.categories, public.catalog_products, public.store_listings, public.stores to anon;
create policy profiles_read on public.profiles for select to authenticated using(id=(select auth.uid()) or (select hatop_private.is_role('admin')));
create policy roles_read on public.user_roles for select to authenticated using(user_id=(select auth.uid()) or (select hatop_private.is_role('admin')));
create policy stores_read on public.stores for select to anon,authenticated using(true);
create policy drivers_read on public.drivers for select to authenticated using(owner_id=(select auth.uid()) or (select hatop_private.is_role('admin')));
create policy applications_read on public.partner_applications for select to authenticated using(user_id=(select auth.uid()) or (select hatop_private.is_role('admin')));
create policy categories_read on public.categories for select to anon,authenticated using(true);
create policy catalog_read on public.catalog_products for select to anon,authenticated using(true);
create policy listings_read on public.store_listings for select to anon,authenticated using(true);
create policy settings_read on public.platform_settings for select to authenticated using(true);
create policy pooling_read on public.pooling_groups for select to authenticated using(
  (select hatop_private.is_role('admin')) or exists(select 1 from public.orders where pooling_group_id=pooling_groups.id and hatop_private.can_see_order(id))
);
create policy orders_read on public.orders for select to authenticated using(hatop_private.can_see_order(id));
create policy store_orders_read on public.store_orders for select to authenticated using(
 (select hatop_private.is_role('admin')) or
 exists(select 1 from public.orders o where o.id=order_id and o.customer_id=(select auth.uid())) or
 exists(select 1 from public.stores s where s.id=store_id and s.owner_id=(select auth.uid())) or
 exists(select 1 from public.shipment_orders x join public.shipments sh on sh.id=x.shipment_id join public.drivers d on d.id=sh.driver_id where x.order_id=order_id and d.owner_id=(select auth.uid()))
);
create policy items_read on public.order_items for select to authenticated using(exists(select 1 from public.store_orders so join public.orders o on o.id=so.order_id left join public.stores s on s.id=so.store_id where so.id=store_order_id and ((select hatop_private.is_role('admin')) or o.customer_id=(select auth.uid()) or s.owner_id=(select auth.uid()) or exists(select 1 from public.shipment_orders x join public.shipments sh on sh.id=x.shipment_id join public.drivers d on d.id=sh.driver_id where x.order_id=o.id and d.owner_id=(select auth.uid())))));
create policy payments_read on public.payments for select to authenticated using(
 (select hatop_private.is_role('admin')) or
 exists(select 1 from public.orders o where o.id=order_id and o.customer_id=(select auth.uid())) or
 (kind='cod_settlement' and exists(select 1 from public.shipment_orders x join public.shipments sh on sh.id=x.shipment_id join public.drivers d on d.id=sh.driver_id where x.order_id=payments.order_id and d.owner_id=(select auth.uid())))
);
create policy shipments_read on public.shipments for select to authenticated using(
 (select hatop_private.is_role('admin')) or
 (driver_id is null and (select hatop_private.is_role('driver')) and status='open') or
 exists(select 1 from public.drivers where id=driver_id and owner_id=(select auth.uid())) or
 exists(select 1 from public.shipment_orders where shipment_id=shipments.id and hatop_private.can_see_order(order_id))
);
create policy shipment_orders_read on public.shipment_orders for select to authenticated using(hatop_private.can_see_order(order_id));
create policy delivery_events_read on public.delivery_events for select to authenticated using(exists(select 1 from public.shipment_orders where shipment_id=delivery_events.shipment_id and hatop_private.can_see_order(order_id)));
create policy audit_read on public.audit_logs for select to authenticated using((select hatop_private.is_role('admin')));

-- Atomic business command gateway: auth.uid is never taken from client payload.
-- Functions not accessible to anon; search_path locked. All amounts calculated from DB.
create function public.hatop_action(p_action text, p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); admin_ok boolean; oid uuid; sid uuid; gid uuid; did uuid;
 x jsonb; entry jsonb; lid uuid; sto uuid; parent uuid; line_name text; line_unit text; unit_price integer; amount integer; item_qty integer;
 stage text; n integer; g text; d date; ids uuid[]; rowid uuid; cnt integer; all_ready boolean; app public.partner_applications%rowtype;
 rec record; sh uuid; r text; total_products integer; shipping_cost integer; svc integer;
begin
 if u is null then raise exception 'Login Google diperlukan'; end if;
 admin_ok:=hatop_private.is_role('admin');
 if p_action='checkout' then
  if jsonb_typeof(p_data->'items') is distinct from 'array' or jsonb_array_length(p_data->'items')<1 or jsonb_array_length(p_data->'items')>35 then raise exception 'Keranjang tidak valid'; end if;
  if length(trim(coalesce(p_data->>'destination','')))<5 or length(coalesce(p_data->>'destination',''))>300 then raise exception 'Alamat pengantaran tidak valid'; end if;
  if length(trim(coalesce(p_data->>'destination_key','')))<2 or length(coalesce(p_data->>'destination_key',''))>80 then raise exception 'Wilayah tujuan tidak valid'; end if;
  d:=(p_data->>'scheduled_date')::date;
  if d<current_date or d>current_date+90 then raise exception 'Tanggal pengiriman di luar batas'; end if;
  select pickup_cost,service_fee into shipping_cost,svc from public.platform_settings where id=1;
  oid:=gen_random_uuid();
  insert into public.orders(id,code,customer_id,destination,destination_key,scheduled_date,notes,shipping,service_fee)
   values(oid,'HTP-'||upper(substr(replace(oid::text,'-',''),1,10)),u,trim(p_data->>'destination'),lower(trim(p_data->>'destination_key')),d,left(coalesce(p_data->>'notes',''),500),shipping_cost,svc);
  for entry in select value from jsonb_array_elements(p_data->'items') loop
   lid:=(entry->>'listing_id')::uuid; item_qty:=(entry->>'qty')::integer;
   if item_qty<1 or item_qty>100 then raise exception 'Jumlah produk di luar batas'; end if;
   select l.store_id,l.demo_price,c.name,c.unit into sto,unit_price,line_name,line_unit
    from public.store_listings l join public.catalog_products c on c.id=l.catalog_id join public.stores s on s.id=l.store_id
    where l.id=lid and l.active and l.stock>=item_qty and s.approved for update of l;
   if not found then raise exception 'Produk tidak tersedia atau stok tidak mencukupi'; end if;
   update public.store_listings set stock=stock-item_qty where id=lid;
   select id into sid from public.store_orders where order_id=oid and store_id=sto;
   if sid is null then insert into public.store_orders(order_id,store_id) values(oid,sto) returning id into sid; end if;
   insert into public.order_items(store_order_id,listing_id,name_snapshot,unit_snapshot,qty,unit_price)
    values(sid,lid,line_name,line_unit,item_qty,unit_price);
   sid:=null;
  end loop;
  select coalesce(sum(oi.total),0) into total_products from public.order_items oi join public.store_orders so on so.id=oi.store_order_id where so.order_id=oid;
  update public.orders set subtotal=total_products,dp=shipping_cost/2,cod=total_products+svc+shipping_cost-(shipping_cost/2),total=total_products+svc+shipping_cost where id=oid;
  insert into public.payments(order_id,kind,amount) values(oid,'shipping_dp',shipping_cost/2),(oid,'cod_settlement',total_products+svc+shipping_cost-(shipping_cost/2));
  insert into public.audit_logs(actor_id,entity,entity_id,action) values(u,'orders',oid,'checkout');
  return jsonb_build_object('order_id',oid);
 elsif p_action='store_decision' then
  sid:=(p_data->>'store_order_id')::uuid;
  select so.order_id into oid from public.store_orders so join public.stores s on s.id=so.store_id
   where so.id=sid and s.owner_id=u and s.approved and so.status='pending' for update of so;
  if not found then raise exception 'Pesanan toko tidak ditemukan atau tidak berhak'; end if;
  r:=p_data->>'decision'; if r not in ('accepted','rejected') then raise exception 'Keputusan tidak valid'; end if;
  update public.store_orders set status=r where id=sid;
  if r='rejected' then
   update public.store_listings l set stock=l.stock+x.qty from (select listing_id,sum(qty)::integer qty from public.order_items where store_order_id=sid group by listing_id) x where x.listing_id=l.id;
  end if;
  if not exists(select 1 from public.store_orders where order_id=oid and status='pending') then
   select coalesce(sum(oi.total),0) into total_products from public.order_items oi join public.store_orders so on so.id=oi.store_order_id where so.order_id=oid and so.status!='rejected';
   if total_products=0 then update public.orders set status='cancelled',subtotal=0,shipping=0,dp=0,cod=0,total=0 where id=oid;
   else
    select shipping,service_fee into shipping_cost,svc from public.orders where id=oid;
    update public.orders set status='ready_for_quote',subtotal=total_products,total=total_products+shipping_cost+svc,cod=total_products+shipping_cost+svc-(shipping_cost/2) where id=oid;
    update public.payments set amount=total_products+shipping_cost+svc-(shipping_cost/2) where order_id=oid and kind='cod_settlement';
   end if;
  end if;
  return jsonb_build_object('ok',true);
 elsif p_action='apply_partner' then
  r:=p_data->>'role'; if r not in ('store','driver') then raise exception 'Jenis mitra tidak valid'; end if;
  if length(trim(coalesce(p_data->>'name','')))<3 then raise exception 'Nama mitra minimal 3 karakter'; end if;
  if exists(select 1 from public.partner_applications where user_id=u and desired_role=r and status='pending') then raise exception 'Pengajuan masih menunggu'; end if;
  insert into public.partner_applications(user_id,desired_role,display_name,area,target_store_id)
   values(u,r,left(p_data->>'name',100),left(coalesce(p_data->>'area','Balige'),70),nullif(p_data->>'store_id','')::uuid);
  return jsonb_build_object('ok',true);
 elsif p_action='review_partner' then
  if not admin_ok then raise exception 'Hanya admin'; end if;
  select * into app from public.partner_applications where id=(p_data->>'id')::uuid and status='pending' for update;
  if not found then raise exception 'Pengajuan tidak tersedia'; end if;
  r:=p_data->>'decision'; if r not in ('approved','rejected') then raise exception 'Keputusan tidak valid'; end if;
  update public.partner_applications set status=r,reviewed_at=now() where id=app.id;
  if r='approved' then
   insert into public.user_roles(user_id,role) values(app.user_id,app.desired_role) on conflict do nothing;
   if app.desired_role='store' then
    if app.target_store_id is not null then
     update public.stores set owner_id=app.user_id,approved=true where id=app.target_store_id and owner_id is null;
     if not found then raise exception 'Toko demo sudah dimiliki mitra lain'; end if;
    else insert into public.stores(owner_id,name,area,demo,approved) values(app.user_id,app.display_name,app.area,true,true); end if;
   else insert into public.drivers(owner_id,name,approved) values(app.user_id,app.display_name,true) on conflict(owner_id) do update set approved=true; end if;
  end if;
  return jsonb_build_object('ok',true);
 elsif p_action='store_ready' then
  sid:=(p_data->>'store_order_id')::uuid;
  update public.store_orders so set status='ready' from public.stores s where so.id=sid and so.store_id=s.id and s.owner_id=u and so.status='accepted';
  if not found then raise exception 'Pesanan toko belum bisa disiapkan'; end if;
  return jsonb_build_object('ok',true);
 elsif p_action='edit_listing' or p_action='add_listing' then
  unit_price:=(p_data->>'price')::integer; item_qty:=(p_data->>'stock')::integer;
  if unit_price<0 or unit_price>100000000 or item_qty<0 or item_qty>100000 then raise exception 'Harga/stok di luar batas'; end if;
  select id into sto from public.stores where owner_id=u and approved;
  if sto is null then raise exception 'Akun bukan pemilik toko aktif'; end if;
  if p_action='edit_listing' then
   update public.store_listings set demo_price=unit_price,stock=item_qty where id=(p_data->>'listing_id')::uuid and store_id=sto;
   if not found then raise exception 'Listing tidak ditemukan'; end if;
  else
   if not exists(select 1 from public.catalog_products where id=p_data->>'catalog_id') then raise exception 'Produk katalog tidak ditemukan'; end if;
   insert into public.store_listings(store_id,catalog_id,demo_price,stock)
    values(sto,p_data->>'catalog_id',unit_price,item_qty)
    on conflict(store_id,catalog_id) do update set demo_price=excluded.demo_price,stock=excluded.stock,active=true;
  end if;
  return jsonb_build_object('ok',true);
 elsif p_action='approve_pool' then
  if not admin_ok then raise exception 'Hanya admin'; end if;
  select array_agg(distinct v::uuid) into ids from jsonb_array_elements_text(p_data->'order_ids') v;
  n:=coalesce(array_length(ids,1),0); if n<2 or n>10 then raise exception 'Pooling membutuhkan 2 sampai 10 pesanan'; end if;
  select max_pool_size,pickup_cost into cnt,shipping_cost from public.platform_settings where id=1;
  if n>cnt then raise exception 'Melebihi kapasitas pooling'; end if;
  select count(*),min(destination_key),min(scheduled_date) into cnt,g,d from public.orders
    where id=any(ids) and status='ready_for_quote' and pooling_group_id is null;
  if cnt<>n then raise exception 'Ada pesanan yang tidak tersedia untuk pooling'; end if;
  if exists(select 1 from public.orders where id=any(ids) and (destination_key<>g or scheduled_date<>d)) then raise exception 'Jadwal atau lokasi tidak sama'; end if;
  insert into public.pooling_groups(name,destination_key,scheduled_date,approved_by) values('Pooling '||to_char(d,'DD Mon YYYY'),g,d,u) returning id into gid;
  for rec in select id,subtotal,service_fee,row_number() over(order by id) as idx from public.orders where id=any(ids) loop
   amount:=shipping_cost/n + case when rec.idx<=(shipping_cost%n) then 1 else 0 end;
   update public.orders set pooling_group_id=gid,shipping=amount,dp=amount/2,cod=rec.subtotal+rec.service_fee+amount-(amount/2),total=rec.subtotal+rec.service_fee+amount where id=rec.id;
   update public.payments set amount=amount/2 where order_id=rec.id and kind='shipping_dp';
   update public.payments set amount=rec.subtotal+rec.service_fee+amount-(amount/2) where order_id=rec.id and kind='cod_settlement';
  end loop;
  insert into public.audit_logs(actor_id,entity,entity_id,action) values(u,'pooling_groups',gid,'approve_pool');
  return jsonb_build_object('pooling_group_id',gid);
 elsif p_action='accept_quote' then
  oid:=(p_data->>'order_id')::uuid;
  update public.orders set status='awaiting_dp' where id=oid and customer_id=u and status='ready_for_quote';
  if not found then raise exception 'Invoice belum siap'; end if;
  return jsonb_build_object('ok',true);
 elsif p_action='submit_dp' then
  oid:=(p_data->>'order_id')::uuid;
  update public.orders set status='dp_submitted' where id=oid and customer_id=u and status='awaiting_dp';
  if not found then raise exception 'Order belum bisa dikonfirmasi pembayaran'; end if;
  update public.payments set status='submitted',note='QRIS DEMO: TIDAK ADA UANG NYATA',updated_at=now() where order_id=oid and kind='shipping_dp';
  return jsonb_build_object('ok',true);
 elsif p_action='review_dp' then
  if not admin_ok then raise exception 'Hanya admin'; end if;
  oid:=(p_data->>'order_id')::uuid; r:=p_data->>'decision';
  if r not in ('verified','rejected') then raise exception 'Keputusan tidak valid'; end if;
  perform 1 from public.orders where id=oid and status='dp_submitted' for update;
  if not found then raise exception 'Bukti DP tidak tersedia'; end if;
  update public.payments set status=r,reviewed_by=u,reviewed_at=now(),updated_at=now() where order_id=oid and kind='shipping_dp';
  update public.orders set status=case when r='verified' then 'dp_verified' else 'awaiting_dp' end where id=oid;
  insert into public.audit_logs(actor_id,entity,entity_id,action) values(u,'orders',oid,'review_dp_'||r);
  return jsonb_build_object('ok',true);
 elsif p_action='dispatch' then
  if not admin_ok then raise exception 'Hanya admin'; end if;
  oid:=(p_data->>'order_id')::uuid;
  select pooling_group_id into gid from public.orders where id=oid and status='dp_verified' for update;
  if not found then raise exception 'DP belum disetujui'; end if;
  if gid is null then ids:=array[oid]; else select array_agg(id) into ids from public.orders where pooling_group_id=gid; end if;
  if exists(select 1 from public.orders where id=any(ids) and status<>'dp_verified') then raise exception 'Semua anggota pooling harus melunasi DP terlebih dahulu'; end if;
  if exists(select 1 from public.store_orders where order_id=any(ids) and status not in ('ready','rejected')) then raise exception 'Barang toko belum semuanya siap'; end if;
  if exists(select 1 from public.shipment_orders where order_id=any(ids)) then raise exception 'Pengiriman sudah dibuat'; end if;
  insert into public.shipments(pooling_group_id) values(gid) returning id into sh;
  insert into public.shipment_orders(shipment_id,order_id) select sh,unnest(ids);
  update public.orders set status='delivery' where id=any(ids);
  return jsonb_build_object('shipment_id',sh);
 elsif p_action='assign_driver' or p_action='claim_shipment' then
  sh:=(p_data->>'shipment_id')::uuid;
  if p_action='assign_driver' then
   if not admin_ok then raise exception 'Hanya admin'; end if;
   did:=(p_data->>'driver_id')::uuid;
   if not exists(select 1 from public.drivers where id=did and approved and available) then raise exception 'Driver tidak tersedia'; end if;
  else
   select id into did from public.drivers where owner_id=u and approved and available;
   if did is null then raise exception 'Akun bukan mitra pickup aktif'; end if;
  end if;
  update public.shipments set driver_id=did,status='assigned' where id=sh and status='open' and driver_id is null;
  if not found then raise exception 'Tugas sudah diambil driver lain'; end if;
  insert into public.delivery_events(shipment_id,actor_id,kind) values(sh,u,'assigned');
  return jsonb_build_object('ok',true);
 elsif p_action='move_shipment' then
  sh:=(p_data->>'shipment_id')::uuid; r:=p_data->>'event';
  if r not in ('picked_up','arrived') then raise exception 'Status pengiriman tidak valid'; end if;
  if r='picked_up' then stage:='assigned'; else stage:='picked_up'; end if;
  update public.shipments s set status=r from public.drivers d where s.id=sh and s.driver_id=d.id and d.owner_id=u and s.status=stage;
  if not found then raise exception 'Transisi pengiriman tidak diizinkan'; end if;
  if r='arrived' then update public.orders set status='inspection' where id in(select order_id from public.shipment_orders where shipment_id=sh); end if;
  insert into public.delivery_events(shipment_id,actor_id,kind) values(sh,u,r);
  return jsonb_build_object('ok',true);
 elsif p_action='inspect_goods' then
  oid:=(p_data->>'order_id')::uuid;
  update public.orders set status='cod_pending' where id=oid and customer_id=u and status='inspection';
  if not found then raise exception 'Barang belum bisa diperiksa'; end if;
  return jsonb_build_object('ok',true);
 elsif p_action='record_cod' then
  oid:=(p_data->>'order_id')::uuid;
  update public.orders o set status='cod_recorded' where o.id=oid and o.status='cod_pending' and exists(
   select 1 from public.shipment_orders so join public.shipments s on s.id=so.shipment_id join public.drivers d on d.id=s.driver_id where so.order_id=o.id and d.owner_id=u
  );
  if not found then raise exception 'Penerimaan COD tidak diizinkan'; end if;
  update public.payments set status='recorded',note='COD DEMO: TANPA PERPINDAHAN UANG',updated_at=now() where order_id=oid and kind='cod_settlement';
  return jsonb_build_object('ok',true);
 elsif p_action='confirm_delivery' then
  oid:=(p_data->>'order_id')::uuid;
  update public.orders set status='completed' where id=oid and customer_id=u and status='cod_recorded';
  if not found then raise exception 'COD belum dicatat driver'; end if;
  update public.payments set status='confirmed',updated_at=now() where order_id=oid and kind='cod_settlement';
  update public.shipments set status='completed' where id in (select sh.shipment_id from public.shipment_orders sh where sh.order_id=oid)
   and not exists(select 1 from public.shipment_orders x join public.orders o on o.id=x.order_id where x.shipment_id=public.shipments.id and o.status<>'completed');
  return jsonb_build_object('ok',true);
 else raise exception 'Perintah tidak dikenal: %',p_action;
 end if;
end $$;
revoke all on function public.hatop_action(text,jsonb) from public,anon;
grant execute on function public.hatop_action(text,jsonb) to authenticated;
revoke all on function hatop_private.is_role(text),hatop_private.can_see_order(uuid) from public,anon;
grant usage on schema hatop_private to authenticated;
grant execute on function hatop_private.is_role(text),hatop_private.can_see_order(uuid) to authenticated;
-- No public or authenticated grant for tables' INSERT/UPDATE/DELETE: mutations only through action.
