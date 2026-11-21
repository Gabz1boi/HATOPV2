import test from 'node:test';
import assert from 'node:assert/strict';
import { shippingDeposit, trustedQrisUrl, successfulQrisStatus, publicListing } from '../src/cloud-payment.mjs';

test('DP is 50 percent of final shipping and COD is balance', () => {
 assert.deepEqual(shippingDeposit({subtotal:52000,shipping:400000,serviceFee:20000}),{total:472000,dp:200000,cod:272000});
 assert.deepEqual(shippingDeposit({subtotal:100,shipping:101,serviceFee:0}),{total:201,dp:50,cod:151});
 assert.throws(()=>shippingDeposit({subtotal:-1,shipping:1,serviceFee:0}));
});
test('QR image links can only use official Midtrans HTTPS hosts', () => {
 assert.equal(trustedQrisUrl('https://api.sandbox.midtrans.com/v2/qris/token/qr-code'),true);
 assert.equal(trustedQrisUrl('https://api.midtrans.com/v2/qris/token/qr-code'),true);
 assert.equal(trustedQrisUrl('https://api.midtrans.com.evil.test/v2/qris/token/qr-code'),false);
 assert.equal(trustedQrisUrl('javascript:alert(1)'),false);
 assert.equal(trustedQrisUrl('http://api.midtrans.com/v2/qris/token/qr-code'),false);
});
test('Only settled QRIS payments accepted as paid',()=>{
 assert.equal(successfulQrisStatus({transaction_status:'settlement',payment_type:'qris',fraud_status:'accept'}),true);
 assert.equal(successfulQrisStatus({transaction_status:'pending',payment_type:'qris'}),false);
 assert.equal(successfulQrisStatus({transaction_status:'settlement',payment_type:'bank_transfer'}),false);
 assert.equal(successfulQrisStatus({transaction_status:'settlement',payment_type:'qris',fraud_status:'deny'}),false);
});
test('Do not list test stores or unverified catalogue items in public',()=>{
 assert.equal(publicListing({active:true,stock:4,store:{approved:true,demo:false},product:{local_verified:true}}),true);
 assert.equal(publicListing({active:true,stock:4,store:{approved:true,demo:true},product:{local_verified:true}}),false);
 assert.equal(publicListing({active:true,stock:4,store:{approved:true,demo:false},product:{local_verified:false}}),false);
});
