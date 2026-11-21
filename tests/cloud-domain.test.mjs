import test from 'node:test';
import assert from 'node:assert/strict';
import { poolingCandidates, quoteTotal } from '../src/cloud-domain.mjs';
test('pooling only recommends orders matching area, schedule, and status',()=>{
 const o=[
  {id:'a',destination_key:'silaen',scheduled_date:'2026-12-01',status:'ready_for_quote',pooling_group_id:null},
  {id:'b',destination_key:'silaen',scheduled_date:'2026-12-01',status:'ready_for_quote',pooling_group_id:null},
  {id:'c',destination_key:'balige',scheduled_date:'2026-12-01',status:'ready_for_quote',pooling_group_id:null},
  {id:'d',destination_key:'silaen',scheduled_date:'2026-12-01',status:'awaiting_dp',pooling_group_id:null},
 ];
 assert.deepEqual(poolingCandidates(o).map(g=>g.map(x=>x.id)),[['a','b']]);
});
test('a group with four valid candidates is split into max size three, never auto-approved',()=>{
 const orders=Array.from({length:4},(_,i)=>({id:''+i,status:'ready_for_quote',destination_key:'silaen',scheduled_date:'2026-12-01',pooling_group_id:null}));
 assert.equal(poolingCandidates(orders,3)[0].length,3);
 assert.equal(poolingCandidates(orders,3).length,1);
});
test('DP is 50% of shipping, COD is all other charges and unpaid shipping',()=>{
 assert.deepEqual(quoteTotal({subtotal:300000,shipping:40000,serviceFee:10000}),{dp:20000,cod:330000,total:350000});
});
test('invalid monetary inputs fail',()=>{assert.throws(()=>quoteTotal({subtotal:-1,shipping:0,serviceFee:0}),/invalid/);});
