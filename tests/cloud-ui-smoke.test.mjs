import test from 'node:test';
import assert from 'node:assert/strict';

const events={};const app={innerHTML:''};
const listingId='5f111111-2222-3333-4444-555555555555';
const product={id:'prd-001',name:'Kapur Dolomit Premium',description:'Dolomit untuk keperluan pertanian.',local_verified:true,category:'pupuk',brand:'Kebun',unit:'karung 25 kg',image_url:'https://images.example.org/dolomit.webp'};
const store={id:'store-1',name:'Toko Mawar',approved:true,demo:false,area:'Balige'};
const datasets={categories:[{code:'pupuk',name:'Pupuk'}],catalog_products:[product],stores:[store],store_listings:[{id:listingId,catalog_id:product.id,store_id:store.id,active:true,stock:3,demo_price:52000}],listing_images:[],product_reviews:[]};
const storage=new Map();
globalThis.HATOP_CONFIG={url:'https://test.supabase.co',publishableKey:'sb_publishable_example',testingPayments:false};
globalThis.localStorage={getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)};
globalThis.location={hash:'#/catalog',search:'',pathname:'/',origin:'http://localhost:8080'};
globalThis.document={getElementById:id=>id==='app'?app:null,addEventListener:(k,fn)=>events[k]=fn};
globalThis.window={addEventListener:(k,fn)=>events[k]=fn};
globalThis.fetch=async url=>({ok:true,json:async()=>{
 const s=String(url);const match=s.match(/\/rest\/v1\/([a-z_]+)/);return match?datasets[match[1]]||[]:{};
}});
globalThis.setInterval=()=>0;
await import('../src/cloud-app.mjs');
await new Promise(resolve=>setTimeout(resolve,30));

test('marketplace landing shows three user journeys without external reference link',()=>{
 assert.match(app.innerHTML,/Belanja mudah/);
 assert.match(app.innerHTML,/Jadi Mitra Toko/);
 assert.match(app.innerHTML,/Jadi Mitra Pickup/);
 assert.doesNotMatch(app.innerHTML,/Referensi web|SEMUA TRANSAKSI DEMO/);
});
test('real product detail route loads descriptions and real review empty state',()=>{
 location.hash=`#/product/${listingId}`;events.hashchange();
 assert.match(app.innerHTML,/Dolomit untuk keperluan pertanian/);
 assert.match(app.innerHTML,/Belum ada ulasan/);
 assert.match(app.innerHTML,/Tambah ke Keranjang/);
});
test('join route promotes seller and pickup opportunities',()=>{
 location.hash='#/join';events.hashchange();
 assert.match(app.innerHTML,/Ajukan Kemitraan Toko/);
 assert.match(app.innerHTML,/Ajukan Kemitraan Pickup/);
});
