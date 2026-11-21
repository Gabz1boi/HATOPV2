/** Pure, testable HATOP business calculations. No database or browser dependencies. */
export function quoteTotal({subtotal,shipping,serviceFee}){
 if(![subtotal,shipping,serviceFee].every(n=>Number.isInteger(n)&&n>=0)) throw new Error('invalid checkout amounts');
 const total=subtotal+shipping+serviceFee;
 const dp=Math.floor(shipping/2);
 return {dp,cod:total-dp,total};
}
export function poolingCandidates(orders,maxPoolSize=3){
 const groups=new Map();
 for(const o of orders){
  if(o.status!=='ready_for_quote'||o.pooling_group_id||!o.destination_key||!o.scheduled_date)continue;
  const key=`${o.destination_key}|${o.scheduled_date}`;
  if(!groups.has(key)) groups.set(key,[]);
  groups.get(key).push(o);
 }
 const result=[];
 for(const g of groups.values()){
  g.sort((a,b)=>String(a.id).localeCompare(String(b.id)));
  for(let i=0;i+1<g.length;i+=maxPoolSize){const slice=g.slice(i,i+maxPoolSize);if(slice.length>=2)result.push(slice);}
 }
 return result;
}
