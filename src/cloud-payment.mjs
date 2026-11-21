// Pure HATOP payment presentation and public catalogue guards.
export function shippingDeposit({subtotal,shipping,serviceFee}){
 const amounts=[subtotal,shipping,serviceFee];
 if(amounts.some(n=>!Number.isSafeInteger(n)||n<0))throw new TypeError('Nilai transaksi tidak valid');
 const total=subtotal+shipping+serviceFee;
 if(!Number.isSafeInteger(total))throw new TypeError('Total transaksi tidak valid');
 const dp=Math.floor(shipping/2); // contractual model in current proposal
 return {total,dp,cod:total-dp};
}
export function trustedQrisUrl(raw){
 try {const url=new URL(raw); return url.protocol==='https:' && ['api.sandbox.midtrans.com','api.midtrans.com'].includes(url.hostname) && /^\/v[24]\/qris\//.test(url.pathname);}catch{return false;}
}
export function successfulQrisStatus(notification){return notification?.transaction_status==='settlement' && notification?.payment_type==='qris' && notification?.fraud_status!=='deny';}
export function publicListing(listing){return Boolean(listing?.active && listing.store?.approved && !listing.store?.demo && listing.product?.local_verified);}
