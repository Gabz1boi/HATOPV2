import { cp, mkdir, rm, writeFile } from 'node:fs/promises';
const config = {
 url: (process.env.VITE_SUPABASE_URL || '').trim().replace(/\/+$/,''),
 publishableKey: (process.env.VITE_SUPABASE_PUBLISHABLE_KEY || '').trim(),
};
if(Boolean(config.url)!==Boolean(config.publishableKey)) throw new Error('Set both VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY');
if(config.url && !/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(config.url)) throw new Error('Invalid Supabase project URL');
if(config.publishableKey && !/^sb_publishable_[a-zA-Z0-9_-]+$/.test(config.publishableKey)) throw new Error('Expected Supabase publishable key');
await rm('dist',{recursive:true,force:true});await mkdir('dist',{recursive:true});
await cp('index.html','dist/index.html');await cp('src','dist/src',{recursive:true});await cp('public','dist',{recursive:true});
// Do not ship old localStorage storefront or service worker to production.
for(const obsolete of ['dist/src/main.mjs','dist/src/data.mjs','dist/src/cloud-seed.mjs','dist/public/sw.js','dist/sw.js'])await rm(obsolete,{force:true});
await writeFile('dist/hatop-config.js',`window.HATOP_CONFIG = ${JSON.stringify(config).replace(/</g,'\\u003c')};\n`);
console.log(`HATOP build complete (${config.url?'Supabase Cloud':'Supabase not configured'})`);
