import test from 'node:test';
import assert from 'node:assert/strict';
import { productPhotos, reviewSummary, calculateDeposit, openPhotoSlots } from '../src/cloud-product.mjs';

test('product Photos display no more than five unique safe image URLs',()=>{
 const l={id:'abc'}, product={image_url:'https://cdn.example/a.jpg'};
 const rows=[{listing_id:'abc',position:1,image_url:'https://cdn.example/b.jpg'},
 {listing_id:'abc',position:2,image_url:'https://cdn.example/b.jpg'},
 {listing_id:'abc',position:3,image_url:'javascript:alert(1)'},
 ...Array.from({length:9},(_,i)=>({listing_id:'abc',position:i+4,image_url:`https://cdn.example/${i}.jpg`}))];
 assert.deepEqual(productPhotos(l,product,rows),['https://cdn.example/b.jpg','https://cdn.example/0.jpg','https://cdn.example/1.jpg','https://cdn.example/2.jpg','https://cdn.example/3.jpg']);
});
test('productPhotos falls back to catalog photo but never fake urls',()=>{
 assert.deepEqual(productPhotos({id:'x'},{image_url:'https://cdn.example/one.png'},[]),['https://cdn.example/one.png']);
 assert.deepEqual(productPhotos({id:'x'},{image_url:'data:text/html,hi'},[]),[]);
});
test('rating summary excludes other listings and does not invent a rating',()=>{
 assert.equal(reviewSummary('x',[]).average,null);
 assert.deepEqual(reviewSummary('x',[{listing_id:'x',rating:5},{listing_id:'x',rating:4},{listing_id:'y',rating:1}]),{average:4.5,count:2});
});
test('the approved DP model is half shipping; other models are not used in checkout',()=>{
 assert.deepEqual(calculateDeposit({subtotal:52000,shipping:400000,serviceFee:20000}),{total:472000,dp:200000,cod:272000});
 assert.deepEqual(calculateDeposit({subtotal:52000,shipping:400000,serviceFee:20000,model:'half_total'}),{total:472000,dp:236000,cod:236000});
 assert.deepEqual(calculateDeposit({subtotal:52000,shipping:400000,serviceFee:20000,model:'half_goods_shipping'}),{total:472000,dp:226000,cod:246000});
});

test('photo uploads reuse vacant positions without collisions',()=>{
 assert.deepEqual(openPhotoSlots([{position:1},{position:3}],3),[2,4,5]);
 assert.throws(()=>openPhotoSlots([{position:1},{position:2},{position:3},{position:4},{position:5}],1),/maximum/);
});
