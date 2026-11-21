// Cloud-only website. Older service workers must not serve a stale storefront.
if(globalThis.navigator?.serviceWorker){
  globalThis.navigator.serviceWorker.getRegistrations().then(regs=>regs.forEach(r=>r.unregister())).catch(()=>{});
}
await import('./cloud-app.mjs');
