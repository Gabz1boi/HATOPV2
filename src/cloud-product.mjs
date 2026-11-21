// Pure merchandising helpers shared by HATOP's storefront and tests.
const safeURL=(raw)=>{
  try {const u=new URL(String(raw));return ['https:','http:'].includes(u.protocol)?u.href:null;} catch{return null;}
};
export function productPhotos(listing, product={}, rows=[]){
 const photos=rows.filter(x=>x.listing_id===listing.id).sort((a,b)=>a.position-b.position).map(x=>x.image_url);
 photos.push(product.image_url);
 return [...new Set(photos.map(safeURL).filter(Boolean))].slice(0,5);
}
export function reviewSummary(listingId, rows=[]){
 const ratings=rows.filter(x=>x.listing_id===listingId && Number.isInteger(x.rating) && x.rating>=1 && x.rating<=5);
 return {average: ratings.length ? Math.round(ratings.reduce((a,x)=>a+x.rating,0)/ratings.length*10)/10 : null,count:ratings.length};
}
export function calculateDeposit({subtotal,shipping,serviceFee,model='half_shipping'}){
 if([subtotal,shipping,serviceFee].some(x=>!Number.isSafeInteger(x)||x<0))throw new Error('invalid amount');
 const total=subtotal+shipping+serviceFee;
 if(!Number.isSafeInteger(total))throw new Error('invalid amount');
 let dp;
 if(model==='half_shipping')dp=Math.floor(shipping/2);
 else if(model==='half_total')dp=Math.floor(total/2);
 else if(model==='half_goods_shipping')dp=Math.floor((subtotal+shipping)/2);
 else throw new Error('invalid deposit model');
 return {total,dp,cod:total-dp};
}
export function openPhotoSlots(current=[], requested=1){
 if(!Number.isInteger(requested)||requested<1)throw new Error('invalid photo count');
 const occupied=new Set(current.map(x=>Number(x.position)));
 const available=[1,2,3,4,5].filter(n=>!occupied.has(n));
 if(requested>available.length)throw new Error('maximum five photos');
 return available.slice(0,requested);
}
