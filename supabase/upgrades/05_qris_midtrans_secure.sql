-- HATOP payment hardening and Midtrans QRIS integration schema.
-- Apply ONCE to a verified staging Supabase project AFTER core schema and 04 media upgrade.
-- Do NOT use without a backup. Does not create a merchant account or enable real money.

create table if not exists public.hatop_qris_sessions (
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null unique references public.orders(id) on delete cascade,
 provider_order_id text not null unique check (char_length(provider_order_id) between 8 and 100),
 amount integer not null check (amount>0),
 status text not null default 'creating' check (status in ('creating','pending','paid','expired','failed')),
 qr_url text,
 provider_transaction_id text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
alter table public.hatop_qris_sessions enable row level security;
revoke all on public.hatop_qris_sessions from public,anon,authenticated;
grant select on public.hatop_qris_sessions to authenticated;
create policy hatop_qris_owner_read on public.hatop_qris_sessions for select to authenticated using (
 exists(select 1 from public.orders o where o.id=hatop_qris_sessions.order_id and o.customer_id=(select auth.uid()))
 or (select hatop_private.is_role('admin'))
);
-- Webhooks and charge requests use service_role, never a browser user.
revoke all on public.hatop_qris_sessions from anon;
grant all on public.hatop_qris_sessions to service_role;

create or replace function public.hatop_qris_prepare(p_order_id uuid,p_customer_id uuid,p_provider_order_id text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.orders%rowtype; s public.hatop_qris_sessions%rowtype;
begin
 select * into o from public.orders where id=p_order_id for update;
 if not found or o.customer_id<>p_customer_id then raise exception 'Pesanan tidak ditemukan'; end if;
 if o.status<>'awaiting_dp' then raise exception 'Ongkir final belum ditetapkan admin'; end if;
 if exists (select 1 from public.store_orders so join public.stores st on st.id=so.store_id where so.order_id=p_order_id and so.status<>'rejected' and (st.demo or not st.approved))
 then raise exception 'Mitra toko belum terverifikasi'; end if;
 if exists (select 1 from public.order_items i join public.store_orders so on so.id=i.store_order_id join public.store_listings l on l.id=i.listing_id join public.catalog_products p on p.id=l.catalog_id where so.order_id=p_order_id and so.status<>'rejected' and not p.local_verified)
 then raise exception 'Produk belum terverifikasi'; end if;
 if o.dp<=0 then raise exception 'DP harus lebih besar dari nol'; end if;
 select * into s from public.hatop_qris_sessions where order_id=p_order_id for update;
 if found then
  if s.amount<>o.dp then raise exception 'DP telah berubah; hubungi admin'; end if;
  return jsonb_build_object('created',false,'status',s.status,'qr_url',s.qr_url,'amount',s.amount,'provider_order_id',s.provider_order_id);
 end if;
 insert into public.hatop_qris_sessions(order_id,provider_order_id,amount)
 values(p_order_id,p_provider_order_id,o.dp) returning * into s;
 return jsonb_build_object('created',true,'status',s.status,'amount',s.amount,'provider_order_id',s.provider_order_id);
end $$;
revoke all on function public.hatop_qris_prepare(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.hatop_qris_prepare(uuid,uuid,text) to service_role;

create or replace function public.hatop_qris_set_created(p_provider_order_id text,p_qr_url text,p_transaction_id text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.hatop_qris_sessions%rowtype;
begin
 select * into s from public.hatop_qris_sessions where provider_order_id=p_provider_order_id for update;
 if not found then raise exception 'Sesi pembayaran tidak ditemukan'; end if;
 if s.status='paid' then return jsonb_build_object('status','paid'); end if;
 if s.status not in ('creating','pending') then raise exception 'Status pembayaran tidak dapat diubah'; end if;
 if p_qr_url not like 'https://api.midtrans.com/v%/qris/%' and p_qr_url not like 'https://api.sandbox.midtrans.com/v%/qris/%'
 then raise exception 'URL QRIS tidak valid'; end if;
 update public.hatop_qris_sessions set status='pending',qr_url=p_qr_url,
 provider_transaction_id=p_transaction_id,updated_at=now() where id=s.id;
 return jsonb_build_object('status','pending');
end $$;
revoke all on function public.hatop_qris_set_created(text,text,text) from public,anon,authenticated;
grant execute on function public.hatop_qris_set_created(text,text,text) to service_role;

create or replace function public.hatop_qris_confirm(p_provider_order_id text,p_amount integer,p_transaction_id text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.hatop_qris_sessions%rowtype;o public.orders%rowtype;
begin
 select * into s from public.hatop_qris_sessions where provider_order_id=p_provider_order_id for update;
 if not found then raise exception 'Transaksi tidak dikenal'; end if;
 select * into o from public.orders where id=s.order_id for update;
 if s.amount<>p_amount or o.dp<>p_amount then raise exception 'Nominal pembayaran tidak cocok'; end if;
 if s.status='paid' then return jsonb_build_object('status','paid','idempotent',true); end if;
 if s.status not in ('pending','creating') or o.status<>'awaiting_dp' then raise exception 'Transaksi tidak siap dikonfirmasi'; end if;
 update public.hatop_qris_sessions set status='paid',provider_transaction_id=p_transaction_id,
 updated_at=now() where id=s.id;
 update public.payments set status='verified',note='Pembayaran QRIS dikonfirmasi provider',updated_at=now()
 where order_id=s.order_id and kind='shipping_dp' and amount=p_amount;
 if not found then raise exception 'Baris DP tidak cocok'; end if;
 update public.orders set status='dp_verified',updated_at=now() where id=s.order_id;
 insert into public.audit_logs(entity,entity_id,action,detail)
 values('orders',s.order_id,'qris_settlement',jsonb_build_object('provider_ref',p_provider_order_id));
 return jsonb_build_object('status','paid','idempotent',false);
end $$;
revoke all on function public.hatop_qris_confirm(text,integer,text) from public,anon,authenticated;
grant execute on function public.hatop_qris_confirm(text,integer,text) to service_role;

create or replace function public.hatop_qris_mark_expired(p_provider_order_id text)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 update public.hatop_qris_sessions set status='expired',updated_at=now()
 where provider_order_id=p_provider_order_id and status in ('pending','creating');
 return jsonb_build_object('status','handled');
end $$;
revoke all on function public.hatop_qris_mark_expired(text) from public,anon,authenticated;
grant execute on function public.hatop_qris_mark_expired(text) to service_role;

-- Prevent accidental double-processing from older user controls by redefining the existing RPC below.

create or replace function public.hatop_action(p_action text, p_data jsonb default '{}'::jsonb)
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
    where l.id=lid and l.active and l.stock>=item_qty and s.approved and not s.demo and c.local_verified for update of l;
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
     update public.stores set owner_id=app.user_id,approved=true,demo=false where id=app.target_store_id and owner_id is null and name=app.display_name;
     if not found then raise exception 'Toko tidak tersedia atau identitas pengajuan tidak sesuai'; end if;
    else insert into public.stores(owner_id,name,area,demo,approved) values(app.user_id,app.display_name,app.area,false,true); end if;
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
   update public.orders set status='awaiting_dp',pooling_group_id=gid,shipping=amount,dp=amount/2,cod=rec.subtotal+rec.service_fee+amount-(amount/2),total=rec.subtotal+rec.service_fee+amount where id=rec.id;
   update public.payments set amount=amount/2 where order_id=rec.id and kind='shipping_dp';
   update public.payments set amount=rec.subtotal+rec.service_fee+amount-(amount/2) where order_id=rec.id and kind='cod_settlement';
  end loop;
  insert into public.audit_logs(actor_id,entity,entity_id,action) values(u,'pooling_groups',gid,'approve_pool');
  return jsonb_build_object('pooling_group_id',gid);
 elsif p_action='finalize_quote' then
  if not admin_ok then raise exception 'Hanya admin'; end if;
  oid:=(p_data->>'order_id')::uuid;
  update public.orders set status='awaiting_dp',updated_at=now() where id=oid and status='ready_for_quote' and pooling_group_id is null;
  if not found then raise exception 'Status pesanan tidak dapat ditetapkan'; end if;
  insert into public.audit_logs(actor_id,entity,entity_id,action) values(u,'orders',oid,'finalize_quote');
  return jsonb_build_object('ok',true);
 elsif p_action in ('accept_quote','submit_dp','review_dp') then
  raise exception 'Status DP hanya dapat berubah melalui verifikasi QRIS resmi';
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
  update public.payments set status='recorded',note='COD dicatat oleh mitra pickup dan menunggu konfirmasi pembeli',updated_at=now() where order_id=oid and kind='cod_settlement';
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
