// HATOP QRIS charge: Midtrans Core API, deploy to Supabase Edge Functions.
// Never expose MIDTRANS_SERVER_KEY or SUPABASE_SERVICE_ROLE_KEY in frontend.
const env=(key:string)=>Deno.env.get(key)||'';
const project=env('SUPABASE_URL').replace(/\/+$/,'');
const service=env('SUPABASE_SERVICE_ROLE_KEY');
const midtransKey=env('MIDTRANS_SERVER_KEY');
const mode=env('MIDTRANS_ENV')==='production'?'production':'sandbox';
const midtransBase=mode==='production'?'https://api.midtrans.com':'https://api.sandbox.midtrans.com';
const allowed=env('HATOP_ALLOWED_ORIGIN')||'https://hatopv-2.vercel.app';
const cors={ 'Access-Control-Allow-Origin':allowed, 'Access-Control-Allow-Headers':'authorization, apikey, content-type', 'Access-Control-Allow-Methods':'POST, OPTIONS', 'Vary':'Origin' };
const reply=(value:unknown,status=200)=>new Response(JSON.stringify(value),{status,headers:{'Content-Type':'application/json',...cors}});
async function rpc(name:string,body:Record<string,unknown>){
 const response=await fetch(`${project}/rest/v1/rpc/${name}`,{method:'POST',headers:{apikey:service,Authorization:`Bearer ${service}`,'Content-Type':'application/json'},body:JSON.stringify(body)});
 const value=await response.json().catch(()=>({}));
 if(!response.ok) throw new Error(value?.message||`Database ${response.status}`);
 return value;
}
const safeQr=(raw:unknown)=>{
 try{const u=new URL(String(raw));return u.protocol==='https:'&&u.hostname===new URL(midtransBase).hostname&&/^\/v[24]\/qris\//.test(u.pathname)?u.href:null;}catch{return null;}
};
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
 if(req.method!=='POST')return reply({error:'Metode tidak tersedia'},405);
 if(req.headers.get('origin') && req.headers.get('origin')!==allowed)return reply({error:'Origin tidak diizinkan'},403);
 if(!project||!service||!midtransKey)return reply({error:'Konfigurasi payment gateway belum lengkap'},503);
 const token=req.headers.get('authorization')?.match(/^Bearer (\S+)$/i)?.[1];
 if(!token)return reply({error:'Login diperlukan'},401);
 const auth=await fetch(`${project}/auth/v1/user`,{headers:{apikey:service,Authorization:`Bearer ${token}`}});
 if(!auth.ok)return reply({error:'Sesi Google tidak valid'},401);
 const user=await auth.json();
 if(!user?.id)return reply({error:'Akun tidak ditemukan'},401);
 let payload:Record<string,unknown>;
 try{payload=await req.json();}catch{return reply({error:'Data tidak valid'},400);}
 const orderId=String(payload.order_id||'');
 if(!/^[0-9a-f-]{36}$/i.test(orderId))return reply({error:'Nomor pesanan tidak valid'},400);
 try{
  const reserved=await rpc('hatop_qris_prepare',{p_order_id:orderId,p_customer_id:user.id,p_provider_order_id:`HTP-${crypto.randomUUID().replaceAll('-','')}`});
  if(!reserved.created){
   if(reserved.status==='pending'&&safeQr(reserved.qr_url))return reply({status:'pending',qr_url:reserved.qr_url,amount:reserved.amount});
   if(reserved.status==='paid')return reply({status:'paid',amount:reserved.amount});
   return reply({error:'Sesi QRIS sudah dicatat namun belum selesai. Hubungi admin untuk pengecekan, jangan membuat tagihan lain.'},409);
  }
  const amount=Number(reserved.amount);
  if(!Number.isSafeInteger(amount)||amount<=0)throw new Error('DP tidak valid');
  const charge=await fetch(`${midtransBase}/v2/charge`,{
   method:'POST',
   headers:{Authorization:`Basic ${btoa(midtransKey+':')}`,'Content-Type':'application/json','Accept':'application/json'},
   body:JSON.stringify({payment_type:'qris',qris:{acquirer:'gopay'},transaction_details:{order_id:reserved.provider_order_id,gross_amount:amount},item_details:[{id:'dp-shipping',price:amount,quantity:1,name:'HATOP - DP 50% ongkir'}]})
  });
  const body=await charge.json().catch(()=>({}));
  if(!charge.ok)throw new Error(`Midtrans tidak dapat menerbitkan QRIS (HTTP ${charge.status}). Periksa dashboard merchant.`);
  const qr=safeQr((body.actions||[]).find((a:any)=>a.name==='generate-qr-code-v2')?.url)||safeQr((body.actions||[]).find((a:any)=>a.name==='generate-qr-code')?.url);
  if(!qr)throw new Error('Provider belum memberikan URL QRIS. Periksa dashboard merchant.');
  await rpc('hatop_qris_set_created',{p_provider_order_id:reserved.provider_order_id,p_qr_url:qr,p_transaction_id:String(body.transaction_id||'')});
  return reply({status:'pending',qr_url:qr,amount});
 }catch(error){
  // The charge may exist even if communication failed: never create a second charge automatically.
  return reply({error:error instanceof Error?error.message:'Gagal menyiapkan QRIS'},409);
 }
});

export {};
