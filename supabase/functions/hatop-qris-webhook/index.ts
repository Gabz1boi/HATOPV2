// Signed Midtrans QRIS webhook; do NOT require a user JWT on this endpoint.
const env=(key:string)=>Deno.env.get(key)||'';
const project=env('SUPABASE_URL').replace(/\/+$/,'');
const service=env('SUPABASE_SERVICE_ROLE_KEY');
const midtransKey=env('MIDTRANS_SERVER_KEY');
const reply=(msg:string,status=200)=>new Response(msg,{status,headers:{'Content-Type':'text/plain'}});
const hex=async(s:string)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-512',new TextEncoder().encode(s)))).map(n=>n.toString(16).padStart(2,'0')).join('');
const same=(a:string,b:string)=>{
 if(a.length!==b.length)return false;
 let diff=0;for(let i=0;i<a.length;i++)diff|=a.charCodeAt(i)^b.charCodeAt(i);
 return diff===0;
};
async function rpc(name:string,body:Record<string,unknown>){
 const response=await fetch(`${project}/rest/v1/rpc/${name}`,{method:'POST',headers:{apikey:service,Authorization:`Bearer ${service}`,'Content-Type':'application/json'},body:JSON.stringify(body)});
 const value=await response.json().catch(()=>({}));
 if(!response.ok)throw new Error(value?.message||`Database ${response.status}`);
 return value;
}
Deno.serve(async req=>{
 if(req.method!=='POST')return reply('Method not allowed',405);
 if(!project||!service||!midtransKey)return reply('Not configured',503);
 let body:Record<string,unknown>;
 try{body=await req.json();}catch{return reply('Invalid JSON',400);}
 const ref=String(body.order_id||'');
 const code=String(body.status_code||'');
 const gross=String(body.gross_amount||'');
 const supplied=String(body.signature_key||'').toLowerCase();
 if(!/^HTP-[a-f0-9]{32}$/.test(ref)||!/^\d{3}$/.test(code)||!/^\d+(\.0{1,2})?$/.test(gross)||!/^[a-f0-9]{128}$/.test(supplied))return reply('Invalid transaction',400);
 const expected=await hex(ref+code+gross+midtransKey);
 if(!same(expected,supplied))return reply('Invalid signature',403);
 if(String(body.payment_type||'')!=='qris')return reply('Unsupported payment type',400);
 if(env('MIDTRANS_MERCHANT_ID') && String(body.merchant_id||'')!==env('MIDTRANS_MERCHANT_ID'))return reply('Wrong merchant',403);
 const status=String(body.transaction_status||'');
 if(['expire','cancel','deny'].includes(status)){try{await rpc('hatop_qris_mark_expired',{p_provider_order_id:ref});return reply('OK');}catch{return reply('Retry later',503);}}
 if(status!=='settlement')return reply('Ignored'); // never trust pending as paid
 if(code!=='200'||(body.fraud_status && body.fraud_status!=='accept'))return reply('Not settled',400);
 const amount=Number(gross);
 if(!Number.isSafeInteger(amount)||amount<=0)return reply('Invalid amount',400);
 try{await rpc('hatop_qris_confirm',{p_provider_order_id:ref,p_amount:amount,p_transaction_id:String(body.transaction_id||'')});return reply('OK');}
 catch{return reply('Retry later',503);} // Midtrans will retry if our DB is temporarily unavailable
});

export {};
